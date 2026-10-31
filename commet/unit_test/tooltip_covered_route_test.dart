import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';

// Vommet issue 876: the desktop emoji picker is a modal just_the_tooltip in
// the navigator's overlay. A route pushed from it (the Library page, the
// import dialog) went under the tooltip's skrim, which took every tap; under
// a full page the skrim's fade-out never ran (the covered route's tickers are
// off), so the app was stuck. The vendored copy steps the skrim aside and
// hides the tooltip while its route is covered.
void main() {
  late JustTheController controller;
  late BuildContext pickerContext;

  Widget app() {
    controller = JustTheController();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: JustTheTooltip(
            isModal: true,
            controller: controller,
            content: Builder(builder: (context) {
              pickerContext = context;
              return const SizedBox(
                  width: 200, height: 200, child: Text('picker'));
            }),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );
  }

  Widget page(VoidCallback onTap) => Scaffold(
      body: Center(
          child: TextButton(onPressed: onTap, child: const Text('back'))));

  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(app());
    controller.showTooltip(autoClose: false);
    await tester.pumpAndSettle();
    expect(find.text('picker'), findsOneWidget);
  }

  testWidgets('a page pushed from a modal tooltip takes taps', (tester) async {
    await openPicker(tester);
    var taps = 0;
    Navigator.of(pickerContext)
        .push(MaterialPageRoute(builder: (_) => page(() => taps++)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog over a modal tooltip takes taps, the tooltip returns',
      (tester) async {
    await openPicker(tester);
    final picker = pickerContext;
    var taps = 0;
    showDialog(
        context: pickerContext,
        builder: (_) => Dialog(
            child: TextButton(
                onPressed: () => taps++, child: const Text('import'))));
    await tester.pumpAndSettle();

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('picker'), findsNothing);
    expect(controller.value, TooltipStatus.isShowing);

    // Back once the dialog closes, with its state kept.
    Navigator.of(pickerContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('picker'), findsOneWidget);
    expect(identical(picker, pickerContext), isTrue);

    // Its skrim works again.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(controller.value, TooltipStatus.isHidden);
    expect(find.text('picker'), findsNothing);
  });

  testWidgets('tapping outside still closes a modal tooltip', (tester) async {
    await openPicker(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('picker'), findsNothing);
    expect(controller.value, TooltipStatus.isHidden);
  });
}
