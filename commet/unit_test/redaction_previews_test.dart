import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/thread_card.dart';
import 'package:commet/ui/molecules/url_preview_widget.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

// Vommet issue 491: link previews and thread cards follow redacted mode.
void main() {
  const settings =
      RedactionSettings(names: NameRedaction.hide, text: TextRedaction.hide);
  final policy = RedactionPolicy(settings);

  Widget app(RedactionSettings settings, Widget child) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(
          body: RedactionScope.withSettings(
              settings: settings, child: SizedBox(width: 360, child: child)),
        ),
      );

  final preview = UrlPreviewWidget(UrlPreviewData(
      Uri.parse("https://example.org/post"),
      siteName: "Example Site",
      title: "A secret title",
      description: "What the page is about"));

  testWidgets('link preview text is kept when redaction is off',
      (tester) async {
    await tester.pumpWidget(app(RedactionSettings.off, preview));
    expect(find.text("Example Site"), findsOneWidget);
    expect(find.text("A secret title"), findsOneWidget);
    expect(find.text("What the page is about"), findsOneWidget);
  });

  testWidgets('link preview text is redacted like message text',
      (tester) async {
    await tester.pumpWidget(app(settings, preview));
    expect(find.text("A secret title"), findsNothing);
    expect(find.text("What the page is about"), findsNothing);
    expect(find.text(policy.text("A secret title")), findsOneWidget);
    expect(find.text(policy.text("What the page is about")), findsOneWidget);
  });

  testWidgets('thread card reply sender and text are redacted', (tester) async {
    await tester.pumpWidget(app(
        settings,
        const ThreadCard(
          replyCount: 2,
          faces: [ThreadCardFace(name: "Kestrel", id: "@k:example.org")],
          replies: [
            ThreadCardReply(
                senderName: "Kestrel",
                senderId: "@k:example.org",
                body: "meet at the usual place",
                time: "21:15",
                maxLines: 2),
          ],
        )));
    expect(find.text("Kestrel"), findsNothing);
    expect(find.text(policy.name("Kestrel", "@k:example.org")), findsOneWidget);
    expect(find.text("meet at the usual place"), findsNothing);
    expect(find.text(policy.text("meet at the usual place")), findsOneWidget);
  });
}
