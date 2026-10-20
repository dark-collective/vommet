import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_transport.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: page messages to and from a docked widget. Same format as the
/// widget window's stdin/stdout lines (widgets_ipc.js).
class MatrixDockedWidgetTransceiver implements WidgetTransceiver {
  MatrixDockedWidgetTransceiver(this.id, Stream<String> messages) {
    _sub = messages
        .listen((m) => _controller.add(Uint8List.fromList(utf8.encode(m))));
  }

  final String id;
  late final StreamSubscription _sub;
  final _controller = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get onReceived => _controller.stream;

  @override
  void send(Uint8List data) {
    final text = jsonEncode(utf8.decode(data));
    WidgetDock.instance.backend
        ?.evaluate(id, "window.onMessagePolyfill($text)");
  }

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}

/// Vommet: a widget docked in the main window (experiment), see
/// [WidgetDock].
class MatrixUserWidgetDockedRunner implements MatrixWidgetRunner {
  @override
  MatrixRoom? room;

  @override
  MatrixClient client;

  @override
  late String widgetId;

  @override
  late WidgetMessageTransport messageTransport;

  @override
  late WidgetEventHandler eventHandler;

  @override
  late WidgetCapabilityManager capabilities;

  @override
  NotifyingList<LogEntry> logs = NotifyingList.empty(growable: true);

  final StreamController _onClosed = StreamController.broadcast();

  @override
  Stream<void> get onClosed => _onClosed.stream;

  @override
  UserWidgetInfo info;

  late final String dockId;
  late MatrixDockedWidgetTransceiver _transceiver;
  bool _disposed = false;

  MatrixUserWidgetDockedRunner._(
      {required this.room,
      required this.widgetId,
      required this.info,
      required this.client});

  /// Same user agent as the widget window (rust widget_runner.rs).
  static const userAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WebKitGTK/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36";

  static Future<String> _initScript() async {
    var script = await rootBundle.loadString("assets/data/widgets_ipc.js");
    final common = await rootBundle.loadString("assets/data/widgets_common.js");
    script = script.replaceAll("//\${SEND_IPC_CODE}",
        "function sendIpc(msg) { window.webkit.messageHandlers.vommetIpc.postMessage(msg); }");
    return script.replaceAll("//\${WIDGETS_COMMON}", common);
  }

  static Future<MatrixUserWidgetDockedRunner> start(
      {required String url,
      required MatrixRoom room,
      required MatrixUserWidgetInfo info,
      required BuildContext context}) async {
    final runner = MatrixUserWidgetDockedRunner._(
        room: room,
        widgetId: info.id,
        info: info,
        client: room.client as MatrixClient);
    runner.dockId = "${info.id}-${DateTime.now().microsecondsSinceEpoch}";

    final messages = await WidgetDock.instance.add(
        DockedWidget(
            id: runner.dockId,
            title: info.name,
            clientId: room.client.identifier,
            roomId: room.identifier,
            icon: info.icon,
            onCloseRequested: runner.dispose),
        url: url,
        script: await _initScript(),
        userAgent: userAgent);

    runner._transceiver =
        MatrixDockedWidgetTransceiver(runner.dockId, messages);
    runner.messageTransport = MatrixWidgetTransport(runner._transceiver);
    runner.eventHandler = MatrixWidgetMessageHandler(runner: runner);
    runner.capabilities =
        MatrixWidgetCapabilitiesManager(runner: runner, context: context);
    return runner;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    Log.i("Closing docked widget $dockId");
    await WidgetDock.instance.remove(dockId);
    _transceiver.dispose();
    _onClosed.add(null);
  }
}
