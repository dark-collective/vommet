import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/molecules/emoticon_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

/// A pack with no images; the picker only needs it to exist.
class _FakePack implements EmoticonPack {
  _FakePack(this.displayName);

  @override
  final String displayName;

  @override
  List<Emoticon> get emotes => const [];
  @override
  List<Emoticon> get emoji => const [];
  @override
  List<Emoticon> get stickers => const [];
  @override
  ImageProvider? get image => null;
  @override
  IconData? get icon => Icons.star;
  @override
  String get identifier => displayName;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
  });

  Future<void> pump(WidgetTester tester, List<EmoticonPack> stickers) {
    return tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: EmoticonPicker(
            emoji: const [],
            stickers: stickers,
            onImportPressed: () {},
          ),
        ),
      ),
    ));
  }

  testWidgets('no sticker packs: no Sticker tab', (tester) async {
    await pump(tester, const []);
    await tester.pump();
    expect(find.text("Sticker"), findsNothing);
  });

  testWidgets('first sticker pack added while open shows the Sticker tab',
      (tester) async {
    await pump(tester, const []);
    await tester.pump();
    expect(find.text("Sticker"), findsNothing);

    await pump(tester, [_FakePack("Mossy Frogs")]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("Emoji"), findsOneWidget);
    expect(find.text("Sticker"), findsOneWidget);

    await tester.tap(find.text("Sticker"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('last sticker pack removed: back to the Emoji tab only',
      (tester) async {
    await pump(tester, [_FakePack("Mossy Frogs")]);
    await tester.pump();
    await tester.tap(find.text("Sticker"));
    await tester.pumpAndSettle();

    await pump(tester, const []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text("Sticker"), findsNothing);
  });
}
