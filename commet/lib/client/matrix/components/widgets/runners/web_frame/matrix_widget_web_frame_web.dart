// Vommet: widgets in the web app. The widget page loads in an <iframe> on the
// app's own page (a Flutter platform view) and talks to the widget API host
// with window.postMessage, as in Element Web. The in-app web view runner the
// other platforms use needs a native web view, which the web app doesn't
// have.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_transport.dart';
import 'package:commet/client/matrix/components/widgets/runners/web_frame/widget_frame_origin.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/room_widgets/room_widgets_view.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:web/web.dart' as web;

String get widgetFrameNotLoadingHint => Intl.message(
    "Nothing showing? Some widgets only work in a tab of their own.",
    desc:
        "Web app: shown above a widget that hasn't talked to Vommet after a while",
    name: "widgetFrameNotLoadingHint");

class MatrixWidgetWebFrame {
  /// The widget API's parentUrl: this page. Widgets (Element Call among
  /// them) take its origin as the one to post their messages to. Query and
  /// fragment stay out (a sign-in callback can carry a token there).
  static String get parentUrl =>
      "${web.window.location.origin}${web.window.location.pathname}";

  static Future<void> open(
      {required String url,
      required MatrixUserWidgetInfo info,
      required MatrixRoom room,
      required MatrixWidgetComponent component,
      required BuildContext context}) async {
    final origin = WidgetFrameOrigin.of(url);
    if (origin == null) {
      throw Exception("Only http and https widgets can open here");
    }
    // A page of the app's own origin in a frame would share its storage
    // (and crypto store) with the app, sandbox or not.
    if (origin == web.window.location.origin) {
      throw Exception("This widget points at Vommet itself");
    }

    final onExitController = StreamController.broadcast();
    final view = MatrixWidgetWebFrameView(
        url: url,
        origin: origin,
        info: info,
        room: room,
        component: component,
        onExitController: onExitController);

    OverlayWindowsManager.of(context).addWindow(OverlayWindow(
        widget: view, title: info.name, onClose: onExitController.stream));
  }

  /// Opens [url] in a new browser tab, without a handle back to this page.
  /// No widget API there, so widgets that need Vommet won't get far.
  static void openInNewTab(String url) {
    web.window.open(url, "_blank", "noopener,noreferrer");
  }
}

/// Vommet: messages between the widget API host and the framed widget.
/// Takes only messages from the frame's own window with the widget's
/// origin, and posts to that origin only (never "*"), so another frame,
/// tab or a page the widget navigated to can't talk to the host or read
/// its replies.
class MatrixWebFrameWidgetTransceiver implements WidgetTransceiver {
  MatrixWebFrameWidgetTransceiver(this.frame, this.origin) {
    _listener = _onMessage.toJS;
    web.window.addEventListener("message", _listener);
  }

  final web.HTMLIFrameElement frame;
  final String origin;
  late final JSFunction _listener;

  final _controller = StreamController<Uint8List>.broadcast();
  Future<void> _queue = Future.value();

  /// Set once the widget sent its first message.
  final firstMessage = Completer<void>();

  @override
  Stream<Uint8List> get onReceived => _controller.stream;

  void _onMessage(web.MessageEvent event) {
    final window = frame.contentWindow;
    final fromFrame = window != null &&
        event.source != null &&
        (event.source as JSAny).strictEquals(window).toDart;
    if (!WidgetFrameOrigin.accepts(
        fromFrame: fromFrame, origin: event.origin, widgetOrigin: origin)) {
      return;
    }

    final data = event.data;
    // Blobs are read asynchronously; the queue keeps messages in order.
    _queue = _queue.then((_) async {
      try {
        final decoded = await _fromJs(data, 0);
        if (decoded is! Map) return;
        if (!firstMessage.isCompleted) firstMessage.complete();
        if (!_controller.isClosed) {
          _controller.add(utf8.encode(jsonEncode(decoded)));
        }
      } catch (e, s) {
        Log.onError(e, s, content: "Couldn't read a widget message");
      }
    });
  }

  @override
  void send(Uint8List data) {
    final window = frame.contentWindow;
    if (window == null) return;
    try {
      window.postMessage(_toJs(jsonDecode(utf8.decode(data)), 0), origin.toJS);
    } catch (e, s) {
      Log.onError(e, s, content: "Couldn't send a message to the widget");
    }
  }

