// Vommet: the unified chat list follows redacted mode (Vommet issue 475).
// Made-up names.
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _image = AssetImage("avatar.png");

ChatEntry _chat() => ChatEntry(
    key: "acct:garden",
    roomId: "!garden:example.org",
    name: "Secret Garden",
    sender: () => "Ada",
    preview: "the key is under the mat",
    avatar: _image);

Future<void> _pump(WidgetTester tester, RedactionSettings settings) =>
    tester.pumpWidget(MaterialApp(
        home: RedactionScope(
            policy: RedactionPolicy(settings, salt: const [1, 2, 3]),
            child: Scaffold(
                body: ChatRowTile(_chat(), now: DateTime(2026, 10, 26))))));

void main() {
  testWidgets("with redaction off the row shows the room as it is",
      (tester) async {
    await _pump(tester, RedactionSettings.off);
    expect(find.textContaining("Secret Garden"), findsOneWidget);
    expect(find.textContaining("under the mat", findRichText: true),
        findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets("hiding room names, text and avatars hides them in the row",
      (tester) async {
    await _pump(
        tester,
        const RedactionSettings(
            names: NameRedaction.hide,
            roomNames: true,
            avatars: true,
            text: TextRedaction.scramble));
    expect(find.textContaining("Secret Garden"), findsNothing);
    expect(
        find.textContaining("under the mat", findRichText: true), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
