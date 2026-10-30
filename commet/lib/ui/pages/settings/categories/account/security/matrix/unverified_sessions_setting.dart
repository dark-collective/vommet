import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 947: whether your message keys go to other people's sessions
/// they haven't verified.
class UnverifiedSessionsSettingStrings {
  static String get panelTitle => Intl.message(
      "Sessions their owner hasn't verified",
      name: "unverifiedSessionsSettingTitle",
      desc:
          "Header of the Security settings section about sending message keys to other people's unverified sessions");

  static String get help => Intl.message(
      "When someone has turned on verification but hasn't verified one of their sessions, it can't read your encrypted messages unless you choose to send to it.",
      name: "unverifiedSessionsSettingHelp",
      desc: "Explains the unverified sessions setting in Security settings");

  static String label(UnverifiedSessionsPolicy p) => switch (p) {
        UnverifiedSessionsPolicy.ask => Intl.message("Ask me",
            name: "unverifiedSessionsSettingAsk",
            desc: "Unverified sessions setting: warn in the room and ask"),
        UnverifiedSessionsPolicy.always => Intl.message("Always send to them",
            name: "unverifiedSessionsSettingAlways",
            desc: "Unverified sessions setting: send message keys to them"),
        UnverifiedSessionsPolicy.never => Intl.message("Never, and don't ask",
            name: "unverifiedSessionsSettingNever",
            desc:
                "Unverified sessions setting: don't send to them and don't warn"),
      };

  static String description(UnverifiedSessionsPolicy p) => switch (p) {
        UnverifiedSessionsPolicy.ask => Intl.message(
            "Rooms warn above the message box and name each session, so you can choose.",
            name: "unverifiedSessionsSettingAskDescription",
            desc: "Explains the Ask me choice"),
        UnverifiedSessionsPolicy.always => Intl.message(
            "Like Element: anyone signed in to their account can read what you send them. Sessions you blocked are still skipped.",
            name: "unverifiedSessionsSettingAlwaysDescription",
            desc: "Explains the Always send to them choice"),
        UnverifiedSessionsPolicy.never => Intl.message(
            "Those sessions can't read your messages, and nothing tells you.",
            name: "unverifiedSessionsSettingNeverDescription",
            desc: "Explains the Never choice"),
      };
}

/// Settings › Security › Sessions their owner hasn't verified.
class UnverifiedSessionsPanel extends StatefulWidget {
  const UnverifiedSessionsPanel({super.key});

  @override
  State<UnverifiedSessionsPanel> createState() =>
      _UnverifiedSessionsPanelState();
}

class _UnverifiedSessionsPanelState extends State<UnverifiedSessionsPanel> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return tiamat.Panel(
      header: UnverifiedSessionsSettingStrings.panelTitle,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.Text.labelLow(UnverifiedSessionsSettingStrings.help),
            RadioGroup<UnverifiedSessionsPolicy>(
              groupValue: UnverifiedSessions.policy,
              onChanged: (value) async {
                if (value == null) return;
                await UnverifiedSessions.setPolicy(value);
                if (mounted) setState(() {});
              },
              child: Column(
                children: [
                  for (final option in UnverifiedSessionsPolicy.values)
                    RadioListTile<UnverifiedSessionsPolicy>(
                      key: ValueKey("unverified-sessions-${option.name}"),
                      value: option,
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(UnverifiedSessionsSettingStrings.label(option)),
                      subtitle: Text(
                          UnverifiedSessionsSettingStrings.description(option),
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: dim)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
