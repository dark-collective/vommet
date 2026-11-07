import 'dart:async';
import 'dart:io';

import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/matrix/components/widgets/runners/remote_http/matrix_remote_http_transceiver.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_capabilities_manager.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_component.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_message_handler.dart';
import 'package:commet/client/matrix/components/widgets/matrix_widget_transport.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/widget_nearby_link_view.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/rng.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class MatrixUserWidgetRemoteHttpRunner implements MatrixWidgetRunner {
  @override
  MatrixRoom? room;

  @override
  MatrixClient client;

  @override
  late String widgetId;

  late HttpServer server;

  @override
  UserWidgetInfo info;

  @override
  NotifyingList<LogEntry> logs = NotifyingList.empty(growable: true);

  @override
  late WidgetMessageTransport messageTransport;

  @override
  late WidgetEventHandler eventHandler;

  @override
  late WidgetCapabilityManager capabilities;

  late MatrixRemoteHttpWidgetTransceiver tx;

  StreamController _onClosed = StreamController.broadcast();

  @override
  Stream<void> get onClosed => _onClosed.stream;

  bool useInsecureHttp;

  bool allowRemoteConnection;

  MatrixUserWidgetRemoteHttpRunner({
    required this.room,
    required String url,
    required this.widgetId,
    required this.client,
    required HttpServer server,
    required BuildContext context,
    required String hostName,
    required bool launchBrowser,
    required this.info,
    required this.useInsecureHttp,
    required this.allowRemoteConnection,
  }) {
    this.server = server;
    final String secret = RandomUtils.getRandomString(50); // "secret_password";

    tx = MatrixRemoteHttpWidgetTransceiver(
        secret: secret,
        widgetUrl: url,
        hostIp: hostName,
        info: info,
        server: server,
        allowRemoteConnection: allowRemoteConnection,
        useHttps: useInsecureHttp == false,
        onClientConnected: handleInitialConnection);

    messageTransport = MatrixWidgetTransport(tx);

    eventHandler = MatrixWidgetMessageHandler(runner: this);
    capabilities =
        MatrixWidgetCapabilitiesManager(runner: this, context: context);

    if (launchBrowser) {
      var url = Uri(
          scheme: "http",
          host: hostName,
          port: server.port,
          queryParameters: {"token": secret});

      Log.i("Launching browser with url: $url");

      launchExternalBrowser(url);
    } else {
      showConnectionInfo(secret, hostName, context);
    }
  }

  // Vommet: "open in browser" is the user's default browser, through the
  // desktop's open-URL portal in the Flatpak (it can't start host programs)
  // and xdg-open elsewhere, so no build needs Chromium.
  void launchExternalBrowser(Uri url) async {
    ErrorUtils.tryRun(
      navigator.currentContext!,
      () async {
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw Exception("Could not open the widget in a browser");
        }
      },
      onError: () async {
        dispose();
      },
    );
  }

  @override
  Future<void> dispose() async {
    await server.close(force: true);
    _onClosed.add(null);
  }

  void handleInitialConnection() async {
    await Future.delayed(Duration(seconds: 2));

    Log.i("Client connected!");
  }

  void showConnectionInfo(
      String secret, String hostName, BuildContext context) async {
    Log.i("Current IP: $hostName");

    var url = Uri(
        scheme: useInsecureHttp ? "http" : "https",
        host: hostName,
        port: server.port,
        queryParameters: {"token": secret});

    Log.i("Url: ${url.toString()}");

    // Vommet: the QR code with what it does and what to expect.
    AdaptiveDialog.show(
      context,
      title: widgetNearbyTitle,
      builder: (context) => WidgetNearbyLinkView(
        url: url.toString(),
        qrImage: const AssetImage(
            'assets/images/app_icon/app_icon_transparent_cropped.png'),
      ),
    );
  }
}
