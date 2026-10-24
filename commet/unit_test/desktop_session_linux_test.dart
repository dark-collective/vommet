import 'dart:io';

import 'package:commet/utils/desktop_session_linux.dart';
import 'package:dbus/dbus.dart';
import 'package:test/test.dart';

class _FakeKsmServer extends DBusObject {
  _FakeKsmServer(this.shuttingDown) : super(DBusObjectPath("/KSMServer"));

  final bool shuttingDown;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == "org.kde.KSMServerInterface" &&
        methodCall.name == "isShuttingDown") {
      return DBusMethodSuccessResponse([DBusBoolean(shuttingDown)]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

void main() {
  late DBusServer server;
  late DBusClient app;
  final desktops = <DBusClient>[];

  setUp(() async {
    server = DBusServer();
    final address =
        await server.listenAddress(DBusAddress.unix(dir: Directory.systemTemp));
    app = DBusClient(address);
    desktops.add(DBusClient(address));
  });

  tearDown(() async {
    await app.close();
    for (final c in desktops) {
      await c.close();
    }
    desktops.clear();
    await server.close();
  });

  Future<void> runKsmServer(bool shuttingDown) async {
    final desktop = desktops.first;
    await desktop.requestName("org.kde.ksmserver");
    await desktop.registerObject(_FakeKsmServer(shuttingDown));
  }

  test("true while Plasma is logging out", () async {
    await runKsmServer(true);
    expect(await kdeSessionIsEnding(bus: app), isTrue);
  });

  test("false while Plasma is running normally", () async {
    await runKsmServer(false);
    expect(await kdeSessionIsEnding(bus: app), isFalse);
  });

  test("false on desktops without ksmserver", () async {
    expect(await kdeSessionIsEnding(bus: app), isFalse);
  });
}
