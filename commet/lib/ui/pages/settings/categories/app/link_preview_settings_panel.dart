import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/url_preview/link_preview_fetcher.dart';
import 'package:commet/client/components/url_preview/url_preview_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/client/matrix/components/url_preview/matrix_room_url_previews.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 676 phase 3: names and descriptions of the link preview
/// modes, shared by Settings › Privacy and the room settings.
class LinkPreviewModeLabels {
  static String get automatic => Intl.message("Automatic",
      name: "labelLinkPreviewModeAutomatic",
      desc: "Link preview default: bundled only in encrypted chats, "
          "homeserver previews too in others");

  static String get automaticDescription => Intl.message(
      "Bundled only in encrypted chats; your homeserver’s previews in others (the sender’s bundled one only when your homeserver has none), unless the room turns previews off.",
      name: "labelLinkPreviewModeAutomaticDescription",
      desc: "Explains the Automatic link preview default");

  static String get bundledOnly => Intl.message("Bundled only (private)",
      name: "labelLinkPreviewModeBundledOnly",
      desc: "Link preview mode: only previews the sender's app attached");

  static String get bundledOnlyDescription =>
      Intl.message("Show previews the sender attached. Never fetch links.",
          name: "labelLinkPreviewModeBundledOnlyDescription",
          desc: "Explains the Bundled only link preview mode");

  static String get all => Intl.message("Bundled + homeserver previews",
      name: "labelLinkPreviewModeAll",
      desc: "Link preview mode: attached previews, and the homeserver "
          "fetches previews for other links");

  static String get allDescription => Intl.message(
      "Also fetch previews for other links. Your homeserver sees those links.",
      name: "labelLinkPreviewModeAllDescription",
      desc: "Explains the Bundled + homeserver link preview mode");

  static String get off => Intl.message("Off",
      name: "labelLinkPreviewModeOff", desc: "Link preview mode: none");

  static String of(UrlPreviewMode mode) => switch (mode) {
        UrlPreviewMode.off => off,
        UrlPreviewMode.bundledOnly => bundledOnly,
        UrlPreviewMode.all => all,
      };

  static String? descriptionOf(UrlPreviewMode mode) => switch (mode) {
        UrlPreviewMode.off => null,
        UrlPreviewMode.bundledOnly => bundledOnlyDescription,
        UrlPreviewMode.all => allDescription,
      };

  static IconData iconOf(UrlPreviewMode? mode) => switch (mode) {
        null => Icons.auto_mode,
        UrlPreviewMode.off => Icons.link_off,
        UrlPreviewMode.bundledOnly => Icons.lock_outline,
        UrlPreviewMode.all => Icons.link,
      };
}

/// One mode choice: the radio, with its description under it.
class LinkPreviewModeOption<T> extends StatelessWidget {
  const LinkPreviewModeOption({
    required this.value,
    required this.groupValue,
    required this.text,
    required this.icon,
    this.description,
    this.onChanged,
    super.key,
  });

  final T value;
  final T groupValue;
  final String text;
  final String? description;
  final IconData icon;
  final void Function(T? value)? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.RadioButton<T>(
          groupValue: groupValue,
          value: value,
          icon: icon,
          text: text,
          onChanged: onChanged,
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(68, 0, 8, 6),
            child: tiamat.Text.labelLow(description!),
          ),
      ],
    );
  }
}

/// Settings › Privacy › Link previews: the default for all chats, and the
/// switches for sending previews and asking in new chats.
class LinkPreviewSettingsPanel extends StatefulWidget {
  const LinkPreviewSettingsPanel({super.key});

  static String get header => Intl.message("Link previews",
      name: "labelLinkPreviewSettingsHeader",
      desc: "Header of the link preview settings panel");

  static String get labelDefault => Intl.message("Default for all chats",
      name: "labelLinkPreviewDefaultForAllChats",
      desc: "Sub-header above the link preview default choices");

  static String get labelSending => Intl.message("Sending",
      name: "labelLinkPreviewSending",
      desc: "Sub-header above the switch for attaching link previews to "
          "sent messages");

  static String get labelWhoseShow =>
      Intl.message("Whose bundled previews show",
          name: "labelLinkPreviewWhoseBundledShow",
          desc: "Sub-header above the switches and lists deciding whose "
              "sender-made link previews show");

  static String get labelAttachTitle =>
      Intl.message("Attach previews to links I send",
          desc: "Toggle: this device builds a preview for a link in the "
              "message box and attaches it to the message",
          name: "labelBundledPreviewsAttachTitle");

