// Vommet issue 947 (redesign): group rooms mark messages sent from a session
// that can't read what you send, room settings list every such session with
// the ones in use first, the strip shows only in DMs for a session in use,
// and a dehydrated device is never named.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/unverified_sender_mark.dart';
import 'package:commet/ui/molecules/unverified_sessions_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _FakeDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _mira = UnverifiedSessionInfo(
    userId: "@mira:example.org",
    owner: "Mira",
    id: "LKQWZTRNAB",
    name: "Pixel 8",
    activity: "Asked you for a key 3 min ago");
const _old = UnverifiedSessionInfo(
    userId: "@juno:example.org", owner: "Juno", id: "PTRAXWQENB");

Widget _app(Widget child, {double width = 900}) => MaterialApp(
      theme: ThemeDark.theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

matrix.DeviceKeys _device(matrix.Client client, String id,
        {String? name, bool dehydrated = false}) =>
    matrix.DeviceKeys.fromJson({
      "user_id": "@ash:example.org",
      "device_id": id,
      "algorithms": ["m.olm.v1.curve25519-aes-sha2"],
      "keys": {"curve25519:$id": "c-$id", "ed25519:$id": "e-$id"},
      "signatures": {},
      if (dehydrated) "dehydrated": true,
      if (name != null) "unsigned": {"device_display_name": name},
    }, client);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    UnverifiedSessions.reloadActivity();
  });

  testWidgets('the mark opens a card that names the session and the action',
      (tester) async {
    var allowed = 0;
    await tester.pumpWidget(_app(
        UnverifiedSenderMarkView(session: _mira, onAllow: () => allowed++)));
    expect(find.byKey(const ValueKey("message-unverified-sender-mark")),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey("message-unverified-sender-mark")));
    await tester.pumpAndSettle();
    expect(find.text(UnverifiedSenderStrings.cardTitle), findsOneWidget);
    expect(find.text(UnverifiedSenderStrings.cardBody("Mira", "Pixel 8")),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("unverified-sender-let-read")));
    await tester.pumpAndSettle();
    expect(allowed, 1);
    // The card closes before the confirmation opens.
    expect(find.text(UnverifiedSenderStrings.cardTitle), findsNothing);
  });

  testWidgets('room settings: sessions in use first, the rest folded',
      (tester) async {
    await tester.pumpWidget(_app(UnverifiedSessionsSection(
        active: const [_mira], quiet: const [_old], onAllow: (_) {})));
    expect(find.text("Asked you for a key 3 min ago"), findsOneWidget);
    expect(find.text("PTRAXWQENB", findRichText: true), findsNothing);
    await tester.tap(find.text(UnverifiedSenderStrings.showQuiet(1)));
    await tester.pumpAndSettle();
    expect(find.text("ID PTRAXWQENB"), findsOneWidget);
    expect(find.text(UnverifiedSenderStrings.allow), findsNWidgets(2));
  });

  testWidgets('room settings: nothing to list', (tester) async {
    await tester.pumpWidget(_app(UnverifiedSessionsSection(
        active: const [], quiet: const [], onAllow: (_) {})));
    expect(find.text(UnverifiedSenderStrings.sectionNone), findsOneWidget);
  });

  test('a dehydrated device is never named', () {
    final client = matrix.Client("test", database: _FakeDatabase());
    expect(
        UnverifiedSessions.isDehydrated(
            _device(client, "DEHYD", dehydrated: true)),
        isTrue);
    expect(
        UnverifiedSessions.isDehydrated(
            _device(client, "OLDELEM", name: "Dehydrated device")),
        isTrue);
    expect(
        UnverifiedSessions.isDehydrated(
            _device(client, "PHONE", name: "Pixel 8")),
        isFalse);
  });

  test('a session counts as in use for 30 days after it asks or writes',
      () async {
    final client = matrix.Client("test", database: _FakeDatabase());
    final phone = _device(client, "PHONE");
    final laptop = _device(client, "LAPTOP");
    final stale = _device(client, "STALE");
    expect(UnverifiedSessions.activityOf(client, phone), isNull);

    final asked = DateTime.now().subtract(const Duration(minutes: 3));
    UnverifiedSessions.noteActivity(client, phone.userId, "PHONE", asked,
        asked: true);
    // A message in the same minute doesn't hide the key request.
    UnverifiedSessions.noteActivity(
        client, phone.userId, "PHONE", asked.add(const Duration(seconds: 20)),
        asked: false);
    expect(UnverifiedSessions.activityOf(client, phone)?.asked, isTrue);

    UnverifiedSessions.noteActivity(client, laptop.userId, "LAPTOP",
        DateTime.now().subtract(const Duration(days: 29)),
        asked: false);
    expect(UnverifiedSessions.activityOf(client, laptop)?.asked, isFalse);

    UnverifiedSessions.noteActivity(client, stale.userId, "STALE",
        DateTime.now().subtract(const Duration(days: 31)),
        asked: true);
    expect(UnverifiedSessions.activityOf(client, stale), isNull);
  });

  test('within a minute a message does not replace a key request', () {
    final client = matrix.Client("test", database: _FakeDatabase());
    final phone = _device(client, "PHONE");
    final t = DateTime.fromMillisecondsSinceEpoch(DateTime.now()
        .subtract(const Duration(minutes: 10))
        .millisecondsSinceEpoch);
    UnverifiedSessions.noteActivity(client, phone.userId, "PHONE", t,
        asked: false);
    // A key request soon after a message replaces it.
    UnverifiedSessions.noteActivity(
        client, phone.userId, "PHONE", t.add(const Duration(seconds: 10)),
        asked: true);
    expect(UnverifiedSessions.activityOf(client, phone)?.asked, isTrue);
    // An older sign is ignored.
    UnverifiedSessions.noteActivity(
        client, phone.userId, "PHONE", t.subtract(const Duration(hours: 1)),
        asked: false);
    expect(UnverifiedSessions.activityOf(client, phone)?.at,
        t.add(const Duration(seconds: 10)));
    // A message well after it is newer and wins.
    final later = t.add(const Duration(minutes: 5));
    UnverifiedSessions.noteActivity(client, phone.userId, "PHONE", later,
        asked: false);
    expect(UnverifiedSessions.activityOf(client, phone)?.asked, isFalse);
    expect(UnverifiedSessions.activityOf(client, phone)?.at, later);
  });

  test('key requests count only for sessions we know', () {
    final client = matrix.Client("test", database: _FakeDatabase());
    final phone = _device(client, "PHONE");
    client.userDeviceKeys[phone.userId] =
        matrix.DeviceKeysList(phone.userId, client)
          ..deviceKeys["PHONE"] = phone;
    matrix.ToDeviceEvent request(String device, {String action = "request"}) =>
        matrix.ToDeviceEvent(
            sender: phone.userId,
            type: matrix.EventTypes.RoomKeyRequest,
            content: {
              "action": action,
              "requesting_device_id": device,
              "request_id": "r1",
            });

    UnverifiedSessions.noteKeyRequest(client, request("MADEUP"));
    expect(UnverifiedSessions.activityOf(client, _device(client, "MADEUP")),
        isNull);
    UnverifiedSessions.noteKeyRequest(
        client, request("PHONE", action: "request_cancellation"));
    expect(UnverifiedSessions.activityOf(client, phone), isNull);
    UnverifiedSessions.noteKeyRequest(client, request("PHONE"));
    expect(UnverifiedSessions.activityOf(client, phone)?.asked, isTrue);
  });

  test('the strip: none in a group room; in a DM only sessions in use', () {
    final client = matrix.Client("test", database: _FakeDatabase());
    final phone = _device(client, "PHONE");
    final old = _device(client, "OLD");
    UnverifiedSessions.noteActivity(client, phone.userId, "PHONE",
        DateTime.now().subtract(const Duration(minutes: 3)),
        asked: true);

    final group = UnverifiedSessions.forTesting(
        matrix.Room(id: "!group:example.org", client: client));
    group.withheld.value = [phone, old];
    expect(group.shown, isEmpty);

    client.accountData["m.direct"] =
        matrix.BasicEvent(type: "m.direct", content: {
      phone.userId: ["!dm:example.org"]
    });
    final dm = UnverifiedSessions.forTesting(
        matrix.Room(id: "!dm:example.org", client: client));
    expect(dm.room.isDirectChat, isTrue);
    dm.withheld.value = [phone, old];
    expect(dm.shown.map((d) => d.deviceId), ["PHONE"]);
  });
}
