import 'dart:async';

import 'package:dbus/dbus.dart';

/// Whether KDE Plasma is logging out, restarting or shutting down.
///
/// Plasma asks every Wayland window to close before it ends the session and
/// waits for them for up to two minutes, so this is how a close request from
/// a logout is told apart from the user closing the window. ksmserver keeps
/// reporting true until the logout finishes or is cancelled. False on other
/// desktops, and when the answer doesn't come quickly. [bus] replaces the
/// session bus (tests); it is left open.
Future<bool> kdeSessionIsEnding({DBusClient? bus}) async {
  final client = bus ?? DBusClient.session();
  try {
    final reply = await client
        .callMethod(
          destination: "org.kde.ksmserver",
          path: DBusObjectPath("/KSMServer"),
          interface: "org.kde.KSMServerInterface",
          name: "isShuttingDown",
          replySignature: DBusSignature("b"),
          noAutoStart: true,
        )
        .timeout(const Duration(milliseconds: 500));
    return reply.returnValues.first.asBoolean();
  } catch (_) {
    return false;
  } finally {
    if (bus == null) unawaited(client.close());
  }
}
