import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/invitation/invite_permission_config.dart';
import 'package:commet/client/matrix/components/invitation/matrix_invite_preview.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/account_selector.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/invite_strings.dart';
import 'package:commet/ui/pages/settings/categories/account/security/blocked_users/blocked_users_panel.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Invitations. Who can invite you, blocked servers and
/// blocked people. Your homeserver enforces all of it (MSC4155 lists and
/// the ignore list), so it holds on every app and device.
class InvitationsSettingsTab extends StatefulWidget {
  const InvitationsSettingsTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  @override
  State<InvitationsSettingsTab> createState() => _InvitationsSettingsTabState();
}

class _InvitationsSettingsTabState extends State<InvitationsSettingsTab> {
  late Client selectedClient;

  @override
  void initState() {
    selectedClient = widget.clientManager.clients.first;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final client = selectedClient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            onClientSelected: (c) => setState(() => selectedClient = c),
          ),
        if (client is MatrixClient)
          MatrixInvitationSettings(client,
              key: ValueKey("invitation-settings-${client.identifier}")),
      ],
    );
  }
}

class MatrixInvitationSettings extends StatefulWidget {
  const MatrixInvitationSettings(this.client, {super.key});
  final MatrixClient client;

  @override
  State<MatrixInvitationSettings> createState() =>
      _MatrixInvitationSettingsState();
}

class _MatrixInvitationSettingsState extends State<MatrixInvitationSettings> {
  late final MatrixInvitePreview perms = MatrixInvitePreview(widget.client);
  StreamSubscription? _sub;
  final TextEditingController _input = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sub = perms.onConfigChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() => _busy = true);
    try {
      await change();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not change the invitation settings");
      if (mounted) {
        AdaptiveDialog.show(context,
            title: inviteSettingsTab,
            builder: (_) => tiamat.Text.label(e is ArgumentError
                ? inviteSettingsNotAServer
                : inviteSettingsUpdateFailed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockTyped() async {
    final server = InvitePermissionConfig.normaliseServer(_input.text);
    if (server == null) {
      AdaptiveDialog.show(context,
          title: inviteSettingsBlockAServer,
          builder: (_) => tiamat.Text.label(inviteSettingsNotAServer));
      return;
    }
    if (InvitePermissionConfig.matches(server, perms.ownServer)) {
      AdaptiveDialog.show(context,
          title: inviteSettingsBlockAServer,
          builder: (_) => tiamat.Text.label(inviteSettingsOwnServer));
      return;
    }
    await _run(() => perms.blockServer(server));
    if (mounted && perms.blockedServers.contains(server)) _input.clear();
  }

  Widget _radio(
      {required bool selected,
      required String title,
      required String explain,
      required Key key,
      required VoidCallback onTap}) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: _busy || selected ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              tiamat.Text.labelEmphasised(title),
              tiamat.Text.labelLow(explain),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = perms.config;
    final blocksAll = config.blocksAll;
    final servers = config.blockedServers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        tiamat.Panel(
          header: inviteSettingsWhoCanInvite,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(children: [
            _radio(
              key: const ValueKey("invites-anyone"),
              selected: !blocksAll,
              title: inviteSettingsAnyone,
              explain: inviteSettingsAnyoneExplain,
              onTap: () => _run(() => perms.setBlocksAll(false)),
            ),
            _radio(
              key: const ValueKey("invites-nobody"),
              selected: blocksAll,
              title: inviteSettingsNobody,
              explain: inviteSettingsNobodyExplain,
              onTap: () => _run(() => perms.setBlocksAll(true)),
            ),
          ]),
        ),
        tiamat.Panel(
          header: inviteSettingsBlockedServers,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (config.listsDisabled && servers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: tiamat.Text.labelLow(inviteSettingsListsOff),
                ),
              if (servers.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: tiamat.Text.label(inviteSettingsNoBlockedServers),
                ),
              for (final server in servers)
                Padding(
                  key: ValueKey("blocked-server-$server"),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.dns_outlined, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tiamat.Text.label(server, maxLines: 1),
                            if (server.contains("*") || server.contains("?"))
                              tiamat.Text.labelLow(
                                  inviteSettingsGlobExplain(server),
                                  maxLines: 1),
                          ]),
                    ),
                    TextButton(
                      key: ValueKey("unblock-server-$server"),
                      onPressed: _busy
                          ? null
                          : () => _run(() => perms.unblockServer(server)),
                      child: Text(inviteSettingsUnblock),
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey("block-server-input"),
                      controller: _input,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: inviteSettingsServerHint,
                        labelText: inviteSettingsBlockAServer,
                      ),
                      onSubmitted: (_) => _blockTyped(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  tiamat.Button(
                    text: inviteSettingsBlock,
                    isLoading: _busy,
                    onTap: _blockTyped,
                  ),
                ]),
              ),
            ],
          ),
        ),
        BlockedUsersPanel(widget.client),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: tiamat.Text.labelLow(inviteSettingsFooter(perms.ownServer)),
        ),
      ],
    );
  }
}
