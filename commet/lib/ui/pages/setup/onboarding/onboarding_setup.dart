// Vommet: a short, skippable set of first-run pages (Vommet issue 524):
// language, layout, theme, message spacing, whether new rooms are
// encrypted, and GIF search. They come first in the first-run setup of a fresh install,
// language first so the rest shows in it, and can be run again from
// Settings › General. Every choice saves as soon as it's picked; skipping
// leaves the rest as they are.
import 'dart:async';

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/room_encryption_default.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/categories/app/app_icon_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/language_settings_panel.dart';
import 'package:commet/ui/pages/settings/categories/app/message_density_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_settings_widget.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/ui/pages/setup/onboarding/layout_preview.dart';
import 'package:commet/ui/pages/setup/setup_menu.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Set once the pages were finished or skipped, so they show only once.
final BoolPreference onboardingShown =
    BoolPreference("vommet_onboarding_shown", defaultValue: false);

class OnboardingSetup {
  /// The pages, in order.
  static List<OnboardingMenu> menus() => [
        OnboardingLanguage(),
        OnboardingLayout(),
        OnboardingTheme(),
        OnboardingAppIcon(),
        OnboardingDensity(),
        OnboardingEncryption(),
        OnboardingGifSearch(),
      ];

  static Future<void> markShown() => onboardingShown.set(true);

  /// Runs the pages again (Settings › General).
  static Future<void> open(BuildContext context) =>
      NavigationUtils.navigateTo(context, SetupPage(menus()));
}

/// One onboarding page. The setup page offers Back and "Skip setup" on these.
abstract class OnboardingMenu implements SetupMenu {
  String get title;
  String get body;
  Widget content(BuildContext context);

  /// The skip button's text, when not "Skip setup" (Getting started).
  String? get skipLabel => null;

  final StreamController<SetupMenuState> _controller =
      StreamController.broadcast();

  @override
  Stream<SetupMenuState> get onStateChanged => _controller.stream;

  @override
  SetupMenuState get state => SetupMenuState.canProgress;

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        tiamat.Text.largeTitle(title),
        tiamat.Text.label(body),
        const SizedBox(height: 8),
        content(context),
      ],
    );
  }

  /// Choices save when picked; nothing is left to do on Next.
  @override
  Future<void> submit() async {}
}

class OnboardingLanguage extends OnboardingMenu {
  @override
  String get title => Intl.message("Pick your language",
      name: "onboardingLanguageTitle",
      desc: "Title of the onboarding page that picks the app language");

  @override
  String get body => Intl.message(
      "Vommet will show in this language. You can change it later in Settings › General.",
      name: "onboardingLanguageBody",
      desc: "Text of the onboarding page that picks the app language");

  @override
  Widget content(BuildContext context) => const LanguageSettingsPanel();
}

class OnboardingLayout extends OnboardingMenu {
  @override
  String get title => Intl.message("Pick a layout",
      name: "onboardingLayoutTitle",
      desc: "Title of the onboarding page that picks the chat layout");

  @override
  String get body => Intl.message(
      "How your spaces, rooms and direct messages are listed. You can switch later under Settings › Experiments.",
      name: "onboardingLayoutBody",
      desc: "Text of the onboarding page that picks the chat layout");

  @override
  Widget content(BuildContext context) => const _LayoutChoice();
}

String get onboardingLayoutDiscord => Intl.message("Like Discord",
    name: "onboardingLayoutDiscord",
    desc: "Onboarding layout option: space icons on the left, like Discord");

String get onboardingLayoutDiscordDescription => Intl.message(
    "Your spaces as icons down the side. Open one to see its rooms; Home has your direct messages.",
    name: "onboardingLayoutDiscordDescription",
    desc: "Describes the Discord-like layout option in onboarding");

String get onboardingRoomsButton => Intl.message(
    "Show a “Rooms outside spaces” button",
    name: "onboardingRoomsButton",
    desc:
        "Onboarding switch for the sidebar button that lists rooms which aren't in a space");

String get onboardingRoomsButtonDescription => Intl.message(
    "Rooms that aren't part of a space get their own # button under Home, so they're easy to find. You can change this later in Settings › Appearance.",
    name: "onboardingRoomsButtonDescription",
    desc:
        "Explains the onboarding switch for the sidebar button that lists rooms which aren't in a space");

