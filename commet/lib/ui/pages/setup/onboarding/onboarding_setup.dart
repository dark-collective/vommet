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
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
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
import 'package:commet/security/local_data_keys.dart';
import 'package:commet/security/local_data_strings.dart';
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
        if (LocalDataKeys.supported) OnboardingLocalData(),
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
    "Your spaces as icons down the side. Open one to see its rooms. Home has People, Rooms and your direct messages.",
    name: "onboardingLayoutDiscordDescription",
    desc: "Describes the Discord-like layout option in onboarding");

String get onboardingLayoutDiscordDescriptionClassicHome => Intl.message(
    "Your spaces as icons down the side. Open one to see its rooms; Home has your direct messages.",
    name: "onboardingLayoutDiscordDescriptionClassicHome",
    desc:
        "Describes the Discord-like layout option in onboarding, when the New Home experiment is off");

String get onboardingShortcutsHeader => Intl.message("Shortcuts under Home",
    name: "onboardingShortcutsHeader",
    desc:
        "Onboarding layout page: small heading over the switches for the sidebar buttons under Home");

String get onboardingPeopleButton => Intl.message("Show a People button",
    name: "onboardingPeopleButton",
    desc:
        "Onboarding switch for the sidebar button under Home that opens People");

String get onboardingPeopleButtonDescription => Intl.message(
    "Opens People in one click: your contacts, direct-message invites and blocked people.",
    name: "onboardingPeopleButtonDescription",
    desc:
        "Explains the onboarding switch for the sidebar button under Home that opens People");

String get onboardingRoomsButton => Intl.message(
    "Show a “Standalone rooms” button",
    name: "onboardingRoomsButton",
    desc:
        "Onboarding switch for the sidebar button that lists rooms which aren't in a space");

String get onboardingRoomsButtonDescription => Intl.message(
    "Standalone rooms are rooms that aren't part of a space. The # button opens them in one click.",
    name: "onboardingRoomsButtonDescription",
    desc:
        "Explains the onboarding switch for the sidebar button that lists rooms which aren't in a space");

String get onboardingShortcutsNoteTitle => Intl.message(
    "These buttons are only shortcuts.",
    name: "onboardingShortcutsNoteTitle",
    desc:
        "Onboarding layout page: first, bold sentence of the note under the sidebar button switches");

String get onboardingShortcutsNote => Intl.message(
    "If you turn them off, People and Rooms are still tabs at the top of Home. Home is all customizable: in Customize Home you can add your own tabs, pick their icons, and give any tab a button here.",
    name: "onboardingShortcutsNote",
    desc:
        "Onboarding layout page: rest of the note under the sidebar button switches");

String get onboardingShortcutsFromAccount => Intl.message(
    "Set to match your account: your Home layout syncs between your devices, and changing these changes it everywhere.",
    name: "onboardingShortcutsFromAccount",
    desc:
        "Onboarding layout page: under the sidebar button switches, when the account's synced Home layout already chose them");

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
  final _store = HomeLayoutStore.instance;

  @override
  void initState() {
    super.initState();
    // With New Home the buttons are part of Home's tabs, which sync with the
    // account: show what the account already has, and follow it when it
    // arrives after this page opened.
    final manager = clientManager;
    if (manager != null) _store.attach(manager);
    _store.tabs.addListener(_changed);
  }

  @override
  void dispose() {
    _store.tabs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Whether Home tab [id]'s button shows, as the sidebar decides it.
  bool _tabButton(String id, bool fallback) {
    final tab = _store.tabs.value.tab(id);
    return tab == null ? fallback : tabInRail(tab);
  }

  /// Whether the account's synced Home layout already set tab [id]'s button.
  bool _fromAccount(String id) =>
      _store.account.value != null && _store.tabs.value.tab(id)?.rail != null;

  @override
  Widget build(BuildContext context) {
    final unified = unifiedChatListEnabled;
    final newHome = newHomeEnabled;
    final roomsButton = newHome
        ? _tabButton(HomeTabs.rooms, preferences.showRoomsInSidebar.value)
        : preferences.showRoomsInSidebar.value;
    // The People button only exists with New Home.
    final peopleButton =
        newHome && _tabButton(HomeTabs.people, peopleInRail.value);
    final fromAccount = newHome &&
        (_fromAccount(HomeTabs.people) || _fromAccount(HomeTabs.rooms));
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
              description: newHome
                  ? onboardingLayoutDiscordDescription
                  : onboardingLayoutDiscordDescriptionClassicHome,
              preview: LayoutPreview(
                  unified: false,
                  roomsButton: roomsButton,
                  peopleButton: peopleButton),
            ),
            ChoiceCardOption(
              value: true,
              title: onboardingLayoutTelegram,
              description: onboardingLayoutTelegramDescription,
              preview: const LayoutPreview(unified: true),
            ),
          ],
        ),
        // The one list already has every room, so the buttons only matter
        // with the space rail.
        if (!unified) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(onboardingShortcutsHeader.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6)),
          ),
          if (newHome)
            _ShortcutSwitch(
              key: const ValueKey("onboarding-people-button-switch"),
              icon: Icons.people_alt_rounded,
              title: onboardingPeopleButton,
              description: onboardingPeopleButtonDescription,
              value: peopleButton,
              onChanged: (on) async {
                await setTabInRail(HomeTabs.people, on);
                if (mounted) setState(() {});
              },
            ),
          _ShortcutSwitch(
            key: const ValueKey("onboarding-rooms-button-switch"),
            icon: Icons.tag,
            title: onboardingRoomsButton,
            description: onboardingRoomsButtonDescription,
            value: roomsButton,
            onChanged: (on) async {
              // With New Home, the Rooms tab's button (Customize Home).
              if (newHome) {
                await setTabInRail(HomeTabs.rooms, on);
              } else {
                await preferences.showRoomsInSidebar.set(on);
              }
              if (mounted) setState(() {});
            },
          ),
          if (fromAccount)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: tiamat.Text.labelLow(onboardingShortcutsFromAccount),
            ),
          // Only true with New Home: the old Home has no People or Rooms.
          if (newHome) const _ShortcutsNote(),
        ],
      ],
    );
  }
}

