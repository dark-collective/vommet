import 'package:commet/ui/molecules/keyboard_swipe_dismiss.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Owner extends StatefulWidget {
  const _Owner({required this.child});
  final Widget child;

  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  @override
  void initState() {
    super.initState();
    KeyboardSwipeDismiss.attach(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  group('KeyboardSwipeDismiss.shouldDismiss', () {
    test('a drag down onto the keyboard dismisses', () {
      expect(
          KeyboardSwipeDismiss.shouldDismiss(
              start: const Offset(100, 350),
              position: const Offset(100, 402),
              keyboardTop: 400),
          isTrue);
    });

    test('not without a keyboard', () {
      expect(
          KeyboardSwipeDismiss.shouldDismiss(
              start: const Offset(100, 350),
              position: const Offset(100, 500),
              keyboardTop: null),
          isFalse);
    });

    test('not above the keyboard, as when scrolling the chat', () {
      expect(
          KeyboardSwipeDismiss.shouldDismiss(
              start: const Offset(100, 100),
              position: const Offset(100, 390),
              keyboardTop: 400),
          isFalse);
    });

    test('not for a touch that barely moved', () {
      expect(
          KeyboardSwipeDismiss.shouldDismiss(
              start: const Offset(100, 395),
              position: const Offset(100, 405),
              keyboardTop: 400),
          isFalse);
    });
  });

  group('KeyboardSwipeDismiss on iOS', () {
    Future<FocusNode> pumpComposer(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);

      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(MaterialApp(
        home: _Owner(
          child: Column(children: [
            const Expanded(child: SizedBox.expand()),
            TextField(focusNode: focus),
          ]),
        ),
      ));
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      return focus;
    }

    testWidgets('dragging down onto the keyboard unfocuses the composer',
        (tester) async {
      final focus = await pumpComposer(tester);

      final gesture = await tester.startGesture(const Offset(200, 480));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(focus.hasFocus, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a drag that stays above the keyboard keeps it',
        (tester) async {
      final focus = await pumpComposer(tester);

      final gesture = await tester.startGesture(const Offset(200, 100));
      await gesture.moveBy(const Offset(0, 200));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(focus.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  });
}
