import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/scheduled_messages/scheduled_messages.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_list_strings.dart';
import 'package:commet/ui/organisms/scheduled_messages/scheduled_messages_view.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Settings is available in every layout; this page never mixes accounts.
class ScheduledMessagesTab extends StatefulWidget {
  const ScheduledMessagesTab({required this.clientManager, super.key});
  final ClientManager clientManager;

  @override
  State<ScheduledMessagesTab> createState() => _ScheduledMessagesTabState();
}

class _ScheduledMessagesTabState extends State<ScheduledMessagesTab> {
  Client? client;
  bool loading = false;
  bool busy = false;
  bool? supported;
  bool failed = false;
  bool signedOut = false;
  int generation = 0;
  late final StreamSubscription clientsChanged;

  bool valid(Client c) =>
      widget.clientManager.clients.contains(c) &&
      c.isLoggedIn() &&
      ScheduledMessages.available(c);

  @override
  void initState() {
    super.initState();
    ScheduledMessages.changed.addListener(update);
    clientsChanged = widget.clientManager.clients.onListUpdated
        .listen((_) => scheduleMicrotask(update));
    // A single signed-in account is unambiguous. Multiple accounts require
    // an explicit choice, even if the main window currently filters one.
    if (widget.clientManager.clients.length == 1) {
      client = widget.clientManager.clients.single;
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    clientsChanged.cancel();
    ScheduledMessages.changed.removeListener(update);
    super.dispose();
  }

  void update() {
    if (!mounted) return;
    if (client != null && !valid(client!)) {
      generation++;
      client = null;
      loading = false;
      busy = false;
      supported = null;
      failed = false;
      signedOut = true;
    } else if (client != null && !loading) {
      supported = ScheduledMessages.supportedCached(client!) ?? supported;
    }
    setState(() {});
  }

  Future<void> choose() async {
    if (busy || widget.clientManager.clients.isEmpty) return;
    final accounts = widget.clientManager.clients
        .where((c) => c.isLoggedIn() && ScheduledMessages.available(c))
        .toList();
    final picked = await AdaptiveDialog.pickOne<Client>(
      context,
      title: ScheduledListStrings.chooseAccount,
      items: accounts,
      itemBuilder: (context, c, callback) {
        final policy = RedactionScope.of(context);
        final id = c.self?.identifier ?? c.identifier;
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(policy.name(c.self?.displayName ?? c.identifier, id)),
            subtitle: Text(policy.name(id, id)),
            onTap: callback,
          ),
        );
      },
    );
    if (!mounted || picked == null || !valid(picked)) return;
    setState(() {
      client = picked;
      signedOut = false;
      supported = null;
      failed = false;
    });
    await load();
  }

  Future<void> load({bool forceSupport = false}) async {
    final c = client;
    if (c == null) return;
    if (!valid(c)) {
      update();
      return;
    }
    final token = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final answer = await ScheduledMessages.supported(c,
          throwOnError: true, force: forceSupport);
      if (answer) await ScheduledMessages.refresh(c, strict: true);
      if (!mounted || token != generation || !identical(c, client)) return;
      if (!valid(c)) {
        update();
        return;
      }
      setState(() {
        supported = answer;
        loading = false;
      });
    } catch (_) {
      if (!mounted || token != generation || !identical(c, client)) return;
      setState(() {
        failed = true;
        loading = false;
      });
    }
  }

  Room? joinedRoom(Client c, ScheduledMessage m) {
    final room = c.getRoom(m.roomId);
    if (room == null || room.isBanned || room.isRemoved) return null;
    if (room is MatrixRoom &&
        room.matrixRoom.membership != matrix.Membership.join) return null;
    return room;
  }

  Future<void> guard(Client c, ScheduledMessage m, bool needsRoom) async {
    void check() {
      if (!mounted || !identical(client, c) || !valid(c)) {
        throw ScheduleException(ScheduledListStrings.signedOut);
      }
      if (needsRoom && joinedRoom(c, m) == null) {
        throw ScheduleException(ScheduledListStrings.roomUnavailableHelp);
      }
    }

    check();
    final items = await ScheduledMessages.refresh(c, strict: true);
    check();
    if (!items
        .any((item) => item.delayId == m.delayId && item.roomId == m.roomId)) {
      throw ScheduleException(ScheduledListStrings.gone);
    }
  }

  void checkDraft(Client c, ScheduledMessage m) {
    if (!valid(c)) throw ScheduleException(ScheduledListStrings.signedOut);
    final room = joinedRoom(c, m);
    if (room == null || !ChatState.canAcceptScheduledEdit(room)) {
      throw ScheduleException(ScheduledListStrings.draftConflict);
    }
  }

  void edit(Client c, Room room, String text) {
    if (!valid(c)) return;
    // Retain the exact room captured before cancellation, even if a leave
    // arrives while the server processes it. Its text remains an edit handoff.
    ChatState.startScheduledEdit(room, text);
    // Leave both the mobile subpage and Settings; the room opens underneath.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = client;
    final redaction = RedactionScope.of(context);
    final items = c == null || loading || failed || supported != true
        ? const <ScheduledMessage>[]
        : ScheduledMessages.inAccount(c);
    return ListView.builder(
      key: const ValueKey('account-scheduled-messages'),
      padding: const EdgeInsets.all(12),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == 0)
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.largeTitle(ScheduleStrings.scheduledListTitle),
              const SizedBox(height: 12),
              Card(
                  child: ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(c == null
                    ? ScheduledListStrings.chooseAccount
                    : redaction.name(c.self?.displayName ?? c.identifier,
                        c.self?.identifier ?? c.identifier)),
                subtitle: Text(c == null
                    ? ScheduledListStrings.noAccount
                    : redaction.name(c.self?.identifier ?? c.identifier,
                        c.self?.identifier ?? c.identifier)),
                trailing: const Icon(Icons.expand_more),
                onTap: busy ? null : choose,
              )),
              if (c != null) ...[
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: tiamat.Text.labelLow(
                        '${ScheduledListStrings.scope} · ${DateTime.now().timeZoneName}')),
                Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                        onPressed: loading || busy
                            ? null
                            : () => load(forceSupport: true),
                        icon: const Icon(Icons.refresh),
                        label: Text(ScheduledListStrings.refresh))),
              ],
              if (signedOut) tiamat.Text.body(ScheduledListStrings.signedOut),
              if (widget.clientManager.clients.isEmpty)
                tiamat.Text.body(ScheduledListStrings.noAccounts),
              if (loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                tiamat.Text.body(ScheduledListStrings.loading)
              ],
              if (failed) ...[
                tiamat.Text.body(ScheduledListStrings.unavailable),
                TextButton(
                    onPressed: busy ? null : () => load(forceSupport: true),
                    child: Text(ScheduledListStrings.retry)),
              ],
              if (!loading && !failed && c != null && supported == false)
                tiamat.Text.body(
                    ScheduleStrings.scheduleUnsupportedExplanation),
              if (!loading &&
                  !failed &&
                  c != null &&
                  supported == true &&
                  items.isEmpty)
                tiamat.Text.body(ScheduledListStrings.none),
            ],
          );
        final m = items[index - 1];
        final room = joinedRoom(c!, m);
        return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: tiamat.Panel(
              mode: tiamat.TileType.surfaceContainerLow,
              child: ScheduledMessageEntry(
                key: ValueKey((c, m.roomId, m.delayId)),
                client: c,
                message: m,
                enabled: !busy,
                roomAvailable: room != null,
                onBusyChanged: (value) {
                  if (mounted) setState(() => busy = value);
                },
                beforeAction: (needsRoom) => guard(c, m, needsRoom),
                onError: (error) async {
                  if (mounted && identical(client, c)) {
                    await SchedulePicker.showError(context, error);
                  }
                },
                beforeEdit: () => checkDraft(c, m),
                onEdit: (text) {
                  if (room != null) edit(c, room, text);
                },
                header: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.tag, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  tiamat.Text.labelEmphasised(
                                      redaction.roomName(
                                          room?.displayName ??
                                              ScheduledListStrings
                                                  .roomUnavailable,
                                          m.roomId)),
                                  SelectableText(
                                      redaction.roomName(m.roomId, m.roomId)),
                                ])),
                          ]),
                      if (room == null)
                        tiamat.Text.labelLow(
                            ScheduledListStrings.roomUnavailableHelp),
                    ]),
              ),
            ));
      },
    );
  }
}