/// A switch for one of the sidebar buttons under Home (People, the #
/// "Standalone rooms" button), which new users have on (Settings ›
/// Appearance).
class _ShortcutSwitch extends StatelessWidget {
  const _ShortcutSwitch(
      {required this.icon,
      required this.title,
      required this.description,
      required this.value,
      required this.onChanged,
      super.key});

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final void Function(bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: value ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                tiamat.Text.labelEmphasised(title),
                tiamat.Text.labelLow(description),
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

/// Says the buttons are only shortcuts: People and Rooms stay in Home.
class _ShortcutsNote extends StatelessWidget {
  const _ShortcutsNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontSize: 12, color: scheme.onSurfaceVariant);
    return Container(
      key: const ValueKey("onboarding-shortcuts-note"),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(Icons.info_rounded, size: 18, color: scheme.primary),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: onboardingShortcutsNoteTitle,
                    style: style?.copyWith(
                        color: scheme.onSurface, fontWeight: FontWeight.w600)),
                const TextSpan(text: " "),
                TextSpan(text: onboardingShortcutsNote),
              ]),
              style: style,
            ),
          ),
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
      "This is where the encryption switch starts when you make a room. You can still turn it on for any room you make, and change this later in Settings › Privacy.",
      name: "onboardingEncryptionBody",
      desc:
          "Text of the onboarding page that picks whether new rooms are encrypted");

  @override
  Widget content(BuildContext context) => const _EncryptionChoice();
}

String get onboardingEncryptionOn => Intl.message("Encrypt new rooms",
    name: "onboardingEncryptionOn",
    desc: "Onboarding option: new rooms start encrypted");

String get onboardingEncryptionOnDescription =>
    Intl.message("Only the people in a room can read it, not your homeserver.",
        name: "onboardingEncryptionOnDescription",
        desc: "Describes the 'Encrypt new rooms' onboarding option");

String get onboardingEncryptionOff => Intl.message("Only when I turn it on",
    name: "onboardingEncryptionOff",
    desc: "Onboarding option: new rooms start unencrypted");

String get onboardingEncryptionOffDescription => Intl.message(
    "New rooms start unencrypted. Turn encryption on for a room when it needs it, like a private chat.",
    name: "onboardingEncryptionOffDescription",
    desc:
        "Describes the 'Only when I turn it on' encryption onboarding option");

String get onboardingChoiceDefault => Intl.message("Default",
    name: "onboardingChoiceDefault",
    desc:
        "Small tag on the onboarding option that is picked unless you choose another");

String get onboardingEncryptionGoodToKnow => Intl.message("Good to know",
    name: "onboardingEncryptionGoodToKnow",
    desc:
        "Heading of the list of upsides under the 'Only when I turn it on' encryption onboarding option");

String get onboardingEncryptionDrawbacks => Intl.message("Drawbacks",
    name: "onboardingEncryptionDrawbacks",
    desc:
        "Heading of the list of drawbacks under the 'Encrypt new rooms' onboarding option");

