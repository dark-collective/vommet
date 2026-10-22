import 'package:commet/client/components/push_notification/modifiers/in_app_banner.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/ui/molecules/in_app_notification_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MessageNotificationContent message() => MessageNotificationContent(
      senderName: "Alice",
      senderId: "@alice:example.org",
      roomName: "General",
      content: "hi",
      eventId: "\$e",
      roomId: "!r:example.org",
      clientId: "c",
      isDirectMessage: false,
    );

void main() {
  // Vommet issue 126: in-app banners instead of system notifications while
  // the app is open.
  test('foreground + enabled: shown as a banner, system notification dropped',
      () async {
    final shown = <NotificationContent>[];
    final sub =
        NotificationModifierInAppBanner.banners.stream.listen(shown.add);
    final m = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => true);

    String? reason;
    final out =
        await m.process(message(), onNotificationRejected: (r) => reason = r);
    await Future<void>.delayed(Duration.zero);

    expect(out, isNull);
    expect((shown.single as MessageNotificationContent).senderName, "Alice");
    expect(reason, isNotNull);
    await sub.cancel();
  });

  test('background, disabled, or no banner host: system notification as before',
      () async {
    final sub = NotificationModifierInAppBanner.banners.stream.listen((_) {});
    final background = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => false);
    final disabled = NotificationModifierInAppBanner(
        isEnabled: () async => false, isForeground: () async => true);
    expect(await background.process(message()), isNotNull);
    expect(await disabled.process(message()), isNotNull);
    await sub.cancel();

    final noHost = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => true);
    expect(await noHost.process(message()), isNotNull);
  });

  testWidgets('banner shows above a page pushed over the host', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: InAppNotificationBannerHost()),
    ));

    navigator.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text("Settings page"))));
    await tester.pumpAndSettle();

    NotificationModifierInAppBanner.banners.add(message());
    await tester.pumpAndSettle();

    expect(find.text("Alice · General"), findsOneWidget);
    expect(find.text("hi"), findsOneWidget);

    // Goes away on its own.
    await tester.pump(InAppNotificationBannerHost.visibleFor);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text("Alice · General"), findsNothing);
  });

  test('quieted (active on another device): system notification, no banner',
      () async {
    final shown = <NotificationContent>[];
    final sub =
        NotificationModifierInAppBanner.banners.stream.listen(shown.add);
    final m = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => true);
    final quiet = message()..priority = NotificationPriority.low;

    expect(await m.process(quiet), same(quiet));
    await Future<void>.delayed(Duration.zero);
    expect(shown, isEmpty);
    await sub.cancel();
  });

  testWidgets('swiping a banner up dismisses it', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: InAppNotificationBannerHost()),
    ));

    NotificationModifierInAppBanner.banners.add(message());
    await tester.pumpAndSettle();
    expect(find.text("Alice · General"), findsOneWidget);

    await tester.fling(
        find.text("Alice · General"), const Offset(0, -300), 1000);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("Alice · General"), findsNothing);
  });

  inviteTests();
}

// Vommet issue 550: room invites use the same banner, and open Home.
RoomInviteNotificationContent invite({bool isDirect = false}) =>
    RoomInviteNotificationContent(
      title: "Room Invite",
      content: "Mira invited you to Board Game Night",
      clientId: "c",
      roomId: "!board:example.org",
      inviterId: "@mira:example.org",
      inviterName: "Mira",
      roomName: "Board Game Night",
      isDirect: isDirect,
    );

void inviteTests() {
  test('a room invite becomes a banner while focused', () async {
    final shown = <NotificationContent>[];
    final sub =
        NotificationModifierInAppBanner.banners.stream.listen(shown.add);
    final m = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => true);

    expect(await m.process(invite()), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(shown.single, isA<RoomInviteNotificationContent>());
    await sub.cancel();

    final background = NotificationModifierInAppBanner(
        isEnabled: () async => true, isForeground: () async => false);
    expect(await background.process(invite()), isNotNull);
  });

  testWidgets('invite banner names the inviter and the room', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: InAppNotificationBannerHost()),
    ));

    NotificationModifierInAppBanner.banners.add(invite());
    await tester.pumpAndSettle();
    expect(find.text("Mira"), findsOneWidget);
    expect(find.text("invited you to Board Game Night"), findsOneWidget);

    // Goes away on its own.
    await tester.pump(InAppNotificationBannerHost.visibleFor);
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text("Mira"), findsNothing);
  });
}
