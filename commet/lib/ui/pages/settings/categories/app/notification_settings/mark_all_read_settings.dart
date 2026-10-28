import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mark_all_read.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 719: Mark all as read, per account, in Settings ›
/// Notifications.
class MarkAllReadSettings extends StatefulWidget {
  const MarkAllReadSettings({super.key});

  @override
  State<MarkAllReadSettings> createState() => _MarkAllReadSettingsState();
}

class _MarkAllReadSettingsState extends State<MarkAllReadSettings> {
  final Set<Client> busy = {};

  List<Client> get clients => clientManager?.clients ?? [];

  Future<void> _mark(Client client) async {
    setState(() => busy.add(client));
    try {
      await MarkAllRead.confirmAndMark(context, [client]);
    } finally {
      if (mounted) setState(() => busy.remove(client));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = clients;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: tiamat.Text.labelLow(MarkAllRead.markAllReadExplain),
        ),
        for (final c in list)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(spacing: 8, children: [
              if (list.length > 1)
                Expanded(
                    child: tiamat.Text.label(
                        c.self?.displayName ?? c.self?.identifier ?? ""))
              else
                const Spacer(),
              if (MarkAllRead.unreadRooms([c]).isEmpty)
                tiamat.Text.labelLow(MarkAllRead.markAllReadNothing)
              else
                tiamat.Button(
                  text: MarkAllRead.markAllReadLabel,
                  isLoading: busy.contains(c),
                  onTap: () => _mark(c),
                ),
            ]),
          ),
      ],
    );
  }
}
