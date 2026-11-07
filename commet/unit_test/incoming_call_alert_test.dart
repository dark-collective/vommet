// Vommet issue 1098: real manager/list and root card; fakes at SDK boundary.
import 'dart:async';

import 'package:commet/client/call_manager.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_invite.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/incoming_call_alert.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

import 'support/incoming_call_fixtures.dart';

void testAlert(String description, WidgetTesterCallback body) {
  testWidgets(description, (t) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  late AlertClients clients;
  late CallManager calls;
  late AlertClient account;
  late List<NotificationContent> notices;
  late List<RoomOpenArgs> opened;
  late StreamSubscription opening;
  ClientManager? previousManager;
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await AppSounds.setNone(SoundEvent.ringIncoming);
    clients = AlertClients();
    account = AlertClient('@lee:example.org');
    clients.clients.add(account);
    calls = CallManager(clients)..playSounds = false;
    clients.callManager = calls;
    previousManager = clientManager;
    clientManager = clients;
    notices = [];
    // ignore: invalid_use_of_visible_for_testing_member
    NotificationManager.debugOnNotify = notices.add;
    opened = [];
    opening = EventBus.openRoom.stream.listen(opened.add);
  });
  tearDown(() async {
    await opening.cancel();
    clientManager = previousManager;
    // ignore: invalid_use_of_visible_for_testing_member
    NotificationManager.debugOnNotify = null;
  });
  Future<void> pump(WidgetTester t,
      {Widget? content,
      RedactionSettings redaction = RedactionSettings.off}) async {
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: RedactionScope.withSettings(
            settings: redaction,
            child: IncomingCallAlertHost(
                calls: calls,
                child: content ?? const Scaffold(body: Text('Other room'))))));
    await t.pumpAndSettle();
  }

  for (final style in LayoutStyle.values) {
    for (final size in [const Size(1100, 700), const Size(360, 800)]) {
      testAlert('incoming actions in $style at $size', (t) async {
        await pickLayoutStyle(style);
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final call = AlertCall(account);
        await pump(t);
        calls.onClientSessionStarted(call);
        await t.pumpAndSettle();
        expect(find.text('Incoming call'), findsOneWidget);
        expect(find.text('Alex Rivera'), findsOneWidget);
        expect(find.text('To @lee:example.org'), findsOneWidget);
        expect(find.text('Other room'), findsOneWidget);
        expect(notices.whereType<CallNotificationContent>().length, 1);
        expect(opened, isEmpty);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Accept'));
        await t.pumpAndSettle();
        expect(call.accepts, 1);
        expect(opened.single.clientId, account.identifier);
        expect(opened.single.roomId, call.roomId);
        expect(find.text('Incoming call'), findsNothing);
      });
    }
  }
  testAlert('no calls, then later incoming state, decline and expiry',
      (t) async {
    final call = AlertCall(account, state: VoipState.unknown);
    calls.currentSessions.add(call);
    await pump(t);
    expect(find.text('Incoming call'), findsNothing);
    call.setState(VoipState.incoming);
    await t.pumpAndSettle();
    expect(find.text('Decline'), findsOneWidget);
    await t.tap(find.text('Decline'));
    await t.pumpAndSettle();
    expect(call.declines, 1);
    expect(opened, isEmpty);
    expect(find.text('Incoming call'), findsNothing);
    final expired = AlertCall(account);
    calls.currentSessions.add(expired);
    await t.pumpAndSettle();
    expired.setState(VoipState.ended);
    await t.pumpAndSettle();
    expect(find.text('Incoming call'), findsNothing);
  });
  testAlert('multiple accounts queue once, select next and remove stale',
      (t) async {
    final other = AlertClient('@lee:other.org');
    clients.clients.add(other);
    final first = AlertCall(account);
    final second = AlertCall(other, caller: 'Sam Chen');
    calls.currentSessions.addAll([first, first, second]);
    await pump(t);
    expect(find.text('2 incoming calls'), findsOneWidget);
    await t.tap(find.text('Next call'));
    await t.pumpAndSettle();
    expect(find.text('Sam Chen'), findsOneWidget);
    expect(find.text('To @lee:other.org'), findsOneWidget);
    clients.clients.remove(other);
    await t.pumpAndSettle();
    expect(find.text('Sam Chen'), findsNothing);
    expect(find.text('Alex Rivera'), findsOneWidget);
    // Removed between paint and click: never act on a stale session.
    calls.currentSessions.clear();
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(first.accepts, 0);
    expect(second.accepts, 0);
    expect(find.text('Incoming call'), findsNothing);
  });
  testAlert('pending action is single-shot; failure allows retry', (t) async {
    final call = AlertCall(account)
      ..wait = Completer()
      ..fail = true;
    calls.currentSessions.add(call);
    await pump(t);
    await t.tap(find.text('Accept'));
    await t.pump();
    await t.tap(find.text('Accept'));
    await t.pump();
    expect(call.accepts, 1);
    call.wait!.complete();
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsOneWidget);
    expect(find.textContaining('private server'), findsNothing);
    expect(opened, isEmpty);
    await t.tap(find.text('Dismiss'));
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsNothing);
    call.fail = false;
    call.wait = null;
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(call.accepts, 2);
    expect(opened.length, 1);
  });
  testAlert('notification off hides the card, Android has no desktop card',
      (t) async {
    calls.currentSessions.add(AlertCall(account));
    await pump(t);
    expect(find.text('Accept'), findsOneWidget);
    await preferences.enableNotifications.set(false);
    await t.pumpAndSettle();
    expect(find.text('Accept'), findsNothing);
    await preferences.enableNotifications.set(true);
    await t.pumpAndSettle();
    expect(find.text('Accept'), findsOneWidget);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pump(t);
    expect(find.text('Accept'), findsNothing);
  });
  testAlert('redaction covers caller, room and receiving account', (t) async {
    calls.currentSessions.add(AlertCall(account));
    await pump(t,
        redaction: const RedactionSettings(
            names: NameRedaction.hide,
            roomNames: true,
            distinguishable: false));
    expect(find.text('Alex Rivera'), findsNothing);
    expect(find.text('Alex DM'), findsNothing);
    expect(find.text('To @lee:example.org'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);
  });
  testAlert('keeps composer focus; Escape does not reject; dispose detaches',
      (t) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(t, content: Scaffold(body: TextField(focusNode: focus)));
    focus.requestFocus();
    await t.pump();
    final call = AlertCall(account);
    calls.currentSessions.add(call);
    await t.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(call.declines, 0);
    expect(find.text('Decline'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    call.setState(VoipState.ended);
    calls.currentSessions.clear();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testAlert('completed acceptance after unmount does not navigate', (t) async {
    final call = AlertCall(account)..wait = Completer<void>();
    calls.currentSessions.add(call);
    await pump(t);
    await t.tap(find.text('Accept'));
    await t.pump();
    await t.pumpWidget(const SizedBox.shrink());
    call.wait!.complete();
    await t.pumpAndSettle();
    expect(call.accepts, 1);
    expect(opened, isEmpty);
    expect(t.takeException(), isNull);
  });
  for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
    testAlert('desktop card also appears on $platform', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      calls.currentSessions.add(AlertCall(account));
      await pump(t);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });
  }
  testAlert('decline pending and rejected is single-shot, then manual retry',
      (t) async {
    final call = AlertCall(account)
      ..wait = Completer<void>()
      ..fail = true;
    calls.currentSessions.add(call);
    await pump(t);
    expect(find.text('Decline'), findsOneWidget);
    await t.tap(find.text('Decline'));
    await t.pump();
    await t.tap(find.text('Decline'));
    await t.pump();
    expect(call.declines, 1);
    expect(t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    call.wait!.complete();
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsOneWidget);
    expect(find.text('Alex Rivera'), findsOneWidget);
    expect(find.textContaining('private server error'), findsNothing);
    await t.pump(const Duration(minutes: 2));
    expect(call.declines, 1, reason: 'There is no automatic retry loop');
    call.fail = false;
    call.wait = null;
    await t.tap(find.text('Decline'));
    await t.pumpAndSettle();
    expect(call.declines, 2);
    expect(opened, isEmpty);
    expect(find.text('Incoming call'), findsNothing);
  });

  testAlert('real room invite removal leaves a dismissible join-failure notice',
      (t) async {
    final component = AlertRoomCallComponent()
      ..wait = Completer<VoipSession?>();
    clients.clients.add(component.client);
    final invite = MatrixRoomCallInvite(component,
        eventId: 'failed-join',
        callerId: '@alex:example.org',
        ring: const Duration(seconds: 30));
    calls.currentSessions.add(invite);
    await pump(t);
    expect(find.text('Accept'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(component.joins, 1);
    expect(invite.state, VoipState.ended);
    expect(calls.currentSessions.contains(invite), isFalse);
    expect(find.text('Accept'), findsNothing);
    component.wait!.completeError(StateError('private join failure'));
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsOneWidget);
    expect(find.textContaining('private join'), findsNothing);
    expect(find.text('Other room'), findsOneWidget);
    expect(find.text('Decline'), findsNothing);
    expect(opened, isEmpty);
    await t.tap(find.text('Dismiss'));
    await t.pumpAndSettle();
    expect(find.text('Incoming call'), findsNothing);
    expect(find.text('Other room'), findsOneWidget);
    expect(component.changes.hasListener, isFalse);
    await component.changes.close();
  });

  for (final returnsToA in [false, true]) {
    for (final fails in [false, true]) {
      testAlert(
          'manager A-to-B${returnsToA ? "-to-A" : ""} ignores stale ${fails ? "failure" : "success"}',
          (t) async {
        final a = calls;
        final old = AlertCall(account)
          ..wait = Completer<void>()
          ..fail = fails;
        a.currentSessions.add(old);
        await pump(t);
        expect(find.text('Accept'), findsOneWidget);
        await t.tap(find.text('Accept'));
        await t.pump();
        final bClients = AlertClients();
        final bAccount = AlertClient('@lee:other.org');
        bClients.clients.add(bAccount);
        final b = CallManager(bClients)..playSounds = false;
        bClients.callManager = b;
        b.currentSessions.add(AlertCall(bAccount, caller: 'Sam Chen'));
        calls = b;
        await pump(t);
        expect(find.text('Sam Chen'), findsOneWidget);
        if (returnsToA) {
          calls = a;
          await pump(t);
          expect(find.text('Alex Rivera'), findsOneWidget);
        }
        old.wait!.complete();
        await t.pumpAndSettle();
        expect(opened, isEmpty,
            reason: 'Completion belongs to the old host generation');
        expect(find.textContaining('The call action failed'), findsNothing);
        if (!returnsToA) expect(find.text('Sam Chen'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testAlert('manager A-to-B-to-A preserves a new pending action', (t) async {
    final a = calls;
    final oldWait = Completer<void>();
    final call = AlertCall(account)
      ..wait = oldWait
      ..fail = true;
    a.currentSessions.add(call);
    await pump(t);
    await t.tap(find.text('Accept'));
    await t.pump();
    final bClients = AlertClients();
    calls = CallManager(bClients)..playSounds = false;
    bClients.callManager = calls;
    await pump(t);
    calls = a;
    await pump(t);
    final newWait = Completer<void>();
    call.wait = newWait;
    await t.tap(find.text('Decline'));
    await t.pump();
    oldWait.complete();
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsNothing);
    expect(
        t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull,
        reason: 'Old completion must not clear the new pending action');
    expect(call.accepts, 1);
    expect(call.declines, 1);
    newWait.complete();
    await t.pumpAndSettle();
    expect(find.textContaining('The call action failed'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull);
    expect(opened, isEmpty);
  });

  for (final accept in [true, false]) {
    testAlert(
        'completed incoming ${accept ? "accept" : "decline"} rejects a stale duplicate callback',
        (t) async {
      final call = AlertCall(account)..keepIncoming = true;
      calls.currentSessions.add(call);
      await pump(t);
      expect(find.text('Accept'), findsOneWidget);
      final button = find.byType(accept ? FilledButton : OutlinedButton);
      final staleCallback = t.widget<ButtonStyleButton>(button).onPressed!;
      staleCallback();
      await t.pumpAndSettle();
      expect(find.text('Incoming call'), findsNothing);
      // Model an already queued callback while SDK state still says incoming.
      staleCallback();
      await t.pumpAndSettle();
      expect(accept ? call.accepts : call.declines, 1);
      expect(opened.length, accept ? 1 : 0);
    });
  }
}
