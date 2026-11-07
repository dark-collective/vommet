import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/telegram_theme_import.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/message_box.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:commet/ui/molecules/composer_ring_colors.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_light.dart';

class ComposerColorsClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const composerFill = Color(0xff363a40);
const composerEdge = Color(0xff535961);

ThemeData withComposerColors(ThemeData theme,
        {Color? background = composerFill, Color? border = composerEdge}) =>
    theme.copyWith(extensions: [
      ...theme.extensions.values.where((e) => e is! ExtraColors),
      theme
          .extension<ExtraColors>()!
          .copyWith(composerBackground: background, composerBorder: border),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    // unit_test/ is not a recognized test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test('legacy light, dark and AMOLED retain their fill and no border',
      () async {
    for (final source in [
      ThemeLight.theme,
      ThemeDark.theme,
      ThemeAmoled.theme
    ]) {
      final draft = ThemeDraft.fromTheme(source, 'Legacy');
      final json = draft.toJson();
      final scheme = json['colorScheme'] as Map;
      expect(scheme.containsKey(ThemeSlot.composerBackgroundKey), isFalse);
      expect(scheme.containsKey(ThemeSlot.composerBorderKey), isFalse);
      final built = (await ThemeJsonConverter.fromJson(json, null))!;
      expect(MessageBox.backgroundColor(built),
          source.colorScheme.surfaceContainerLow);
      expect(built.extension<ExtraColors>()!.composerBorder, isNull);
    }
  });

  test('fill and border independently round-trip; resetting removes raw keys',
      () async {
    for (final colors in [
      {ThemeSlot.composerBackgroundKey: const Color(0x88363a40)},
      {ThemeSlot.composerBorderKey: composerEdge},
      {
        ThemeSlot.composerBackgroundKey: composerFill,
        ThemeSlot.composerBorderKey: composerEdge
      },
    ]) {
      final draft = ThemeDraft.fromTheme(ThemeDark.theme, 'Custom');
      draft.colors.addAll(colors);
      final json = draft.toJson();
      final built = (await ThemeJsonConverter.fromJson(json, null))!;
      final copy = ThemeDraft.fromTheme(built, 'Custom', raw: json).copy();
      for (final key in [
        ThemeSlot.composerBackgroundKey,
        ThemeSlot.composerBorderKey
      ]) {
        expect(ThemeSlot.read(built, key), colors[key]);
        expect(copy.colors[key], colors[key]);
        copy.colors.remove(key);
        expect((copy.toJson()['colorScheme'] as Map).containsKey(key), isFalse);
      }
      expect(built.colorScheme.surfaceContainerLow,
          ThemeDark.theme.colorScheme.surfaceContainerLow);
    }
  });

  test('theme interpolation and copying retain composer colors', () {
    final a = withComposerColors(ThemeDark.theme).extension<ExtraColors>()!;
    final b = withComposerColors(ThemeLight.theme,
            background: const Color(0xffe8eaee),
            border: const Color(0xffc6cbd2))
        .extension<ExtraColors>()!;
    final mid = a.lerp(b, 0.5) as ExtraColors;
    expect(mid.composerBackground,
        Color.lerp(a.composerBackground, b.composerBackground, 0.5));
    expect(mid.composerBorder,
        Color.lerp(a.composerBorder, b.composerBorder, 0.5));
    final copied = a.copyWith(linkColor: Colors.red) as ExtraColors;
    expect(copied.composerBackground, composerFill);
    expect(copied.composerBorder, composerEdge);
  });

  test(
      'Telegram imports explicit composer fills without inventing missing ones',
      () async {
    for (final supplied in [false, true]) {
      final desktop = TelegramThemeImport.fromDesktop({
        'windowBg': 0xff17212b,
        if (supplied) 'historyComposeAreaBg': 0xff363a40,
      }, 'Desktop');
      final android =
          TelegramThemeImport.fromAndroid(Uint8List.fromList(utf8.encode('''
windowBackgroundWhite=-15263977
${supplied ? 'chat_messagePanelBackground=-13223360' : ''}
''')), 'Android')!;
      for (final draft in [desktop, android]) {
        expect(draft.colors[ThemeSlot.composerBackgroundKey],
            supplied ? composerFill : null);
        expect(draft.colors[ThemeSlot.composerBorderKey], isNull);
        final built =
            (await ThemeJsonConverter.fromJson(draft.toJson(), null))!;
        expect(built.extension<ExtraColors>()!.composerBackground,
            supplied ? composerFill : null);
      }
    }
  });

  Future<void> pump(WidgetTester tester,
      {required ThemeData theme,
      bool custom = true,
      bool expanded = false,
      bool reply = false,
      double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
            size: tester.view.physicalSize,
            textScaler: TextScaler.linear(scale)),
        child: Scaffold(
            body: Column(children: [
          if (!expanded) const Spacer(),
          Flexible(
              flex: expanded ? 1 : 0,
              child: MessageInput(
                client: ComposerColorsClient(),
                useComposerColors: custom,
                compact: !custom,
                showAttachmentButton: custom,
                availibleEmoticons: const [],
                initialText: 'A draft message',
                expanded: expanded ? ValueNotifier(true) : null,
                interactionType: reply ? EventInteractionType.reply : null,
                relatedEventBody: reply ? 'Earlier message' : null,
                relatedEventSenderName: reply ? 'Maya' : null,
                onSendMessage: (message, {overrideClient}) =>
                    MessageInputSendResult.success,
              )),
        ])),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Container painted(WidgetTester tester) => tester.widget<Container>(find
      .descendant(of: find.byType(MessageBox), matching: find.byType(Container))
      .first);

  for (final layout in LayoutStyle.values) {
    for (final device in ['mobile', 'desktop']) {
      testWidgets('$layout $device: fill and border do not move controls',
          (tester) async {
        await preferences.layoutOverride.set(device);
        await pickLayoutStyle(layout);
        tester.view.physicalSize = Size(device == 'mobile' ? 390 : 1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pump(tester, theme: ThemeDark.theme);
        final field =
            tester.getRect(find.byKey(const ValueKey('composer-input-field')));
        await pump(tester, theme: withComposerColors(ThemeDark.theme));
        expect(
            tester.getRect(find.byKey(const ValueKey('composer-input-field'))),
            field);
        expect(
            (painted(tester).decoration! as BoxDecoration).color, composerFill);
        final border = (painted(tester).foregroundDecoration! as BoxDecoration)
            .border! as Border;
        expect(border.top, const BorderSide(color: composerEdge, width: 1));
        final state =
            tester.state<MessageInputState>(find.byType(MessageInput));
        expect(state.ringColors([ComposerRingState.reading]), [
          ringColor(ComposerRingState.reading.homeHue,
              ThemeDark.theme.colorScheme.primary, composerFill)
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('expanded reply uses box colors; quote stays outside the box',
      (tester) async {
    await preferences.layoutOverride.set('mobile');
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester,
        theme: withComposerColors(ThemeAmoled.theme),
        expanded: true,
        reply: true,
        scale: 1.5);
    expect((painted(tester).decoration! as BoxDecoration).color, composerFill);
    final quote = find.text('Earlier message');
    expect(quote, findsOneWidget);
    expect(find.descendant(of: find.byType(MessageBox), matching: quote),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bio opt-out keeps legacy fill and no border', (tester) async {
    await pump(tester,
        theme: withComposerColors(ThemeDark.theme), custom: false);
    expect((painted(tester).decoration! as BoxDecoration).color,
        ThemeDark.theme.colorScheme.surfaceContainerLow);
    expect(painted(tester).foregroundDecoration, isNull);
  });
  for (final device in ['mobile', 'desktop']) {
    testWidgets('$device: editor changes and resets the optional border',
        (tester) async {
      await preferences.layoutOverride.set(device);
      tester.view.physicalSize = Size(device == 'mobile' ? 390 : 1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme,
        home: ThemeEditorPage(
            draft: ThemeDraft.fromTheme(
                withComposerColors(ThemeDark.theme), 'Test')),
      ));
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.prefixIcon is Icon);
      final editorList = find.byKey(const ValueKey('theme-editor-controls'));
      final scrollable = find
          .descendant(of: editorList, matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(search, 200, scrollable: scrollable);
      await tester.enterText(search, 'message box');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Message box border'), 100,
          scrollable: scrollable);
      await tester.tap(find.text('Message box border').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final hex = find.descendant(
          of: find.byType(ThemeColorPicker), matching: find.byType(TextField));
      await tester.enterText(hex, '#717273');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').last);
      await tester.pumpAndSettle();
      expect(find.text('#717273'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Message box border'), 100,
          scrollable: scrollable);
      await tester.tap(find.text('Message box border').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use automatic'));
      await tester.pumpAndSettle();
      expect(find.text('Automatic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('an automatic border can be picked visibly with the color square',
      (tester) async {
    await preferences.layoutOverride.set('desktop');
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: ThemeEditorPage(
          draft: ThemeDraft.fromTheme(ThemeDark.theme, 'Legacy')),
    ));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.prefixIcon is Icon);
    final list = find.byKey(const ValueKey('theme-editor-controls'));
    final scrollable =
        find.descendant(of: list, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(search, 200, scrollable: scrollable);
    await tester.enterText(search, 'message box');
    await tester.pumpAndSettle();
    final border = find.text('Message box border');
    await tester.scrollUntilVisible(border, 100, scrollable: scrollable);
    await tester.tap(border);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ThemeColorPicker>(find.byType(ThemeColorPicker))
            .initial
            .a,
        1);
    final square = find
        .descendant(
            of: find.byType(ThemeColorPicker),
            matching: find.byType(GestureDetector))
        .first;
    await tester.drag(square, const Offset(12, 8));
    await tester.pumpAndSettle();
    final hex = tester
        .widget<TextField>(find.descendant(
            of: find.byType(ThemeColorPicker),
            matching: find.byType(TextField)))
        .controller!
        .text;
    expect(hex.length, 7,
        reason: 'Picking from Automatic creates an opaque #RRGGBB border');
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.text(hex.toUpperCase()), findsWidgets);
    expect(find.text('Automatic'), findsOneWidget,
        reason: 'Only the background is still automatic');
    expect(tester.takeException(), isNull);
  });
}