String get onboardingLayoutTelegram => Intl.message("Like Telegram",
    name: "onboardingLayoutTelegram",
    desc: "Onboarding layout option: one chat list, like Telegram");

String get onboardingLayoutTelegramDescription => Intl.message(
    "One list with your direct messages, rooms and spaces together, newest first.",
    name: "onboardingLayoutTelegramDescription",
    desc: "Describes the Telegram-like layout option in onboarding");

class _LayoutChoice extends StatefulWidget {
  const _LayoutChoice();

  @override
  State<_LayoutChoice> createState() => _LayoutChoiceState();
}

class _LayoutChoiceState extends State<_LayoutChoice> {
  @override
  Widget build(BuildContext context) {
    final unified = unifiedChatListEnabled;
    final roomsButton = preferences.showRoomsInSidebar.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        ChoiceCards<bool>(
          selected: unified,
          onSelected: (unified) async {
            await experimentUnifiedChatList.set(unified);
            onUnifiedChatListToggled(unified);
            if (mounted) setState(() {});
          },
          options: [
            ChoiceCardOption(
              value: false,
              title: onboardingLayoutDiscord,
              description: onboardingLayoutDiscordDescription,
              preview: LayoutPreview(unified: false, roomsButton: roomsButton),
            ),
            ChoiceCardOption(
              value: true,
              title: onboardingLayoutTelegram,
              description: onboardingLayoutTelegramDescription,
              preview: const LayoutPreview(unified: true),
            ),
          ],
        ),
        // The one list already has every room, so the button only matters
        // with the space rail.
        if (!unified)
          _RoomsButtonSwitch(
            value: roomsButton,
            onChanged: (on) async {
              await preferences.showRoomsInSidebar.set(on);
              if (mounted) setState(() {});
            },
          ),
      ],
    );
  }
}

/// The sidebar's # button for rooms outside spaces, which new users have
/// on (Settings › Appearance).
class _RoomsButtonSwitch extends StatelessWidget {
  const _RoomsButtonSwitch({required this.value, required this.onChanged});

  final bool value;
  final void Function(bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey("onboarding-rooms-button-switch"),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.tag,
              size: 20,
              color: value ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                tiamat.Text.labelEmphasised(onboardingRoomsButton),
                tiamat.Text.labelLow(onboardingRoomsButtonDescription),
              ],
            ),
          ),
          const SizedBox(width: 8),
          tiamat.Switch(state: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class OnboardingAppIcon extends OnboardingMenu {
  @override
  String get title => Intl.message("Pick an icon",
      name: "onboardingAppIconTitle",
      desc: "Title of the onboarding page that picks the app's icon");

  @override
  String get body => Intl.message(
      "Which icon Vommet shows. You can change it later in Settings › Appearance.",
      name: "onboardingAppIconBody",
      desc: "Text of the onboarding page that picks the app's icon");

  @override
  Widget content(BuildContext context) => const AppIconPicker();
}

class OnboardingTheme extends OnboardingMenu {
  @override
  String get title => Intl.message("Pick a theme",
      name: "onboardingThemeTitle",
      desc: "Title of the onboarding page that picks the app theme");

  @override
  String get body => Intl.message(
      "More themes, gradients and a theme editor are in Settings › Appearance.",
      name: "onboardingThemeBody",
      desc: "Text of the onboarding page that picks the app theme");

  @override
  Widget content(BuildContext context) =>
      const ThemeListWidget(cardsOnly: true);
}

class OnboardingDensity extends OnboardingMenu {
  @override
  String get title => Intl.message("Pick your message spacing",
      name: "onboardingDensityTitle",
      desc: "Title of the onboarding page that picks the message spacing");

  @override
  String get body =>
      Intl.message("You can change this later in Settings › Appearance.",
          name: "onboardingDensityBody",
          desc: "Text of the onboarding page that picks the message spacing");

  @override
  Widget content(BuildContext context) => const MessageDensityPicker();
}

class OnboardingEncryption extends OnboardingMenu {
  @override
  String get title => Intl.message("Encrypt new rooms?",
      name: "onboardingEncryptionTitle",
      desc:
          "Title of the onboarding page that picks whether new rooms are encrypted");

  @override
  String get body => Intl.message(
      "This is where the encryption switch starts when you make a room. You can still change it for each room, and later in Settings › Privacy.",
      name: "onboardingEncryptionBody",
      desc:
          "Text of the onboarding page that picks whether new rooms are encrypted");

  @override
  Widget content(BuildContext context) => const _EncryptionChoice();
}

String get onboardingEncryptionOn => Intl.message("Encrypt new rooms",
    name: "onboardingEncryptionOn",
    desc: "Onboarding option: new rooms start encrypted");

String get onboardingEncryptionOnDescription => Intl.message(
    "Only the people in a room can read it. Keep your recovery key safe: without it, a new device can't read older messages.",
    name: "onboardingEncryptionOnDescription",
    desc: "Describes the 'Encrypt new rooms' onboarding option");

String get onboardingEncryptionOff => Intl.message("Only when I turn it on",
    name: "onboardingEncryptionOff",
    desc: "Onboarding option: new rooms start unencrypted");

String get onboardingEncryptionOffDescription => Intl.message(
    "New rooms start unencrypted, so nothing can get locked away. Once a room is encrypted, it can't be turned off.",
    name: "onboardingEncryptionOffDescription",
    desc:
        "Describes the 'Only when I turn it on' encryption onboarding option");

class _EncryptionChoice extends StatefulWidget {
  const _EncryptionChoice();

  @override
  State<_EncryptionChoice> createState() => _EncryptionChoiceState();
}

class _EncryptionChoiceState extends State<_EncryptionChoice> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<bool>(
      selected: encryptNewRoomsByDefault.value,
      onSelected: (on) async {
        await encryptNewRoomsByDefault.set(on);
        if (mounted) setState(() {});
      },
      options: [
        ChoiceCardOption(
          value: true,
          title: onboardingEncryptionOn,
          description: onboardingEncryptionOnDescription,
          icon: Icons.lock_outline,
        ),
        ChoiceCardOption(
          value: false,
          title: onboardingEncryptionOff,
          description: onboardingEncryptionOffDescription,
          icon: Icons.lock_open,
        ),
      ],
    );
  }
}

