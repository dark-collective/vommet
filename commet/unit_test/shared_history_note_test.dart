// Vommet: messages decrypted with keys from an invite's history bundle
// (MSC4268) show who shared them: a mark next to the time with a "Shared by"
// tooltip, and a strip above the timeline.
import 'package:commet/ui/molecules/shared_history_banner.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Widget _message({String? sharedBy}) => MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: TimelineEventLayoutMessage(
          senderName: "Theo Lindqvist",
          senderColor: Colors.teal,
          showSender: true,
          timestamp: "21:04",
          formattedContent: const Text("Pinned the meetup notes"),
          sharedBy: sharedBy,
        ),
      ),
    );

void main() {
  testWidgets('a shared message has a mark saying who shared it',
      (tester) async {
    await tester.pumpWidget(_message(sharedBy: "Dana Reyes"));
    final mark = find.byKey(const ValueKey("message-shared-history-mark"));
    expect(mark, findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: mark, matching: find.byType(Tooltip)));
    expect(tooltip.message, "Shared by Dana Reyes");
  });

  testWidgets('other messages have no mark', (tester) async {
    await tester.pumpWidget(_message());
    expect(find.byKey(const ValueKey("message-shared-history-mark")),
        findsNothing);
  });

  test('the strip names who shared the history', () {
    expect(SharedHistoryBanner.message("Dana Reyes"),
        "Earlier messages were shared by Dana Reyes when you joined. You have Dana Reyes's word for who sent them.");
  });
}
