// Vommet issue 1224: drive the fullscreen controls with CallWidget's real
// action bridge. Only the SDK/session and OS window channel are faked.
import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
import 'package:commet/ui/organisms/call_view/vommet_call_view_streams.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

class _Session extends FakeVoipSession {
  _Session(super.client, super.roomId, {super.streams});

  int hangups = 0;

  @override
  Future<void> hangUpCall() async {
    hangups++;
    await super.hangUpCall();
  }
}

class _Watching extends FakeStreamWatching {
  final stops = <VoipStream>[];
  Completer<void>? stopGate;

  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {
    if (!watching) stops.add(stream);
    await super.setWatching(stream, watching);
    if (!watching) await stopGate?.future;
  }
}

// Locate the real red control by its existing surface, on both exact base
// and fixed code. A missing newly introduced key cannot be our red proof.
Finder redAction() => find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is Material && w.color == const Color(0xff8c1d18),
      ),
      matching: find.byType(InkWell),
    );

Finder fullscreen() => find.byType(StreamFullscreenView);

const custom = LayoutOptions(
  oneChatList: true,
  captionBelow: false,
  limitWidth: false,
  bubbles: false,
  ownSide: OwnBubbleSide.left,
  avatarAtBottom: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('FlutterWebRTC.Event'), (_) async => null);
    await roomPageSetUp();
  });
  tearDown(() async {
    StreamMiniPlayer.instance.hide();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    await roomPageTearDown();
  });

  late _Session session;
  late _Watching watching;
  late FakeVoipStream share;

  Future<void> pumpCall(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    LayoutOptions layout = LayoutOptions.discord,
    bool ownShare = false,
  }) async {
    await layout.save();
    await preferences.layoutOverride.set(
      size.width < 700 ? 'mobile' : 'desktop',
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isFullScreen' ? false : null,
    );
    share = FakeVoipStream(
      remoteUser,
      VoipStreamDirection.incoming,
      type: VoipStreamType.screenshare,
    );
    session = _Session(
      roomPageClient,
      callRoom,
      streams: [
        FakeVoipStream(me, VoipStreamDirection.outgoing),
        FakeVoipStream(remoteUser, VoipStreamDirection.incoming),
        share,
        FakeVoipStream(
          remoteUser,
          VoipStreamDirection.incoming,
          type: VoipStreamType.screenshareAudio,
        ),
      ],
    );
    if (ownShare) session.startScreenshare();
    watching = _Watching();
    VoipStreamWatching.register(session, watching);
    clientManager!.callManager.currentSessions.add(session);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: CallWidget(session)),
      ),
    );
    await watching.setWatching(share, true);
    watching.requestFocus(share);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> open(WidgetTester tester, {VoipStream? stream}) async {
    // The same bridge used by the call's fullscreen button, preserving the
    // actual CallWidget -> session callbacks rather than invented actions.
    final view = tester.widget<CallView>(find.byType(CallView));
    expect(
      vommetOpenFullscreen(
        view,
        stream ?? share,
        tester.element(find.byType(CallView)),
      ),
      isTrue,
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fullscreen(), findsOneWidget);
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.tap(redAction());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(session.hangups, 0, reason: 'Stop watching must never call hangUp');
    expect(session.state, VoipState.connected);
    expect(watching.isWatching(share), isFalse);
    expect(fullscreen(), findsNothing);
    expect(find.byType(CallWidget), findsOneWidget);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(tester.takeException(), isNull);
  }

  for (final layout in [
    ('Discord', LayoutOptions.discord),
    ('Telegram', LayoutOptions.telegram),
    ('Custom mix', custom),
  ]) {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      testWidgets(
        '${layout.$1} $size: stop returns; next call action hangs up',
        (tester) async {
          await pumpCall(tester, size: size, layout: layout.$2);
          await open(tester);
          await stop(tester);
          expect(watching.stops, [share]);
          expect(clientManager!.callManager.currentSessions, contains(session));
          expect(
            session.streams.where((s) => s.type == VoipStreamType.audio),
            hasLength(2),
          );
          expect(
            watching.isWatching(session.streams.last),
            isFalse,
            reason: 'the stopped share audio belongs to the same participant',
          );
          expect(
            find.byKey(ValueKey('watchedStream_${share.streamId}')),
            findsNothing,
            reason: 'stopped share is no longer large',
          );
          expect(
            find.byKey(ValueKey('streamTile_${share.streamId}')),
            findsOneWidget,
          );
          // A separate real call control after fullscreen has gone, with its
          // original CallWidget callback and session ownership.
          await tester.tap(find.byIcon(Icons.call_end));
          await tester.pump();
          expect(session.hangups, 1);
          expect(session.state, VoipState.ended);
          await finish(tester);
        },
      );
    }
  }

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets(
      'red X semantics and visible keyboard focus: ${key.keyLabel}',
      (tester) async {
        await pumpCall(tester);
        await open(tester);
        final semantics = tester.ensureSemantics();
        expect(
          find.descendant(of: redAction(), matching: find.byIcon(Icons.close)),
          findsOneWidget,
        );
        expect(
          find.byTooltip(CallControlStrings.callControlLeaveCall),
          findsNothing,
        );
        expect(tester.getSemantics(redAction()).label, 'Stop watching');
        final focus = Focus.of(tester.element(find
            .descendant(of: redAction(), matching: find.byType(MouseRegion))
            .first));
        for (var i = 0; i < 12 && !focus.hasPrimaryFocus; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focus.hasPrimaryFocus, isTrue);
        await tester.pump(const Duration(seconds: 6));
        final overlay = find.ancestor(
            of: redAction(), matching: find.byType(AnimatedOpacity));
        expect(tester.widget<AnimatedOpacity>(overlay).opacity, 1);
        await tester.sendKeyEvent(key);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(session.hangups, 0);
        expect(watching.stops, [share]);
        expect(fullscreen(), findsNothing);
        semantics.dispose();
        await finish(tester);
      },
    );
  }

  testWidgets(
    'duplicate red/top activation closes one route while stop is pending',
    (tester) async {
      await pumpCall(tester);
      await open(tester);
      watching.stopGate = Completer<void>();
      final activate = tester.widget<InkWell>(redAction()).onTap!;
      // Deliver repeated activation before the route transition disposes its
      // controls. Both entry points still use the actual route callback.
      activate();
      activate();
      final top = find.text('Stop watching');
      final topInk = find.ancestor(of: top, matching: find.byType(InkWell));
      tester.widget<InkWell>(topInk).onTap?.call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(session.hangups, 0);
      expect(watching.stops, [share]);
      expect(fullscreen(), findsNothing);
      expect(find.byType(CallWidget), findsOneWidget);
      watching.stopGate!.complete();
      await tester.pump();
      await finish(tester);
    },
  );

  testWidgets('stopping remote preserves own share, mic, deafen and camera', (
    tester,
  ) async {
    await pumpCall(tester, ownShare: true);
    await session.setMicrophoneMute(true);
    await session.setCamera(null);
    clientManager!.callManager.toggleDeafenIn(session);
    await tester.pump();
    await open(tester);
    await stop(tester);
    expect(session.isSharingScreen, isTrue);
    expect(session.isMicrophoneMuted, isTrue);
    expect(session.isCameraEnabled, isTrue);
    expect(clientManager!.callManager.isDeafenedIn(session), isTrue);
    final own = session.streams.firstWhere(
      (s) =>
          s.direction == VoipStreamDirection.outgoing &&
          s.type == VoipStreamType.screenshare,
    );
    await open(tester, stream: own);
    expect(
      find.byTooltip(CallControlStrings.callControlLeaveCall),
      findsOneWidget,
      reason: 'own-share behavior was not approved to change',
    );
    await tester.tap(redAction());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(session.hangups, 1);
    expect(watching.stops, [share]);
    await finish(tester);
  });

  testWidgets('stream gone during exit and disposal cannot pop another route', (
    tester,
  ) async {
    await pumpCall(tester, size: const Size(390, 844));
    final other = FakeVoipStream(
      '@carol:example.com',
      VoipStreamDirection.incoming,
      type: VoipStreamType.screenshare,
    );
    session.publish(other);
    await watching.setWatching(other, true);
    await open(tester);
    final activate = tester.widget<InkWell>(redAction()).onTap!;
    activate();
    session.unpublish(share);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(session.hangups, 0);
    expect(watching.stops, [share]);
    expect(watching.isWatching(other), isTrue);
    expect(find.byType(CallWidget), findsOneWidget);
    expect(fullscreen(), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.reconnect();
    await watching.setWatching(other, false);
    await tester.pump(const Duration(minutes: 2));
    expect(session.hangups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 px fullscreen stop and stream removal keep the call',
      (tester) async {
    await pumpCall(tester, size: const Size(320, 740));
    await open(tester);
    tester.widget<InkWell>(redAction()).onTap!();
    session.unpublish(share);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(session.hangups, 0);
    expect(watching.stops, [share]);
    expect(find.byType(CallWidget), findsOneWidget);
    expect(fullscreen(), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'after stop, Escape and camera fullscreen keep their original meaning',
    (tester) async {
      await pumpCall(tester);
      await open(tester);
      await stop(tester);
      await watching.setWatching(share, true);
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(watching.isWatching(share), isTrue);
      expect(session.hangups, 0);
      final camera = FakeVoipStream(
        remoteUser,
        VoipStreamDirection.incoming,
        type: VoipStreamType.video,
      );
      session.publish(camera);
      await tester.pump();
      await open(tester, stream: camera);
      expect(
        find.byTooltip(CallControlStrings.callControlLeaveCall),
        findsOneWidget,
      );
      await tester.tap(redAction());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(session.hangups, 1);
      expect(watching.stops, [share]);
      await finish(tester);
    },
  );
}
