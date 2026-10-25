import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 676: shown instead of a link preview the sender's app
/// bundled (MSC4095), the first time one arrives in a chat. The sender wrote
/// it, so it may not match the page; the user decides whether to see them.
class BundledUrlPreviewConsentCard extends StatelessWidget {
  const BundledUrlPreviewConsentCard({
    required this.senderName,
    required this.uri,
    this.onAllowChat,
    this.onAllowEverywhere,
    this.onNotNow,
    super.key,
  });

  final String senderName;

  /// The link the preview is for; its domain is shown.
  final Uri uri;

  final void Function()? onAllowChat;
  final void Function()? onAllowEverywhere;
  final void Function()? onNotNow;

  static String get labelBundledPreviewConsentTitle => Intl.message(
      "Show link previews from this chat?",
      name: "labelBundledPreviewConsentTitle",
      desc: "Title of the card asking before a sender-made link preview shows");

  static String labelBundledPreviewConsentBody(String sender) => Intl.message(
      "$sender’s app made this preview, not yours, so its title, text or "
      "picture might not match the real page. Showing it doesn’t contact the "
      "site, and your homeserver never sees the link.",
      args: [sender],
      name: "labelBundledPreviewConsentBody",
      desc: "Explains that a bundled link preview was written by the sender "
          "and could be misleading");

  static String get labelBundledPreviewConsentGoesTo => Intl.message(
      "Link goes to ",
      name: "labelBundledPreviewConsentGoesTo",
      desc: "Before the domain a link really points to, on the consent card");

  static String get labelBundledPreviewAllowChat => Intl.message(
      "Show in this chat",
      name: "labelBundledPreviewAllowChat",
      desc: "Button: show sender-made link previews in this chat from now on");

  static String get labelBundledPreviewAllowEverywhere =>
      Intl.message("Show in all chats",
          name: "labelBundledPreviewAllowEverywhere",
          desc: "Button: show sender-made link previews in every chat");

  static String get labelBundledPreviewNotNow => Intl.message("Not now",
      name: "labelBundledPreviewNotNow",
      desc: "Button: hide this one sender-made link preview without deciding");

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
                          labelBundledPreviewConsentTitle),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(labelBundledPreviewConsentBody(senderName),
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
                      text: labelBundledPreviewAllowChat,
                      onTap: onAllowChat,
                    ),
                    tiamat.Button.secondary(
                      text: labelBundledPreviewAllowEverywhere,
                      onTap: onAllowEverywhere,
                    ),
                    TextButton(
                      onPressed: onNotNow,
                      child: Text(labelBundledPreviewNotNow),
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
