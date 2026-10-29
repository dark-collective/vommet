import 'package:commet/ui/atoms/mention.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:commet/ui/pages/settings/categories/app/redaction_settings_page.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet issue 400: widgets consult the nearest RedactionScope.
void main() {
  setUpAll(() => tiamat.Avatar.redactor = redactAvatar);

  Widget app(RedactionSettings settings, Widget child) => MaterialApp(
        home: Scaffold(
          body: RedactionScope.withSettings(settings: settings, child: child),
        ),
      );

  const level4 = RedactionSettings(
      names: NameRedaction.hide, avatars: true, distinguishable: true);

  final image = tiamat.transparentImage.image;

  // The sender's picture: a FadeInImage, or an Image keyed to it (since the
  // Vommet issue 432 avatar placeholder fix).
  final picture = find.byWidgetPredicate(
      (w) => w is FadeInImage || (w is Image && w.image == image));

  Widget message() => TimelineEventLayoutMessage(
        senderId: "@ada:example.org",
        senderName: "Ada Lovelace",
        senderColor: const Color(0xFFE57373),
        senderAvatar: image,
        formattedContent: const RedactedText("hello there"),
      );

  testWidgets('outside any scope nothing is redacted', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: message())));
    expect(find.text("Ada Lovelace"), findsOneWidget);
    expect(find.text("hello there"), findsOneWidget);
    expect(picture, findsWidgets);
  });

  testWidgets('timeline message: name and avatar hidden, text kept',
      (tester) async {
    await tester.pumpWidget(app(level4, message()));
    final policy = RedactionPolicy(level4);
    expect(find.text("Ada Lovelace"), findsNothing);
    expect(find.text(policy.name("Ada Lovelace", "@ada:example.org")),
        findsOneWidget);
    expect(find.text("hello there"), findsOneWidget);
    // The picture is replaced by a placeholder with the person's tag.
    expect(picture, findsNothing);
    expect(find.text(policy.avatarLetter("@ada:example.org")), findsOneWidget);
  });

  testWidgets('hidden text is drawn as bars, not the words', (tester) async {
    await tester.pumpWidget(
        app(const RedactionSettings(text: TextRedaction.hide), message()));
    expect(find.text("hello there"), findsNothing);
    final text = tester.widget<Text>(find.text("••••• •••••"));
    expect(text.style?.color?.a, 0);
    expect(text.style?.backgroundColor?.a, greaterThan(0));
  });

  testWidgets('mention pills follow the name switch', (tester) async {
    await tester.pumpWidget(app(
        level4,
        const MentionWidget(
          displayName: "Grace Hopper",
          userId: "@grace:example.org",
          placeholderColor: Colors.blue,
        )));
    expect(find.text("Grace Hopper"), findsNothing);
    expect(
        find.text(
            RedactionPolicy(level4).name("Grace Hopper", "@grace:example.org")),
        findsOneWidget);
  });

  testWidgets('images are blurred only when the switch is on', (tester) async {
    const child = SizedBox(width: 10, height: 10);
    await tester.pumpWidget(app(level4, const RedactedImage(child: child)));
    expect(find.byType(ImageFiltered), findsNothing);

    await tester.pumpWidget(app(const RedactionSettings(images: true),
        const RedactedImage(child: child)));
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('a nested scope overrides its subtree only (screenshots)',
      (tester) async {
    await tester.pumpWidget(app(
        RedactionSettings.off,
        Column(children: [
          const RedactedText("outside"),
          RedactionScope.withSettings(
              settings: const RedactionSettings(text: TextRedaction.scramble),
              child: const RedactedText("inside")),
        ])));
    expect(find.text("outside"), findsOneWidget);
    expect(find.text("inside"), findsNothing);
  });

  testWidgets('settings preview renders every level', (tester) async {
    for (final preset in RedactionPreset.values) {
      await tester.pumpWidget(app(preset.applyTo(RedactionSettings.off),
          const SingleChildScrollView(child: RedactionPreview())));
      expect(find.text("Ada Lovelace"), findsNothing);
      expect(find.text("Grace Hopper"), findsNothing);
      expect(find.byType(ImageFiltered),
          preset.text == TextRedaction.keep ? findsNothing : findsOneWidget);
    }
  });
}
