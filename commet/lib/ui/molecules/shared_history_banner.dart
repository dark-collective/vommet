// Vommet: a strip above the timeline when this room's earlier messages were
// shared with us by the person who invited us (MSC4268). Closable per room.
// Vommet issue 744: also when someone shared them without an invite (a
// history grant), and a second strip while such history waits for us to
// verify whoever shared it.

import 'dart:async';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/shared_history_info.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SharedHistoryBanner extends StatefulWidget {
  const SharedHistoryBanner({required this.room, super.key});

  final Room room;

  static final StringPreference _closed =
      StringPreference("vommet_shared_history_banner_closed", defaultValue: "");

  static bool isClosed(String roomKey) =>
      _closed.value.split("\n").contains(roomKey);

  static Future<void> close(String roomKey) async {
    if (isClosed(roomKey)) return;
    final list = _closed.value.split("\n")..removeWhere((e) => e.isEmpty);
    await _closed.set([...list, roomKey].join("\n"));
  }

  static String message(String sharer, {int withheld = 0}) =>
      "Earlier messages were shared by $sharer when you joined. You have "
      "$sharer's word for who sent them."
      "${withheld > 0 ? " Some weren't shared: their senders' apps didn't "
          "allow it, so those can't be read here." : ""}";

  @override
  State<SharedHistoryBanner> createState() => _SharedHistoryBannerState();
}

class _SharedHistoryBannerState extends State<SharedHistoryBanner> {
  String? sharer;
  int withheld = 0;

  /// People whose shared history waits for us to verify them.
  List<String> held = const [];
  final List<StreamSubscription> _subs = [];

  String get roomKey => widget.room.localId;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    final sharing = ShareHistory.sharingOf(room);
    if (room is MatrixRoom && sharing != null) {
      final id = room.matrixRoom.id;
      _subs.add(sharing.onHistoryImported.stream
          .where((r) => r == id)
          .listen((_) => load()));
      _subs.add(sharing.onGrantHeld.stream
          .where((r) => r == id)
          .listen((_) => load()));
    }
    load();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> load() async {
    final history = SharedHistoryBanner.isClosed(roomKey)
        ? null
        : await SharedHistoryInfo.historyOf(widget.room);
    final room = widget.room;
    final waiting = room is MatrixRoom
        ? await ShareHistory.sharingOf(room)
                ?.heldGrantSenders(room.matrixRoom.id) ??
            const <String>[]
        : const <String>[];
    if (!mounted) return;
    setState(() {
      sharer = history?.sharer;
      withheld = history?.withheld ?? 0;
      held = waiting;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = sharer;
    final room = widget.room;
    final waiting = room is MatrixRoom ? held.firstOrNull : null;
    if (name == null && waiting == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (name != null)
        Container(
          key: const ValueKey("shared-history-banner"),
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.history, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
                child: tiamat.Text.labelLow(
                    SharedHistoryBanner.message(name, withheld: withheld))),
            IconButton(
              tooltip: "Close",
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: const Icon(Icons.close),
              onPressed: () async {
                await SharedHistoryBanner.close(roomKey);
                if (mounted) setState(() => sharer = null);
              },
            ),
          ]),
        ),
      if (room is MatrixRoom && waiting != null)
        _heldStrip(context, room, waiting),
    ]);
  }

  Widget _heldStrip(BuildContext context, MatrixRoom room, String userId) {
    final scheme = Theme.of(context).colorScheme;
    final amber = Colors.amber.shade600;
    final name = ShareHistory.nameOf(room.matrixRoom, userId);
    return Container(
      key: const ValueKey("shared-history-held"),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          border: Border.all(color: amber.withAlpha(170)),
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: amber),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.Text.body(ShareHistoryStrings.heldTitle(name)),
                tiamat.Text.labelLow(ShareHistoryStrings.heldVerify(name)),
              ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const ValueKey("shared-history-verify"),
          onPressed: () async {
            await ShareHistory.verify(context, room.matrixRoom.client, userId);
            await load();
          },
          child: Text(ShareHistoryStrings.verify),
        ),
      ]),
    );
  }
}
