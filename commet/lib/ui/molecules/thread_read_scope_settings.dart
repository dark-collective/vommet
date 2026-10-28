import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issues 804 and 805: the "Read state per thread" controls in
/// Settings › Notifications, room info and space info.

String threadReadScopeLabel(ThreadReadScope scope) => switch (scope) {
      ThreadReadScope.off => "Off",
      ThreadReadScope.mine => "Threads I'm in",
      ThreadReadScope.all => "All threads",
    };

const String threadReadScopeTitle = "Read state per thread";

const String threadReadScopeExplain =
    "A tracked thread keeps its own unread mark until you read it, and keeps "
    "the room unread. \"Threads I'm in\" = threads you started or replied "
    "in. Other threads are marked read when you read the room.";

/// The choice made in the list: [scope] null is "Use default (…)".
class ThreadReadScopePick {
  const ThreadReadScopePick(this.scope);
  final ThreadReadScope? scope;
}

/// "Use default (…)" first, then the three choices; null when closed
/// without a pick.
Future<ThreadReadScopePick?> pickThreadReadScope(BuildContext context,
        {required ThreadReadScope? own,
        required ThreadReadScope defaultScope}) =>
    AdaptiveDialog.show<ThreadReadScopePick>(context,
        title: threadReadScopeTitle, builder: (context) {
      Widget choice(ThreadReadScope? scope, String text) {
        final selected = scope == own;
        return ListTile(
          key: ValueKey("thread-read-scope-${scope?.name ?? "default"}"),
          leading: Icon(selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(text),
          selected: selected,
          onTap: () => Navigator.of(context).pop(ThreadReadScopePick(scope)),
        );
      }

      return Column(mainAxisSize: MainAxisSize.min, children: [
        choice(null, "Use default (${threadReadScopeLabel(defaultScope)})"),
        for (final scope in ThreadReadScope.values)
          choice(scope, threadReadScopeLabel(scope)),
      ]);
    });

/// The room's (or space's) "Read state per thread" row; a tap picks its
/// own choice or "Use default".
class ThreadReadScopeRow extends StatefulWidget {
  const ThreadReadScopeRow(this.room, {super.key});
  final matrix.Room room;

  @override
  State<ThreadReadScopeRow> createState() => _ThreadReadScopeRowState();
}

class _ThreadReadScopeRowState extends State<ThreadReadScopeRow> {
  Future<void> _pick() async {
    final room = widget.room;
    final pick = await pickThreadReadScope(context,
        own: ThreadReadScopes.ownScope(room),
        defaultScope: ThreadReadScopes.defaultFor(room));
    if (pick == null) return;
    await ThreadReadScopes.setOwnScope(room, pick.scope);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final own = ThreadReadScopes.ownScope(room);
    return InfoRow(
      key: const ValueKey("room-info-thread-read-scope"),
      icon: Icons.forum_outlined,
      title: threadReadScopeTitle,
      subtitle: room.isSpace ? "For the rooms in this space" : null,
      value: own == null
          ? "Default (${threadReadScopeLabel(ThreadReadScopes.defaultFor(room))})"
          : threadReadScopeLabel(own),
      onTap: _pick,
    );
  }
}

/// Settings › Notifications › Threads: the account default, set on every
/// Matrix account at once.
class ThreadReadScopeSettings extends StatefulWidget {
  const ThreadReadScopeSettings({super.key});

  @override
  State<ThreadReadScopeSettings> createState() =>
      _ThreadReadScopeSettingsState();
}

class _ThreadReadScopeSettingsState extends State<ThreadReadScopeSettings> {
  List<matrix.Client> get clients => [
        for (final c in clientManager?.clients ?? [])
          if (c is MatrixClient) c.getMatrixClient(),
      ];

  Future<void> _set(ThreadReadScope scope) async {
    for (final c in clients) {
      await ThreadReadScopes.setAccountDefault(c, scope);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = clients;
    if (list.isEmpty) return const SizedBox.shrink();
    final current = ThreadReadScopes.accountDefault(list.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(threadReadScopeExplain),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ThreadReadScope>(
              key: const ValueKey("thread-read-scope-default"),
              showSelectedIcon: false,
              segments: [
                for (final scope in ThreadReadScope.values)
                  ButtonSegment(
                      value: scope, label: Text(threadReadScopeLabel(scope))),
              ],
              selected: {current},
              onSelectionChanged: (s) => _set(s.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(
              "Rooms and spaces can override this in their info page."),
        ),
      ],
    );
  }
}
