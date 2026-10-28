import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/components/widgets/runners/subprocess/matrix_subprocess_widget_transceiver.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_transport.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';

class MatrixUserWidgetSubprocessRunner implements MatrixWidgetRunner {
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

  late Process process;

  bool hidden;

  bool privileged;

  @override
  NotifyingList<LogEntry> logs = NotifyingList.empty(growable: true);

  StreamController _onClosed = StreamController.broadcast();

  @override
  Stream<void> get onClosed => _onClosed.stream;

  @override
  UserWidgetInfo info;

  MatrixUserWidgetSubprocessRunner(
      {required Process process,
      required this.room,
      required this.widgetId,
      required BuildContext context,
      required this.info,
      this.hidden = false,
      this.privileged = false,
      required this.client}) {
    var tx = MatrixSubprocessWidgetTransceiver(process: process);
    this.process = process;

    messageTransport = MatrixWidgetTransport(tx);
    eventHandler = MatrixWidgetMessageHandler(runner: this);

    capabilities = MatrixWidgetCapabilitiesManager(
        runner: this, context: context, privileged: privileged);

    // Vommet: always drain the runner's stderr. Unread, the pipe fills (the
    // runner logs at debug level) and the runner blocks on its next write,
    // which on Windows left a frozen white "Not Responding" window. Keep the
    // last lines for Vommet's own log when the runner fails.
    var stderrTail = <String>[];
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      stderrTail.add(line);
      if (stderrTail.length > 40) stderrTail.removeAt(0);
      if (preferences.widgetDeveloperMode.value) {
        logs.add(LogEntry(LogType.info, line));
      }
    });

    process.exitCode.then((i) {
      Log.i("Subprocess exited with code: $i");
      if (i != 0 && stderrTail.isNotEmpty) {
        Log.w("Widget runner output:\n${stderrTail.join("\n")}");
      }
      dispose();
    });
  }

  @override
  Future<void> dispose() async {
    process.kill();
    _onClosed.add(null);
  }
}
