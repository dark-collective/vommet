// Vommet issue 1192: neutral icons must not recolor timestamps or state glyphs.
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/config/layout_style.dart';
import 'package:commet/config/theme_config.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:commet/main.dart' as app;
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/atoms/thread_reply_footer.dart';
import 'package:commet/ui/molecules/message.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/pages/get_or_create_room/voice_chat_view.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_color_picker.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_editor_page.dart';
import 'package:commet/utils/clock_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/tiamat.dart' as t;

const iconInk = Color(0xff5ba7be);
const mutedInk = Color(0xffa67496);

Future<ThemeData> iconsTheme({bool picked = true}) async =>
    (await ThemeJsonConverter.fromJson({
      'base': 'dark',
      'colorScheme': {
        'secondary': '#a67496',
        if (picked) 'icons': '#5ba7be',
      },
    }, null))!;

Widget iconRoleSpecimen() => Builder(builder: (context) {
      final s = Theme.of(context).colorScheme;
      return Wrap(
          spacing: 12,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            t.IconButton(icon: Icons.search, onPressed: () {}),
            t.CircleButton(icon: Icons.add, onPressed: () {}),
            t.ImageButton(icon: Icons.tag, size: 40, onTap: () {}),
            const Icon(Icons.more_horiz),
            const t.IconButton(icon: Icons.close),
            t.IconButton(
                icon: Icons.star, iconColor: s.primary, onPressed: () {}),
            const t.Text.labelLow('12:42'),
            t.IconToggle(
                icon: Icons.visibility, state: true, onPressed: (_) {}),
            IconButton(icon: const Icon(Icons.cancel), onPressed: null),
            t.TextButton('Selected',
                icon: Icons.folder,
                highlighted: true,
                highlightTextColor: s.onPrimary,
                onTap: () {}),
            const RoomListCollapseButton(collapsed: false),
            SizedBox(
              height: 50,
              child: ThreadReplyFooter(
                  body: 'A reply', senderName: 'Mika', onTap: () {}),
            ),
            const VoiceChatCreatorDescription().buildVoiceChatMember(context,
                image:
                    const AssetImage('assets/images/placeholders/avatar1.jpg'),
                name: 'Mika',
                color: s.primary,
                mute: true),
            chatKindIcon(context, ChatKind.room)!,
            chatKindIcon(context, ChatKind.voice, voiceActive: true)!,
            Icon(Icons.error_outline, color: s.error),
          ]);
    });

Widget messageAndIcons() => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconRoleSpecimen(),
        Message(
          senderName: 'Mika',
          senderColor: Colors.teal,
          sentTimeStamp: DateTime(2026, 11, 5, 12, 42),
          body: const Text('Message body'),
          currentUserIdentifier: '@mika:example.org',
        ),
      ],
    );

Text messageTimestamp(WidgetTester tester) => tester.widget<Text>(
    find.descendant(of: find.byType(Message), matching: find.text('12:42')));

Color? glyphColor(WidgetTester tester, IconData data) {
  final finder = find.byIcon(data).first;
  final glyph = tester.widget<Icon>(finder);
  return glyph.color ?? IconTheme.of(tester.element(finder)).color;
}

