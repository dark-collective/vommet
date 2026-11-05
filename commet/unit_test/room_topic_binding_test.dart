import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/atoms/room_panel_view.dart';
import 'package:commet/ui/atoms/room_topic_line.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'topic_room_fakes.dart';

void main() {
  testWidgets(
      'live DM topic updates retain the real message and search snippets',
      (tester) async {
    final client = TopicClient();
    final room = TopicRoom(client,
        identifier: 'alex',
        displayName: 'Alex',
        at: DateTime(2026, 10, 31, 10),
        topic: 'Playing Portal 2');
    addTearDown(room.updates.close);
    Future<void> show({String? search, bool redacted = false}) async {
      await tester.pumpWidget(MaterialApp(
          home: RedactionScope.withSettings(
              settings: redacted
                  ? const RedactionSettings(text: TextRedaction.hide)
                  : RedactionSettings.off,
              child: Scaffold(
                  body: ListView(
                      children: [RoomPanel(room, searchLine: search)])))));
      await tester.pump();
    }

    await show();
    var view = tester.widget<RoomPanelView>(find.byType(RoomPanelView));
    expect(view.body, 'Want to play after dinner?');
    expect(view.topic, 'Playing Portal 2');
    expect(view.subtitle, isNull);
    room.updateTopic('Online');
    await tester.pump();
    view = tester.widget<RoomPanelView>(find.byType(RoomPanelView));
    expect(view.body, 'Want to play after dinner?');
    expect(view.topic, 'Online');
    await show(search: 'Matched topic snippet');
    view = tester.widget<RoomPanelView>(find.byType(RoomPanelView));
    expect(view.subtitle, 'Matched topic snippet');
    expect(view.topic, isNull);
    expect(view.body, isNull);
    await show(redacted: true);
    expect(find.byType(RoomTopicLine), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unified source keeps topic and real message distinct',
      (tester) async {
    final client = TopicClient();
    final room = TopicRoom(client,
        identifier: 'alex',
        displayName: 'Alex',
        at: DateTime(2026, 10, 31, 10),
        topic: 'Playing Portal 2',
        count: 3);
    addTearDown(room.updates.close);
    final entry = chatEntryOf(room, direct: true);
    expect(entry.preview, 'Want to play after dinner?');
    expect(entry.topic, 'Playing Portal 2');
    expect(entry.sender!(), 'You');
    expect(entry.lastActivity, room.at);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      ChatRowTile(entry, now: DateTime(2026, 10, 31, 12))
    ]))));
    expect(find.text('Topic · Playing Portal 2'), findsOneWidget);
    expect(
        find.textContaining('Want to play after dinner?', findRichText: true),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
