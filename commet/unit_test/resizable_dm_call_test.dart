// Vommet issue 1211: real room/call path with fakes at the SDK boundary.
import 'dart:ui' show PointerDeviceKind, SemanticsAction;

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/call_timer_text.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'fixtures/popout_fixtures.dart' show FakePopoutBackend;
import 'roomlist_fixture.dart';
import 'support/fake_voip_session.dart';
import 'support/room_page_fixtures.dart';

final divider = find.byKey(const ValueKey('dm-call-resize'));
final collapse = find.byTooltip('Collapse call panel');
final restore = find.byTooltip('Expand call panel');

Future<FakeVoipSession> pumpDm(WidgetTester t,
    {double width = 1014, double height = 1060}) async {
  final room = roomPageClient.getRoom(callRoom)!;
  final session = startCall(room, CallCase.remote);
  addTearDown(() => finishRoomPage(t));
  await pumpRoomPage(t, room, width: width, height: height);
  return session;
}

Future<void> dragDivider(WidgetTester t, double delta) async {
  final gesture = await t.startGesture(t.getCenter(divider));
  await gesture.moveBy(Offset(0, delta.isNegative ? -20 : 20));
  await t.pump();
  await gesture.moveBy(Offset(0, delta));
  await t.pump();
  await gesture.up();
  await settle(t);
}

