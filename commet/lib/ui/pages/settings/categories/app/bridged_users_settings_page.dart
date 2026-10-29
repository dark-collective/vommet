// Vommet issue 853: Settings › Bridged users.
import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/bridged_user_marker.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class BridgedUsersSettingsPage extends StatefulWidget {
  const BridgedUsersSettingsPage({super.key});

  @override
  State<BridgedUsersSettingsPage> createState() =>
      _BridgedUsersSettingsPageState();
}

class _BridgedUsersSettingsPageState extends State<BridgedUsersSettingsPage> {
  StreamSubscription? _sub;
  final TextEditingController _pattern = TextEditingController();
  BridgeNetwork _network = BridgeNetwork.irc;
  bool _dmsReach = false;

  @override
  void initState() {
    super.initState();
    _sub = preferences.onSettingChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pattern.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final off = BridgedUsers.disabledBuiltIns.value.toSet();
    final patterns = BridgedUsers.userPatterns;
    final overrides = BridgedUsers.overrideMap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Panel(
          header: bridgedSettingsTitle,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(children: [
            BooleanPreferenceToggle(
              preference: BridgedUsers.mark,
              title: bridgedSettingsMark,
              description: bridgedSettingsMarkDescription,
            ),
            BooleanPreferenceToggle(
              preference: BridgedUsers.warn,
              title: bridgedSettingsWarn,
              description: bridgedSettingsWarnDescription,
            ),
          ]),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: bridgedSettingsRecognized,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(bridgedSettingsRecognizedHint,
                    style: TextStyle(color: muted)),
              ),
              for (final b in builtInBridges)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  secondary: BridgeNetworkIcon(b.network, size: 20),
                  title: Text(BridgedUsers.builtInLabel(b.network)),
                  value: !off.contains(b.id),
                  onChanged: (on) => BridgedUsers.disabledBuiltIns
                      .set(on ? (off.toList()..remove(b.id)) : [...off, b.id]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: bridgedSettingsYourPatterns,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in patterns)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: BridgeNetworkIcon(p.network, size: 20),
                  title: Text(
                      "${p.pattern} → ${BridgedUsers.networkLabel(p.network)}"),
                  subtitle: p.dmsReach ? Text(bridgedSettingsDmsReach) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => BridgedUsers.patterns.set(BridgedUsers
                        .patterns.value
                        .where((s) => s != p.encode())
                        .toList()),
                  ),
                ),
              _addPattern(context),
            ],
          ),
        ),
        if (overrides.isNotEmpty) ...[
          const SizedBox(height: 10),
          tiamat.Panel(
            header: bridgedSettingsPeopleChanged,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(children: [
              for (final entry in overrides.entries)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(entry.key),
                  subtitle: Text(entry.value == notBridgedOverride
                      ? bridgedSettingsNotBridged
                      : BridgedUsers.builtInLabel(
                          networkFromName(entry.value) ?? BridgeNetwork.other)),
                  trailing: TextButton(
                    onPressed: () => BridgedUsers.setOverride(entry.key, null),
                    child: Text(bridgedSettingsReset),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _addPattern(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pattern,
                decoration: InputDecoration(
                    isDense: true, hintText: bridgedSettingsPatternHint),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<BridgeNetwork>(
              value: _network,
              onChanged: (n) => setState(() => _network = n ?? _network),
              items: [
                for (final n in BridgeNetwork.values)
                  DropdownMenuItem(
                      value: n, child: Text(BridgedUsers.networkLabel(n))),
              ],
            ),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _dmsReach,
            onChanged: (v) => setState(() => _dmsReach = v ?? false),
            title: Text(bridgedSettingsDmsReach),
          ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(bridgedSettingsAddPattern),
            onPressed: _add,
          ),
        ],
      ),
    );
  }

  void _add() {
    final text = _pattern.text.trim();
    if (text.isEmpty) return;
    final p = UserBridgePattern(text, _network, dmsReach: _dmsReach);
    BridgedUsers.patterns.set([...BridgedUsers.patterns.value, p.encode()]);
    _pattern.clear();
    setState(() => _dmsReach = false);
  }
}
