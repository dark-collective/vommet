// Vommet: the panes of the Telegram-style unified chat list (Vommet issue
// 291): the list itself, an open space's rooms, and the folded avatar column
// shown beside an open space on desktop. Presentational: the main page wires
// them to the clients (unified_main_page.dart).
import 'package:commet/client/alert.dart';
import 'package:commet/ui/molecules/alert_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:flutter/material.dart';

typedef RowWrapper<T> = Widget Function(T item, Widget child);

/// Menu, search field and new-chat button above the list.
class ChatListTopBar extends StatelessWidget {
  const ChatListTopBar(
      {super.key, required this.search, this.onMenu, this.onCompose});
  final TextEditingController search;
  final VoidCallback? onMenu;
  final VoidCallback? onCompose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Row(children: [
        IconButton(
            tooltip: "Menu", onPressed: onMenu, icon: const Icon(Icons.menu)),
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: search,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: "Search",
                isDense: true,
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: search,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: search.clear),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        IconButton(
            tooltip: "New chat",
            onPressed: onCompose,
            icon: const Icon(Icons.edit_outlined)),
      ]),
    );
  }
}

/// An alert from the alert manager, dismissible for this session.
class AlertBanner extends StatelessWidget {
  const AlertBanner(this.alert, {super.key, this.onDismiss});
  final Alert alert;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          Expanded(child: AlertView(alert)),
          IconButton(
              tooltip: "Dismiss",
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18)),
        ]),
      ),
    );
  }
}

/// The one list: alerts, Invitations, then every chat and top-level space.
class ChatListPane extends StatelessWidget {
  const ChatListPane({
    super.key,
    required this.rows,
    required this.search,
    required this.now,
    this.selectedKey,
    this.alerts = const [],
    this.invitationCount = 0,
    this.invitationSubtitle,
    this.onMenu,
    this.onCompose,
    this.onInvitations,
    this.onDismissAlert,
    this.onRowTap,
    this.wrapRow,
    this.tabs,
    this.searchRows,
    this.archive,
    this.onArchive,
    this.emptyText = "No chats yet",
  });

  final List<TopRow> rows;

  /// Folder tabs, under the top bar (phone).
  final Widget? tabs;

  /// What search looks through (every chat, archived too); [rows] if null.
  final List<TopRow>? searchRows;

  /// The Archived chats row, shown under pins when anything is archived.
  final ArchiveSummary? archive;
  final VoidCallback? onArchive;
  final String emptyText;
  final TextEditingController search;
  final DateTime now;
  final String? selectedKey;
  final List<Alert> alerts;
  final int invitationCount;
  final String? invitationSubtitle;
  final VoidCallback? onMenu;
  final VoidCallback? onCompose;
  final VoidCallback? onInvitations;
  final void Function(Alert alert)? onDismissAlert;
  final void Function(TopRow row)? onRowTap;
  final RowWrapper<TopRow>? wrapRow;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ChatListTopBar(search: search, onMenu: onMenu, onCompose: onCompose),
      if (tabs != null) tabs!,
      for (final alert in alerts)
        AlertBanner(alert, onDismiss: () => onDismissAlert?.call(alert)),
      Expanded(
        child: ValueListenableBuilder(
          valueListenable: search,
          builder: (context, value, _) {
            final searching = value.text.trim().isNotEmpty;
            final shown = filterTopRows(
                searching ? searchRows ?? rows : rows, value.text);
            final invites = invitationCount > 0 && !searching;
            final offset = invites ? 1 : 0;
            final showArchive =
                !searching && archive != null && archive!.count > 0;
            // Under the invitations and the pinned chats.
            final archiveAt = !showArchive
                ? -1
                : offset + shown.takeWhile((row) => row.pinned).length;

            if (shown.isEmpty && !invites && !showArchive) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(searching ? "No chats found" : emptyText,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              );
            }

            // Lazy: only rows on screen are built, so sender names (a member
            // lookup each) are resolved only for those.
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: shown.length + offset + (showArchive ? 1 : 0),
              itemBuilder: (context, index) {
                if (invites && index == 0) {
                  return InvitationsRowTile(
                      count: invitationCount,
                      subtitle: invitationSubtitle,
                      onTap: onInvitations);
                }
                if (index == archiveAt) {
                  return ArchivedRowTile(archive!,
                      key: const ValueKey("unified-archived-row"),
                      onTap: onArchive);
                }
                final row = shown[index -
                    offset -
                    (showArchive && index > archiveAt ? 1 : 0)];
                final tile = _topRowTile(row);
                return KeyedSubtree(
                    key: ValueKey("unified-row-${row.key}"),
                    child: wrapRow?.call(row, tile) ?? tile);
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _topRowTile(TopRow row) => topRowTile(row,
      now: now, selectedKey: selectedKey, onTap: () => onRowTap?.call(row));
}

/// The tile for a top-level row: a chat or a space.
Widget topRowTile(TopRow row,
        {required DateTime now, String? selectedKey, VoidCallback? onTap}) =>
    switch (row) {
      ChatTopRow(:final chat) => ChatRowTile(chat,
          now: now,
          pinned: row.pinned,
          selected: chat.key == selectedKey,
          onTap: onTap),
      SpaceTopRow(:final space, :final digest) => SpaceRowTile(space, digest,
          now: now,
          pinned: row.pinned,
          selected: space.key == selectedKey,
          onTap: onTap),
    };

/// An open space (or subspace): its rooms, then rooms not joined yet, then
/// its subspaces.
class SpacePane extends StatelessWidget {
  const SpacePane({
    super.key,
    required this.space,
    required this.now,
    this.parentName,
    this.selectedKey,
    this.onBack,
    this.onMenu,
    this.onRoomTap,
    this.onJoinVoice,
    this.onPreviewTap,
    this.onSubspaceTap,
    this.wrapRoom,
  });

  final SpaceEntry space;
  final DateTime now;

  /// Shown as "Parent ›" above the title when this is a subspace.
  final String? parentName;
  final String? selectedKey;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;
  final void Function(ChatEntry room)? onRoomTap;
  final void Function(ChatEntry room)? onJoinVoice;
  final void Function(ChatPreviewEntry preview)? onPreviewTap;
  final void Function(SpaceEntry subspace)? onSubspaceTap;
  final RowWrapper<ChatEntry>? wrapRoom;

  @override
  Widget build(BuildContext context) {
    final rows = buildSpacePaneRows(space);
    return Column(children: [
      SpacePaneHeader(
          title: space.name,
          subtitle: spaceSubtitle(space),
          parentName: parentName,
          onBack: onBack,
          onMenu: onMenu),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Text("No rooms here yet",
                    style: Theme.of(context).textTheme.bodyMedium))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: rows.length,
                itemBuilder: (context, index) => switch (rows[index]) {
                  SpaceRoomRow(:final room) => KeyedSubtree(
                      key: ValueKey("unified-space-room-${room.key}"),
                      child: _wrap(
                          room,
                          SpaceRoomTile(room,
                              now: now,
                              selected: room.key == selectedKey,
                              onTap: () => onRoomTap?.call(room),
                              onJoinVoice: onJoinVoice == null
                                  ? null
                                  : () => onJoinVoice!(room))),
                    ),
                  SpacePreviewRow(:final preview) => SpacePreviewTile(preview,
                      onTap: () => onPreviewTap?.call(preview)),
                  SubspaceRow(space: final sub, :final digest) => SubspaceTile(
                      sub, digest,
                      now: now, onTap: () => onSubspaceTap?.call(sub)),
                },
              ),
      ),
    ]);
  }

