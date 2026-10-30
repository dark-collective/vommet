// Vommet issue 947: a session whose owner hasn't verified it can't read what
// you send. The room names each such session above the message box, lets you
// send to it too, and notes under your messages which sessions can't read
// them.
import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:commet/ui/molecules/unverified_sessions_banner.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/unverified_sessions_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

const _pixel = UnverifiedSessionInfo(
    userId: "@mira:example.org",
    owner: "Mira",
    id: "LKQWZTRNAB",
    name: "Pixel 8");
const _unnamed = UnverifiedSessionInfo(
    userId: "@kit:example.org", owner: "Kit", id: "QQXJRMDPTE");

Widget _app(Widget child, {double width = 900}) => MaterialApp(
      theme: ThemeDark.theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('the setting defaults to Ask and reads unknown values as Ask', () {
    expect(UnverifiedSessions.policy, UnverifiedSessionsPolicy.ask);
    expect(UnverifiedSessionsPolicy.parse("always"),
        UnverifiedSessionsPolicy.always);
    expect(
        UnverifiedSessionsPolicy.parse("bogus"), UnverifiedSessionsPolicy.ask);
  });

  testWidgets('the strip names the person and session, and explains why',
      (tester) async {
    var sent = 0;
    var closed = 0;
    await tester.pumpWidget(_app(UnverifiedSessionsStrip(
        sessions: const [_pixel],
        onSend: () => sent++,
        onNotNow: () => closed++)));
    expect(
        find.textContaining(
            "Mira's session \"Pixel 8\" can't read what you send here.",
            findRichText: true),
        findsOneWidget);
    expect(find.text("ID LKQWZTRNAB"), findsOneWidget);
    expect(find.text("Copy a note for Mira"), findsOneWidget);
    expect(find.byKey(const ValueKey("unverified-sessions-why")), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey("unverified-sessions-why-button")));
    await tester.pump();
    expect(
        find.byKey(const ValueKey("unverified-sessions-why")), findsOneWidget);

    await tester.tap(find.text("Send to Mira's session too…"));
    await tester.tap(find.byKey(const ValueKey("unverified-sessions-not-now")));
    expect((sent, closed), (1, 1));
  });

  testWidgets('several people: each row has its owner, no single note',
      (tester) async {
    await tester.pumpWidget(_app(UnverifiedSessionsStrip(
        sessions: const [_pixel, _unnamed], onSend: () {}, onNotNow: () {})));
    expect(
        find.textContaining("2 sessions can't read what you send here.",
            findRichText: true),
        findsOneWidget);
    expect(find.text("Kit"), findsOneWidget);
    expect(find.text("Unnamed session"), findsOneWidget);
    expect(find.text("Choose sessions to send to…"), findsOneWidget);
    expect(find.textContaining("Copy a note"), findsNothing);
  });

  testWidgets('more than five sessions: the rest are counted', (tester) async {
    await tester.pumpWidget(_app(UnverifiedSessionsStrip(sessions: [
      for (var i = 0; i < 7; i++)
        UnverifiedSessionInfo(userId: "@p$i:x", owner: "P$i", id: "DEV$i"),
    ], onSend: () {}, onNotNow: () {})));
    expect(find.text("and 2 more"), findsOneWidget);
    expect(find.text("ID DEV5"), findsNothing);
  });

  testWidgets('the sheet says which session they wrote from', (tester) async {
    final chosen = <UnverifiedSessionInfo>[];
    await tester.pumpWidget(_app(UnverifiedSessionsSheet(sessions: const [
      _pixel
    ], lastWrote: {
      _pixel.userId: (
        deviceId: _pixel.id,
        time: DateTime.now().subtract(const Duration(minutes: 2))
      ),
    }, onConfirm: (c) async => chosen.addAll(c))));
    expect(find.byKey(const ValueKey("unverified-sessions-wrote-here")),
        findsOneWidget);
    expect(
        find.text("Mira wrote from this session · 2 min ago"), findsOneWidget);
    expect(find.textContaining("Messages you already sent stay locked"),
        findsOneWidget);
    await tester.tap(find.text("Send to Pixel 8 too"));
    await tester.pump();
    expect(chosen, [_pixel]);
  });

  testWidgets('the sheet says when someone hasn\'t written yet; untick one',
      (tester) async {
    final chosen = <UnverifiedSessionInfo>[];
    await tester.pumpWidget(_app(UnverifiedSessionsSheet(
        sessions: const [_pixel, _unnamed],
        lastWrote: const {},
        onConfirm: (c) async => chosen.addAll(c))));
    expect(
        find.text(
            "Kit hasn't written here yet, so Vommet can't tell which session they use."),
        findsOneWidget);
    expect(find.text("Send to 2 sessions too"), findsOneWidget);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    await tester.tap(find.text("Send to 1 session too"));
    await tester.pump();
    expect(chosen, [_pixel]);
  });

  test('the copied note names the session and its id', () {
    expect(
        unverifiedSessionsNote(const [_pixel]),
        "Hi Mira, my app says your session \"Pixel 8\" (ID LKQWZTRNAB) isn't verified, "
        "so my messages won't open on it. Could you verify it, from one of your other "
        "sessions or with your recovery key?");
  });

  testWidgets('the note under a message, full and in a bubble', (tester) async {
    await tester.pumpWidget(_app(TimelineEventLayoutMessage(
      senderName: "Me",
      senderColor: Colors.teal,
      showSender: true,
      timestamp: "21:04",
      formattedContent: const Text("Are you around tonight?"),
      readNote: ({required bool compact}) => UnverifiedSessionsNoteView(
          sessions: const [_pixel], compact: compact),
    )));
    expect(find.text("Mira's \"Pixel 8\" can't read this"), findsOneWidget);

    await tester.pumpWidget(_app(const UnverifiedSessionsNoteView(
        sessions: [_pixel, _unnamed], compact: true)));
    expect(find.text("2 sessions can't read"), findsOneWidget);
  });

  test('sending again keeps text, formatting, thread and reply; drops edits',
      () {
    expect(
        unverifiedSessionsResendContent({
          "msgtype": "m.text",
          "body": "hi",
          "format": "org.matrix.custom.html",
          "formatted_body": "<b>hi</b>",
          "m.relates_to": {
            "m.in_reply_to": {"event_id": r"$a"}
          },
        }),
        {
          "msgtype": "m.text",
          "body": "hi",
          "format": "org.matrix.custom.html",
          "formatted_body": "<b>hi</b>",
          "m.relates_to": {
            "m.in_reply_to": {"event_id": r"$a"}
          },
        });
    final thread = {
      "rel_type": "m.thread",
      "event_id": r"$root",
      "is_falling_back": true,
      "m.in_reply_to": {"event_id": r"$b"},
    };
    expect(
        unverifiedSessionsResendContent(
            {"msgtype": "m.text", "body": "x", "m.relates_to": thread}),
        {"msgtype": "m.text", "body": "x", "m.relates_to": thread});
    expect(
        unverifiedSessionsResendContent({
          "msgtype": "m.text",
          "body": "* fixed",
          "m.new_content": {"msgtype": "m.text", "body": "fixed"},
          "m.relates_to": {"rel_type": "m.replace", "event_id": r"$c"},
        }),
        {"msgtype": "m.text", "body": "fixed"});
  });

  testWidgets('the setting switches between the three choices', (tester) async {
    await tester.pumpWidget(_app(const UnverifiedSessionsPanel()));
    expect(find.text("Ask me"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("unverified-sessions-always")));
    await tester.pumpAndSettle();
    expect(UnverifiedSessions.policy, UnverifiedSessionsPolicy.always);
    await tester.tap(find.byKey(const ValueKey("unverified-sessions-never")));
    await tester.pumpAndSettle();
    expect(UnverifiedSessions.policy, UnverifiedSessionsPolicy.never);
  });
}
