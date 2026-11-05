import 'package:commet/main.dart';
import 'package:commet/ui/atoms/thread_card.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';
import 'package:intl/intl.dart';

/// Vommet: Settings › Appearance › Threads.
class ThreadPreviewSettings extends StatefulWidget {
  const ThreadPreviewSettings({super.key});

  @override
  State<ThreadPreviewSettings> createState() => _ThreadPreviewSettingsState();
}

class _ThreadPreviewSettingsState extends State<ThreadPreviewSettings> {
  @override
  Widget build(BuildContext context) {
    return Panel(
      header: threadPreviewSettingsHeader,
      mode: TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            tiamat.Text(threadPreviewSettingsTitle),
            tiamat.Text.labelLow(threadPreviewSettingsDescription),
            tiamat.DropdownSelector<ThreadPreviewMode>(
              color: ColorScheme.of(context).surfaceContainerLow,
              items: ThreadPreviewMode.values,
              itemBuilder: (item) => tiamat.Text(item.label),
              onItemSelected: (item) async {
                if (item == null) return;
                await preferences.threadPreviewMode.set(item.name);
                if (mounted) setState(() {});
              },
              value:
                  ThreadPreviewMode.parse(preferences.threadPreviewMode.value),
            ),
            const SizedBox(height: 4),
            tiamat.Text.labelLow(threadPreviewSettingsPreviewLabel),
            ThreadCardPreview(
                mode: ThreadPreviewMode.parse(
                    preferences.threadPreviewMode.value)),
          ],
        ),
      ),
    );
  }
}

/// A made-up thread with the card as [mode] shows it, so the setting shows
/// what each choice looks like. The replies are long enough to be cut.
class ThreadCardPreview extends StatelessWidget {
  const ThreadCardPreview({required this.mode, super.key});
  final ThreadPreviewMode mode;

  static const _avery = ThreadCardFace(name: "Avery", color: Color(0xff7fd1a8));
  static const _sam = ThreadCardFace(name: "Sam", color: Color(0xffc58cff));
  static const _jo = ThreadCardFace(name: "Jo", color: Color(0xffffb86b));

  static ThreadCardReply _reply(
          ThreadCardFace who, String body, int lines, String time) =>
      ThreadCardReply(
          senderName: who.name,
          senderColor: who.color,
          body: body,
          time: time,
          maxLines: lines);

  static String get _first => threadPreviewSettingsSampleFirstReply;
  static String get _latest => threadPreviewSettingsSampleLatestReply;

  List<ThreadCardReply> get replies => switch (mode) {
        ThreadPreviewMode.latest => [_reply(_jo, _latest, 2, "20:41")],
        ThreadPreviewMode.first => [_reply(_sam, _first, 3, "20:02")],
        ThreadPreviewMode.both => [
            _reply(_sam, _first, 2, "20:02"),
            _reply(_jo, _latest, 2, "20:41"),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Container(
          key: const ValueKey("thread-card-preview"),
          decoration: BoxDecoration(
              color: scheme.surface, borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Avatar(
                  placeholderText: _avery.name,
                  placeholderColor: _avery.color,
                  radius: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text(_avery.name,
                        color: _avery.color, autoAdjustBrightness: true),
                    const SizedBox(height: 2),
                    tiamat.Text(threadPreviewSettingsSampleRootMessage),
                    const SizedBox(height: 8),
                    ThreadCard(
                      replyCount: 8,
                      lastReply:
                          DateTime.now().subtract(const Duration(minutes: 3)),
                      faces: const [_jo, _sam, _avery],
                      replies: replies,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get threadPreviewSettingsHeader => Intl.message("Threads",
    name: "threadPreviewSettingsHeader",
    desc: "Header of the Threads settings panel");

String get threadPreviewSettingsTitle => Intl.message("Thread previews",
    name: "threadPreviewSettingsTitle",
    desc: "Title of the thread preview setting");

String get threadPreviewSettingsDescription =>
    Intl.message("Which replies the card under a thread's first message shows",
        name: "threadPreviewSettingsDescription",
        desc: "Description of the thread preview setting");

String get threadPreviewSettingsPreviewLabel => Intl.message("Preview",
    name: "threadPreviewSettingsPreviewLabel",
    desc: "Label above the sample thread card in the thread preview setting");

String get threadPreviewSettingsSampleFirstReply => Intl.message(
    "I'm in! Bringing the snacks again, and this time I'm not sharing the good chips with anyone who turns up late, or anyone who complains about the playlist.",
    name: "threadPreviewSettingsSampleFirstReply",
    desc:
        "Made-up first reply in the sample thread card (casual chat; any similar message is fine)");

String get threadPreviewSettingsSampleLatestReply => Intl.message(
    "Running ten minutes late, save me a spot and absolutely do not let anyone touch the good chips before I get there.",
    name: "threadPreviewSettingsSampleLatestReply",
    desc:
        "Made-up latest reply in the sample thread card (casual chat; any similar message is fine)");

String get threadPreviewSettingsSampleRootMessage => Intl.message(
    "who's up for raid night on friday?",
    name: "threadPreviewSettingsSampleRootMessage",
    desc:
        "Made-up first message of the sample thread (casual chat, lower case on purpose)");
