// Desktop notifications right after signing in, without restarting the app.
//
// MatrixRoom.shouldNotify stays quiet until the account's first sync is in
// (so the catch-up after a start doesn't notify). That flag used to be set
// only when a saved session was loaded at start, so after a fresh sign-in
// every message was dropped until the app restarted. The app (user 1) signs
// in fresh; user 2, on its own client, messages it in a new room; the
// message must pass shouldNotify.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("NOTIFY-SIGN-IN $s");
}

void main() {
  testWidgets("notifications work right after a fresh sign-in", (tester) async {
    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);

    final client = app.clientManager.clients[0] as MatrixClient;
    final mx = client.getMatrixClient();
    await tester.waitFor(() => client.firstSyncComplete,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    expect(client.firstSync, isNotNull,
        reason: "a fresh sign-in tracks its first sync too");

    final other = await tester.createTestClient(
        user: tester.userTwoName, password: tester.userTwoPassword);
    addTearDown(() => other.dispose(closeDatabase: true));
    await other.oneShotSync();
    final roomId = await other.createRoom(
        name: "Notify after sign-in",
        invite: [mx.userID!],
        preset: matrix.CreateRoomPreset.privateChat);
    await tester.waitFor(() => mx.getRoomById(roomId) != null,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    await mx.joinRoom(roomId);
    await tester.waitFor(() => client.getRoom(roomId) != null,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    final room = client.getRoom(roomId)! as MatrixRoom;

    final notified = <matrix.Event>[];
    final sub = mx.onNotification.stream
        .where((e) => e.roomId == roomId)
        .listen(notified.add);
    addTearDown(sub.cancel);

    await tester.waitFor(() => other.getRoomById(roomId) != null,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
    await other.getRoomById(roomId)!.sendTextEvent("ping after sign-in");
    await tester.waitFor(() => notified.isNotEmpty,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);

    final reasons = <String>[];
    final notify = room.shouldNotify(room.convertEvent(notified.first),
        onNotificationRejected: reasons.add);
    _log("firstSyncComplete=${client.firstSyncComplete} "
        "shouldNotify=$notify rejected=$reasons");
    expect(notify, true,
        reason: "a message right after signing in notifies ($reasons)");
    await app.clientManager.close();
  });
}
