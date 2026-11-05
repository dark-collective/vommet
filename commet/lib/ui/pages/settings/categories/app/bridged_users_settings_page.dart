// Vommet issue 853: Settings › Bridged users. Network marks: the Matrix
// icon, a switch per network and the trusted bridge servers.
import 'dart:async';

import 'package:commet/main.dart';
import 'package:commet/ui/atoms/bridged_user_marker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/utils/bridged_users.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The networks with a switch, in the order shown.
const List<BridgeNetwork> switchedNetworks = [
  BridgeNetwork.telegram,
  BridgeNetwork.discord,
  BridgeNetwork.voiceBridge,
  BridgeNetwork.whatsapp,
  BridgeNetwork.signal,
  BridgeNetwork.irc,
];

/// Opens "Add a trusted bridge server", filled in with [server] and
/// [network] (from a user card's "Trust this server…").
Future<void> showAddTrustedServerDialog(BuildContext context,
    {String? server, BridgeNetwork? network}) async {
  await AdaptiveDialog.show<void>(context,
      title: bridgedTrustedAdd,
      builder: (context) => _AddTrustedServer(
          server: server, network: network ?? BridgeNetwork.telegram));
}

/// A server name: host name or IP, optional port.
bool isValidServerName(String server) => RegExp(
        r"^(\[[0-9a-fA-F:.]+\]|[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*)(:\d{1,5})?$")
    .hasMatch(server);

class BridgedUsersSettingsPage extends StatefulWidget {
  const BridgedUsersSettingsPage({super.key});

  @override
  State<BridgedUsersSettingsPage> createState() =>
      _BridgedUsersSettingsPageState();
}

class _BridgedUsersSettingsPageState extends State<BridgedUsersSettingsPage> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = BridgedUsers.onAnyChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final hidden = BridgedUsers.hiddenNetworks;
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
            _matrixIcon(context),
            BooleanPreferenceToggle(
              preference: BridgedUsers.warn,
              title: bridgedSettingsWarn,
              description: bridgedSettingsWarnDescription,
            ),
          ]),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: bridgedSettingsShowIconsFor,
          mode: tiamat.TileType.surfaceContainerLow,
          child: SettingsSearchTarget(
            ids: [
              BridgedUsers.disabledBuiltIns.key,
              bridgedSettingsShowIconsFor
            ],
            child: Column(children: [
              for (final n in switchedNetworks)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  secondary: BridgeNetworkIcon(n, size: 20),
                  title: Text(n == BridgeNetwork.voiceBridge
                      ? bridgedSettingsVoiceBridge
                      : BridgedUsers.networkLabel(n)),
                  value: !hidden.contains(n),
                  onChanged: (on) => _showNetwork(n, on),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: bridgedSettingsTrusted,
          mode: tiamat.TileType.surfaceContainerLow,
          child: SettingsSearchTarget(
            ids: [BridgedUsers.disabledTrusted.key, bridgedSettingsTrusted],
            child: _trusted(context, muted),
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

  void _showNetwork(BridgeNetwork network, bool on) {
    final ids = {
      for (final b in builtInBridges)
        if (b.network == network) b.id
    };
    final off = BridgedUsers.disabledBuiltIns.value.toSet();
    BridgedUsers.disabledBuiltIns
        .set(on ? off.difference(ids).toList() : off.union(ids).toList());
  }

  Widget _matrixIcon(BuildContext context) {
    String label(MatrixMarkMode mode) {
      switch (mode) {
        case MatrixMarkMode.bridgedRooms:
          return bridgedMatrixIconBridgedRooms;
        case MatrixMarkMode.everywhere:
          return bridgedMatrixIconEverywhere;
        case MatrixMarkMode.never:
          return bridgedMatrixIconNever;
      }
    }

    return SettingsSearchTarget(
      ids: [BridgedUsers.matrixMark.key, bridgedSettingsMatrixIcon],
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.labelEmphasised(bridgedSettingsMatrixIcon),
              tiamat.Text.labelLow(bridgedSettingsMatrixIconDescription),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<MatrixMarkMode>(
          value: BridgedUsers.matrixMarkMode,
          onChanged: (m) {
            if (m != null) BridgedUsers.matrixMark.set(m.name);
          },
          items: [
            for (final m in MatrixMarkMode.values)
              DropdownMenuItem(value: m, child: Text(label(m))),
          ],
        ),
      ]),
    );
  }

  Widget _chip(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }

  String _networks(Iterable<BridgeNetwork> networks) =>
      networks.map((n) => BridgedUsers.networkLabel(n)).join(", ");

  Widget _trusted(BuildContext context, Color muted) {
    final off = BridgedUsers.disabledTrusted.value.toSet();
    final homeservers = <String, Set<BridgeNetwork>>{};
    for (final client in clientManager?.clients ?? const []) {
      final server = serverOfUserId(client.self?.identifier ?? "");
      if (server == null) continue;
      (homeservers[server] ??= {})
          .addAll(BridgedUsers.ownServerNetworks(client));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child:
              Text(bridgedSettingsTrustedHint, style: TextStyle(color: muted)),
        ),
        for (final entry in homeservers.entries)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.home_outlined),
            title: Text(entry.key),
            subtitle: Text(bridgedTrustedHomeserver(entry.value.isEmpty
                ? bridgedTrustedNoneSeen
                : _networks(entry.value))),
            trailing: _chip(context, bridgedTrustedAutomatic),
          ),
        for (final t in builtInTrustedServers)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.verified_outlined),
            title: Text(t.server),
            subtitle: Text(BridgedUsers.networkLabel(t.network)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _chip(context, bridgedTrustedBuiltIn),
              const SizedBox(width: 8),
              Switch(
                value: !off.contains(t.id),
                onChanged: (on) => BridgedUsers.disabledTrusted
                    .set(on ? (off.toList()..remove(t.id)) : [...off, t.id]),
              ),
            ]),
          ),
        for (final p in BridgedUsers.userPatterns)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.person_outline),
            title: Text(p.serverName ?? p.pattern),
            subtitle: Text([
              BridgedUsers.networkLabel(p.network),
              if (p.pattern.isNotEmpty) p.pattern,
              if (p.dmsReach) bridgedSettingsDmsReach,
            ].join(" · ")),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _chip(context, bridgedTrustedYours),
              IconButton(
                tooltip: bridgedTrustedRemove,
                icon: const Icon(Icons.close),
                onPressed: () => BridgedUsers.patterns.set(BridgedUsers
                    .patterns.value
                    .where((s) =>
                        UserBridgePattern.decode(s)?.encode() != p.encode())
                    .toList()),
              ),
            ]),
          ),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text(bridgedTrustedAdd),
          onPressed: () => showAddTrustedServerDialog(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Text(bridgedTrustedRoomFooter, style: TextStyle(color: muted)),
        ),
      ],
    );
  }
}

