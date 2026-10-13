import 'package:commet/ui/molecules/composer_formatting/composer_formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final controller = TextEditingController(text: "we start at 9, be on time");
  late final FocusNode focus = FocusNode(
      onKeyEvent: (node, event) => formatting.handleKey(event)
          ? KeyEventResult.handled
          : KeyEventResult.ignored);
  late final formatting =
      ComposerFormatting(controller: controller, focusNode: focus);

  @override
  void dispose() {
    formatting.dispose();
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(children: [
            Expanded(
                child: TextField(
                    key: const ValueKey("composer"),
                    controller: controller,
                    focusNode: focus)),
            formatting.mobileToggle(context, const SizedBox(width: 36)),
          ]),
        ],
      ),
    );
  }
}

void main() {
  late _HarnessState state;

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        themeAnimationDuration: Duration.zero,
        home: const _Harness()));
    state = tester.state(find.byType(_Harness));
  }

  Future<void> select(WidgetTester tester, int start, int end) async {
    await tester.tap(find.byKey(const ValueKey("composer")));
    await tester.pump();
    state.controller.selection =
        TextSelection(baseOffset: start, extentOffset: end);
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('bar appears over a selection and applies bold', (tester) async {
    await pumpHarness(tester);
    expect(find.byIcon(Icons.format_bold), findsNothing);

    await select(tester, 15, 17); // "be"
    expect(find.byIcon(Icons.format_bold), findsOneWidget);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pump();
    expect(state.controller.text, "we start at 9, **be** on time");
    // The bar stays, now showing bold as applied.
    expect(find.byIcon(Icons.format_bold), findsOneWidget);
    expect(state.focus.hasFocus, isTrue);

    state.controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(find.byIcon(Icons.format_bold), findsNothing);
  });

  testWidgets('shortcuts and Escape', (tester) async {
    await pumpHarness(tester);
    await select(tester, 15, 17);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(state.controller.text, "we start at 9, *__be__* on time");

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byIcon(Icons.format_bold), findsNothing);
  });

  testWidgets('Aa row toggles and formats', (tester) async {
    await pumpHarness(tester);
    await select(tester, 0, 2); // "we"
    // Close the desktop bar so only the Aa row shows the icons.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.text_format));
    await tester.pump();
    expect(find.byIcon(Icons.format_strikethrough), findsOneWidget);

    await tester.tap(find.byIcon(Icons.format_strikethrough));
    await tester.pump();
    expect(state.controller.text, "~~we~~ start at 9, be on time");

    await tester.tap(find.byIcon(Icons.text_format));
    await tester.pump();
    expect(find.byIcon(Icons.format_strikethrough), findsNothing);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pasting a URL over a selection makes a link', (tester) async {
    await pumpHarness(tester);
    await select(tester, 15, 17);
    var v = state.controller.value;
    state.controller.value = TextEditingValue(
        text: v.text.replaceRange(15, 17, "https://x.example"),
        selection: const TextSelection.collapsed(offset: 32));
    await tester.pump();
    expect(state.controller.text,
        "we start at 9, [be](https://x.example) on time");
    await tester.pump(const Duration(seconds: 1));
  });
}