  void dispose() {
    web.window.removeEventListener("message", _listener);
    _controller.close();
  }

  // Structured clone allows cycles; real widget API messages are shallow.
  static const _maxDepth = 64;

  static Map<String, String> _bytes(Uint8List bytes) =>
      {"__type": "ArrayBuffer", "data": base64Encode(bytes)};

  /// A page message as JSON, binary data marked the way the transport
  /// expects (widgets_common.js does the same on the other platforms).
  static Future<Object?> _fromJs(JSAny? value, int depth) async {
    if (value == null || value.isUndefinedOrNull || depth > _maxDepth) {
      return null;
    }
    if (value.typeofEquals("string")) return (value as JSString).toDart;
    if (value.typeofEquals("boolean")) return (value as JSBoolean).toDart;
    if (value.typeofEquals("number")) {
      final d = (value as JSNumber).toDartDouble;
      // JSON.stringify writes 1, not 1.0; keep whole numbers ints.
      if (d.isFinite &&
          d == d.truncateToDouble() &&
          d.abs() < 9007199254740992) {
        return d.toInt();
      }
      return d.isFinite ? d : null;
    }
    if (!value.typeofEquals("object")) return null;

    if (value.isA<JSArrayBuffer>()) {
      return _bytes((value as JSArrayBuffer).toDart.asUint8List());
    }
    if (value.isA<web.Blob>()) {
      final buffer = await (value as web.Blob).arrayBuffer().toDart;
      return _bytes(buffer.toDart.asUint8List());
    }
    final arrayBuffer = globalContext["ArrayBuffer"] as JSObject;
    if (arrayBuffer.callMethod<JSBoolean>("isView".toJS, value).toDart) {
      final view = value as JSObject;
      final buffer = view["buffer"];
      if (buffer == null || !buffer.isA<JSArrayBuffer>()) return null;
      return _bytes((buffer as JSArrayBuffer).toDart.asUint8List(
          (view["byteOffset"] as JSNumber).toDartInt,
          (view["byteLength"] as JSNumber).toDartInt));
    }
    if (value.isA<JSArray>()) {
      return [
        for (final item in (value as JSArray<JSAny?>).toDart)
          await _fromJs(item, depth + 1)
      ];
    }

    final object = value as JSObject;
    final keys = (globalContext["Object"] as JSObject)
        .callMethod<JSArray<JSString>>("keys".toJS, object)
        .toDart;
    return {
      for (final key in keys)
        key.toDart: await _fromJs(object.getProperty(key), depth + 1)
    };
  }

  /// JSON from the transport as a JS value, with its binary data as
  /// ArrayBuffers and Blobs again.
  static JSAny? _toJs(Object? value, int depth) {
    if (value == null || depth > _maxDepth) return null;
    if (value is String) return value.toJS;
    if (value is bool) return value.toJS;
    if (value is num) return value.toJS;
    if (value is List) {
      return <JSAny?>[for (final item in value) _toJs(item, depth + 1)].toJS;
    }
    if (value is Map) {
      final type = value["__type"];
      final data = value["data"];
      if (data is String && (type == "ArrayBuffer" || type == "Blob")) {
        final bytes = Uint8List.fromList(base64Decode(data));
        if (type == "Blob") return web.Blob(<web.BlobPart>[bytes.toJS].toJS);
        return bytes.buffer.toJS;
      }
      final object = JSObject();
      for (final entry in value.entries) {
        object.setProperty(
            entry.key.toString().toJS, _toJs(entry.value, depth + 1));
      }
      return object;
    }
    return null;
  }
}

/// Vommet: a widget framed in the web app's page.
class MatrixUserWidgetWebFrameRunner implements MatrixWidgetRunner {
  MatrixUserWidgetWebFrameRunner(
      {required MatrixRoom this.room,
      required this.info,
      required this.onExitController,
      required this.transceiver,
      required BuildContext context})
      : client = room.client as MatrixClient,
        widgetId = info.id {
    messageTransport = MatrixWidgetTransport(transceiver);
    eventHandler = MatrixWidgetMessageHandler(runner: this);
    capabilities =
        MatrixWidgetCapabilitiesManager(runner: this, context: context);
  }

