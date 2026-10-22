// Vommet: the Archive and folder widgets of the Telegram-style chat list
// (Vommet issue 291, phase 2): the Archived chats row and pane, the folder
// tabs on phones and the folder strip on desktop. Presentational only.
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_rows.dart';
import 'package:flutter/material.dart';

/// One tab: All chats (id null) or a folder.
class FolderTab {
  const FolderTab(
      {required this.id,
      required this.label,
      this.icon,
      this.emoji,
      this.unread = 0});
  final String? id;
  final String label;
  final IconData? icon;
  final String? emoji;
  final int unread;
}

/// The tabs for [folders], All chats first.
List<FolderTab> folderTabs(
        ChatFoldersDoc folders, int Function(String? id) unread) =>
    [
      FolderTab(
          id: null,
          label: "All chats",
          icon: Icons.chat_bubble_outline,
          unread: unread(null)),
      for (final f in folders.folders)
        FolderTab(
            id: f.id,
            label: f.name,
            icon: folderIcon(f),
            emoji: f.emoji,
            unread: unread(f.id)),
    ];

/// An icon that says what the folder holds, like Telegram Desktop's.
IconData folderIcon(ChatFolder folder) {
  if (folder.excludeRead) return Icons.mark_chat_unread_outlined;
  if (folder.types.length == 1) {
    return switch (folder.types.first) {
      FolderChatType.direct => Icons.person_outline,
      FolderChatType.room => Icons.tag,
      FolderChatType.space => Icons.workspaces_outline,
    };
  }
  return Icons.folder_outlined;
}

typedef TabWrapper = Widget Function(FolderTab tab, Widget child);

/// Phone: a scrolling row of tabs above the list, with unread badges.
class FolderTabBar extends StatelessWidget {
  const FolderTabBar(
      {super.key,
      required this.tabs,
      this.selected,
      this.onSelect,
      this.wrapTab});

  final List<FolderTab> tabs;
  final String? selected;
  final void Function(String? id)? onSelect;
  final TabWrapper? wrapTab;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final tab in tabs)
            KeyedSubtree(
              key: ValueKey("folder-tab-${tab.id ?? "all"}"),
              child: _wrap(
                  tab,
                  _TabButton(tab,
                      selected: tab.id == selected,
                      onTap: () => onSelect?.call(tab.id))),
            ),
        ],
      ),
    );
  }

  Widget _wrap(FolderTab tab, Widget child) =>
      wrapTab?.call(tab, child) ?? child;
}

class _TabButton extends StatelessWidget {
  const _TabButton(this.tab, {this.selected = false, this.onTap});
  final FolderTab tab;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (tab.emoji != null)
            Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(tab.emoji!, style: const TextStyle(fontSize: 14))),
          Text(tab.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
          if (tab.unread > 0)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: _SmallBadge(tab.unread, active: selected),
            ),
        ]),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.count, {this.active = true});
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: active ? scheme.primary : scheme.outline,
          borderRadius: BorderRadius.circular(9)),
      child: Text(count > 99 ? "99+" : "$count",
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? scheme.onPrimary : Colors.white)),
    );
  }
}

/// Desktop: Telegram Desktop's folder strip at the far left, an icon and
/// a name per folder, Edit at the bottom.
class FolderStrip extends StatelessWidget {
  const FolderStrip(
      {super.key,
      required this.tabs,
      this.selected,
      this.onSelect,
      this.onEdit,
      this.wrapTab});

  static const double width = 76;

  final List<FolderTab> tabs;
  final String? selected;
  final void Function(String? id)? onSelect;
  final VoidCallback? onEdit;
  final TabWrapper? wrapTab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final tab in tabs)
                KeyedSubtree(
                  key: ValueKey("folder-strip-${tab.id ?? "all"}"),
                  child: _wrap(
                      tab,
                      _StripItem(
                          icon: tab.icon ?? Icons.folder_outlined,
                          emoji: tab.emoji,
                          label: tab.label,
                          unread: tab.unread,
                          selected: tab.id == selected,
                          onTap: () => onSelect?.call(tab.id))),
                ),
            ],
          ),
        ),
        if (onEdit != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _StripItem(icon: Icons.tune, label: "Edit", onTap: onEdit),
          ),
      ]),
    );
  }

  Widget _wrap(FolderTab tab, Widget child) =>
      wrapTab?.call(tab, child) ?? child;
}

class _StripItem extends StatelessWidget {
  const _StripItem(
      {required this.icon,
      required this.label,
      this.emoji,
      this.unread = 0,
      this.selected = false,
      this.onTap});
  final IconData icon;
  final String? emoji;
  final String label;
  final int unread;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
              color: selected ? scheme.primaryContainer.withAlpha(90) : null,
              border: Border(
                  left: BorderSide(
                      color: selected ? scheme.primary : Colors.transparent,
                      width: 3))),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              height: 28,
              width: 44,
              child: Stack(clipBehavior: Clip.none, children: [
                Center(
                  child: emoji != null
                      ? Text(emoji!, style: const TextStyle(fontSize: 21))
                      : Icon(icon, size: 24, color: color),
                ),
                if (unread > 0)
                  Positioned(right: -4, top: -4, child: _SmallBadge(unread)),
              ]),
            ),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

/// The Archived chats row near the top of the list: archived chats' names
/// (unread ones bold) and how many unread chats that aren't muted it holds.
class ArchivedRowTile extends StatelessWidget {
  const ArchivedRowTile(this.summary, {super.key, this.onTap});
  final ArchiveSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body =
        theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle),
                child: Icon(Icons.archive_outlined,
                    color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("Archived chats",
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: scheme.onSurface)),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(children: [
                          for (var i = 0; i < summary.names.length; i++)
                            TextSpan(
                                text:
                                    (i == 0 ? "" : ", ") + summary.names[i].$1,
                                style: summary.names[i].$2
                                    ? TextStyle(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w600)
                                    : null),
                        ]),
                        style: body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
              ),
              if (summary.unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: UnreadBadge(summary.unread, muted: true),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The archive, opened from its row: the same rows as the list, with Back.
class ArchivePane extends StatelessWidget {
  const ArchivePane({
    super.key,
    required this.rows,
    required this.now,
    this.selectedKey,
    this.onBack,
    this.onRowTap,
    this.wrapRow,
  });

  final List<TopRow> rows;
  final DateTime now;
  final String? selectedKey;
  final VoidCallback? onBack;
  final void Function(TopRow row)? onRowTap;
  final RowWrapper<TopRow>? wrapRow;

  @override
  Widget build(BuildContext context) {
    final count = rows.length;
    return Column(children: [
      SpacePaneHeader(
          title: "Archived chats",
          subtitle: "$count ${count == 1 ? "chat" : "chats"}",
          onBack: onBack),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      "No archived chats. Archive a chat from its menu to tidy it away.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final tile = topRowTile(row,
                      now: now,
                      selectedKey: selectedKey,
                      onTap: () => onRowTap?.call(row));
                  return KeyedSubtree(
                      key: ValueKey("unified-archived-${row.key}"),
                      child: wrapRow?.call(row, tile) ?? tile);
                },
              ),
      ),
    ]);
  }
}
