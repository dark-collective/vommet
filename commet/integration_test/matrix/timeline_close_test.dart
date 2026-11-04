// A room's timeline closes when its chat closes (follow-up to missed
// messages after a server outage, 2026-11-02).
//
// The chat only ended its visit, so every room opened in a run kept its SDK
// timeline and its sliding sync room subscription, and after a long pause
// the SDK checked those rooms for gaps as if they were on screen. The app
// opens 10 rooms one after another through the UI; afterwards only the
// room on screen may have a live timeline (Telemetry.timelinesLive, the
// "timelines_live" field) and count as open for the long-pause check.

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../extensions/common_flows.dart';
import '../extensions/wait_for.dart';

void _log(String s) {
  // ignore: avoid_print
  print("TLCLOSE $s");
}

Future<void> _run(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    await Future.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets("timeline close: leaving rooms closes their timelines", (
    tester,
  ) async {
    final app = await tester.setupApp();
    await tester.pumpWidget(app);
    await tester.login(app);
    await tester.pumpAndSettle();
    final client = app.clientManager.clients[0] as MatrixClient;
    final mx = client.getMatrixClient();
    await tester.waitFor(() => client.firstSyncComplete,
        timeout: const Duration(seconds: 30), skipPumpAndSettle: true);

    final run = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rooms = <String>[];
    for (var i = 0; i < 11; i++) {
      final id = await mx.createRoom(name: "Timeline close $i $run");
      await tester.waitFor(() => client.getRoom(id) != null,
          timeout: const Duration(seconds: 30), skipPumpAndSettle: true);
      await mx.getRoomById(id)!.sendTextEvent("hello $i");
      rooms.add(id);
    }
    final baseline = Telemetry.timelinesLive;
    final gaps = mx.slidingSyncController.gaps;

    Future<int> open(String id) async {
      final clock = Stopwatch()..start();
      // As utd_vanish_test opens rooms: again until the chat shows it.
      for (var attempt = 0; client.getRoom(id)!.timeline == null; attempt++) {
        if (attempt == 20) throw StateError("$id never opened");
        EventBus.doOpenRoom(id, clientId: client.identifier);
        await _run(tester, const Duration(seconds: 1));
      }
      final ms = clock.elapsedMilliseconds;
      // Let the previous chat's dispose run.
      await _run(tester, const Duration(milliseconds: 500));
      return ms;
    }

    for (final id in rooms) {
      await open(id);
    }
    final live = Telemetry.timelinesLive;
    final withTimeline =
        rooms.where((id) => client.getRoom(id)!.timeline != null).toList();
    final checked = rooms.where(gaps.isOpen).toList();
    _log("timelines_live before=$baseline after 11 rooms=$live; "
        "with a timeline=${withTimeline.length} open for checks="
        "${checked.length}");
    expect(withTimeline, [rooms.last],
        reason: "only the room on screen keeps its timeline");
    expect(checked, [rooms.last],
        reason: "a long pause checks only the room on screen");
    expect(live - baseline, lessThanOrEqualTo(1));

    // Opening a room again still works, from the stored events.
    final ms = await open(rooms.first);
    _log("reopened the first room in $ms ms; "
        "timelines_live=${Telemetry.timelinesLive}");
    expect(rooms.where(gaps.isOpen).toList(), [rooms.first]);
  });
}
