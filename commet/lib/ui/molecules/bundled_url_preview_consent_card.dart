import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 676: shown instead of a link preview the sender's app
/// bundled (MSC4095) until the user trusts the sender or the chat. The
/// sender wrote it, so it may not match the page; the user decides whether
/// to see them: always from this person, from everyone in this chat, not
/// for this message, or never in this chat.
class BundledUrlPreviewConsentCard extends StatelessWidget {
  const BundledUrlPreviewConsentCard({
    required this.senderName,
    required this.uri,
    this.homeserverFallback = false,
    this.onAlwaysFromSender,
    this.onAllowChat,
    this.onNotNow,
    this.onNeverInChat,
    super.key,
  });

  final String senderName;

  /// The link the preview is for; its domain is shown.
  final Uri uri;

  /// The homeserver had no preview for the link (an unencrypted chat that
  /// prefers the homeserver's): the text says so.
  final bool homeserverFallback;

  final void Function()? onAlwaysFromSender;
  final void Function()? onAllowChat;
  final void Function()? onNotNow;
  final void Function()? onNeverInChat;

  static String labelBundledPreviewConsentTitle(String sender) =>
      Intl.message("Show link previews from $sender?",
          args: [sender],
          name: "labelBundledPreviewConsentTitleFrom",
          desc: "Title of the card asking before a link preview the sender's "
              "app made shows; sender is their display name");

  static String labelBundledPreviewConsentBody(String sender) => Intl.message(
      "$sender’s app made this preview, not yours, so its title, text or "
      "picture might not match the real page. Showing it doesn’t contact the "
      "site, and your homeserver never sees the link.",
      args: [sender],
      name: "labelBundledPreviewConsentBody",
      desc: "Explains that a bundled link preview was written by the sender "
          "and could be misleading");

  static String labelBundledPreviewConsentFallbackBody(String sender) =>
      Intl.message(
          "Your homeserver couldn’t preview this link. $sender’s app attached "
          "one, but $sender wrote it, so it might not match the real page.",
          args: [sender],
          name: "labelBundledPreviewConsentFallbackBody",
          desc: "Consent card text in an unencrypted chat when the "
              "homeserver had no preview and only the sender's own one is "
              "left");

  static String get labelBundledPreviewConsentGoesTo => Intl.message(
      "Link goes to ",
      name: "labelBundledPreviewConsentGoesTo",
      desc: "Before the domain a link really points to, on the consent card");

  static String labelBundledPreviewAlwaysFrom(String sender) =>
      Intl.message("Always from $sender",
          args: [sender],
          name: "labelBundledPreviewAlwaysFrom",
          desc: "Button: always show link previews this person's app "
              "attaches, in every chat");

  static String get labelBundledPreviewEveryoneInChat =>
      Intl.message("Everyone in this chat",
          name: "labelBundledPreviewEveryoneInChat",
          desc: "Button: show sender-made link previews from everyone in "
              "this chat from now on");

  static String get labelBundledPreviewNotNow => Intl.message("Not now",
      name: "labelBundledPreviewNotNow",
      desc: "Button: hide this one sender-made link preview without deciding");

  static String get labelBundledPreviewNeverInChat =>
      Intl.message("Never in this chat",
          name: "labelBundledPreviewNeverInChat",
          desc: "Button: never show sender-made link previews in this chat "
              "(and stop asking)");

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Tile.surfaceContainer(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: tiamat.Text.labelEmphasised(
                          labelBundledPreviewConsentTitle(senderName)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    homeserverFallback
                        ? labelBundledPreviewConsentFallbackBody(senderName)
                        : labelBundledPreviewConsentBody(senderName),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: labelBundledPreviewConsentGoesTo,
                        style: TextStyle(color: scheme.secondary)),
                    TextSpan(
                        text: uri.host,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    tiamat.Button(
                      text: labelBundledPreviewAlwaysFrom(senderName),
                      onTap: onAlwaysFromSender,
                    ),
                    tiamat.Button.secondary(
                      text: labelBundledPreviewEveryoneInChat,
                      onTap: onAllowChat,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: onNotNow,
                      child: Text(labelBundledPreviewNotNow),
                    ),
                    TextButton(
                      onPressed: onNeverInChat,
                      child: Text(labelBundledPreviewNeverInChat),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
