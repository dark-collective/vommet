import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/molecules/emoticon_picker.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

class _FakeGifs implements GifComponent {
  @override
  List<FavoriteGif> get favorites => const [];
  @override
  Stream get onFavoritesChanged => const Stream.empty();
  @override
  String get searchPlaceholder => "Search";
  @override
  Future<List<GifSearchResult>> search(String query) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Vommet issue 991: changing the emoticon picker's tab must leave the
// on-screen keyboard as it was. Phones and tablets get the picker in the
// composer (Vommet issue 939), which takes the keyboard's place until a search
// field brings it back.
void main() {
  final iOS = TargetPlatformVariant.only(TargetPlatform.iOS);
  final computer = TargetPlatformVariant.only(TargetPlatform.linux);
  const keyboardHeight = 360.0;
  const screens = {
    "iPad": Size(1024, 1366),
    "phone": Size(390, 844),
  };

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  tearDown(() => preferences.layoutOverride.set(null));

  late ValueNotifier<double> keyboardInset;

  /// The test binding has no keyboard, so its height follows the text input.
  void moveKeyboard(WidgetTester tester) {
    keyboardInset.value = tester.testTextInput.isVisible ? keyboardHeight : 0;
  }

  // The GIF page never settles (its sending spinner keeps ticking).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    moveKeyboard(tester);
    await tester.pump(const Duration(seconds: 1));
    moveKeyboard(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  /// A tablet gets the desktop layout. Tests can't override the platform
  /// that layout is picked from, so it's set by hand.
  Future<void> pumpScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await preferences.layoutOverride
        .set(size.width < 600 ? "mobile" : "desktop");
    await preferences.autoFocusMessageTextBox.set(false);
  }

  Future<void> pumpComposer(WidgetTester tester,
      {Size? size, bool gifSearch = true}) async {
    await pumpScreen(tester, size ?? screens["iPad"]!);
    await preferences.tenorGifSearchEnabled.set(gifSearch);
    keyboardInset = ValueNotifier(0);
    addTearDown(keyboardInset.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: MessageInput(
                client: _FakeClient(),
                availibleEmoticons: [_FakePack("Faces")],
                availibleStickers: [_FakePack("Frogs")],
                gifComponent: _FakeGifs(),
                showGifSearch: true,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  final composer = find
      .descendant(
          of: find.byType(MessageInput), matching: find.byType(TextField))
      .first;
  final search = find.descendant(
      of: find.byType(EmoticonPicker), matching: find.byType(TextField));

  Future<void> tapEmojiButton(WidgetTester tester) async {
    await tester.tap(find.byType(RandomEmojiButton));
    await settle(tester);
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tapEmojiButton(tester);
    expect(find.byType(EmoticonPicker), findsOneWidget);
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await settle(tester);
  }

  /// Whether [field] has the focus, and so the keyboard.
  bool focused(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

  bool hiding(WidgetTester tester) =>
      tester.testTextInput.log.any((call) => call.method == "TextInput.hide");

  /// Opens the picker with the keyboard up for the message box, the way
  /// the reported steps do. The picker takes the keyboard's place.
  Future<void> openPickerFromKeyboard(WidgetTester tester) async {
    await tester.tap(composer);
    await settle(tester);
    expect(focused(tester, composer), isTrue);
    expect(keyboardInset.value, keyboardHeight);

    await openPicker(tester);
    expect(tester.testTextInput.isVisible, isFalse);
  }

  for (final MapEntry(key: name, value: size) in screens.entries) {
    testWidgets('$name: picker in the composer, tabs make no text input calls',
        (tester) async {
      await pumpComposer(tester, size: size);
      await openPickerFromKeyboard(tester);
      final picker = tester.getRect(find.byType(EmoticonPicker));
      tester.testTextInput.log.clear();

      for (final tab in ["Sticker", "Gif", "Emoji"]) {
        await openTab(tester, tab);
        expect(tester.getRect(find.byType(EmoticonPicker)), picker,
            reason: tab);
      }

      expect(tester.testTextInput.log, isEmpty);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: iOS);

    testWidgets('$name: picker opened with no keyboard never brings it up',
        (tester) async {
      await pumpComposer(tester, size: size);
      tester.testTextInput.log.clear();

      await openPicker(tester);
      await openTab(tester, "Sticker");
      await openTab(tester, "Gif");
      await openTab(tester, "Emoji");

      expect(tester.testTextInput.log, isEmpty);
      expect(tester.testTextInput.isVisible, isFalse);
    }, variant: iOS);

    testWidgets('$name: changing tabs while searching keeps the keyboard',
        (tester) async {
      await pumpComposer(tester, size: size);
      await openPickerFromKeyboard(tester);
      await tester.tap(search);
      await settle(tester);
      expect(focused(tester, search), isTrue);
      expect(keyboardInset.value, keyboardHeight);
      final picker = tester.getRect(find.byType(EmoticonPicker));
      tester.testTextInput.log.clear();

      for (final tab in ["Sticker", "Gif", "Emoji"]) {
        await tester.tap(find.text(tab));
        // The picker must not drop behind the keyboard during the handover.
        for (var frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.getRect(find.byType(EmoticonPicker)), picker,
              reason: "$tab, frame $frame");
        }
        await settle(tester);
        // One field: the old tab's page isn't kept alive by its focus.
        expect(focused(tester, search), isTrue, reason: tab);
      }
      expect(tester.testTextInput.isVisible, isTrue);
      expect(hiding(tester), isFalse);
      expect(tester.takeException(), isNull);
    }, variant: iOS);
  }

  testWidgets('the emoji button moves the search keyboard to the message box',
      (tester) async {
    await pumpComposer(tester);
    await openPickerFromKeyboard(tester);
    await tester.tap(search);
    await settle(tester);
    await openTab(tester, "Sticker");

    tester.testTextInput.log.clear();
    await tapEmojiButton(tester);

    final state = tester.state<MessageInputState>(find.byType(MessageInput));
    expect(state.showEmotePicker, isFalse);
    expect(focused(tester, composer), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(hiding(tester), isFalse);
  }, variant: iOS);

  testWidgets('searching, a swipe moves the focus once the tab has changed',
      (tester) async {
    await pumpComposer(tester);
    await openPicker(tester);
    await tester.tap(search);
    await settle(tester);

    // A swipe let go early falls back to the same tab.
    final picker = tester.getCenter(find.byType(EmoticonPicker));
    final swipe = await tester.startGesture(picker);
    await swipe.moveBy(const Offset(-30, 0));
    await tester.pump();
    await swipe.moveBy(const Offset(-30, 0));
    await tester.pump();
    await swipe.moveBy(const Offset(50, 0));
    await tester.pump();
    await swipe.up();
    await settle(tester);
    expect(focused(tester, search), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    tester.testTextInput.log.clear();

    await tester.drag(find.byType(EmoticonPicker), const Offset(-800, 0));
    await settle(tester);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(search, findsOneWidget);
    expect(focused(tester, search), isTrue);
    expect(hiding(tester), isFalse);
  }, variant: iOS);

  testWidgets('a tab with no search field (GIF search off) changes nothing',
      (tester) async {
    await pumpComposer(tester, gifSearch: false);
    await openPicker(tester);
    await tester.tap(search);
    await settle(tester);

    await openTab(tester, "Gif");
    await openTab(tester, "Emoji");
    expect(tester.takeException(), isNull);
    expect(focused(tester, search), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  }, variant: iOS);

  // The reaction and home tab icon pickers are an EmojiPicker of their own,
  // with no composer to say it is in the keyboard's place.
  Future<void> pumpEmojiPicker(WidgetTester tester) async {
    await pumpScreen(tester, screens["iPad"]!);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body:
            EmojiPicker([_FakePack("Faces")], searchDelegate: (_) => const []),
      ),
    ));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  }

  testWidgets('an EmojiPicker of its own leaves an iPad keyboard hidden',
      (tester) async {
    await pumpEmojiPicker(tester);
    expect(tester.testTextInput.log, isEmpty);
    expect(tester.testTextInput.isVisible, isFalse);
  }, variant: iOS);

  testWidgets('on a computer an EmojiPicker focuses its search field',
      (tester) async {
    await pumpEmojiPicker(tester);
    expect(focused(tester, find.byType(TextField)), isTrue);
  }, variant: computer);

  testWidgets('on a computer each tab still focuses its search field',
      (tester) async {
    await pumpComposer(tester);

    await openPicker(tester);
    expect(focused(tester, search), isTrue);
    await openTab(tester, "Sticker");
    expect(focused(tester, search.first), isTrue);
    await openTab(tester, "Gif");
    expect(focused(tester, search.first), isTrue);

    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.byType(EmoticonPicker), findsNothing);
    expect(focused(tester, composer), isTrue);
  }, variant: computer);

  testWidgets('on a computer the composer can go away with the picker open',
      (tester) async {
    await pumpComposer(tester);
    await openPicker(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: computer);

  test('only phones and tablets count as having an on-screen keyboard', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(Layout.onScreenKeyboard,
          platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
