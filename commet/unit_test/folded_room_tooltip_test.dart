import 'dart:ui' as ui;

import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';

const _name = 'Accessibility and internationalization working group · '
    'release coordination and community review';

Future<void> _showRail(
  WidgetTester tester, {
  required Size size,
  Alignment alignment = Alignment.centerLeft,
  ThemeData? theme,
  double textScale = 1,
  Offset offset = Offset.zero,
  String name = _name,
  bool visible = true,
  bool square = false,
  int unread = 0,
  int mentions = 0,
  bool marked = false,
  GlobalKey? captureKey,
  VoidCallback? onTap,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: (theme ?? ThemeDark.theme).copyWith(platform: TargetPlatform.linux),
    builder: (context, child) => RepaintBoundary(
      key: captureKey,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
    ),
    home: Scaffold(
      body: Align(
        alignment: alignment,
        child: Transform.translate(
          offset: offset,
          child: TooltipVisibility(
            visible: visible,
            child: SizedBox(
              width: 72,
              child: FoldedAvatar(
                name: name,
                square: square,
                unread: unread,
                mentions: mentions,
                marked: marked,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ));
}

Future<TestGesture> _hoverAvatar(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: tester.getCenter(find.byType(ChatAvatar)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
  return mouse;
}

void _expectRight(WidgetTester tester, {String name = _name}) {
  final label = tester.getRect(find.text(name, findRichText: true));
  final avatar = tester.getRect(find.byType(ChatAvatar));
  expect(label.left, greaterThan(avatar.right));
  expect(label.center.dy, closeTo(avatar.center.dy, 2));
}

void main() {
  testWidgets('folded room hover opens beside the avatar and clears on exit',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    final label = find.text(_name, findRichText: true);
    final avatar = tester.getRect(find.byType(ChatAvatar));
    expect(tester.getRect(label).left, greaterThan(avatar.right));
    expect(tester.getCenter(label).dy, closeTo(avatar.center.dy, 2));

    await mouse.moveTo(const Offset(600, 310));
    await tester.pumpAndSettle();
    expect(label, findsNothing);
  });

  testWidgets('long room name flips left and stays in the narrow viewport',
      (tester) async {
    await _showRail(
      tester,
      size: const Size(420, 520),
      alignment: Alignment.centerRight,
    );
    await _hoverAvatar(tester);
    final label = find.text(_name, findRichText: true);
    final avatar = tester.getRect(find.byType(ChatAvatar));
    expect(tester.getRect(label).right, lessThan(avatar.left));
    expect(tester.getRect(label).left, greaterThan(0));
    expect(tester.getCenter(label).dy, closeTo(avatar.center.dy, 2));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(160, 520);
    await tester.pumpAndSettle();
    final movedAvatar = tester.getRect(find.byType(ChatAvatar));
    expect(tester.getRect(label).bottom, lessThan(movedAvatar.top));
    expect(tester.getRect(label).right, lessThan(160));
  });

  testWidgets('Tab shows the room name and Escape leaves the avatar focused',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final focus = FocusManager.instance.primaryFocus;
    final label = find.text(_name, findRichText: true);
    expect(label, findsOneWidget);
    expect(tester.getRect(label).left,
        greaterThan(tester.getRect(find.byType(ChatAvatar)).right));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(label, findsNothing);
    expect(FocusManager.instance.primaryFocus, same(focus));
  });
  for (final badge in ['unread', 'mention', 'dot']) {
    testWidgets('room label remains visible over the $badge badge',
        (tester) async {
      await _showRail(
        tester,
        size: const Size(880, 620),
        unread: badge == 'unread' ? 3 : 0,
        mentions: badge == 'mention' ? 1 : 0,
        marked: badge == 'dot',
      );
      final mouse = await _hoverAvatar(tester);
      _expectRight(tester);
      final badgeFinder = switch (badge) {
        'unread' => find.byType(UnreadBadge),
        'mention' => find.byType(MentionBadge),
        _ => find.byType(DotIndicator),
      };
      await mouse.moveTo(tester.getCenter(badgeFinder));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(_name, findRichText: true), findsOneWidget);
      _expectRight(tester);
    });
  }

  for (final (themeName, theme) in [
    ('Dark', ThemeDark.theme),
    ('Light', ThemeLight.theme),
    ('AMOLED', ThemeAmoled.theme),
  ]) {
    testWidgets(
        '$themeName room bubble paints the theme surface and foreground',
        (tester) async {
      final capture = GlobalKey();
      await _showRail(tester,
          size: const Size(880, 620), theme: theme, captureKey: capture);
      await _hoverAvatar(tester);
      _expectRight(tester);
      final label = find.text(_name, findRichText: true);
      final text = tester.widget<RichText>(label);
      expect(text.text.style!.color, theme.colorScheme.onSurface);
      final sample = tester.getTopLeft(label) + const Offset(-5, 7);
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final pixel = (sample.dy.floor() * image.width + sample.dx.floor()) * 4;
        final color = Color.fromARGB(
          data.getUint8(pixel + 3),
          data.getUint8(pixel),
          data.getUint8(pixel + 1),
          data.getUint8(pixel + 2),
        );
        image.dispose();
        expect(color, theme.colorScheme.surfaceContainerHigh);
      });
    });
  }

  for (final (label, size, alignment, side, scale) in [
    (
      'shrink right',
      const Size(360, 520),
      Alignment.center,
      AxisDirection.right,
      1.0
    ),
    (
      'below',
      const Size(160, 520),
      Alignment.topCenter,
      AxisDirection.down,
      1.0
    ),
    (
      'above',
      const Size(160, 520),
      Alignment.bottomCenter,
      AxisDirection.up,
      1.0
    ),
    (
      'top edge',
      const Size(880, 620),
      Alignment.topLeft,
      AxisDirection.right,
      2.0
    ),
    (
      'bottom edge',
      const Size(880, 620),
      Alignment.bottomLeft,
      AxisDirection.right,
      2.0
    ),
  ]) {
    testWidgets('room bubble adapts to $label at text scale $scale',
        (tester) async {
      await _showRail(tester, size: const Size(880, 620));
      final mouse = await _hoverAvatar(tester);
      _expectRight(tester);
      await mouse.moveTo(const Offset(600, 310));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await _showRail(tester,
          size: size, alignment: alignment, textScale: scale);
      await tester.pumpAndSettle();
      final text = find.text(_name, findRichText: true);
      expect(text, findsOneWidget);
      final rect = tester.getRect(text);
      final avatar = tester.getRect(find.byType(ChatAvatar));
      switch (side) {
        case AxisDirection.right:
          expect(rect.left, greaterThan(avatar.right));
        case AxisDirection.down:
          expect(rect.top, greaterThan(avatar.bottom));
        case AxisDirection.up:
          expect(rect.bottom, lessThan(avatar.top));
        case AxisDirection.left:
          expect(rect.right, lessThan(avatar.left));
      }
      final painted =
          find.ancestor(of: text, matching: find.byType(CustomPaint)).first;
      final bubble = tester.getRect(painted);
      expect(bubble.left, greaterThanOrEqualTo(8));
      expect(bubble.right, lessThanOrEqualTo(size.width - 8));
      expect(bubble.top, greaterThanOrEqualTo(8));
      expect(bubble.bottom, lessThanOrEqualTo(size.height - 8));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('hidden, offscreen and tiny room labels stay suppressed',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    _expectRight(tester);
    await mouse.moveTo(const Offset(600, 310));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await _showRail(tester, size: const Size(880, 620), visible: false);
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsNothing);
    await _showRail(tester, size: const Size(880, 620));
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsOneWidget);
    await _showRail(tester,
        size: const Size(880, 620), offset: const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsNothing);
    await _showRail(tester, size: const Size(12, 12));
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsNothing);
    await _showRail(tester, size: const Size(880, 24));
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hover cancellation and disposal leave no delayed room bubble',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    _expectRight(tester);
    await mouse.moveTo(const Offset(600, 310));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(ChatAvatar)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(_name, findRichText: true), findsNothing);
    await mouse.moveTo(const Offset(600, 310));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_name, findRichText: true), findsNothing);
    await mouse.moveTo(tester.getCenter(find.byType(ChatAvatar)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(_name, findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'touch long press shows the room bubble and expires after release',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    _expectRight(tester);
    await mouse.moveTo(const Offset(600, 310));
    await tester.pumpAndSettle();
    final finger = await tester.startGesture(
        tester.getCenter(find.byType(ChatAvatar)),
        kind: ui.PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 600));
    _expectRight(tester);
    await finger.up();
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text(_name, findRichText: true), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(_name, findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'covered routes hide the room bubble and hover works after return',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    _expectRight(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    final route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cover')));
    nav.push(route);
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true, skipOffstage: false),
        findsNothing);
    nav.pop();
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(600, 310));
    await mouse.moveTo(tester.getCenter(find.byType(ChatAvatar)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    _expectRight(tester);
  });

  testWidgets(
      'focus loss hides the room bubble and activation remains available',
      (tester) async {
    var taps = 0;
    await _showRail(tester, size: const Size(880, 620), onTap: () => taps++);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    _expectRight(tester);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    expect(find.text(_name, findRichText: true), findsNothing);
    await tester.tap(find.byType(ChatAvatar));
    expect(taps, 1);
    await _showRail(tester,
        size: const Size(880, 620), name: '', onTap: () => taps++);
    await tester.tap(find.byType(ChatAvatar));
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'real folded column uses redacted room names and keeps space labels',
      (tester) async {
    await _showRail(tester, size: const Size(880, 620));
    final mouse = await _hoverAvatar(tester);
    _expectRight(tester);
    await mouse.moveTo(const Offset(600, 310));
    final policy = RedactionPolicy(
      const RedactionSettings(names: NameRedaction.hide, roomNames: true),
      salt: const [1, 2, 3],
    );
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: RedactionScope(
          policy: policy,
          child: Scaffold(
            body: SizedBox(
                width: 72,
                child: FoldedChatColumn(
                  rows: const [
                    ChatTopRow(ChatEntry(
                        key: 'acct:room', roomId: 'room', name: _name))
                  ],
                  onRowTap: (_) {},
                )),
          )),
    ));
    await tester.pumpAndSettle();
    final hidden = tester.widget<ChatAvatar>(find.byType(ChatAvatar)).name;
    expect(hidden, isNot(_name));
    await mouse.moveTo(tester.getCenter(find.byType(ChatAvatar)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    _expectRight(tester, name: hidden);
    expect(find.text(_name, findRichText: true), findsNothing);
    await mouse.moveTo(const Offset(600, 310));
    await _showRail(tester, size: const Size(880, 620), square: true);
    await mouse.moveTo(tester.getCenter(find.byType(ChatAvatar)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_name, findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