void main() {
  setUp(() async {
    // unit_test is outside the analyzer's recognized test directory.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await app.preferences.init();
    await app.preferences.clockFormat.set(ClockStyle.twentyFourHour.name);
    await app.preferences.messageTimeSeconds.set(false);
  });

  test('picked icons survives draft copy, rebuild, web ZIP and reset',
      () async {
    final raw = {
      'base': 'dark',
      'colorScheme': {'secondary': '#a67496', 'icons': '#5ba7be'},
      'customUnrecognized': {'keep': true},
    };
    final draft = ThemeDraft.fromTheme(
        (await ThemeJsonConverter.fromJson(raw, null))!, 'Icons',
        raw: raw);
    // Fails on the base: unknown raw keys alone never populate the optional slot.
    expect(draft.colors['icons'], iconInk);
    for (final (hex, expected) in [
      ('5BA7BE', iconInk),
      ('#805ba7be', const Color(0x805ba7be)),
      ('805BA7BE', const Color(0x805ba7be)),
    ]) {
      final parsed = (await ThemeJsonConverter.fromJson({
        'base': 'dark',
        'colorScheme': {'icons': hex},
      }, null))!;
      expect(parsed.iconTheme.color, expected);
      expect(ThemeDraft.fromTheme(parsed, 'import').colors['icons'], expected);
    }
    for (final invalid in ['bad color', '#12345', '', ' 5ba7be', 23, null]) {
      final fallback = (await ThemeJsonConverter.fromJson({
        'base': 'dark',
        'colorScheme': {'icons': invalid},
      }, null))!;
      expect(fallback.iconTheme.color, ThemeDark.theme.iconTheme.color);
      expect(ThemeDraft.fromTheme(fallback, 'invalid').colors['icons'], isNull);
    }
    final json = draft.copy().toJson();
    final files = {
      'theme.json': Uint8List.fromList(utf8.encode(jsonEncode(json))),
      'background.png': Uint8List.fromList([1, 2, 3]),
    };
    final unpacked = ThemeConfig.themeFilesFromZip(ThemeDraft.zipFiles(files))!;
    final saved = ThemeConfig.webThemeJson(unpacked)!;
    expect(unpacked['background.png'], [1, 2, 3]);
    expect(saved['customUnrecognized'], {'keep': true});
    final reopened = ThemeDraft.fromTheme(
        (await ThemeJsonConverter.fromJson(saved, null))!, 'Copy',
        raw: saved);
    expect(reopened.colors['icons'], iconInk);
    reopened.colors.remove('icons');
    expect(
        (reopened.toJson()['colorScheme'] as Map).containsKey('icons'), false);
    expect((await reopened.build()).iconTheme.color,
        ThemeDark.theme.iconTheme.color);
    expect(reopened.colors['secondary'], mutedInk);
  });

  test(
      'extension copies and interpolation retain picked icons without changing text',
      () async {
    final theme = await iconsTheme();
    final extra = theme.extension<ExtraColors>()!;
    final copied =
        theme.copyWith(extensions: [extra.copyWith(linkColor: Colors.red)]);
    expect(ThemeDraft.fromTheme(copied, 'copy').colors['icons'], iconInk);
    final lerped = theme.copyWith(extensions: [extra.lerp(extra, .5)]);
    expect(ThemeDraft.fromTheme(lerped, 'lerp').colors['icons'], iconInk);
    expect(lerped.colorScheme.secondary, mutedInk);
  });

  testWidgets('Icons controls inherited and explicit neutral glyphs only',
      (tester) async {
    final theme = await iconsTheme();
    await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Material(child: ClockFormatScope(child: messageAndIcons()))));
    await tester.pumpAndSettle();
    for (final icon in [
      Icons.search,
      Icons.add,
      Icons.tag,
      Icons.more_horiz,
      Icons.message_rounded
    ]) {
      expect(glyphColor(tester, icon), iconInk, reason: '$icon');
    }
    expect(glyphColor(tester, Icons.star), theme.colorScheme.primary);
    expect(glyphColor(tester, Icons.visibility), theme.colorScheme.primary);
    expect(glyphColor(tester, Icons.folder), theme.colorScheme.onPrimary);
    expect(glyphColor(tester, Icons.close), mutedInk);
    expect(glyphColor(tester, Icons.error_outline), theme.colorScheme.error);
    final timestamp = messageTimestamp(tester);
    expect(timestamp.style!.color, mutedInk);
    expect(tester.takeException(), isNull);

    // A local semantic foreground still wins when it equals the neutral role.
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Material(
          child: IconTheme(
        data: const IconThemeData(color: iconInk),
        child: Builder(
            builder: (context) => const VoiceChatCreatorDescription()
                .buildVoiceChatMember(context,
                    image: const AssetImage(
                        'assets/images/placeholders/avatar1.jpg'),
                    name: 'Mika',
                    color: theme.colorScheme.primary,
                    mute: true)),
      )),
    ));
    await tester.pumpAndSettle();
    expect(glyphColor(tester, Icons.mic_off), iconInk);
    expect(tester.takeException(), isNull);

    const themedInk = Color(0xff229955);
    final themed =
        theme.copyWith(iconTheme: theme.iconTheme.copyWith(color: themedInk));
    await tester.pumpWidget(MaterialApp(
      theme: themed,
      home: Material(
          child: Builder(
              builder: (context) => const VoiceChatCreatorDescription()
                  .buildVoiceChatMember(context,
                      image: const AssetImage(
                          'assets/images/placeholders/avatar1.jpg'),
                      name: 'Mika',
                      color: theme.colorScheme.primary,
                      mute: true))),
    ));
    await tester.pumpAndSettle();
    expect(glyphColor(tester, Icons.mic_off), themedInk);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Automatic retains old inheritance and explicit controls; picking is independent',
      (tester) async {
    final legacy = await iconsTheme(picked: false);
    await tester.pumpWidget(MaterialApp(
        theme: legacy,
        home: Material(child: ClockFormatScope(child: messageAndIcons()))));
    await tester.pumpAndSettle();
    expect(glyphColor(tester, Icons.search), mutedInk);
    expect(
        glyphColor(tester, Icons.more_horiz), ThemeDark.theme.iconTheme.color);
    final voice = glyphColor(tester, Icons.volume_up);
    final disabled = glyphColor(tester, Icons.cancel);
    final muted = glyphColor(tester, Icons.mic_off);
    final picked = await iconsTheme();
    await tester.pumpWidget(MaterialApp(
        theme: picked,
        home: Material(child: ClockFormatScope(child: messageAndIcons()))));
    await tester.pumpAndSettle();
    expect(glyphColor(tester, Icons.search), iconInk);
    expect(glyphColor(tester, Icons.volume_up), voice);
    expect(glyphColor(tester, Icons.cancel), disabled);
    expect(glyphColor(tester, Icons.mic_off), muted);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'neutral glyph and timestamp separation works across themes, sizes and layouts',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const custom = LayoutOptions(
        oneChatList: true,
        captionBelow: false,
        limitWidth: true,
        bubbles: true,
        ownSide: OwnBubbleSide.left,
        avatarAtBottom: false);
    for (final base in [ThemeDark.theme, ThemeLight.theme, ThemeAmoled.theme]) {
      final draft = ThemeDraft.fromTheme(base, 'Icons')
        ..colors['icons'] = iconInk;
      final theme = await draft.build();
      for (final layout in [
        LayoutOptions.discord,
        LayoutOptions.telegram,
        custom
      ]) {
        await layout.save();
        for (final size in [
          const Size(1440, 900),
          const Size(390, 844),
          const Size(360, 800)
        ]) {
          await app.preferences.layoutOverride
              .set(size.width < 600 ? 'mobile' : 'desktop');
          await tester.binding.setSurfaceSize(size);
          await tester.pumpWidget(MaterialApp(
              theme: theme,
              home:
                  Material(child: ClockFormatScope(child: messageAndIcons()))));
          await tester.pumpAndSettle();
          expect(glyphColor(tester, Icons.search), iconInk);
          expect(messageTimestamp(tester).style!.color,
              theme.colorScheme.secondary);
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('editor picks Icons from Automatic and resets the saved override',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final draft =
        ThemeDraft.fromTheme(await iconsTheme(picked: false), 'Icons theme');
    await tester.pumpWidget(MaterialApp(home: ThemeEditorPage(draft: draft)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Find a color'), 'Icons');
    await tester.pumpAndSettle();
    final rowLabel =
        find.byWidgetPredicate((w) => w is Text && w.data == 'Icons');
    expect(rowLabel, findsOneWidget);
    await tester.tap(rowLabel);
    await tester.pumpAndSettle();
    final picker = find.byType(ThemeColorPicker);
    expect(tester.widget<ThemeColorPicker>(picker).initial, mutedInk);
    final hex = find.descendant(of: picker, matching: find.byType(TextField));
    await tester.enterText(hex, '#5ba7be');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    expect(find.text('#5BA7BE'), findsOneWidget);
    await tester.tap(rowLabel);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use automatic'));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(ThemeEditorPage));
    final edited = state.draft as ThemeDraft;
    expect(edited.colors.containsKey('icons'), false);
    expect((edited.toJson()['colorScheme'] as Map).containsKey('icons'), false);
    expect(find.text('Automatic'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
