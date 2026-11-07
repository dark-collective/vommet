import 'package:commet/ui/atoms/thread_card.dart';
import 'package:commet/ui/pages/settings/categories/app/thread_preview_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = "Hey guys, did you know that in terms of male human and female "
    "Pokémon breeding, Vaporeon is the most compatible Pokémon for humans? "
    "Not only are they in the field egg group, which is mostly comprised of "
    "mammals, Vaporeon are an average of 3\"03' tall and 63.9 pounds.";

Widget _card(List<ThreadCardReply> replies, {VoidCallback? onTap}) =>
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: ThreadCard(
            replyCount: 12,
            faces: const [
              ThreadCardFace(name: "Dark"),
              ThreadCardFace(name: "Ewan"),
              ThreadCardFace(name: "Kestrel"),
              ThreadCardFace(name: "Mira"),
            ],
            replies: replies,
            onTap: onTap,
          ),
        ),
      ),
    );

ThreadCardReply _reply(String body, int lines) => ThreadCardReply(
    senderName: "Kestrel", body: body, time: "21:15", maxLines: lines);

void main() {
  test("reply count label", () {
    expect(ThreadCard.countLabel(1), "1 event reported");
    expect(ThreadCard.countLabel(12), "12 events reported");
  });

  test("preview mode parses, unknown values fall back to latest", () {
    expect(ThreadPreviewMode.parse("first"), ThreadPreviewMode.first);
    expect(ThreadPreviewMode.parse("both"), ThreadPreviewMode.both);
    expect(ThreadPreviewMode.parse("latest"), ThreadPreviewMode.latest);
    expect(ThreadPreviewMode.parse("bogus"), ThreadPreviewMode.latest);
  });

  testWidgets("a short reply is not faded", (tester) async {
    await tester.pumpWidget(_card([_reply("I hate you...", 2)]));
    expect(find.text("12 events reported"), findsOneWidget);
    expect(find.text("Reply preview from loaded activity"), findsOneWidget);
    expect(find.byKey(const ValueKey("thread-card-fade")), findsNothing);
  });

  testWidgets("a long reply is cut and fades out", (tester) async {
    await tester.pumpWidget(_card([_reply(_long, 2)]));
    expect(find.byKey(const ValueKey("thread-card-fade")), findsOneWidget);
    final text = tester.widget<Text>(find.text(_long));
    expect(text.maxLines, 2);
  });

  testWidgets("first and latest show both with one divider", (tester) async {
    await tester
        .pumpWidget(_card([_reply(_long, 2), _reply("I hate you...", 2)]));
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byKey(const ValueKey("thread-card-fade")), findsOneWidget);
  });

  testWidgets("tapping the card opens the thread", (tester) async {
    var opened = 0;
    await tester.pumpWidget(_card([_reply("hi", 2)], onTap: () => opened++));
    await tester.tap(find.byKey(const ValueKey("thread-card")));
    expect(opened, 1);
  });

  testWidgets("the settings preview shows each mode's replies, cut",
      (tester) async {
    for (final (mode, count) in [
      (ThreadPreviewMode.latest, 1),
      (ThreadPreviewMode.first, 1),
      (ThreadPreviewMode.both, 2),
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body:
                  SizedBox(width: 360, child: ThreadCardPreview(mode: mode)))));
      expect(
          find.byKey(const ValueKey("thread-card-fade")), findsNWidgets(count),
          reason: mode.name);
    }
  });
}