  static String get labelAttachDescription => Intl.message(
      "To build a preview your device opens the page, so the site sees your IP address, as if you had opened the link. In encrypted chats the preview image is encrypted too.",
      desc: "Description of the toggle for attaching link previews to sent "
          "messages",
      name: "labelBundledPreviewsAttachDescription");

  static String get labelAskTitle =>
      Intl.message("Ask before showing bundled previews",
          desc: "Toggle: ask before showing link previews that the sender's "
              "app attached, until the person or chat is trusted",
          name: "labelBundledPreviewsAskTitle");

  static String get labelAskDescription => Intl.message(
      "Recommended: a sender can make a preview look like a different page. Only asked in encrypted chats.",
      desc: "Description of the toggle for asking before showing link "
          "previews the sender's app attached",
      name: "labelBundledPreviewsAskInNewChatDescription");

  static String get labelVerifiedTitle =>
      Intl.message("Always show from people I’ve verified",
          desc: "Toggle: show link previews from verified people without "
              "asking",
          name: "labelBundledPreviewsTrustVerifiedTitle");

  static String get labelVerifiedDescription => Intl.message(
      "Only for encrypted messages sent from one of their verified sessions.",
      desc: "Description of the toggle for showing link previews from "
          "verified people without asking",
      name: "labelBundledPreviewsTrustVerifiedDescription");

  static String labelAlwaysFrom(int count) =>
      Intl.message("Always show from · $count",
          args: [count],
          name: "labelBundledPreviewsAlwaysList",
          desc: "Heading of the list of people whose link previews always "
              "show, with how many there are");

  static String labelNeverFrom(int count) =>
      Intl.message("Never show from · $count",
          args: [count],
          name: "labelBundledPreviewsNeverList",
          desc: "Heading of the list of people whose link previews never "
              "show, with how many there are");

  static String get labelListsNote => Intl.message(
      "Add people from the preview card or their profile. The lists are kept in your account data, which your homeserver can read.",
      name: "labelBundledPreviewsListsNote",
      desc: "Under the Always/Never link preview lists: where to add people "
          "and where the lists are stored");

  static String labelRemove(String name) => Intl.message("Remove $name",
      args: [name],
      name: "labelBundledPreviewsRemovePerson",
      desc: "Tooltip of the button removing someone from a link preview list");

  @override
  State<LinkPreviewSettingsPanel> createState() =>
      _LinkPreviewSettingsPanelState();
}

class _LinkPreviewSettingsPanelState extends State<LinkPreviewSettingsPanel> {
  // "auto" stands for Automatic, so the radios have a non-null group value.
  String get current => urlPreviewModeName(globalUrlPreviewModeSetting);

  /// Each signed-in account that keeps Always/Never lists.
  List<(Client, BundledUrlPreviewConsent)> get accounts => [
        for (final client in clientManager?.clients ?? <Client>[])
          if (client.getComponent<UrlPreviewComponent>()
              case BundledUrlPreviewConsent consent)
            (client, consent),
      ];

  late final List<BundledUrlPreviewConsent> _watched;

