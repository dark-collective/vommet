import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
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

// Vommet issue 991: an iPad gets the desktop layout, but changing the emoticon
// picker's tab must leave its on-screen keyboard as it was.
void main() {
  final iPad = TargetPlatformVariant.only(TargetPlatform.iOS);

  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  // The GIF page never settles (its sending spinner keeps ticking).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpComposer(WidgetTester tester,
      {bool gifSearch = true}) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await preferences.tenorGifSearchEnabled.set(gifSearch);
    await preferences.autoFocusMessageTextBox.set(false);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: Align(
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
    ));
    await tester.pump();
  }

  final composer = find.descendant(
      of: find.byType(MessageInput), matching: find.byType(TextField));
  final search = find.descendant(
      of: find.byType(EmoticonPicker), matching: find.byType(TextField));

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byType(RandomEmojiButton));
    await settle(tester);
    expect(find.byType(EmoticonPicker), findsOneWidget);
  }

  Future<void> closePicker(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.byType(EmoticonPicker), findsNothing);
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

  testWidgets('a keyboard that is showing is left alone', (tester) async {
    await pumpComposer(tester);
    await tester.tap(composer);
    await settle(tester);
    expect(focused(tester, composer), isTrue);
    tester.testTextInput.log.clear();

    await openPicker(tester);
    await openTab(tester, "Sticker");
    await openTab(tester, "Gif");
    await openTab(tester, "Emoji");
    await closePicker(tester);

    expect(focused(tester, composer), isTrue);
    expect(tester.testTextInput.log.map((call) => call.method),
        isNot(contains("TextInput.clearClient")));
    expect(tester.testTextInput.log.map((call) => call.method),
        isNot(contains("TextInput.setClient")));
    expect(hiding(tester), isFalse);
  }, variant: iPad);

  testWidgets('a hidden keyboard stays hidden, also after closing the picker',
      (tester) async {
    await pumpComposer(tester);
    tester.testTextInput.log.clear();

    await openPicker(tester);
    await openTab(tester, "Sticker");
    await openTab(tester, "Gif");
    await openTab(tester, "Emoji");
    await closePicker(tester);

    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.testTextInput.log.map((call) => call.method),
        isNot(contains("TextInput.setClient")));
    expect(focused(tester, composer), isFalse);
  }, variant: iPad);

  testWidgets(
      'changing tabs while searching keeps the keyboard, on the new tab',
      (tester) async {
    await pumpComposer(tester);
    await openPicker(tester);
    await tester.tap(search);
    await settle(tester);
    expect(focused(tester, search), isTrue);
    tester.testTextInput.log.clear();

    for (final tab in ["Sticker", "Gif", "Emoji"]) {
      await openTab(tester, tab);
      // One field: the old tab's page isn't kept alive by its focus.
      expect(focused(tester, search), isTrue, reason: tab);
    }
    expect(tester.testTextInput.isVisible, isTrue);
    expect(hiding(tester), isFalse);

    // The keyboard stays open for the message box.
    await closePicker(tester);
    expect(focused(tester, composer), isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(hiding(tester), isFalse);
  }, variant: iPad);

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

    await tester.drag(find.byType(EmoticonPicker), const Offset(-400, 0));
    await settle(tester);
    expect(find.text("Search"), findsOneWidget);
    expect(focused(tester, search), isTrue);
    expect(hiding(tester), isFalse);
  }, variant: iPad);

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
  }, variant: iPad);

  testWidgets('on a computer each tab still focuses its search field',
      (tester) async {
    await pumpComposer(tester);

    await openPicker(tester);
    expect(focused(tester, search), isTrue);
    await openTab(tester, "Sticker");
    expect(focused(tester, search.first), isTrue);
    await openTab(tester, "Gif");
    expect(focused(tester, search.first), isTrue);

    await closePicker(tester);
    expect(focused(tester, composer), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  test('only phones and tablets count as having an on-screen keyboard', () {
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(Layout.onScreenKeyboard,
          platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
