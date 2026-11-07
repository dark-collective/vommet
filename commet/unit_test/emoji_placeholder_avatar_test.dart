// Vommet issue 1183: exercise the collapsed room-icon path and its expanded
// room/preview counterparts. The issue gives screenshots rather than dp sizes;
// 64 dp is ResponsiveDesktop.compactListWidth, not a guessed avatar width.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/client/components/component.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_preview_text_button.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/sidebar_room_icon.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import 'helpers/unread_fixtures.dart';

class _Client extends UnreadClient {
  @override
  T? getComponent<T extends Component>() => null;
}

class _Permissions extends Permissions {}

class _Room extends UnreadRoom {
  _Room(super.client, super.identifier, this.displayName);
  @override
  final String displayName;
  @override
  ImageProvider? get avatar => null;
  @override
  Color get defaultColor => Colors.teal;
  @override
  bool get isSpecialRoomType => false;
  @override
  Permissions get permissions => _Permissions();
}

const _names = {
  '💬 Community Centre': '💬',
  '🛜 Tech': '🛜',
  '🎭️ Memes Channel': '🎭️',
  'ℹ️ Information': 'ℹ️',
  '⛱️ Off-Topic': '⛱️',
  '👩🏽‍💻 Developers': '👩🏽‍💻',
  '🇺🇸 Community': '🇺🇸',
  '𐐨 Letters': '𐐀',
  'e\u0301 Cafe': 'E\u0301',
  'garden': 'G',
};

void main() {
  late _Client client;
  final boundary = GlobalKey();
  setUp(() async {
    // unit_test/ isn't a recognized test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.showRoomAvatars.set(true);
    await preferences.usePlaceholderRoomAvatars.set(true);
    client = _Client();
    clientManager = null;
  });
  tearDown(() async {
    for (final room in client.rooms) {
      await (room as _Room).updates.close();
    }
    await client.close();
  });

  Widget surface(List<_Room> rooms, {required ThemeData theme}) => MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 284,
                  height: rooms.length * 64,
                  child: RepaintBoundary(
                    key: boundary,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: ResponsiveDesktop.compactListWidth,
                              child: Column(children: [
                                for (final room in rooms)
                                  SidebarRoomIcon(room,
                                      key: ValueKey(
                                          'compact-${room.identifier}'),
                                      width:
                                          ResponsiveDesktop.compactListWidth),
                              ]),
                            ),
                            SizedBox(
                              width: 220,
                              child: Column(children: [
                                for (final room in rooms)
                                  RoomTextButton(room,
                                      key: ValueKey(
                                          'expanded-${room.identifier}')),
                              ]),
                            ),
                          ]),
                    ),
                  ))),
        ),
      );

  for (final style in LayoutStyle.values) {
    for (final phone in [false, true]) {
      testWidgets(
          '$style ${phone ? "phone 390" : "desktop 1200"}: full graphemes on both paths',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(phone ? 390 : 1200, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
        await pickLayoutStyle(style);
        final rooms = [
          for (final entry in _names.entries)
            _Room(client, entry.key, entry.key),
        ];
        await tester.pumpWidget(surface(rooms, theme: ThemeDark.theme));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final entry in _names.entries) {
          final compact = find.byKey(ValueKey('compact-${entry.key}'));
          final expanded = find.byKey(ValueKey('expanded-${entry.key}'));
          expect(find.descendant(of: compact, matching: find.text(entry.value)),
              findsOneWidget,
              reason:
                  'collapsed ${entry.key} must paint the whole first grapheme');
          expect(
              find.descendant(of: expanded, matching: find.text(entry.value)),
              findsOneWidget);
          final semantics = tester.widgetList<Semantics>(
              find.descendant(of: compact, matching: find.byType(Semantics)));
          expect(semantics.any((s) => s.properties.label == entry.key), isTrue,
              reason: 'the full room name remains the accessible label');
          if (TextUtils.isEmoji(entry.key.characters.first)) {
            final colors = tester
                .widgetList<Material>(find.descendant(
                    of: compact, matching: find.byType(Material)))
                .map((m) => m.color);
            expect(colors, contains(Colors.transparent));
          }
        }
        for (final entry in _names.entries) {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeDark.theme,
            home: SizedBox(
                width: 220,
                child: RoomPreviewTextButton(GenericRoomPreview(entry.key,
                    displayName: entry.key, type: null))),
          ));
          await tester.pumpAndSettle();
          expect(find.text(entry.value), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('ImageButton siblings keep complex initials, empty and semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();

    try {
      for (final entry in {..._names, '': ''}.entries) {
        await tester.pumpWidget(MaterialApp(
            home: tiamat.ImageButton(
                size: 64, placeholderText: entry.key, onTap: () {})));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (entry.value.isNotEmpty)
          expect(find.text(entry.value), findsOneWidget);
        expect(tester.getSemantics(find.byType(tiamat.ImageButton)).label,
            entry.key);
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty room names render without exceptions', (tester) async {
    final room = _Room(client, 'empty', '');
    await tester.pumpWidget(surface([room], theme: ThemeDark.theme));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('empty preview names render without exceptions', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: RoomPreviewTextButton(
            GenericRoomPreview('empty', displayName: '', type: null))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // Optional real-widget captures, deliberately kept in this fixture so before
  // and after use identical widgets, data, widths and theme surfaces.
  const captureDir = String.fromEnvironment('CAPTURE_DIR');
  if (captureDir.isNotEmpty) {
    testWidgets('matched real room-icon captures', (tester) async {
      // The local engine reports malformed UTF-16 and leaves the glyph blank;
      // the reporter's Flatpak paints a replacement glyph. Capture the actual
      // base result without rewriting text or substituting a fake glyph.
      const before = String.fromEnvironment('CAPTURE_PHASE') == 'Before';
      final previousErrorHandler = FlutterError.onError;
      var invalidTextErrors = 0;
      FlutterError.onError = (details) {
        if (before &&
            details.exception is ArgumentError &&
            details.exception.toString().contains('not well-formed UTF-16')) {
          invalidTextErrors++;
        } else {
          previousErrorHandler?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      await tester.runAsync(() async {
        for (final font in {
          'RobotoCustom': 'assets/font/roboto/Roboto-Regular.ttf',
          'NunitoSans':
              'assets/font/nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf',
          'EmojiFont': 'assets/font/emoji-font/TwemojiCOLR.otf',
        }.entries) {
          final file = File(font.value);
          if (file.existsSync()) {
            final loader = FontLoader(font.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes())));
            await loader.load();
          }
        }
      });
      final rooms = [
        for (final name in _names.keys.take(5)) _Room(client, name, name)
      ];
      for (final phone in [false, true]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(phone ? 390 : 1200, 900);
        for (final theme in {
          'Dark': ThemeDark.theme,
          'Light': ThemeLight.theme,
          'AMOLED': ThemeAmoled.theme
        }.entries) {
          await preferences.layoutOverride.set(phone ? 'mobile' : 'desktop');
          await pickLayoutStyle(LayoutStyle.discord);
          await tester.pumpWidget(surface(rooms, theme: theme.value));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final png =
                (await image.toByteData(format: ui.ImageByteFormat.png))!;
            await File(
                    '$captureDir/${const String.fromEnvironment("CAPTURE_PHASE")}-${theme.key}-${phone ? "phone" : "desktop"}.png')
                .writeAsBytes(png.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      if (before) expect(invalidTextErrors, greaterThan(0));
      debugPrint('Capture malformed UTF-16 paint errors: $invalidTextErrors');
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
    });
  }
}
