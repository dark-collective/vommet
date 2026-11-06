import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/random_emoji_button.dart';
import 'package:commet/ui/molecules/emoticon_picker.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
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

// Vommet issue 939: an iPad gets the desktop room layout, but its picker
// replaces the on-screen keyboard at the full composer width.
void main() {
  setUp(() async {
    // unit_test/ isn't a recognised test directory for the analyzer.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    await preferences.layoutOverride.set('desktop');
  });

  tearDown(() => preferences.layoutOverride.set(null));

  Future<ValueNotifier<double>> pumpComposer(
    WidgetTester tester, {
    required Size size,
    double keyboardHeight = 360,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keyboardInset = ValueNotifier(keyboardHeight);
    addTearDown(keyboardInset.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
        body: ValueListenableBuilder<double>(
          valueListenable: keyboardInset,
          builder: (context, inset, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: MessageInput(
                client: _FakeClient(),
                availibleEmoticons: [_FakePack()],
                availibleStickers: [_FakePack()],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return keyboardInset;
  }

  Future<void> openInlinePicker(WidgetTester tester) async {
    final composer = find.descendant(
      of: find.byType(MessageInput),
      matching: find.byType(TextField),
    );
    await tester.tap(composer);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      MediaQuery.of(tester.element(find.byType(MessageInput)))
          .viewInsets
          .bottom,
      360,
    );

    await tester.tap(find.byType(RandomEmojiButton));
    await tester.pumpAndSettle();
    expect(find.byType(EmoticonPicker), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byType(RandomEmojiButton),
            matching: find.byType(JustTheTooltip)),
        findsNothing);
    final editable = find
        .descendant(
          of: composer,
          matching: find.byType(EditableText),
        )
        .first;
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  }

  Future<void> checkIPadLayout(WidgetTester tester, Size size) async {
    const keyboardHeight = 360.0;
    final keyboardInset =
        await pumpComposer(tester, size: size, keyboardHeight: keyboardHeight);
    await openInlinePicker(tester);

    // Simulate iPadOS finishing the keyboard dismissal. The picker keeps the
    // captured keyboard height and stays open.
    keyboardInset.value = 0;
    await tester.pumpAndSettle();
    final picker = tester.getRect(find.byType(EmoticonPicker));
    final input = tester.getRect(find.byType(MessageInput));
    expect(picker.left, closeTo(input.left, 0.1));
    expect(picker.right, closeTo(input.right, 0.1));
    expect(picker.height, closeTo(keyboardHeight, 1));
    expect(find.byType(EmoticonPicker), findsOneWidget);

    // The same button returns to the keyboard and removes the picker.
    await tester.tap(find.byType(RandomEmojiButton));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.byType(EmoticonPicker), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
  }

  final iPad = TargetPlatformVariant.only(TargetPlatform.iOS);

  testWidgets('portrait: picker replaces the keyboard at composer width',
      (tester) => checkIPadLayout(tester, const Size(1024, 1366)),
      variant: iPad);

  testWidgets('landscape: picker replaces the keyboard at composer width',
      (tester) => checkIPadLayout(tester, const Size(1366, 1024)),
      variant: iPad);

  testWidgets('computer keeps the 500 point tooltip picker', (tester) async {
    await pumpComposer(tester, size: const Size(1366, 1024));
    await tester.tap(find.byType(RandomEmojiButton));
    await tester.pumpAndSettle();

    expect(
        find.ancestor(
            of: find.byType(RandomEmojiButton),
            matching: find.byType(JustTheTooltip)),
        findsOneWidget);
    expect(find.byType(EmoticonPicker), findsOneWidget);
    expect(tester.getSize(find.byType(EmoticonPicker)).width, 500);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
