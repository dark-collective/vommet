import 'package:commet/main.dart';
import 'package:commet/ui/atoms/reply_quote.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

/// Vommet: Settings › Appearance › Replies.
class ReplyStyleSettings extends StatefulWidget {
  const ReplyStyleSettings({super.key});

  @override
  State<ReplyStyleSettings> createState() => _ReplyStyleSettingsState();
}

class _ReplyStyleSettingsState extends State<ReplyStyleSettings> {
  @override
  Widget build(BuildContext context) {
    final style = ReplyStyle.current;
    return SettingsSearchTarget(
      ids: [preferences.replyStyle.key, replyStyleSettingsHeader],
      child: Panel(
        header: replyStyleSettingsHeader,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              tiamat.Text(replyStyleSettingsTitle),
              tiamat.Text.labelLow(replyStyleSettingsDescription),
              tiamat.DropdownSelector<ReplyStyle>(
                color: ColorScheme.of(context).surfaceContainerLow,
                items: ReplyStyle.values,
                itemBuilder: (item) => tiamat.Text(item.label),
                onItemSelected: (item) async {
                  if (item == null) return;
                  await preferences.replyStyle.set(item.name);
                  if (mounted) setState(() {});
                },
                value: style,
              ),
              const SizedBox(height: 4),
              tiamat.Text.labelLow(replyStyleSettingsPreviewLabel),
              ReplyStylePreview(style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// A made-up reply in [style], so the setting shows what each choice looks
/// like.
class ReplyStylePreview extends StatelessWidget {
  const ReplyStylePreview({required this.style, super.key});
  final ReplyStyle style;

  static const _rowan = Color(0xff7fd1a8);
  static const _kit = Color(0xffc58cff);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quoted = replyStyleSettingsSampleQuoted;

    final compactLine = Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 2),
      child: Row(children: [
        Icon(Icons.subdirectory_arrow_right, size: 14, color: scheme.secondary),
        const SizedBox(width: 4),
        tiamat.Text.name("Rowan", color: _rowan),
        const SizedBox(width: 4),
        Flexible(
          child: tiamat.Text(quoted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              color: scheme.secondary),
        ),
      ]),
    );

    return ExcludeSemantics(
      child: IgnorePointer(
        child: Container(
          key: const ValueKey("reply-style-preview"),
          decoration: BoxDecoration(
              color: scheme.surface, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!style.inline) compactLine,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Avatar(
                      placeholderText: "Kit",
                      placeholderColor: _kit,
                      radius: 16),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tiamat.Text.name("Kit", color: _kit),
                        if (style.inline)
                          ReplyQuote(
                              style: style,
                              senderName: "Rowan",
                              senderColor: _rowan,
                              body: quoted),
                        tiamat.Text(replyStyleSettingsSampleReply),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get replyStyleSettingsHeader => Intl.message("Replies",
    name: "replyStyleSettingsHeader",
    desc: "Header of the Replies settings panel");

String get replyStyleSettingsTitle => Intl.message("Reply style",
    name: "replyStyleSettingsTitle",
    desc:
        "Title of the setting that picks how replies show the quoted message");

String get replyStyleSettingsDescription =>
    Intl.message("How a reply shows the message it answers",
        name: "replyStyleSettingsDescription",
        desc: "Description of the reply style setting");

String get replyStyleSettingsPreviewLabel => Intl.message("Preview",
    name: "replyStyleSettingsPreviewLabel",
    desc: "Label above the sample reply in the reply style setting");

String get replyStyleSettingsSampleQuoted => Intl.message(
    "If we take the river route we skip the toll bridge, but it adds about a day to the trip.",
    name: "replyStyleSettingsSampleQuoted",
    desc:
        "Made-up quoted message in the reply style preview (casual chat; any similar message is fine)");

String get replyStyleSettingsSampleReply => Intl.message(
    "river route, the horses need the rest anyway",
    name: "replyStyleSettingsSampleReply",
    desc:
        "Made-up reply in the reply style preview (casual chat, lower case on purpose)");
