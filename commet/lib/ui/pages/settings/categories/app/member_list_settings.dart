import 'package:commet/main.dart';
import 'package:commet/ui/molecules/member_subtitle.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Appearance › Member list.
class MemberListSettings extends StatefulWidget {
  const MemberListSettings({super.key});

  @override
  State<MemberListSettings> createState() => _MemberListSettingsState();
}

class _MemberListSettingsState extends State<MemberListSettings> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurfaceVariant;
    return tiamat.Panel(
      header: "Member list",
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const tiamat.Text.labelLow("Under each member's name, show"),
            RadioGroup<MemberListSubtitle>(
              groupValue: MemberListSubtitle.current,
              onChanged: (value) async {
                if (value == null) return;
                await preferences.memberListSubtitle.set(value.name);
                if (mounted) setState(() {});
              },
              child: Column(
                children: [
                  for (final option in MemberListSubtitle.values)
                    RadioListTile<MemberListSubtitle>(
                      key: ValueKey("member-list-subtitle-${option.name}"),
                      value: option,
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                      subtitle: Text(option.description,
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
