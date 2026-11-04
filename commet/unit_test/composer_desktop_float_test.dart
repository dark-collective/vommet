import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeProfile implements Profile {
  @override
  String get displayName => "Robin";

  @override
  Color get defaultColor => Colors.orange;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeOverrideClient extends FakeClient {
  @override
  Profile? get self => FakeProfile();
}

const boxKey = ValueKey("composer-input");
const renderKey = ValueKey("composer-render");
final card = find.byKey(const ValueKey("composer-autofill-card"));
final chip = find.textContaining("Sending as:");
final overrideClient = FakeOverrideClient();

List<AutofillSearchResult> autofill(String text) => text.contains("@")
    ? [
        AutofillSearchResultAvatar("Alice", "@alice:x", null, Colors.red),
        AutofillSearchResultAvatar("Albert", "@albert:x", null, Colors.blue),
      ]
    : [];

// The real MessageInput at the bottom of a room-like column. Typing a text
// that starts with "+" sends it as [overrideClient] (the "sending as" chip).
Future<void> pumpComposer(WidgetTester tester,
    {Size size = const Size(412, 700), bool expanded = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: renderKey,
      child: MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              if (!expanded)
                const Expanded(child: ColoredBox(color: Colors.teal)),
              Flexible(
                flex: expanded ? 1 : 0,
                child: MessageInput(
                  client: FakeClient(),
                  expanded: expanded ? ValueNotifier(true) : null,
                  availibleEmoticons: const [],
                  processAutofill: autofill,
                  findOverrideClient: (text) =>
                      text.startsWith("+") ? overrideClient : null,
                  onSendMessage: (message, {overrideClient}) =>
                      MessageInputSendResult.success,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> typeInComposer(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump();
}

double gapUnderBox(WidgetTester tester) =>
    tester.view.physicalSize.height - tester.getRect(find.byKey(boxKey)).bottom;

// The semantics node a click at [point] lands on, as the web app's
// semantics DOM (what browsers and screen readers use) routes it: the
// topmost node under the point with no child under it.
SemanticsNode? semanticsAt(SemanticsNode node, Offset point) {
  if (!node.rect.contains(point)) return null;
  const order = DebugSemanticsDumpOrder.inverseHitTest;
  final children = node.debugListChildrenInOrder(order);
  for (final child in children.reversed) {
    var local = point;
    if (child.transform != null) {
      final inverse = Matrix4.inverted(child.transform!);
      local = MatrixUtils.transformPoint(inverse, point);
    }
    final hit = semanticsAt(child, local);
    if (hit != null) return hit;
  }
  return node;
}

// Vommet issue 915: no reserved row under the desktop box either;
// autocomplete floats above it as the phones' vertical card and the
// "sending as" chip sits above it.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => preferences.layoutOverride.set(null));

  // The Linux screenshot in Vommet issue 915 is 1096 px wide at scale 1;
  // the gap under the box was the 30 + 2 dp row.
  const linux = Size(1096, 700);
  for (final style in LayoutStyle.values) {
    Future<void> desktop(WidgetTester tester) async {
      await preferences.layoutOverride.set("desktop");
      if (style == LayoutStyle.custom) {
        // A Custom mix: Telegram options, then picked as Custom.
        await pickLayoutStyle(LayoutStyle.telegram);
      }
      await pickLayoutStyle(style);
      addTearDown(() => pickLayoutStyle(LayoutStyle.discord));
      await pumpComposer(tester, size: linux);
    }

    testWidgets("desktop, ${style.name}: no reserved row under the box",
        (tester) async {
      await desktop(tester);
      expect(gapUnderBox(tester), moreOrLessEquals(0, epsilon: 0.5));
    });

    testWidgets("desktop, ${style.name}: autocomplete floats above the box",
        (tester) async {
      await desktop(tester);
      await typeInComposer(tester, "hi");
      final before = tester.getRect(find.byKey(boxKey));
      await typeInComposer(tester, "hi @al");
      expect(card, findsOneWidget);
      expect(tester.getRect(find.byKey(boxKey)), before);
      expect(gapUnderBox(tester), moreOrLessEquals(0, epsilon: 0.5));
      expect(tester.getRect(card).bottom, lessThanOrEqualTo(before.top));

      final albert = find.descendant(of: card, matching: find.text("Albert"));
      await tester.tap(albert);
      await tester.pump();
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, contains("@albert:x"));
      expect(card, findsNothing);
    });

    testWidgets("desktop, ${style.name}: a click reaches the text field",
        (tester) async {
      final semantics = tester.ensureSemantics();
      await desktop(tester);
      final center = tester.getCenter(find.byType(EditableText));
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      final root = owner.rootSemanticsNode!;
      final hit = semanticsAt(root, center);
      expect(hit, isNotNull);
      expect(hit!.hasFlag(SemanticsFlag.isTextField), isTrue,
          reason: "the click lands on $hit, not the text field");
      semantics.dispose();
    });

    testWidgets(
        "desktop, ${style.name}: a click reaches the text field "
        "with suggestions open", (tester) async {
      final semantics = tester.ensureSemantics();
      await desktop(tester);
      await typeInComposer(tester, "@a");
      expect(card, findsOneWidget);
      final center = tester.getCenter(find.byType(EditableText));
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      final root = owner.rootSemanticsNode!;
      final hit = semanticsAt(root, center);
      expect(hit, isNotNull);
      expect(hit!.hasFlag(SemanticsFlag.isTextField), isTrue,
          reason: "the click lands on $hit, not the text field");
      semantics.dispose();
    });

    testWidgets("desktop, ${style.name}: the card goes away with the composer",
        (tester) async {
      final semantics = tester.ensureSemantics();
      await desktop(tester);
      await typeInComposer(tester, "@a");
      expect(card, findsOneWidget);
      // Leave the room: same app and Overlay, no composer.
      await tester.pumpWidget(
        RepaintBoundary(
          key: renderKey,
          child: const MaterialApp(
            home: Scaffold(body: ColoredBox(color: Colors.teal)),
          ),
        ),
      );
      await tester.pump();
      expect(card, findsNothing);
      expect(find.bySemanticsLabel(RegExp("Alice|Albert")), findsNothing,
          reason: "orphan suggestion rows stay in the semantics tree");
      semantics.dispose();
    });

    testWidgets("desktop, ${style.name}: the sending-as chip is above the box",
        (tester) async {
      await desktop(tester);
      await typeInComposer(tester, "+hi");
      expect(chip, findsOneWidget);
      expect(tester.getRect(chip).bottom,
          lessThanOrEqualTo(tester.getRect(find.byKey(boxKey)).top));
      expect(gapUnderBox(tester), moreOrLessEquals(0, epsilon: 0.5));
      // As wide as its text, not the whole window.
      final ink = find.ancestor(of: chip, matching: find.byType(InkWell));
      expect(tester.getSize(ink.first).width, lessThan(300));
    });
  }

  testWidgets("phone: the sending-as chip stays above the box", (tester) async {
    await preferences.layoutOverride.set("mobile");
    await pumpComposer(tester);
    await typeInComposer(tester, "+hi");
    expect(chip, findsOneWidget);
    expect(tester.getRect(chip).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(boxKey)).top));
  });
}
