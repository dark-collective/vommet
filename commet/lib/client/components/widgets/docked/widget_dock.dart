import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/components/widgets/docked/macos_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/native_widget_dock_backend.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/image_or_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';

/// Vommet: what a platform needs to show a widget's web view inside the
/// main window ("docked") and to move that same view into a window of its
/// own and back without reloading it ("popped out").
///
/// Linux: a WebKitWebView in a GtkOverlay above the Flutter view. Windows:
/// a WebView2 controller moved between a child window of the main window
/// and a window of its own (`put_ParentWindow`). macOS: a WKWebView
/// filling a Flutter platform view, moved into a window of its own and
/// back (MacosWidgetDockBackend). The Dart side stays the same.
abstract class WidgetDockBackend {
  static WidgetDockBackend? forPlatform() {
    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      return NativeWidgetDockBackend.instance;
    }
    if (!kIsWeb && Platform.isMacOS && MacosWidgetDockBackend.supported) {
      return MacosWidgetDockBackend.instance;
    }
    return null;
  }

  /// The page's `sendIpc` body for widgets_ipc.js: WebView2 takes page
  /// messages on `chrome.webview`, WebKit (GTK and macOS) on a script
  /// message handler named vommetIpc.
  static String sendIpcCode() => PlatformUtils.isWindows
      ? "window.chrome.webview.postMessage(msg);"
      : "window.webkit.messageHandlers.vommetIpc.postMessage(msg);";

  Stream<WidgetDockEvent> get events;

  Future<bool> isAvailable();

  /// Starts loading [url] with [script] injected before the page's own
  /// scripts. The view stays hidden until it gets a rect and is shown.
  Future<void> create(
      {required String id,
      required String url,
      required String script,
      required String title,
      String? userAgent});

  /// [rect] is in physical pixels of the main window.
  Future<void> setRect(String id, Rect rect);

  Future<void> setVisible(String id, bool visible);

  Future<void> evaluate(String id, String script);

  Future<void> popOut(String id);

  Future<void> dockBack(String id);

  /// A PNG of what the view shows, to stand in for it while Flutter UI
  /// covers its rect (native views always draw above Flutter).
  Future<Uint8List?> snapshot(String id);

  /// Gives keyboard focus back to Flutter after the user clicked outside
  /// the view.
  Future<void> focusHost();

  Future<void> destroy(String id);
}

enum WidgetDockEventKind {
  message,
  poppedOut,
  docked,
  focused,
  closed,

  /// The page went full screen: the backend made its window full screen,
  /// and a docked view covers the whole main window until
  /// [fullscreenLeft]. Viewport rects sent meanwhile are kept for after.
  fullscreenEntered,
  fullscreenLeft,
}

class WidgetDockEvent {
  const WidgetDockEvent(this.kind, this.id, {this.message});
  final WidgetDockEventKind kind;
  final String id;
  final String? message;
}

/// One widget shown through the dock.
class DockedWidget {
  DockedWidget(
      {required this.id,
      required this.title,
      required this.clientId,
      required this.roomId,
      required this.onCloseRequested,
      this.icon});
  final String id;
  final String title;

  /// The room it was opened in: it shows there (see DockedWidgetArea).
  final String clientId;
  final String roomId;
  final ImageOrIcon? icon;

  /// The panel's close button: the runner disposes, which calls
  /// [WidgetDock.remove].
  final VoidCallback onCloseRequested;

  bool poppedOut = false;

  /// The page is full screen (see [WidgetDockEventKind.fullscreenEntered]).
  bool fullscreen = false;
}

/// Vommet: the docked widgets (behind an experiment). Placement UI listens
/// to this and puts a [DockedWidgetViewport] wherever the widget should
/// show, so the layout can change without touching the native side.
class WidgetDock extends ChangeNotifier {
  WidgetDock._();
  static final WidgetDock instance = WidgetDock._();

  static final BoolPreference experiment =
      BoolPreference("vommet_experiment_docked_widgets", defaultValue: false);

  /// Platforms with a dock backend, see [WidgetDockBackend.forPlatform].
  static bool available() => WidgetDockBackend.forPlatform() != null;

  static bool get enabled => experiment.value && available();

  WidgetDockBackend? get backend => WidgetDockBackend.forPlatform();

  final Map<String, DockedWidget> _widgets = {};
  final Map<String, StreamController<String>> _messages = {};
  StreamSubscription? _events;
  bool _viewHasFocus = false;
  bool _pointerRouteAdded = false;

  Iterable<DockedWidget> get widgets => _widgets.values;

  DockedWidget? get current => _widgets.values.lastOrNull;

  /// The widget docked in this room, if any (the newest one).
  DockedWidget? inRoom(String clientId, String roomId) => _widgets.values
      .where((w) => w.clientId == clientId && w.roomId == roomId)
      .lastOrNull;

  void _listen() {
    _events ??= backend!.events.listen(_onEvent);
    if (!_pointerRouteAdded) {
      _pointerRouteAdded = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  // Clicks on the web view never reach Flutter, so any pointer down Flutter
  // sees is outside it: take the keyboard back.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent && _viewHasFocus) {
      _viewHasFocus = false;
      backend?.focusHost();
    }
  }

  void _onEvent(WidgetDockEvent event) {
    final widget = _widgets[event.id];
    switch (event.kind) {
      case WidgetDockEventKind.message:
        _messages[event.id]?.add(event.message ?? "");
        return;
      case WidgetDockEventKind.focused:
        _viewHasFocus = true;
        return;
      case WidgetDockEventKind.poppedOut:
        widget?.poppedOut = true;
      case WidgetDockEventKind.docked:
        widget?.poppedOut = false;
      case WidgetDockEventKind.fullscreenEntered:
        widget?.fullscreen = true;
      case WidgetDockEventKind.fullscreenLeft:
        widget?.fullscreen = false;
      case WidgetDockEventKind.closed:
        Log.w("Docked widget ${event.id} closed by its web process");
        widget?.onCloseRequested();
    }
    notifyListeners();
  }

  /// Creates the view; its page messages arrive on the returned stream.
  Future<Stream<String>> add(DockedWidget widget,
      {required String url, required String script, String? userAgent}) async {
    _listen();
    // Not broadcast: keeps what the page sends before the runner listens.
    final messages = StreamController<String>();
    _messages[widget.id] = messages;
    _widgets[widget.id] = widget;
    await backend!.create(
        id: widget.id,
        url: url,
        script: script,
        title: widget.title,
        userAgent: userAgent);
    notifyListeners();
    return messages.stream;
  }

  Future<void> remove(String id) async {
    if (_widgets.remove(id) == null) return;
    await _messages.remove(id)?.close();
    notifyListeners();
    await backend?.destroy(id);
  }

  Future<void> popOut(String id) async => backend?.popOut(id);

  Future<void> dockBack(String id) async => backend?.dockBack(id);

  /// Raises the popped out window (popping out again only presents it).
  Future<void> showWindow(String id) async => backend?.popOut(id);
}
