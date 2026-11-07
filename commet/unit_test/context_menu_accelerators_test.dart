// Vommet issue 1213: exercise real overlay focus, dispatch and underlining.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/config/style/theme_dark.dart';

Future<void> openMenu(WidgetTester t, String label) async {
  await t.tap(find.text(label), buttons: kSecondaryMouseButton);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
      'letter activates immediately once, isolates typing and restores focus',
      (t) async {
    var calls = 0;
    String? key = 'R';
    final focus = FocusNode();
    final controller = TextEditingController(text: 'Draft');
    addTearDown(focus.dispose);
    addTearDown(controller.dispose);
    await t.pumpWidget(MaterialApp(
        theme: ThemeDark.theme.copyWith(platform: TargetPlatform.linux),
        home: Scaffold(
            body: Column(children: [
          TextField(focusNode: focus, controller: controller),
          ContextMenu(items: [
            ContextMenuItem(
                text: 'Reply', accelerator: () => key, onPressed: () => calls++)
          ], child: const Text('Message')),
        ]))));
    focus.requestFocus();
    await t.pump();
    await openMenu(t, 'Message');
    expect(focus.hasFocus, false);
    expect(ContextMenuOverlay.acceleratedMenuOpen, true);
    await t.sendKeyEvent(LogicalKeyboardKey.keyQ);
    expect(controller.text, 'Draft');
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ContextMenuOverlay), findsNothing);
    expect(focus.hasFocus, true);
    expect(ContextMenuOverlay.acceleratedMenuOpen, false);
    key = 'X';
    await openMenu(t, 'Message');
    expect(find.text('Reply (X)', findRichText: true), findsOneWidget);
    final label = t.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && w.textSpan?.toPlainText() == 'Reply (X)'));
    expect(
        (label.textSpan as TextSpan)
            .children!
            .whereType<TextSpan>()
            .singleWhere((s) => s.style?.decoration == TextDecoration.underline)
            .text,
        'X');
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(calls, 1);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyX);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, 1);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyX);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('a cleared binding stays available by mouse', (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(
          body: ContextMenu(items: [
        ContextMenuItem(
          text: 'Reply',
          accelerator: () => null,
          onPressed: () => calls++,
        ),
      ], child: const Text('Message'))),
    ));
    await openMenu(t, 'Message');
    await t.sendKeyEvent(LogicalKeyboardKey.keyR, platform: 'windows');
    await t.pumpAndSettle();
    expect(calls, 0);
    await t.tap(find.text('Reply'));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(ContextMenuOverlay), findsNothing);
    expect(ContextMenuOverlay.acceleratedMenuOpen, false);
  });

  testWidgets('translated labels show the assigned fallback letter', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContextMenu(items: [
      ContextMenuItem(text: '編集', accelerator: () => 'E', onPressed: () {}),
    ], child: const Text('Message')))));
    await openMenu(t, 'Message');
    expect(find.text('編集 (E)', findRichText: true), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.keyE);
    await t.pumpAndSettle();
    expect(find.byType(ContextMenuOverlay), findsNothing);
  });

  testWidgets(
      'duplicate keys and disabled actions never fire; Escape dismisses',
      (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ContextMenu(items: [
      ContextMenuItem(
          text: 'Reply', accelerator: () => 'R', onPressed: () => calls++),
      ContextMenuItem(
          text: 'Other', accelerator: () => 'R', onPressed: () => calls++),
      ContextMenuItem(text: 'Edit', accelerator: () => 'E'),
    ], child: const Text('Message')))));
    await openMenu(t, 'Message');
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.sendKeyEvent(LogicalKeyboardKey.keyE);
    expect(calls, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(ContextMenuOverlay), findsNothing);
  });

  testWidgets(
      'second menu replaces the first and disposal releases key ownership',
      (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      for (final name in ['First', 'Second'])
        ContextMenu(items: [
          ContextMenuItem(
              text: name, accelerator: () => 'R', onPressed: () => calls++),
        ], child: Text(name)),
    ]))));
    await openMenu(t, 'First');
    // Open through the real menu state while the first overlay intercepts taps.
    final second = t.widget<ContextMenu>(find.byType(ContextMenu).last);
    final gesture = find
        .descendant(
            of: find.byWidget(second), matching: find.byType(GestureDetector))
        .first;
    t.widget<GestureDetector>(gesture).onSecondaryTap!();
    await t.pumpAndSettle();
    expect(find.byType(ContextMenuOverlay), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.keyR);
    await t.pumpAndSettle();
    expect(calls, 1);
    await openMenu(t, 'First');
    await t.pumpWidget(const SizedBox());
    await t.pump();
    expect(ContextMenuOverlay.acceleratedMenuOpen, false);
    expect(t.takeException(), isNull);
  });
}
