import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/molecules/desktop_emoji_picker_container.dart';
import 'package:commet/ui/molecules/emoticon_picker.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePack implements EmoticonPack {
  @override
  String get displayName => 'Faces';
  @override
  List<Emoticon> get emotes => const [];
  @override
  List<Emoticon> get emoji => const [];
  @override
  List<Emoticon> get stickers => const [];
  @override
  ImageProvider? get image => null;
  @override
  IconData? get icon => Icons.emoji_emotions;
  @override
  String get identifier => 'faces';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Vommet issue 1206: desktop emoji/sticker/GIF picker scales with window size
// on large or full-screen windows (>= 500x500) and can be resized by dragging
// its corners.
void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });

  tearDown(() => preferences.layoutOverride.set(null));

  Future<void> pumpComposer(WidgetTester tester,
      {required Size size, bool inset = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: inset ? 780 : size.width),
              child: MessageInput(
                client: _FakeClient(),
                insetChatField: inset,
                availibleEmoticons: [_FakePack()],
                availibleStickers: [_FakePack()],
              ),
            )
          ]),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(RandomEmojiButton));
    await tester.pumpAndSettle();
    expect(find.byType(EmoticonPicker), findsOneWidget);
  }

  Future<void> closePicker(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
  }

  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);
  final panel = find.byKey(const ValueKey('desktop-picker-panel'));
  Finder pickerSurface() =>
      panel.evaluate().isEmpty ? find.byType(EmoticonPicker) : panel;
  final grip = find.byKey(const ValueKey('desktop_picker_handle_top_left'));

  testWidgets(
    'desktop picker grows with window size on full-screen windows (issue 1206)',
    (tester) async {
      // Normal/compact window: 1366x768 stays at standard 500x500.
      await pumpComposer(tester, size: const Size(1366, 768));
      await openPicker(tester);
      final normalSize = tester.getSize(pickerSurface());
      expect(normalSize.width, 500.0);
      expect(normalSize.height, 500.0);
      await closePicker(tester);

      // Large/full-screen window (issue 1206 Windows full-screen 1920x1080):
      // picker grows beyond 500x500.
      await pumpComposer(tester, size: const Size(1920, 1080));
      await openPicker(tester);
      final largeSize = tester.getSize(pickerSurface());
      expect(largeSize.width, greaterThan(500.0));
      expect(largeSize.height, greaterThan(500.0));
      await closePicker(tester);
    },
    variant: desktop,
  );

  testWidgets('top-left grip follows the pointer and saves and resets size',
      (tester) async {
    await pumpComposer(tester, size: const Size(1920, 1080));
    await openPicker(tester);
    expect(grip, findsOneWidget);
    final start = tester.getRect(panel);
    const delta = Offset(-60, -50);
    await tester.drag(grip, delta);
    await tester.pumpAndSettle();
    final resized = tester.getRect(panel);

    expect(resized.left, closeTo(start.left + delta.dx, 1));
    expect(resized.top, closeTo(start.top + delta.dy, 1));
    expect(resized.bottom, closeTo(start.bottom, 1));
    expect(
        preferences.desktopEmojiPickerWidth.value, closeTo(resized.width, 1));
    expect(
        preferences.desktopEmojiPickerHeight.value, closeTo(resized.height, 1));
    expect(tester.getBottomLeft(grip).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(EmoticonPicker)).dy));

    await closePicker(tester);
    await openPicker(tester);
    expect(tester.getRect(panel), resized);

    await tester.tap(grip);
    await tester.pump(const Duration(milliseconds: 70));
    await tester.tap(grip);
    await tester.pumpAndSettle();
    expect(tester.getRect(panel), start);
    expect(preferences.desktopEmojiPickerWidth.value, 0);
    expect(preferences.desktopEmojiPickerHeight.value, 0);
    await closePicker(tester);
  }, variant: desktop);

  for (final viewport in [const Size(1920, 1080), const Size(1366, 768)]) {
    testWidgets('oversized saved picker stays above composer at $viewport',
        (tester) async {
      await preferences.desktopEmojiPickerWidth.set(1800);
      await preferences.desktopEmojiPickerHeight.set(1040);
      await pumpComposer(tester, size: viewport);
      await openPicker(tester);
      final picker = tester.getRect(panel);
      final button = tester.getRect(find.byType(RandomEmojiButton));
      expect(picker.top, greaterThanOrEqualTo(0));
      expect(picker.left, greaterThanOrEqualTo(0));
      expect(picker.right, lessThanOrEqualTo(viewport.width));
      expect(picker.bottom, lessThan(button.top));
      await closePicker(tester);
    }, variant: desktop);
  }

  testWidgets('inset Telegram composer keeps the picker inside the window',
      (tester) async {
    await pickLayoutStyle(LayoutStyle.telegram);
    addTearDown(() => pickLayoutStyle(LayoutStyle.discord));
    const viewport = Size(1920, 1080);
    await pumpComposer(tester, size: viewport, inset: true);
    await openPicker(tester);
    final initial = tester.getRect(panel);
    expect(initial.width, closeTo(672, 1));
    expect(initial.height, closeTo(626.4, 1));
    const delta = Offset(-80, -45);
    await tester.drag(grip, delta);
    await tester.pumpAndSettle();
    final resized = tester.getRect(panel);
    expect(resized.left, closeTo(initial.left + delta.dx, 1));
    expect(resized.top, closeTo(initial.top + delta.dy, 1));
    expect(resized.right, lessThanOrEqualTo(viewport.width));
    await closePicker(tester);
  }, variant: desktop);

  group('DesktopEmojiPickerGeometry', () {
    test('default size stays at minimum 500x500 on standard/compact windows',
        () {
      expect(DesktopEmojiPickerGeometry.defaultSize(const Size(1024, 768)),
          const Size(500, 500));
      expect(DesktopEmojiPickerGeometry.defaultSize(const Size(1280, 720)),
          const Size(500, 500));
      expect(DesktopEmojiPickerGeometry.defaultSize(const Size(1366, 768)),
          const Size(500, 500));
    });

    test('default size scales with window on large and full-screen windows',
        () {
      final size1080p =
          DesktopEmojiPickerGeometry.defaultSize(const Size(1920, 1080));
      expect(size1080p.width, closeTo(672.0, 0.1));
      expect(size1080p.height, closeTo(626.4, 0.1));

      final size1440p =
          DesktopEmojiPickerGeometry.defaultSize(const Size(2560, 1440));
      expect(size1440p.width, closeTo(896.0, 0.1));
      expect(size1440p.height, closeTo(835.2, 0.1));
    });

    test('default size does not exceed maximum bounds on ultra-large displays',
        () {
      final size4k =
          DesktopEmojiPickerGeometry.defaultSize(const Size(3840, 2160));
      expect(size4k.width, DesktopEmojiPickerGeometry.maxDefaultWidth);
      expect(size4k.height, DesktopEmojiPickerGeometry.maxDefaultHeight);
    });

    test('clampSize enforces 500x500 minimum and available window limits', () {
      const screen = Size(1920, 1080);
      expect(DesktopEmojiPickerGeometry.clampSize(const Size(300, 200), screen),
          const Size(500, 500));
      expect(
          DesktopEmojiPickerGeometry.clampSize(const Size(3000, 2000), screen),
          screen);
      expect(DesktopEmojiPickerGeometry.clampSize(const Size(720, 640), screen),
          const Size(720, 640));
    });
  });
}
