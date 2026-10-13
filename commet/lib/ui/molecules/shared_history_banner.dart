// Vommet: a strip above the timeline when this room's earlier messages were
// shared with us by the person who invited us (MSC4268). Closable per room.

import 'package:commet/client/matrix/shared_history_info.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/preferences/string_preference.dart';
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

  static String message(String sharer) =>
      "Earlier messages were shared by $sharer when you joined. You have "
      "$sharer's word for who sent them.";

  @override
  State<SharedHistoryBanner> createState() => _SharedHistoryBannerState();
}

class _SharedHistoryBannerState extends State<SharedHistoryBanner> {
  String? sharer;

  String get roomKey => widget.room.localId;

  @override
  void initState() {
    super.initState();
    if (!SharedHistoryBanner.isClosed(roomKey)) load();
  }

  Future<void> load() async {
    final name = await SharedHistoryInfo.sharerOf(widget.room);
    if (mounted && name != null) setState(() => sharer = name);
  }

  @override
  Widget build(BuildContext context) {
    final name = sharer;
    if (name == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
            child: tiamat.Text.labelLow(SharedHistoryBanner.message(name))),
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
    );
  }
}
