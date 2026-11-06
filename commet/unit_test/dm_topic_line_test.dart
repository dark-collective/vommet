// unit_test is the repository test directory, but the analyzer does not recognize it.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// Vommet issue 970: status is metadata below the latest message in both lists.
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/config/room_row_size.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/atoms/room_topic_line.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/utils/dm_topic_line.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const topic = "Playing Starfield Racers · in a lobby with a very long name";
const message = "You: see you there";

Widget topicRow(bool unified,
        {String? status = topic, String? preview = message}) =>
    unified
        ? ChatRowTile(
            ChatEntry(
                key: "acct:!dm",
                roomId: "!dm",
                name: "Christopher Alexander Henderson",
                kind: ChatKind.direct,
                preview: preview,
                topic: status,
                unread: 3,
                mentions: 1),
            now: DateTime(2026, 10, 31))
        : RoomPanelView(
            displayName: "Christopher Alexander Henderson",
            body: preview,
            topic: status,
            highlightNotificationCount: 3);

Future<Size> pumpRow(WidgetTester tester, Widget row,
    {double scale = 1,
    double width = 320,
    RedactionSettings redaction = RedactionSettings.off}) async {
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: RedactionScope.withSettings(
              settings: redaction,
              child: Scaffold(
                  body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          child: SingleChildScrollView(child: row))))))));
  return tester.getSize(find.byWidget(row));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  test("the topic becomes one trimmed line, or nothing", () {
    expect(dmTopicLine(null), isNull);
    expect(dmTopicLine("  \n "), isNull);
    expect(dmTopicLine(" Playing\nStarfield   Racers "),
        "Playing Starfield Racers");
  });

  for (final unified in [false, true]) {
    final list =
        unified ? "unified (Telegram / Custom)" : "classic (Discord / Custom)";
    testWidgets("$list: message precedes topic; topic updates preserve preview",
        (tester) async {
      final plain = await pumpRow(tester, topicRow(unified, status: null));
      expect(find.byType(RoomTopicLine), findsNothing);
      final withTopic = await pumpRow(tester, topicRow(unified));
      expect(
          tester
              .getBottomLeft(
                  find.textContaining(message, findRichText: true).first)
              .dy,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(RoomTopicLine)).dy));
      expect(withTopic.height, greaterThan(plain.height));
      final text = tester.widget<Text>(find.text("Topic · $topic"));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      await pumpRow(tester, topicRow(unified, status: "Online"));
      expect(find.textContaining(message, findRichText: true), findsWidgets);
      expect(find.text("Topic · Online"), findsOneWidget);
      final cleared = await pumpRow(tester, topicRow(unified, status: null));
      expect(cleared.height, plain.height);
    });

    testWidgets("$list: an absent preview never becomes the topic",
        (tester) async {
      await pumpRow(tester, topicRow(unified, preview: null));
      expect(find.text("Topic · $topic"), findsOneWidget);
      expect(find.text(topic, findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        "$list: full topic is available to assistive technology and hover",
        (tester) async {
      final handle = tester.ensureSemantics();

      try {
        await pumpRow(tester, topicRow(unified));
        expect(find.bySemanticsLabel("Room topic: $topic"), findsOneWidget);
        expect(
            find.byWidgetPredicate((w) => w is Tooltip && w.message == topic),
            findsOneWidget);
      } finally {
        handle.dispose();
      }
    });

    for (final width in [320.0, 600.0]) {
      for (final size in RoomRowSize.values) {
        testWidgets(
            "$list: $width wide, $size, 200% text keeps preview and badges visible",
            (tester) async {
          await roomRowSizePreference.set(size.name);
          final regular =
              await pumpRow(tester, topicRow(unified), width: width);
          final enlarged =
              await pumpRow(tester, topicRow(unified), width: width, scale: 2);
          expect(enlarged.height, greaterThan(regular.height));
          final preview =
              find.textContaining(message, findRichText: true).first;
          expect(tester.getSize(preview).height, greaterThan(20));
          expect(
              tester.getBottomLeft(preview).dy,
              lessThanOrEqualTo(
                  tester.getTopLeft(find.byType(RoomTopicLine)).dy));
          final badge = unified
              ? find.byType(UnreadBadge)
              : find.byType(NotificationBadge);
          final count = find.descendant(of: badge, matching: find.text("3"));
          expect(tester.getSize(count).height,
              lessThanOrEqualTo(tester.getSize(badge).height));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets("classic search snippets keep their own slot", (tester) async {
    await pumpRow(
        tester,
        const RoomPanelView(
            displayName: "Rowan",
            subtitle: "A matched topic snippet",
            subtitleHighlight: (start: 2, end: 9)));
    expect(find.textContaining("matched", findRichText: true), findsWidgets);
    expect(find.byType(RoomTopicLine), findsNothing);
  });

  testWidgets("redacted topics do not leak through labels or tooltips",
      (tester) async {
    final handle = tester.ensureSemantics();

    try {
      for (final settings in [
        const RedactionSettings(roomNames: true),
        const RedactionSettings(text: TextRedaction.hide)
      ]) {
        await pumpRow(tester, topicRow(true), redaction: settings);
        expect(find.byType(RoomTopicLine), findsNothing);
        expect(
            find.byWidgetPredicate((w) => w is Tooltip && w.message == topic),
            findsNothing);
        expect(find.bySemanticsLabel("Room topic: $topic"), findsNothing);
      }
    } finally {
      handle.dispose();
    }
  });
}