void expectSafe(WidgetTester t) {
  expect(t.takeException(), isNull);
  final chat = t.getRect(find.byType(Chat));
  expect(chat.bottom, t.getRect(find.byKey(roomViewKey)).bottom);
  expect(t.getRect(find.byType(MessageInput).first).bottom,
      lessThanOrEqualTo(chat.bottom));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(roomPageSetUp);
  tearDown(roomPageTearDown);
  const linux = TargetPlatformVariant({TargetPlatform.linux});
  for (final style in LayoutStyle.values) {
    testWidgets('${style.name}: drag gives chat space, bar keeps essentials',
        (t) async {
      await pickLayoutStyle(style);
      final session = await pumpDm(t);
      final chatBefore = t.getSize(find.byType(Chat)).height;
      final state = t.state(find.byType(CallWidget));
      await dragDivider(t, -220);
      expect(t.getSize(find.byType(Chat)).height, greaterThan(chatBefore));
      expect(find.byType(CompactCallStrip), findsNothing);
      await dragDivider(t, -400);
      expect(find.byType(CompactCallStrip), findsOneWidget);
      expect(find.byType(CallTimerText), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(CompactCallStrip),
              matching: find.byType(tiamat.Avatar)),
          findsNWidgets(2));
      expect(
          t.state(find.byType(CallWidget, skipOffstage: false)), same(state));
      expect(session.state, VoipState.connected);
      expect(session.streams, hasLength(2));
      expect(t.getSize(find.byType(CompactCallStrip)).height, 52);
      final bar = t.getRect(find.byType(CompactCallStrip));
      final chat = t.getRect(find.byType(Chat));
      expect(bar.left, chat.left);
      expect(bar.right, chat.right);
      expectSafe(t);
      await t.tap(restore);
      await settle(t);
      expect(find.byType(CompactCallStrip), findsNothing);
      expect(t.getSize(find.byType(Chat)).height, greaterThan(chatBefore));
      await finishRoomPage(t);
    }, variant: linux);
  }
  testWidgets('hysteresis, keyboard and semantic actions', (t) async {
    await pumpDm(t);
    await dragDivider(t, -180);
    await t.tap(collapse);
    await settle(t);
    final g = await t.startGesture(t.getCenter(divider));
    await g.moveBy(const Offset(0, 20));
    await t.pump();
    await g.moveBy(const Offset(0, 65));
    await t.pump();
    expect(find.byType(CompactCallStrip), findsOneWidget);
    await g.moveBy(const Offset(0, 30));
    await t.pump();
    expect(find.byType(CompactCallStrip), findsNothing);
    await g.moveBy(const Offset(0, -15));
    await t.pump();
    expect(find.byType(CompactCallStrip), findsNothing);
    await g.moveBy(const Offset(0, -40));
    await t.pump();
    expect(find.byType(CompactCallStrip), findsOneWidget);
    await g.up();
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.home);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsNothing);
    final before = t.getSize(find.byType(Chat)).height;
    t.semantics.performAction(
        find.semantics.byLabel('Resize call panel'), SemanticsAction.increase);
    await settle(t);
    expect(t.getSize(find.byType(Chat)).height, lessThan(before));
    t.semantics.performAction(
        find.semantics.byLabel('Resize call panel'), SemanticsAction.decrease);
    await settle(t);
    expect(t.getSize(find.byType(Chat)).height, before);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('collapse keeps watching; mute and hang up use live session',
      (t) async {
    final session = await pumpDm(t);
    final watching = FakeStreamWatching();
    VoipStreamWatching.register(session, watching);
    final share = FakeVoipStream(remoteUser, VoipStreamDirection.incoming,
        type: VoipStreamType.screenshare);
    session.publish(share);
    await watching.setWatching(share, true);
    watching.requestFocus(share);
    await settle(t);
    final backend = FakePopoutBackend();
    final windows = StreamPopoutWindow(backend, afterFrame: () async {});
    addTearDown(() async {
      session.end();
      windows.dispose();
      await backend.changes.close();
    });
    await windows.open(session, share);
    final state = t.state(find.byType(CallWidget));
    await t.tap(collapse);
    await settle(t);
    expect(windows.isShowing(session, share), isTrue);
    expect(backend.live, {1});
    expect(watching.isWatching(share), isTrue);
    expect(t.state(find.byType(CallWidget, skipOffstage: false)), same(state));
    expect(session.streams, contains(share));
    Finder inStrip(Finder finder) =>
        find.descendant(of: find.byType(CompactCallStrip), matching: finder);
    await t.tap(inStrip(find.byIcon(Icons.mic)));
    await settle(t);
    expect(session.isMicrophoneMuted, isTrue);
    expect(inStrip(find.byIcon(Icons.mic_off)), findsOneWidget);
    await t.tap(inStrip(find.byIcon(Icons.call_end)));
    await settle(t);
    expect(session.state, VoipState.ended);
    expect(clientManager!.callManager.currentSessions, isEmpty);
    expect(divider, findsNothing);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('same-call memory survives navigation; a new call resets',
      (t) async {
    final session = await pumpDm(t);
    await t.tap(collapse);
    await settle(t);
    await pumpRoomPage(t, roomPageClient.getRoom(emptyRoom)!,
        width: 1014, height: 1060);
    await pumpRoomPage(t, roomPageClient.getRoom(callRoom)!,
        width: 1014, height: 1060);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    session.end();
    await settle(t);
    await pumpDm(t);
    expect(find.byType(CompactCallStrip), findsNothing);
    expect(collapse, findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('stream arrivals, narrow large text and short windows',
      (t) async {
    final session = await pumpDm(t, width: 420, height: 600);
    await t.tap(collapse);
    await settle(t);
    await t.tap(restore);
    await settle(t);
    for (final stream in [...session.streams]) {
      session.unpublish(stream);
    }
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    session.publish(FakeVoipStream(me, VoipStreamDirection.outgoing));
    await settle(t);
    expect(find.byType(CompactCallStrip), findsNothing);
    t.view.physicalSize = const Size(320, 340);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(t);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('push to talk stays available in the compact desktop bar',
      (t) async {
    final session = await pumpDm(t);
    await preferences.voipPushToTalk.set(true);
    await t.tap(collapse);
    await settle(t);
    expect(find.byType(TalkButton), findsOneWidget);
    expect(t.getSize(find.byType(TalkButton)), const Size(48, 48));
    final hold = await t.startGesture(t.getCenter(find.byType(TalkButton)));
    await settle(t);
    expect(clientManager!.callManager.isTalkingIn(session), isTrue);
    await hold.up();
    await settle(t);
    expect(clientManager!.callManager.isTalkingIn(session), isFalse);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('m.direct DM without a legacy remote ID also resizes', (t) async {
    addTearDown(() => finishRoomPage(t));
    await t.runAsync(() => sync(roomPageClient, accountData: [
          directChats({
            remoteUser: [callRoom]
          })
        ]));
    final session = FakeVoipSession(roomPageClient, callRoom);
    clientManager!.callManager.currentSessions.add(session);
    await pumpRoomPage(t, roomPageClient.getRoom(callRoom)!,
        width: 1014, height: 800);
    expect(divider, findsOneWidget);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(CompactCallStrip),
            matching: find.byType(tiamat.Avatar)),
        findsNWidgets(2));
    session.publish(FakeVoipStream(me, VoipStreamDirection.outgoing));
    await settle(t);
    expect(collapse, findsOneWidget);
    await t.tap(collapse);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
  testWidgets('Windows widget platform: canceled drag and window resize',
      (t) async {
    await pumpDm(t);
    expect(Theme.of(t.element(divider)).platform, TargetPlatform.windows);
    final gesture = await t.startGesture(t.getCenter(divider),
        kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, -100));
    await t.pump();
    t.view.physicalSize = const Size(420, 340);
    await settle(t);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    await gesture.moveBy(const Offset(0, 20));
    await gesture.cancel();
    await settle(t);
    expectSafe(t);
    t.view.physicalSize = const Size(1014, 1060);
    await settle(t);
    if (restore.evaluate().isNotEmpty) {
      await t.tap(restore);
      await settle(t);
    }
    await dragDivider(t, -700);
    expect(find.byType(CompactCallStrip), findsOneWidget);
    await t.tap(restore);
    await settle(t);
    expect(collapse, findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('ringing keeps the call view without resize controls', (t) async {
    final room = roomPageClient.getRoom(callRoom)!;
    final ringing = FakeVoipSession(roomPageClient, callRoom,
        state: VoipState.outgoing, remoteUserId: remoteUser);
    clientManager!.callManager.currentSessions.add(ringing);
    addTearDown(() => finishRoomPage(t));
    await pumpRoomPage(t, room, width: 1014, height: 800);
    expect(find.byType(CallWidget), findsOneWidget);
    expect(divider, findsNothing);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);

  testWidgets('connected strip disables expand without video or voice tiles',
      (t) async {
    final room = roomPageClient.getRoom(callRoom)!;
    final session = FakeVoipSession(roomPageClient, callRoom,
        state: VoipState.outgoing, remoteUserId: remoteUser);
    clientManager!.callManager.currentSessions.add(session);
    addTearDown(() => finishRoomPage(t));
    await pumpRoomPage(t, room, width: 1014, height: 800);
    final viewState = t.state(find.byType(CallWidget));
    session.publish(FakeVoipStream(remoteUser, VoipStreamDirection.incoming,
        type: VoipStreamType.screenshareAudio));
    session.setState(VoipState.connected);
    await settle(t);
    expect(
        t.state(find.byType(CallWidget, skipOffstage: false)), same(viewState));
    final expandButton = find.descendant(
        of: find.byType(CompactCallStrip),
        matching: find.widgetWithIcon(IconButton, Icons.expand_more));
    expect(t.widget<IconButton>(expandButton).onPressed, isNull);
    final label = find.bySemanticsLabel('Resize call panel');
    expect(
        t
            .getSemantics(label)
            .getSemanticsData()
            .hasAction(SemanticsAction.increase),
        isFalse);
    t.semantics.performAction(
        find.semantics.byLabel('Resize call panel'), SemanticsAction.increase,
        checkForAction: false);
    Focus.of(t.element(divider)).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.end);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(t);
    expect(t.widget<IconButton>(expandButton).onPressed, isNull);
    session.publish(FakeVoipStream(remoteUser, VoipStreamDirection.incoming));
    await settle(t);
    expect(collapse, findsOneWidget);
    // Disabled expand actions must leave the initial half-height split intact.
    expect(t.getSize(find.byType(CallWidget)).height, greaterThan(300));
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);

  testWidgets('compact session replacement routes actions to the new call',
      (t) async {
    final first = await pumpDm(t);
    expect(Theme.of(t.element(divider)).platform, TargetPlatform.linux);
    await t.tap(collapse);
    await settle(t);
    final oldStrip = t.state(find.byType(CompactCallStrip));
    final replacement =
        FakeVoipSession(roomPageClient, callRoom, remoteUserId: remoteUser);
    clientManager!.callManager.currentSessions
      ..clear()
      ..add(replacement);
    await settle(t);
    expect(t.state(find.byType(CompactCallStrip)), isNot(same(oldStrip)));
    await t.tap(find.descendant(
        of: find.byType(CompactCallStrip), matching: find.byIcon(Icons.mic)));
    await settle(t);
    expect(replacement.isMicrophoneMuted, isTrue);
    expect(first.isMicrophoneMuted, isFalse);
    expectSafe(t);
    await finishRoomPage(t);
  }, variant: linux);
}