/// Vommet: GIF search is off by default, and many people never found the
/// setting, so setup offers it (the "No GIF search" card starts picked).
class OnboardingGifSearch extends OnboardingMenu {
  @override
  String get title => Intl.message("Turn on GIF search?",
      name: "onboardingGifSearchTitle",
      desc: "Title of the onboarding page that picks whether GIF search is on");

  @override
  String get body => Intl.message(
      "Find GIFs from the GIF tab next to emoji and stickers. You can change this later in Settings › General.",
      name: "onboardingGifSearchBody",
      desc: "Text of the onboarding page that picks whether GIF search is on");

  @override
  Widget content(BuildContext context) => const _GifSearchChoice();

  @override
  Future<void> submit() => OnboardingSetup.markShown();
}

String get onboardingGifSearchOn => Intl.message("Search for GIFs",
    name: "onboardingGifSearchOn",
    desc: "Onboarding option: turn GIF search on");

String onboardingGifSearchOnDescription(String service) => Intl.message(
    "Your searches go to $service through Vommet's server, so $service sees what you search for but not who you are.",
    name: "onboardingGifSearchOnDescription",
    args: [service],
    desc: "Describes the 'Search for GIFs' onboarding option");

String get onboardingGifSearchOff => Intl.message("No GIF search",
    name: "onboardingGifSearchOff",
    desc: "Onboarding option: leave GIF search off");

String get onboardingGifSearchOffDescription => Intl.message(
    "Nothing is sent anywhere. You can still save GIFs people post and send them from My GIFs.",
    name: "onboardingGifSearchOffDescription",
    desc: "Describes the 'No GIF search' onboarding option");

class _GifSearchChoice extends StatefulWidget {
  const _GifSearchChoice();

  @override
  State<_GifSearchChoice> createState() => _GifSearchChoiceState();
}

class _GifSearchChoiceState extends State<_GifSearchChoice> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<bool>(
      selected: preferences.tenorGifSearchEnabled.value,
      onSelected: (on) async {
        await preferences.tenorGifSearchEnabled.set(on);
        if (mounted) setState(() {});
      },
      options: [
        ChoiceCardOption(
          value: true,
          title: onboardingGifSearchOn,
          description: onboardingGifSearchOnDescription("KLIPY"),
          icon: Icons.gif_box_outlined,
        ),
        ChoiceCardOption(
          value: false,
          title: onboardingGifSearchOff,
          description: onboardingGifSearchOffDescription,
          icon: Icons.search_off,
        ),
      ],
    );
  }
}
