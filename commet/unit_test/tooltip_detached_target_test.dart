import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';

// Vommet: just_the_tooltip built its overlay entry while its target's render
// box was detached, and localToGlobal threw (owner!.rootNode in
// RenderObject.getTransformTo, seen in Linux telemetry). The vendored copy in
// packages/just_the_tooltip draws nothing while targetIsLaidOut is false.
void main() {
  testWidgets('a showing tooltip survives its target leaving the tree',
      (tester) async {
    final tooltipKey = GlobalKey();
    final overlayKey = GlobalKey<OverlayState>();

    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(key: overlayKey, initialEntries: [
          OverlayEntry(builder: (_) => const SizedBox.expand()),
        ])));

    // The target lives in its own overlay entry, below the tooltip's.
    final targetEntry = OverlayEntry(
        builder: (_) => Center(
              child: JustTheTooltip(
                key: tooltipKey,
                content: const Text('tip'),
                child: const SizedBox(width: 20, height: 20),
              ),
            ));
    overlayKey.currentState!.insert(targetEntry);
    await tester.pump();

    // As the package's own tests do: the state class is private.
    // ignore: avoid_dynamic_calls
    (tooltipKey.currentState as dynamic).ensureTooltipVisible();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('tip'), findsOneWidget);

    // The guard must not hide a live tooltip, and dropping its target while
    // it shows must leave no error and no entry behind.
    targetEntry.remove();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The deactivated tooltip removes its entry after that frame.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('tip'), findsNothing);
  });

  testWidgets('targetIsLaidOut is false once the target is detached',
      (tester) async {
    expect(targetIsLaidOut(null), isFalse);
    expect(
        targetIsLaidOut(RenderConstrainedBox(
            additionalConstraints: const BoxConstraints())),
        isFalse);

    await tester.pumpWidget(const Center(
        child: SizedBox(key: ValueKey('target'), width: 10, height: 10)));
    final box = tester.renderObject(find.byKey(const ValueKey('target')));
    expect(targetIsLaidOut(box), isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(box.attached, isFalse);
    expect(targetIsLaidOut(box), isFalse);
  });
}
