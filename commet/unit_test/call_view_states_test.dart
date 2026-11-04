// The call view itself (CallWidget, as the room page and the voice room show
// it) in every state and with every set of streams a call can have, at
// desktop and phone sizes: ringing out, connected with nothing published,
// alone with the microphone, with one or two others, with someone's screen
// share or your own, and ended; plus the changes between them as the real
// session fires them (a stream arrives or goes, a share starts and stops,
// LiveKit reconnects). The call view must fill the area it is given, draw a
// tile for each stream it shows (or the ringing avatar), keep hang up
// reachable, and show a focused screen share as the big tile.
//
// No widget in call_view reads the layout style (Discord, Telegram, Custom)
// except the share quality picker, a dialog these states don't open, so the
// style is not a dimension here; the phone layout is.
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/multi_stream_focus.dart';
import 'package:commet/ui/organisms/call_view/own_stream_card.dart';
import 'package:commet/utils/animation/ripple.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

const carol = "@carol:example.com";
const callKey = ValueKey("call-area");

/// Window sizes; the last is the phone layout.
const sizes = [
  ("1014x1060", 1014.0, 1060.0, false),
  ("1600x1000", 1600.0, 1000.0, false),
  ("phone 400x860", 400.0, 860.0, true),
];

/// The streams a call can have.
enum Streams { none, ownMic, oneRemote, twoRemote, remoteShare, ownShare }

FakeVoipStream mic(String user) => FakeVoipStream(user,
    user == me ? VoipStreamDirection.outgoing : VoipStreamDirection.incoming);
FakeVoipStream share(String user, {bool audio = false}) => FakeVoipStream(user,
    user == me ? VoipStreamDirection.outgoing : VoipStreamDirection.incoming,
    type: audio ? VoipStreamType.screenshareAudio : VoipStreamType.screenshare);

/// What a LiveKit call publishes in each case: a share is its video and its
/// audio, two tracks (MatrixLivekitVoipSession.setScreenShare).
List<VoipStream> streamsOf(Streams s) => switch (s) {
      Streams.none => [],
      Streams.ownMic => [mic(me)],
      Streams.oneRemote => [mic(me), mic(remoteUser)],
      Streams.twoRemote => [mic(me), mic(remoteUser), mic(carol)],
      Streams.remoteShare => [
          mic(me),
          mic(remoteUser),
          share(remoteUser),
          share(remoteUser, audio: true)
        ],
      Streams.ownShare => [mic(me), share(me), share(me, audio: true)],
    };

/// The tiles the grid shows: never a share's audio; without stream
/// watching a sharer's voice tile gives way to their share, with it they
/// keep it (CallView.shouldShowAudioStream).
List<VoipStream> tilesOf(List<VoipStream> streams, bool watching) => streams
    .where((s) => s.type != VoipStreamType.screenshareAudio)
    .where((s) =>
        watching ||
        s.type != VoipStreamType.audio ||
        !streams.any((o) =>
            o.type == VoipStreamType.screenshare &&
            o.streamUserId == s.streamUserId))
    .toList();

/// The grid tile of [s], whichever widget draws it.
Finder tile(VoipStream s) => find.byWidgetPredicate((w) =>
    w.key == ValueKey("callView__${s.streamId}") ||
    w.key == ValueKey("ownStreamCard_${s.streamId}") ||
    w.key == ValueKey("streamTile_${s.streamId}"));

/// Every grid tile, of any stream.
final gridTiles = find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    ["callView__", "ownStreamCard_", "streamTile_"]
        .any((p) => (w.key as ValueKey<String>).value.startsWith(p)));

/// [s] shown big: for a share you watch, its controls (with the main
/// stream view inside them), else the main stream view.
Finder big(VoipStream s) => bigViews(s).first;

/// Every view showing [s] big (a watched share's controls and the view
/// inside them).
Finder bigViews(VoipStream s) => find.byWidgetPredicate((w) =>
    w.key == ValueKey("callView_mainStreamView_${s.streamId}") ||
    w.key == ValueKey("watchedStream_${s.streamId}"));

FakeVoipSession newSession(List<VoipStream> streams,
    {VoipState state = VoipState.connected, bool watching = false}) {
  final session = FakeVoipSession(roomPageClient, callRoom,
      state: state, streams: streams, roomName: "User QS");
  if (watching) VoipStreamWatching.register(session, FakeStreamWatching());
  clientManager!.callManager.currentSessions.add(session);
  return session;
}

/// The call view in a [w] x [h] window, under a 50 px room header, as the
/// room page sizes it.
Future<void> pumpCall(WidgetTester tester, FakeVoipSession session,
    {required double w, required double h, required bool phone}) async {
  if (phone) await preferences.layoutOverride.set("mobile");
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeDark.theme,
    home: Scaffold(
      body: Column(children: [
        const SizedBox(height: 50),
        Expanded(child: SizedBox(key: callKey, child: CallWidget(session))),
      ]),
    ),
  ));
  await pumpCallView(tester, session);
}

