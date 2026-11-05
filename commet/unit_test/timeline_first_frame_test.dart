// Vommet issue 919: a room opened under a route that was not laid out yet
// kept its timeline offstage (blank) until the room was reopened.
import 'dart:math';

import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/timeline.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const a = "!a:example.com";

matrix.MatrixEvent message(String id, int n) => matrix.MatrixEvent(
      type: matrix.EventTypes.Message,
      content: {"msgtype": "m.text", "body": "body $id"},
      senderId: "@bob:example.com",
      eventId: id,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1700000100000 + n),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late Timeline timeline;
  var n = 0;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("timeline-first-frame-${n++}");
    await sync(
      client,
      join: {
        a: matrix.JoinedRoomUpdate(
          state: roomState(a),
          timeline: matrix.TimelineUpdate(
            events: [message(r"$e1", 1), message(r"$e2", 2)],
            prevBatch: "p",
          ),
        ),
      },
    );
    timeline = await client.getRoom(a)!.getTimeline();
  });

  tearDown(() async {
    await timeline.close();
    await client.getMatrixClient().dispose(closeDatabase: true);
  });

  final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

  Widget app(Widget body) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: SizedBox.expand(child: body)),
      );

  bool retryLogged() => Log.log.any(
        (e) => e.rawContent.contains(
          "Timeline view not laid out after its first frame",
        ),
      );

  testWidgets("a timeline first laid out frames later still shows", (
    tester,
  ) async {
    // Like a route still offstage: an opaque entry above keeps the view's
    // entry built (so its first-frame callback runs) but not laid out.
    final cover = OverlayEntry(opaque: true, builder: (_) => const SizedBox());
    final overlayKey = GlobalKey<OverlayState>();
    await tester.pumpWidget(
      app(
        Overlay(
          key: overlayKey,
          initialEntries: [
            OverlayEntry(
              maintainState: true,
              builder: (_) =>
                  RoomTimelineWidgetView(key: viewKey, timeline: timeline),
            ),
            cover,
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(viewKey.currentState!.firstFrame, isTrue);
    expect(retryLogged(), isTrue);

    cover.remove();
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(viewKey.currentState!.firstFrame, isFalse);
    expect(find.text("body \$e2"), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The SDK's member lookups leave a one-minute timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets("a timeline covered past the retry cap shows and restores", (
    tester,
  ) async {
    Log.log.clear();
    final cover = OverlayEntry(opaque: true, builder: (_) => const SizedBox());
    await tester.pumpWidget(
      app(
        Overlay(
          initialEntries: [
            OverlayEntry(
              maintainState: true,
              builder: (_) =>
                  RoomTimelineWidgetView(key: viewKey, timeline: timeline),
            ),
            cover,
          ],
        ),
      ),
    );
    // A saved position (issue 634) must survive the fallback.
    viewKey.currentState!.restoreOffset = -10;
    for (var i = 0;
        i < RoomTimelineWidgetViewState.maxFirstFrameRetries + 2;
        i++) {
      await tester.pump();
    }
    expect(viewKey.currentState!.firstFrame, isFalse);
    expect(
      Log.log.any(
        (e) => e.rawContent.contains("still not laid out after 10 frames"),
      ),
      isTrue,
    );
    expect(viewKey.currentState!.restoreOffset, -10);

    cover.remove();
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    final state = viewKey.currentState!;
    expect(find.text("body \$e2"), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(state.restoreOffset, isNull);
    expect(
      state.controller.offset,
      max(state.controller.position.minScrollExtent, -10),
    );

    // The SDK's member lookups leave a one-minute timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets("a timeline laid out at once shows after one frame", (
    tester,
  ) async {
    Log.log.clear();
    await tester.pumpWidget(
      app(RoomTimelineWidgetView(key: viewKey, timeline: timeline)),
    );
    // pumpWidget's frame runs the first-frame callback.
    expect(viewKey.currentState!.firstFrame, isFalse);
    await tester.pump();
    expect(find.text("body \$e2"), findsOneWidget);
    expect(retryLogged(), isFalse);

    // The SDK's member lookups leave a one-minute timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  });
}