  @override
  MatrixRoom? room;

  @override
  MatrixClient client;

  @override
  String widgetId;

  @override
  final MatrixUserWidgetInfo info;

  @override
  late WidgetMessageTransport messageTransport;

  @override
  late WidgetEventHandler eventHandler;

  @override
  late WidgetCapabilityManager capabilities;

  @override
  NotifyingList<LogEntry> logs = NotifyingList.empty(growable: true);

  final MatrixWebFrameWidgetTransceiver transceiver;
  final StreamController onExitController;
  final StreamController _onClosed = StreamController.broadcast();
  bool _disposed = false;

  @override
  Stream<void> get onClosed => _onClosed.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    Log.i("Closing widget frame ${info.id}");
    transceiver.dispose();
    onExitController.add(null);
    _onClosed.add(null);
  }
}

class MatrixWidgetWebFrameView extends StatefulWidget {
  const MatrixWidgetWebFrameView(
      {required this.url,
      required this.origin,
      required this.info,
      required this.room,
      required this.component,
      required this.onExitController,
      super.key});

  final String url;
  final String origin;
  final MatrixUserWidgetInfo info;
  final MatrixRoom room;
  final MatrixWidgetComponent component;
  final StreamController onExitController;

  @override
  State<MatrixWidgetWebFrameView> createState() =>
      _MatrixWidgetWebFrameViewState();
}

class _MatrixWidgetWebFrameViewState extends State<MatrixWidgetWebFrameView> {
  static int _views = 0;

  late final String viewType;
  late final web.HTMLIFrameElement frame;
  MatrixUserWidgetWebFrameRunner? runner;
  Timer? _quietTimer;
  bool quiet = false;

  @override
  void initState() {
    super.initState();
    frame = web.HTMLIFrameElement()
      // Element Web's sandbox and permissions, so the same widgets (call
      // widgets among them) work.
      ..setAttribute("sandbox",
          "allow-forms allow-popups allow-popups-to-escape-sandbox allow-same-origin allow-scripts allow-modals allow-downloads")
      ..setAttribute("allow",
          "camera; microphone; display-capture; clipboard-write; autoplay; fullscreen")
      ..setAttribute("allowfullscreen", "")
      ..setAttribute("referrerpolicy", "no-referrer")
      ..style.setProperty("border", "none")
      ..style.setProperty("width", "100%")
      ..style.setProperty("height", "100%");
    // The app is cross-origin isolated (COEP credentialless, for the
    // WebAssembly renderer's threads), which blocks frames of pages that
    // don't opt in themselves. A credentialless frame needs no opt-in; the
    // widget gets no cookies and fresh storage instead. Browsers without
    // credentialless frames (Firefox) still load widgets that send COEP.
    if (web.window.crossOriginIsolated) {
      frame.setAttribute("credentialless", "");
    }
    frame.src = widget.url;

    viewType = "vommet-widget-frame-${_views++}";
    ui_web.platformViewRegistry
        .registerViewFactory(viewType, (int viewId) => frame);

    final transceiver = MatrixWebFrameWidgetTransceiver(frame, widget.origin);
    runner = MatrixUserWidgetWebFrameRunner(
        room: widget.room,
        info: widget.info,
        onExitController: widget.onExitController,
        transceiver: transceiver,
        context: navigator.currentContext ?? context);
    widget.component.registerRunner(runner!);

    // Pages without the widget API never say anything; a framed page the
    // browser blocked can't either. Offer the tab after a while.
    _quietTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !transceiver.firstMessage.isCompleted) {
        setState(() => quiet = true);
      }
    });
    transceiver.firstMessage.future.then((_) {
      if (mounted && quiet) setState(() => quiet = false);
    });
  }

  @override
  void dispose() {
    _quietTimer?.cancel();
    runner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: quiet
                    ? tiamat.Text.labelLow(widgetFrameNotLoadingHint)
                    : const SizedBox.shrink(),
              ),
              TextButton.icon(
                key: const ValueKey("widget-frame-open-in-tab"),
                onPressed: () => MatrixWidgetWebFrame.openInNewTab(widget.url),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(widgetOpenInNewTab),
              ),
            ],
          ),
        ),
        Expanded(child: HtmlElementView(viewType: viewType)),
      ],
    );
  }
}