/// A few frames, with the volume poll the real session runs every 100 ms.
Future<void> pumpCallView(WidgetTester tester, FakeVoipSession session) async {
  for (var i = 0; i < 6; i++) {
    session.tickVolumes();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}

/// Nothing threw or overflowed; the call view fills its area; each of
/// [tiles] is drawn, with a size, inside it, and no other grid tile is.
void expectCallView(WidgetTester tester, FakeVoipSession session,
    {required List<VoipStream> tiles, String reason = ""}) {
  final error = tester.takeException();
  expect(error == null || error is MissingPluginException, isTrue,
      reason: "$reason: $error");
  final area = tester.getRect(find.byKey(callKey));
  final view = tester.getRect(find.byType(CallView));
  expect(view.size.width, moreOrLessEquals(area.width, epsilon: 1),
      reason: "$reason: the call view is narrower than its area");
  expect(view.size.height, moreOrLessEquals(area.height, epsilon: 1),
      reason: "$reason: the call view is shorter than its area");
  bool inside(Rect r) =>
      r.width > 0 &&
      r.height > 0 &&
      r.left >= view.left - 1 &&
      r.top >= view.top - 1 &&
      r.right <= view.right + 1 &&
      r.bottom <= view.bottom + 1;
  for (final s in session.streams) {
    final shown = tiles.contains(s);
    expect(tile(s), shown ? findsOneWidget : findsNothing,
        reason: "$reason: tile of ${s.streamId}");
    if (shown) {
      expect(inside(tester.getRect(tile(s))), isTrue,
          reason: "$reason: tile of ${s.streamId} is empty or outside the "
              "call view: ${tester.getRect(tile(s))} in $view");
    }
  }
  // A stream that left the session must not keep its tile either.
  expect(gridTiles, findsNWidgets(tiles.length),
      reason: "$reason: grid tiles other than ${tiles.map((t) => t.streamId)}");
  if (session.state == VoipState.connected ||
      session.state == VoipState.outgoing) {
    final hangUp = find.byIcon(Icons.call_end);
    expect(hangUp, findsOneWidget, reason: "$reason: no hang up");
    expect(inside(tester.getRect(hangUp)), isTrue,
        reason: "$reason: hang up is outside the call view");
  }
}

/// [s] is the big tile: drawn, and larger than every grid tile.
void expectBig(WidgetTester tester, VoipStream s, {String reason = ""}) {
  expect(big(s), findsOneWidget, reason: "$reason: ${s.streamId} not big");
  final area = tester.getRect(big(s)).size;
  for (final t in tester.widgetList(gridTiles)) {
    final r = tester.getRect(find.byWidget(t)).size;
    expect(area.width * area.height, greaterThan(r.width * r.height),
        reason: "$reason: the big ${s.streamId} is no bigger than ${t.key}");
  }
}

/// Makes [s] big the way you do it: tap its tile, or for someone's share
/// with stream watching, Watch from the sidebar (setWatching then
/// requestFocus, as StreamWatchCard and the sidebar do).
Future<void> focus(
    WidgetTester tester, FakeVoipSession session, VoipStream s) async {
  final watching = VoipStreamWatching.of(session);
  if (watching != null && s.direction == VoipStreamDirection.incoming) {
    await watching.setWatching(s, true);
    watching.requestFocus(s);
  } else {
    // The tile's own tap (the grid's ClickableGestureDetector around it,
    // CallView.generateLayout): on a phone the call buttons cover the grid
    // and an own stream card has Stop streaming in its middle, so a tap at
    // a point can land on them instead.
    final tap = tester.widget<ClickableGestureDetector>(find
        .ancestor(of: tile(s), matching: find.byType(ClickableGestureDetector))
        .first);
    tap.onTap!();
  }
  await pumpCallView(tester, session);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(roomPageSetUp);
  tearDown(roomPageTearDown);

  for (final (name, w, h, phone) in sizes) {
    for (final st in Streams.values) {
      final shares = st == Streams.remoteShare || st == Streams.ownShare;
      for (final watching in [false, if (shares) true]) {
        final label = "$name connected ${st.name}"
            "${watching ? " (stream watching)" : ""}";
        testWidgets("$label: filled, a tile per stream", (tester) async {
          final session = newSession(streamsOf(st), watching: watching);
          await pumpCall(tester, session, w: w, h: h, phone: phone);
          expectCallView(tester, session,
              tiles: tilesOf(session.streams, watching), reason: label);
          if (watching && st == Streams.ownShare) {
            expect(find.byType(OwnStreamCard), findsOneWidget);
          }
          if (shares) {
            final s = session.streams
                .firstWhere((s) => s.type == VoipStreamType.screenshare);
            await focus(tester, session, s);
            expectBig(tester, s, reason: "$label, share focused");
            expect(tile(s), findsNothing,
                reason: "$label: the big share is also a small tile");
            expectCallView(tester, session,
                tiles: tilesOf(session.streams, watching)
                    .where((t) => t != s)
                    .toList(),
                reason: "$label, share focused");
          }
          await finish(tester);
        });
      }
    }

    testWidgets("$name outgoing: the ringing avatar and hang up",
        (tester) async {
      final session = newSession([], state: VoipState.outgoing);
      await pumpCall(tester, session, w: w, h: h, phone: phone);
      expectCallView(tester, session, tiles: [], reason: "$name outgoing");
      expect(find.byType(RippleAnimation), findsOneWidget);
      await finish(tester);
    });

    testWidgets("$name ended: no tiles and no call controls", (tester) async {
      final session = newSession(streamsOf(Streams.oneRemote));
      await pumpCall(tester, session, w: w, h: h, phone: phone);
      await session.hangUpCall();
      await pumpCallView(tester, session);
      expect(tester.takeException(), isNull);
      expect(find.byType(CallView), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsNothing);
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.text("Call ended"), findsOneWidget);
      await finish(tester);
    });
  }

  // The changes between states, as the real session fires them.
  for (final (name, w, h, phone) in [sizes.first, sizes.last]) {
    testWidgets("$name nothing, then streams arrive and leave", (tester) async {
      final session = newSession([]);
      await pumpCall(tester, session, w: w, h: h, phone: phone);
      expectCallView(tester, session, tiles: [], reason: "$name empty");
      final mine = mic(me);
      session.publish(mine);
      await pumpCallView(tester, session);
      expectCallView(tester, session, tiles: [mine], reason: "$name mic");
      final bob = mic(remoteUser), c = mic(carol);
      session.publish(bob);
      session.publish(c);
      await pumpCallView(tester, session);
      expectCallView(tester, session,
          tiles: [mine, bob, c], reason: "$name joined");
      session.unpublish(bob);
      await pumpCallView(tester, session);
      expectCallView(tester, session,
          tiles: [mine, c], reason: "$name bob left");
      await finish(tester);
    });

    for (final watching in [false, true]) {
      final mode = watching ? " (stream watching)" : "";
      testWidgets("$name a remote share starts, is focused and stops$mode",
          (tester) async {
        final session =
            newSession(streamsOf(Streams.oneRemote), watching: watching);
        await pumpCall(tester, session, w: w, h: h, phone: phone);
        final before = [...session.streams];
        final s = share(remoteUser), a = share(remoteUser, audio: true);
        session.publish(s);
        session.publish(a);
        await pumpCallView(tester, session);
        expectCallView(tester, session,
            tiles: tilesOf(session.streams, watching), reason: "$name shared");
        await focus(tester, session, s);
        expectBig(tester, s, reason: "$name focused");
        session.unpublish(s);
        session.unpublish(a);
        await pumpCallView(tester, session);
        expect(bigViews(s), findsNothing,
            reason: "$name: a stopped share stays big");
        expectCallView(tester, session, tiles: before, reason: "$name stopped");
        await finish(tester);
      });

      testWidgets("$name own share starts and stops$mode", (tester) async {
        final session =
            newSession(streamsOf(Streams.oneRemote), watching: watching);
        await pumpCall(tester, session, w: w, h: h, phone: phone);
        final before = [...session.streams];
        session.startScreenshare();
        await pumpCallView(tester, session);
        expectCallView(tester, session,
            tiles: tilesOf(session.streams, watching), reason: "$name sharing");
        expect(find.byType(OwnStreamCard),
            watching ? findsOneWidget : findsNothing);
        await session.stopScreenshare();
        await pumpCallView(tester, session);
        expect(find.byType(OwnStreamCard), findsNothing);
        expectCallView(tester, session, tiles: before, reason: "$name stopped");
        await finish(tester);
      });
    }

    testWidgets("$name reconnecting keeps the tiles and the big share",
        (tester) async {
      final session = newSession(streamsOf(Streams.remoteShare));
      await pumpCall(tester, session, w: w, h: h, phone: phone);
      final s = session.streams
          .firstWhere((s) => s.type == VoipStreamType.screenshare);
      await focus(tester, session, s);
      final tiles = tilesOf(session.streams, false).where((t) => t != s);
      session.reconnect();
      await pumpCallView(tester, session);
      expect(session.state, VoipState.connected);
      expectBig(tester, s, reason: "$name reconnected");
      expectCallView(tester, session,
          tiles: tiles.toList(), reason: "$name reconnected");
      await finish(tester);
    });

    testWidgets("$name two shares watched: side by side, then one stops",
        (tester) async {
      final session = newSession([
        mic(me),
        mic(remoteUser),
        mic(carol),
        share(remoteUser),
        share(carol)
      ], watching: true);
      await pumpCall(tester, session, w: w, h: h, phone: phone);
      final bobShare = session.streams[3], carolShare = session.streams[4];
      await focus(tester, session, bobShare);
      await focus(tester, session, carolShare);
      expect(find.byType(MultiStreamLayout), findsOneWidget,
          reason: "$name: two watched shares are not side by side");
      expect(big(bobShare), findsOneWidget);
      expect(big(carolShare), findsOneWidget);
      expectCallView(tester, session,
          tiles: [session.streams[0], session.streams[1], session.streams[2]],
          reason: "$name side by side");
      session.unpublish(carolShare);
      await pumpCallView(tester, session);
      expect(find.byType(MultiStreamLayout), findsNothing);
      expectBig(tester, bobShare, reason: "$name one left");
      await finish(tester);
    });
  }
}