  Widget _wrap(ChatEntry room, Widget child) =>
      wrapRoom?.call(room, child) ?? child;
}

/// "38 members · 8 rooms".
String spaceSubtitle(SpaceEntry space) {
  final rooms = space.allRooms.length + space.previews.length;
  return [
    if (space.memberCount != null)
      "${space.memberCount} ${space.memberCount == 1 ? "member" : "members"}",
    "$rooms ${rooms == 1 ? "room" : "rooms"}",
  ].join(" · ");
}

class SpacePaneHeader extends StatelessWidget {
  const SpacePaneHeader(
      {super.key,
      required this.title,
      this.subtitle,
      this.parentName,
      this.onBack,
      this.onMenu});
  final String title;
  final String? subtitle;
  final String? parentName;
  final VoidCallback? onBack;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(children: [
        IconButton(
            tooltip: "Back",
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back)),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (parentName != null)
                  Text("$parentName ›",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w600)),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.secondary)),
              ]),
        ),
        if (onMenu != null)
          IconButton(
              tooltip: "Space options",
              onPressed: onMenu,
              icon: const Icon(Icons.more_vert)),
      ]),
    );
  }
}

/// The list folded into a column of avatars, beside an open space.
class FoldedChatColumn extends StatelessWidget {
  const FoldedChatColumn(
      {super.key,
      required this.rows,
      this.selectedKey,
      this.onMenu,
      this.onRowTap});

  final List<TopRow> rows;
  final String? selectedKey;
  final VoidCallback? onMenu;
  final void Function(TopRow row)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: IconButton(
              tooltip: "Menu", onPressed: onMenu, icon: const Icon(Icons.menu)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return switch (row) {
                ChatTopRow(:final chat) => FoldedAvatar(
                    key: ValueKey("unified-fold-${row.key}"),
                    name: chat.name,
                    image: chat.avatar,
                    color: chat.color,
                    unread: chat.unread,
                    mentions: chat.mentions,
                    marked: chat.unreadMark,
                    muted: chat.muted,
                    selected: row.key == selectedKey,
                    onTap: () => onRowTap?.call(row)),
                SpaceTopRow(:final space, :final digest) => FoldedAvatar(
                    key: ValueKey("unified-fold-${row.key}"),
                    name: space.name,
                    image: space.avatar,
                    color: space.color,
                    square: true,
                    unread: digest.unread,
                    mentions: digest.mentions,
                    marked: digest.unreadMark,
                    muted: space.muted,
                    selected: row.key == selectedKey,
                    onTap: () => onRowTap?.call(row)),
              };
            },
          ),
        ),
      ]),
    );
  }
}
