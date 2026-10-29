import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/nicknames/name_history.dart';
import 'package:commet/client/matrix/nicknames/nickname_experiment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet moderator view (identity per place, R7): who someone is behind the
/// name they show in this room. Opened from the member menu by people who
/// can kick there.
class NameHistoryView extends StatefulWidget {
  const NameHistoryView({required this.room, required this.userId, super.key});

  final matrix.Room room;
  final String userId;

  /// The "Name history" item for a member's menu: only for people who can
  /// kick in [room], and not on yourself.
  static List<tiamat.ContextMenuItem> menuItems(BuildContext context,
      {required Room room, required String userId, required bool isSelf}) {
    if (isSelf ||
        room is! MatrixRoom ||
        !room.permissions.canKick ||
        !experimentNameSafety.value) {
      return const [];
    }
    final matrixRoom = room.matrixRoom;
    return [
      tiamat.ContextMenuItem(
          text: "Name history",
          icon: Icons.history,
          onPressed: () => AdaptiveDialog.show(context,
              title: "Name history",
              builder: (_) =>
                  NameHistoryView(room: matrixRoom, userId: userId))),
    ];
  }

  @override
  State<NameHistoryView> createState() => _NameHistoryViewState();
}

class _NameHistoryViewState extends State<NameHistoryView> {
  late final Future<NameHistory> history =
      NameHistory.load(widget.room, widget.userId);

  String _time(BuildContext context, DateTime time) {
    final l = MaterialLocalizations.of(context);
    return "${l.formatMediumDate(time)} ${l.formatTimeOfDay(TimeOfDay.fromDateTime(time))}";
  }

  Widget _row(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.labelLow(label),
            SelectableText(value ?? "(none)"),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 400,
      child: FutureBuilder<NameHistory>(
        future: history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return tiamat.Text.error("Couldn't load the name history");
          }
          final data = snapshot.data;
          if (data == null) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _row("Name in this room", data.roomName),
              _row("Global name", data.globalName),
              _row("Matrix ID", data.userId),
              const SizedBox(height: 8),
              tiamat.Text.labelEmphasised("Names used here, newest first"),
              if (data.changes.isEmpty)
                tiamat.Text.labelLow("No name changes found"),
              for (final change in data.changes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(change.name ?? "(no name)"),
                      ),
                      tiamat.Text.labelLow(_time(context, change.time)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