String get onboardingEncryptionOffPointHistory => Intl.message(
    "People who join later can read the room's whole history.",
    name: "onboardingEncryptionOffPointHistory",
    desc:
        "Upside of unencrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOffPointFast => Intl.message(
    "Big rooms stay fast, and nothing gets locked away if you lose your recovery key.",
    name: "onboardingEncryptionOffPointFast",
    desc:
        "Upside of unencrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOffPointHomeserver => Intl.message(
    "Your homeserver can read these messages, so don't use them for anything private.",
    name: "onboardingEncryptionOffPointHomeserver",
    desc:
        "Caveat of unencrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOnPointHistory => Intl.message(
    "People who join later may see only part of the history, or none of it.",
    name: "onboardingEncryptionOnPointHistory",
    desc:
        "Drawback of encrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOnPointSlow => Intl.message(
    "Rooms with lots of people can get slow, because every message's keys go to every device.",
    name: "onboardingEncryptionOnPointSlow",
    desc:
        "Drawback of encrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOnPointRecoveryKey => Intl.message(
    "Keep your recovery key safe: without it, a new device can't read older messages.",
    name: "onboardingEncryptionOnPointRecoveryKey",
    desc:
        "Drawback of encrypted rooms, listed in the encryption onboarding page");

String get onboardingEncryptionOnPointPermanent => Intl.message(
    "Once a room is encrypted, it can't be turned off.",
    name: "onboardingEncryptionOnPointPermanent",
    desc:
        "Drawback of encrypted rooms, listed in the encryption onboarding page");

List<String> get onboardingEncryptionOffPoints => [
      onboardingEncryptionOffPointHistory,
      onboardingEncryptionOffPointFast,
      onboardingEncryptionOffPointHomeserver,
    ];

List<String> get onboardingEncryptionOnPoints => [
      onboardingEncryptionOnPointHistory,
      onboardingEncryptionOnPointSlow,
      onboardingEncryptionOnPointRecoveryKey,
      onboardingEncryptionOnPointPermanent,
    ];

class _EncryptionChoice extends StatefulWidget {
  const _EncryptionChoice();

  @override
  State<_EncryptionChoice> createState() => _EncryptionChoiceState();
}

class _EncryptionChoiceState extends State<_EncryptionChoice> {
  @override
  Widget build(BuildContext context) {
    // The tag marks whatever a new install starts with.
    final byDefault = encryptNewRoomsByDefault.defaultForNewUser;
    return ChoiceCards<bool>(
      selected: encryptNewRoomsByDefault.value,
      onSelected: (on) async {
        await encryptNewRoomsByDefault.set(on);
        if (mounted) setState(() {});
      },
      options: [
        ChoiceCardOption(
          value: false,
          title: onboardingEncryptionOff,
          description: onboardingEncryptionOffDescription,
          icon: Icons.lock_open,
          badge: byDefault == false ? onboardingChoiceDefault : null,
          extra: ChoiceCardPoints(
            heading: onboardingEncryptionGoodToKnow,
            points: onboardingEncryptionOffPoints,
            icon: Icons.check_rounded,
            iconColor: const Color(0xff4fb383),
          ),
        ),
        ChoiceCardOption(
          value: true,
          title: onboardingEncryptionOn,
          description: onboardingEncryptionOnDescription,
          icon: Icons.lock_outline,
          badge: byDefault == true ? onboardingChoiceDefault : null,
          extra: ChoiceCardPoints(
            heading: onboardingEncryptionDrawbacks,
            points: onboardingEncryptionOnPoints,
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xffe0a43a),
          ),
        ),
      ],
    );
  }
}

/// Vommet: local data encryption is opt-in (decision 9); a new install
/// is asked here, "Not now" picked unless they choose Encrypt. The pages run
/// after the first sign-in, so Encrypt converts what that sign-in stored at
/// the next start.
class OnboardingLocalData extends OnboardingMenu {
  @override
  String get title => localDataOnboardingTitle;

  @override
  String get body => localDataOnboardingBody;

  @override
  Widget content(BuildContext context) => const _LocalDataChoice();

  /// Next without changing the cards: "Not now" is the answer.
  @override
  Future<void> submit() async {
    if (!LocalDataKeys.chosen) {
      await LocalDataKeys.choose(LocalDataKeys.encrypt, source: "first_run");
    }
  }
}

class _LocalDataChoice extends StatefulWidget {
  const _LocalDataChoice();

  @override
  State<_LocalDataChoice> createState() => _LocalDataChoiceState();
}

class _LocalDataChoiceState extends State<_LocalDataChoice> {
  @override
  Widget build(BuildContext context) {
    return ChoiceCards<bool>(
      selected: LocalDataKeys.encrypt,
      onSelected: (on) async {
        await LocalDataKeys.choose(on, source: "first_run");
        if (mounted) setState(() {});
      },
      options: [
        ChoiceCardOption(
          value: false,
          title: localDataChoiceNotNow,
          description: localDataChoiceNotNowDescription,
          icon: Icons.lock_open,
          badge: onboardingChoiceDefault,
        ),
        ChoiceCardOption(
          value: true,
          title: localDataChoiceEncrypt,
          description: localDataChoiceEncryptDescription,
          icon: Icons.lock_outline,
        ),
      ],
    );
  }
}

/// Vommet: many people never found the GIF search setting, so setup offers
/// it. New installs have it on (the "Search for GIFs" card starts picked);
/// installs from before it was on by default keep theirs.
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
