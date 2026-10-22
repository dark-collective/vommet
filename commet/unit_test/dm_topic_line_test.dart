// Vommet issue 564: a DM's room topic (bridge rich presence, e.g. the game
// someone is playing) shows as one quiet line under the contact's name in the
// room lists. Rows without a topic keep their height. Made-up names.
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/utils/dm_topic_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _topic = "Playing Starfield Racers · in a lobby";

Future<Size> _pump(WidgetTester tester, Widget row) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 320, child: row)))));
  return tester.getSize(find.byWidget(row));
}

ChatEntry _dm({String? topic}) => ChatEntry(
    key: "acct:!dm",
    roomId: "!dm",
    name: "Rowan Vale",
    kind: ChatKind.direct,
    preview: "see you there",
    topic: topic);

void main() {
  test("the topic becomes one trimmed line, or nothing", () {
    expect(dmTopicLine(null), isNull);
    expect(dmTopicLine("  \n "), isNull);
    expect(dmTopicLine(" Playing\nStarfield   Racers "),
        "Playing Starfield Racers");
  });

  testWidgets("classic list: the topic sits under the name, one line",
      (tester) async {
    final plain = await _pump(
        tester, const RoomPanelView(displayName: "Rowan Vale", body: "hi"));
    expect(find.text(_topic), findsNothing);

    final withTopic = await _pump(
        tester,
        const RoomPanelView(
            displayName: "Rowan Vale", body: "hi", subtitle: _topic));
    final text = tester.widget<Text>(find.text(_topic));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(withTopic.height, greaterThan(plain.height));
  });

  testWidgets("chat list: the topic sits between the name and the preview",
      (tester) async {
    final now = DateTime(2026, 10, 22, 12);
    final plain = await _pump(tester, ChatRowTile(_dm(), now: now));
    expect(find.text(_topic), findsNothing);

    final withTopic =
        await _pump(tester, ChatRowTile(_dm(topic: _topic), now: now));
    final text = tester.widget<Text>(find.text(_topic));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getTopLeft(find.text(_topic)).dy,
        greaterThan(tester.getTopLeft(find.text("Rowan Vale")).dy));
    expect(withTopic.height, greaterThanOrEqualTo(plain.height));
  });
}
