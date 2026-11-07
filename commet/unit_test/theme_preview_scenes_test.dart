import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_light.dart';

void main() {
  setUp(() async {
    // unit_test/ is not a recognized test directory for this annotation.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });
  const own = Color(0xff127658);
  const other = Color(0xff652375);
  ThemeData marked(ThemeData theme) => theme.copyWith(extensions: [
        ...theme.extensions.values.where((e) => e is! ExtraColors),
        (theme.extension<ExtraColors>() ??
                ExtraColors.fromScheme(theme.colorScheme))
            .copyWith(ownBubble: own, otherBubble: other),
      ]);
  Finder painted(Color color) => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).color == color);
  Future<void> show(WidgetTester tester, ThemeData theme, bool phone,
      {double desktopWidth = 800}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        phone ? const Size(390, 844) : const Size(1280, 900);
    await tester.pumpWidget(MaterialApp(
        theme: theme.copyWith(
            platform: phone ? TargetPlatform.android : TargetPlatform.linux),
        home: Scaffold(
          body: Center(
              child: SizedBox(
                  width: phone ? 366 : desktopWidth,
                  height: phone ? 220 : 500,
                  child: ThemeLivePreview(theme: theme, compact: phone))),
        )));
    await tester.pumpAndSettle();
  }

  for (final phone in [false, true]) {
    for (final style in LayoutStyle.values) {
      testWidgets(
          '1193 scenes and ${style.name} messages at ${phone ? '390px' : 'desktop'}',
          (tester) async {
        addTearDown(tester.view.reset);
        await pickLayoutStyle(style);
        if (style == LayoutStyle.custom) {
          await preferences.chatBubbleLayout.set(true);
          await ownBubbleSide.set(OwnBubbleSide.left.name);
        }
        final theme = marked(ThemeDark.theme);
        await show(tester, theme, phone);
        expect(find.text('Chat'), findsOneWidget);
        expect(find.text('Panels & popups'), findsOneWidget);
        expect(painted(other),
            style == LayoutStyle.discord ? findsNothing : findsWidgets);
        if (phone) {
          await tester.drag(
              find
                  .descendant(
                      of: find.byType(ThemeLivePreview),
                      matching: find.byType(ListView))
                  .first,
              const Offset(0, -350));
          await tester.pumpAndSettle();
        }
        expect(painted(own),
            style == LayoutStyle.discord ? findsNothing : findsOneWidget);
        await tester.tap(find.text('Panels & popups'));
        await tester.pumpAndSettle();
        expect(find.text('Settings panel'), findsOneWidget);
        final scroll = find.byKey(const ValueKey('theme-preview-samples'));
        await tester.drag(scroll, const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(find.text('Reply'), findsOneWidget);
        expect(find.text('Could not save — sample error'), findsOneWidget);
        final attachmentTab = find.text('Attachments');
        await tester.ensureVisible(attachmentTab);
        await tester.tap(attachmentTab);
        await tester.pumpAndSettle();
        expect(find.text('1 file'), findsOneWidget);
        expect(
            tester.getRect(find.text('1 file')).top,
            greaterThanOrEqualTo(
                tester.getRect(find.byType(ThemeLivePreview)).top));
        expect(find.text('Remove hidden info'), findsOneWidget);
        expect(find.text('Send smaller'), findsOneWidget);
        expect(find.text('Clear all'), findsOneWidget);
        await tester.drag(find.byKey(const ValueKey('theme-preview-samples')),
            const Offset(0, -500));
        await tester.pumpAndSettle();
        final before = preferences.sendSmallerPictures.value;
        await tester.tap(find.text('Clear all'), warnIfMissed: false);
        await tester.pump();
        expect(find.text('1 file'), findsOneWidget);
        expect(preferences.sendSmallerPictures.value, before);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      '1193 reacts to layout changes and keeps the scene on draft changes',
      (tester) async {
    addTearDown(tester.view.reset);
    await LayoutOptions.telegram.save();
    await show(tester, marked(ThemeDark.theme), false);
    expect(painted(own), findsOneWidget);
    await preferences.chatBubbleLayout.set(false);
    await tester.pumpAndSettle();
    expect(painted(own), findsNothing);
    await tester.tap(find.text('Panels & popups'));
    await tester.pumpAndSettle();
    for (final theme in [ThemeLight.theme, ThemeAmoled.theme]) {
      await show(tester, theme, false);
      expect(find.text('Settings panel'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is ChoiceChip &&
              w.selected &&
              w.label is Text &&
              (w.label as Text).data == 'Panels & popups'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      '1193 custom own-side follows the selected option and actual preview width',
      (tester) async {
    addTearDown(tester.view.reset);
    await LayoutOptions.telegram.save();
    await ownBubbleSide.set(OwnBubbleSide.left.name);
    await show(tester, marked(ThemeDark.theme), false);
    var left = tester.getRect(painted(own)).left;
    await ownBubbleSide.set(OwnBubbleSide.right.name);
    await tester.pumpAndSettle();
    expect(tester.getRect(painted(own)).left, greaterThan(left));
    await ownBubbleSide.set(OwnBubbleSide.rightWhenNarrow.name);
    await tester.pumpAndSettle();
    expect(tester.getRect(painted(own)).left, greaterThan(left));
    tester.view.physicalSize = const Size(1600, 900);
    final wideTheme = marked(ThemeDark.theme);
    await tester.pumpWidget(MaterialApp(
        theme: wideTheme,
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 1400,
                    height: 600,
                    child: ThemeLivePreview(theme: wideTheme))))));
    await tester.pumpAndSettle();
    expect(tester.getRect(painted(own)).left,
        tester.getRect(painted(other).first).left,
        reason:
            'Right when narrow uses the preview timeline width, not the window width');
    expect(tester.takeException(), isNull);
  });

  testWidgets('1193 limits the visible list message width live',
      (tester) async {
    addTearDown(tester.view.reset);
    await pickLayoutStyle(LayoutStyle.discord);
    final theme = ThemeDark.theme;
    await show(tester, theme, false, desktopWidth: 1000);
    final mention = find.byWidgetPredicate((w) =>
        w is Container && w.color == theme.colorScheme.tertiary.withAlpha(30));
    final fullWidth = tester.getSize(mention).width;
    await limitMessageWidth.set(true);
    await tester.pumpAndSettle();
    expect(tester.getSize(mention).width, lessThan(fullWidth));
    await limitMessageWidth.set(false);
    await tester.pumpAndSettle();
    expect(tester.getSize(mention).width, fullWidth);
  });

  testWidgets('1193 moves an incoming bubble avatar to the bottom live',
      (tester) async {
    addTearDown(tester.view.reset);
    await pickLayoutStyle(LayoutStyle.telegram);
    await avatarAtBottomOfGroup.set(false);
    await show(tester, marked(ThemeDark.theme), false);
    final avatar =
        find.ancestor(of: find.text('T'), matching: find.byType(CircleAvatar));
    final top = tester.getTopLeft(avatar).dy;
    await avatarAtBottomOfGroup.set(true);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(avatar).dy, greaterThan(top));
    await avatarAtBottomOfGroup.set(false);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(avatar).dy, top);
  });

  testWidgets('1193 attachment shape follows Custom and samples stay inert',
      (tester) async {
    addTearDown(tester.view.reset);
    await pickLayoutStyle(LayoutStyle.discord);
    final theme = ThemeDark.theme;
    await show(tester, theme, false);
    expect(find.text('Attachments'), findsOneWidget);
    await tester.tap(find.text('Attachments'));
    await tester.pumpAndSettle();
    final tray = painted(theme.colorScheme.surfaceContainerHigh);
    BorderRadiusGeometry? radius() =>
        (tester.widget<Container>(tray).decoration! as BoxDecoration)
            .borderRadius;

    final square = radius();
    await pickLayoutStyle(LayoutStyle.custom);
    await tester.pumpAndSettle();
    final rounded = radius();
    expect(rounded, isNot(square));

    await pickLayoutStyle(LayoutStyle.discord);
    await tester.pumpAndSettle();
    expect(radius(), square);
    await captionBelowMedia.set(true);
    await tester.pumpAndSettle();
    expect(radius(), rounded);
    await captionBelowMedia.set(false);
    await tester.pumpAndSettle();
    expect(radius(), square);
    await experimentUnifiedChatList.set(true);
    await tester.pumpAndSettle();
    expect(radius(), rounded);

    final sendSmaller =
        find.descendant(of: tray, matching: find.byType(Switch)).last;
    final position = tester.getCenter(sendSmaller);
    final hit = tester.hitTestOnBinding(position);
    expect(hit.path.map((entry) => entry.target),
        anyElement(isA<RenderAbsorbPointer>()));
    final before = preferences.sendSmallerPictures.value;
    await tester.tapAt(position);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(sendSmaller).value, isFalse);
    expect(preferences.sendSmallerPictures.value, before);

    final sample =
        tester.element(find.byKey(const ValueKey('theme-preview-samples')));
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus!.context! as Element;
      var inside = false;
      focused.visitAncestorElements((element) {
        inside = element == sample;
        return !inside;
      });
      expect(inside, isFalse);
    }
    expect(find.text('1 file'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pickLayoutStyle(LayoutStyle.telegram);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await show(tester, marked(theme), false);
    expect(painted(own), findsOneWidget);
    expect(find.text('1 file'), findsNothing);
  });
}
