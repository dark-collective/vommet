import 'package:commet/client/components/url_preview/link_preview_fetcher.dart';
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
      "Bundled only in encrypted chats; Bundled + homeserver in others, unless the room turns previews off.",
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

  static String get labelSending => Intl.message("Sending and new chats",
      name: "labelLinkPreviewSendingAndNewChats",
      desc: "Sub-header above the link preview switches for sending and "
          "for asking in new chats");

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
      Intl.message("Ask before showing bundled previews in a new chat",
          desc: "Toggle: ask once per chat before showing link previews that "
              "the sender's app attached to the message",
          name: "labelBundledPreviewsAskInNewChatTitle");

  static String get labelAskDescription => Intl.message(
      "Recommended: a sender can make a preview look like a different page.",
      desc: "Description of the toggle for asking before showing link "
          "previews the sender's app attached",
      name: "labelBundledPreviewsAskInNewChatDescription");

  @override
  State<LinkPreviewSettingsPanel> createState() =>
      _LinkPreviewSettingsPanelState();
}

class _LinkPreviewSettingsPanelState extends State<LinkPreviewSettingsPanel> {
  // "auto" stands for Automatic, so the radios have a non-null group value.
  String get current => urlPreviewModeName(globalUrlPreviewModeSetting);

  Future<void> choose(String? name) async {
    if (name == null) return;
    await preferences.urlPreviewMode.set(name);
    if (mounted) setState(() {});
  }

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

    return SettingsSearchTarget(
      ids: [
        preferences.urlPreviewMode.key,
        preferences.bundledUrlPreviewsAskInNewChats.key,
        preferences.bundledUrlPreviewsAttach.key,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                child:
                    tiamat.Text.labelLow(LinkPreviewSettingsPanel.labelSending),
              ),
              // The web app can't read other sites' pages, so it makes none.
              if (canMakeLinkPreviews)
                BooleanPreferenceToggle(
                  preference: preferences.bundledUrlPreviewsAttach,
                  title: LinkPreviewSettingsPanel.labelAttachTitle,
                  description: LinkPreviewSettingsPanel.labelAttachDescription,
                ),
              const SizedBox(height: 10),
              BooleanPreferenceToggle(
                preference: preferences.bundledUrlPreviewsAskInNewChats,
                title: LinkPreviewSettingsPanel.labelAskTitle,
                description: LinkPreviewSettingsPanel.labelAskDescription,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
