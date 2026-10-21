// Vommet issue 524: the first-run onboarding pages, Skip and Back, and the
// settings they set.
import 'package:commet/client/client.dart';
import 'package:commet/config/message_density.dart';
import 'package:commet/config/room_encryption_default.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creator.dart';
import 'package:commet/ui/pages/settings/categories/app/message_density_settings.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/ui/pages/setup/onboarding/layout_preview.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Page extends OnboardingMenu {
  _Page(this.title);

  @override
  final String title;

  @override
  String get body => "body of $title";

  @override
  Widget content(BuildContext context) => const SizedBox(height: 10);
}

class _Other implements SetupMenu {
  bool submitted = false;

  @override
  Widget builder(BuildContext context) => const Text("other page");

  @override
  Stream<SetupMenuState> get onStateChanged => const Stream.empty();

  @override
  SetupMenuState get state => SetupMenuState.canProgress;

  @override
  Future<void> submit() async => submitted = true;
}

void main() {
  setUp(() async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  Widget app(Widget child) => MaterialApp(
        theme: ThemeDark.theme,
        home: Scaffold(body: child),
      );

  /// Opens a SetupPage of [menus] from a button, so it can pop.
  Future<void> openSetup(WidgetTester tester, List<SetupMenu> menus) async {
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => SetupPage(menus))),
            child: const Text("open")))));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  test("the pages, language first and GIF search last", () {
    final menus = OnboardingSetup.menus();
    expect(menus.map((m) => m.runtimeType), [
      OnboardingLanguage,
      OnboardingLayout,
      OnboardingTheme,
      OnboardingDensity,
      OnboardingEncryption,
      OnboardingGifSearch,
    ]);
  });

  test("defaults: cozy messages, new rooms encrypted, not shown yet", () {
    expect(messageDensity, MessageDensity.cozy);
    expect(encryptNewRoomsByDefault.value, isTrue);
    expect(onboardingShown.value, isFalse);
    expect(MessageDensity.parse("nonsense"), MessageDensity.cozy);
    expect(MessageDensity.parse("compact"), MessageDensity.compact);
    expect(MessageDensity.compact.avatarSize,
        lessThan(MessageDensity.cozy.avatarSize));
    expect(MessageDensity.compact.verticalPadding,
        lessThan(MessageDensity.cozy.verticalPadding));
  });

  testWidgets("Skip setup jumps past every onboarding page", (tester) async {
    final other = _Other();
    await openSetup(tester, [_Page("one"), _Page("two"), other]);
    expect(find.text("one"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("onboarding-skip-button")));
    await tester.pumpAndSettle();

    expect(find.text("other page"), findsOneWidget);
    expect(onboardingShown.value, isTrue);
    // The page after the onboarding ones runs as usual, and has no Skip.
    expect(find.byKey(const ValueKey("onboarding-skip-button")), findsNothing);
    expect(other.submitted, isFalse);
  });

  testWidgets("Back only between onboarding pages", (tester) async {
    await openSetup(tester, [_Page("one"), _Page("two"), _Other()]);
    expect(find.text("Back"), findsNothing);

    await tester.tap(find.text("Next"));
    await tester.pumpAndSettle();
    expect(find.text("two"), findsOneWidget);

    await tester.tap(find.text("Back"));
    await tester.pumpAndSettle();
    expect(find.text("one"), findsOneWidget);

    await tester.tap(find.text("Next"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Next"));
    await tester.pumpAndSettle();
    expect(find.text("other page"), findsOneWidget);
    expect(find.text("Back"), findsNothing);
  });

  testWidgets("skipping on the last page closes the setup", (tester) async {
    await openSetup(tester, [_Page("one")]);
    await tester.tap(find.byKey(const ValueKey("onboarding-skip-button")));
    await tester.pumpAndSettle();
    expect(find.text("open"), findsOneWidget);
  });

  testWidgets("finishing the last page marks onboarding shown", (tester) async {
    await OnboardingEncryption().submit();
    expect(onboardingShown.value, isFalse);
    await OnboardingGifSearch().submit();
    expect(onboardingShown.value, isTrue);
  });

  testWidgets("GIF search starts off and the page turns it on", (tester) async {
    expect(preferences.tenorGifSearchEnabled.value, isFalse);
    await tester.pumpWidget(app(SingleChildScrollView(
        child: Builder(builder: OnboardingGifSearch().builder))));
    await tester.tap(find.byKey(const ValueKey("choice-card-true")));
    await tester.pumpAndSettle();
    expect(preferences.tenorGifSearchEnabled.value, isTrue);

    await tester.tap(find.byKey(const ValueKey("choice-card-false")));
    await tester.pumpAndSettle();
    expect(preferences.tenorGifSearchEnabled.value, isFalse);
  });

  testWidgets("picking a layout switches the chat list experiment",
      (tester) async {
    await tester.pumpWidget(app(SingleChildScrollView(
        child: Builder(builder: OnboardingLayout().builder))));
    await tester.tap(find.byKey(const ValueKey("choice-card-true")));
    await tester.pumpAndSettle();
    expect(unifiedChatListEnabled, isTrue);

    await tester.tap(find.byKey(const ValueKey("choice-card-false")));
    await tester.pumpAndSettle();
    expect(unifiedChatListEnabled, isFalse);
  });

  testWidgets("picking encryption sets where the create-room switch starts",
      (tester) async {
    await tester.pumpWidget(app(SingleChildScrollView(
        child: Builder(builder: OnboardingEncryption().builder))));
    await tester.tap(find.byKey(const ValueKey("choice-card-false")));
    await tester.pumpAndSettle();
    expect(encryptNewRoomsByDefault.value, isFalse);
  });

  test("the create-room encryption switch starts from the setting", () async {
    bool? start(RoomFieldEncryption field) {
      final args = CreateRoomArgs();
      field.setDefaults(args);
      return args.enableE2EE;
    }

    expect(start(RoomFieldEncryption(defaultEnabled: true)), isTrue);
    await encryptNewRoomsByDefault.set(false);
    expect(start(RoomFieldEncryption(defaultEnabled: true)), isFalse);
    await encryptNewRoomsByDefault.set(true);
    // Room types that can't be encrypted (voice rooms) stay off.
    expect(
        start(RoomFieldEncryption(
            defaultEnabled: false, canEnableEncryption: false)),
        isFalse);
  });

  testWidgets("picking a message spacing saves it", (tester) async {
    await tester.pumpWidget(
        app(const SingleChildScrollView(child: MessageDensityPicker())));
    await tester
        .tap(find.byKey(ValueKey("choice-card-${MessageDensity.compact}")));
    await tester.pumpAndSettle();
    expect(messageDensity, MessageDensity.compact);
  });

  for (final width in [320.0, 470.0, 900.0]) {
    testWidgets("layout pictures fit a ${width.toInt()} px wide page",
        (tester) async {
      await tester.pumpWidget(app(Center(
          child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: ChoiceCards<bool>(
                  selected: false,
                  onSelected: (_) {},
                  options: const [
                    ChoiceCardOption(
                        value: false,
                        title: "a",
                        description: "d",
                        preview: LayoutPreview(unified: false)),
                    ChoiceCardOption(
                        value: true,
                        title: "b",
                        description: "d",
                        preview: LayoutPreview(unified: true)),
                  ],
                ),
              )))));
      expect(tester.takeException(), isNull);
      expect(
          find.byKey(const ValueKey("layout-preview-discord")), findsOneWidget);
      expect(find.byKey(const ValueKey("layout-preview-telegram")),
          findsOneWidget);
    });
  }
}