  @override
  void initState() {
    super.initState();
    _watched = [for (final (_, consent) in accounts) consent];
    for (final consent in _watched) {
      consent.bundledConsentChanges.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final consent in _watched) {
      consent.bundledConsentChanges.removeListener(_changed);
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> choose(String? name) async {
    if (name == null) return;
    await preferences.urlPreviewMode.set(name);
    if (mounted) setState(() {});
  }

  Future<void> remove(BundledUrlPreviewConsent consent, String userId) async {
    try {
      await consent.setBundledPreviewTrust(userId, null);
    } catch (e) {
      Log.w("Couldn't update the link preview lists: $e");
    }
  }

  List<Widget> people(BundledPreviewPersonTrust trust) {
    final multiple = accounts.length > 1;
    return [
      for (final (client, consent) in accounts)
        for (final id
            in (trust == BundledPreviewPersonTrust.always
                    ? consent.bundledPreviewPeople.always
                    : consent.bundledPreviewPeople.never)
                .toList()
              ..sort())
          BundledPreviewPersonRow(
            key: ValueKey("bundled-${trust.name}-${client.identifier}-$id"),
            client: client,
            userId: id,
            account: multiple ? client.self?.identifier : null,
            onRemove: () => remove(consent, id),
          ),
    ];
  }

  Widget subhead(String text, {double top = 12}) => Padding(
        padding: EdgeInsets.fromLTRB(8, top, 8, 4),
        child: tiamat.Text.labelLow(text),
      );

  @override
  Widget build(BuildContext context) {
    final group = current;
    Widget option(UrlPreviewMode? mode) => LinkPreviewModeOption<String>(
          value: urlPreviewModeName(mode),
          groupValue: group,
          icon: LinkPreviewModeLabels.iconOf(mode),
          text: mode == null
              ? LinkPreviewModeLabels.automatic
              : LinkPreviewModeLabels.of(mode),
          description: mode == null
              ? LinkPreviewModeLabels.automaticDescription
              : LinkPreviewModeLabels.descriptionOf(mode),
          onChanged: choose,
        );

    final always = people(BundledPreviewPersonTrust.always);
    final never = people(BundledPreviewPersonTrust.never);

    return SettingsSearchTarget(
      ids: [
        preferences.urlPreviewMode.key,
        preferences.bundledUrlPreviewsAskInNewChats.key,
        preferences.bundledUrlPreviewsTrustVerified.key,
        preferences.bundledUrlPreviewsAttach.key,
        bundledPreviewsPeopleSearchId,
      ],
      child: tiamat.Panel(
        header: LinkPreviewSettingsPanel.header,
        mode: tiamat.TileType.surfaceContainerLow,
        mainAxisSize: MainAxisSize.min,
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child:
                    tiamat.Text.labelLow(LinkPreviewSettingsPanel.labelDefault),
              ),
              option(null),
              option(UrlPreviewMode.bundledOnly),
              option(UrlPreviewMode.all),
              option(UrlPreviewMode.off),
              // The web app can't read other sites' pages, so it makes none.
              if (canMakeLinkPreviews) ...[
                subhead(LinkPreviewSettingsPanel.labelSending),
                BooleanPreferenceToggle(
                  preference: preferences.bundledUrlPreviewsAttach,
                  title: LinkPreviewSettingsPanel.labelAttachTitle,
                  description: LinkPreviewSettingsPanel.labelAttachDescription,
                ),
              ],
              subhead(LinkPreviewSettingsPanel.labelWhoseShow),
              BooleanPreferenceToggle(
                preference: preferences.bundledUrlPreviewsAskInNewChats,
                title: LinkPreviewSettingsPanel.labelAskTitle,
                description: LinkPreviewSettingsPanel.labelAskDescription,
              ),
              const SizedBox(height: 10),
              BooleanPreferenceToggle(
                preference: preferences.bundledUrlPreviewsTrustVerified,
                title: LinkPreviewSettingsPanel.labelVerifiedTitle,
                description: LinkPreviewSettingsPanel.labelVerifiedDescription,
              ),
              if (always.isNotEmpty) ...[
                subhead(LinkPreviewSettingsPanel.labelAlwaysFrom(always.length),
                    top: 16),
                ...always,
              ],
              if (never.isNotEmpty) ...[
                subhead(LinkPreviewSettingsPanel.labelNeverFrom(never.length),
                    top: 16),
                ...never,
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child: tiamat.Text.labelLow(
                    LinkPreviewSettingsPanel.labelListsNote),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings search id of the Always/Never lists (not a preference).
const String bundledPreviewsPeopleSearchId =
    "vommet_bundled_url_previews_people";

/// One person on the Always or Never list: avatar, name, user ID, ×.
class BundledPreviewPersonRow extends StatelessWidget {
  const BundledPreviewPersonRow(
      {required this.client,
      required this.userId,
      required this.onRemove,
      this.account,
      super.key});

  final Client client;
  final String userId;

  /// The account whose list this is, shown when more than one is signed in.
  final String? account;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: client
          .getComponent<UserProfileComponent>()
          ?.getProfile(userId)
          .then<Profile?>((p) => p)
          .catchError((_) => null),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final name = profile?.displayName ?? userId;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
          child: Row(
            children: [
              tiamat.Avatar(
                image: profile?.avatar,
                placeholderText: name,
                placeholderColor: profile?.defaultColor,
                radius: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.label(name, maxLines: 1),
                    tiamat.Text.labelLow(
                        account == null ? userId : "$userId · $account",
                        maxLines: 1),
                  ],
                ),
              ),
              IconButton(
                tooltip: LinkPreviewSettingsPanel.labelRemove(name),
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
            ],
          ),
        );
      },
    );
  }
}
