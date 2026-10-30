import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_page_preview.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

/// Vommet (Vommet issue 674): the Direct messages full-size card. Every
/// direct message of the filtered account, newest first, with its last
/// message, time and unread count (the chat list's rows), and a search.
class NewHomeDirectMessages extends StatefulWidget {
  const NewHomeDirectMessages({
    super.key,
    required this.clientManager,
    required this.filterClient,
    required this.phone,
    this.preview,
    this.onSeeAll,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final bool phone;

  /// As a card beside other cards (Vommet issue 782): only this many rows,
  /// no search, and "See all" calls [onSeeAll].
  final int? preview;
  final VoidCallback? onSeeAll;

  @override
  State<NewHomeDirectMessages> createState() => _NewHomeDirectMessagesState();
}

class _NewHomeDirectMessagesState extends State<NewHomeDirectMessages> {
  final List<StreamSubscription> subs = [];
  final TextEditingController search = TextEditingController();
  Timer? refresh;
  String query = "";

  @override
  void initState() {
    super.initState();
    final dms = widget.clientManager.directMessages;
    final rooms = dms.directMessageRooms;
    subs.addAll([
      rooms.onAdd.listen((_) => refreshSoon()),
      rooms.onRemove.listen((_) => refreshSoon()),
      rooms.onListUpdated.listen((_) => refreshSoon()),
      dms.onEventReceived.stream.listen((_) => refreshSoon()),
    ]);
  }

  @override
  void dispose() {
    for (final s in subs) {
      s.cancel();
    }
    refresh?.cancel();
    search.dispose();
    super.dispose();
  }

  void refreshSoon() {
    if (refresh?.isActive ?? false) return;
    refresh = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  /// The filtered account's direct messages that match the search, newest
  /// first.
  List<Room> get rooms {
    final filter = widget.filterClient;
    final q = query.trim().toLowerCase();
    return [
      for (final room in widget.clientManager.directMessages.directMessageRooms)
        if ((filter == null || room.client == filter) &&
            !hiddenFromNewHome(room) &&
            (q.isEmpty || room.displayName.toLowerCase().contains(q)))
          room
    ]..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = rooms;
    final preview = widget.preview;
    final shown = preview == null ? all : all.take(preview).toList();
    final now = DateTime.now();
    return ListView(
      shrinkWrap: preview != null,
      physics: preview != null ? const NeverScrollableScrollPhysics() : null,
      padding: preview != null
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: widget.phone ? 6 : 14, vertical: 10),
      children: [
        if (preview == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: SizedBox(
              height: 38,
              child: TextField(
                key: const ValueKey("NewHomeDmsSearch"),
                controller: search,
                onChanged: (text) => setState(() => query = text),
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerLowest,
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  hintText: "Find a DM by name",
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                query.trim().isEmpty
                    ? "No direct messages yet."
                    : "No direct messages match.",
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        for (final room in shown)
          ChatRowTile(
            chatEntryOf(room, direct: true),
            key: ValueKey("NewHomeDm-${room.localId}"),
            now: now,
            onTap: () => EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier),
          ),
        if (preview != null && all.length > shown.length)
          NewHomeSeeAll(total: all.length, onTap: widget.onSeeAll ?? () {}),
      ],
    );
  }
}