class _AddTrustedServer extends StatefulWidget {
  const _AddTrustedServer({this.server, required this.network});

  final String? server;
  final BridgeNetwork network;

  @override
  State<_AddTrustedServer> createState() => _AddTrustedServerState();
}

class _AddTrustedServerState extends State<_AddTrustedServer> {
  late final TextEditingController _server =
      TextEditingController(text: widget.server ?? "");
  final TextEditingController _ids = TextEditingController();
  late BridgeNetwork _network = widget.network;
  bool _dmsReach = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _ids.dispose();
    super.dispose();
  }

  void _add() {
    final server = _server.text.trim().toLowerCase();
    if (!isValidServerName(server)) {
      setState(() => _error = bridgedTrustedInvalid);
      return;
    }
    final p = UserBridgePattern(_ids.text.trim(), _network,
        server: server, dmsReach: _dmsReach);
    BridgedUsers.patterns.set([...BridgedUsers.patterns.value, p.encode()]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(bridgedTrustedWarning, style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            TextField(
              controller: _server,
              autofocus: widget.server == null,
              decoration: InputDecoration(
                  labelText: bridgedTrustedServer,
                  hintText: "example.org",
                  errorText: _error),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<BridgeNetwork>(
              initialValue: _network,
              decoration: InputDecoration(labelText: bridgedTrustedNetwork),
              onChanged: (n) => setState(() => _network = n ?? _network),
              items: [
                for (final n in switchedNetworks)
                  DropdownMenuItem(
                      value: n, child: Text(BridgedUsers.networkLabel(n))),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ids,
              decoration: InputDecoration(
                  labelText: bridgedTrustedIds,
                  hintText: "@signal_*",
                  helperText: bridgedTrustedIdsHint),
              onSubmitted: (_) => _add(),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _dmsReach,
              onChanged: (v) => setState(() => _dmsReach = v ?? false),
              title: Text(bridgedSettingsDmsReach),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(bridgedCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _add,
                  child: Text(bridgedTrustedAddButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
