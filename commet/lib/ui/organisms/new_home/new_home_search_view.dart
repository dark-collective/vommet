// Vommet (New Home): the side list's search results (new_home_search.dart):
// a chips row (DMs, Rooms, matched spaces and tags), the breadcrumb of a
// space scope, then the ranked groups: NAME, IN <space>, TAGGED, TOPIC
// and SPACES. Groups other than NAME show three rooms and "Show N more",
// which expands in place.
import 'package:commet/client/client.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the results do when tapped; the column keeps the state.
class NewHomeSearchActions {
  const NewHomeSearchActions({
    required this.scopeTo,
    required this.expand,
    required this.open,
    required this.menu,
    required this.accountHint,
  });

  /// Narrows (or widens, null: everything) the search.
  final void Function(SearchScope<Space>? scope) scopeTo;

  /// "Show N more" / "Show less" for a group.
  final void Function(Object key) expand;
  final void Function(Room room) open;

  /// "Go to <space>" and "Search in <space>" items.
  final List<tiamat.ContextMenuItem> Function(Room room) menu;

  /// Whether a row shows its account (another account's room).
  final bool Function(Room room) accountHint;
}

class NewHomeSearchView {
  /// How many rooms a group other than NAME shows before "Show N more".
  static const int groupRows = 3;

  /// A row after the results (another search, e.g. of messages, can add
  /// "Search messages for …"); null for none.
  static Widget? Function(BuildContext context, String query)? trailing;

  /// A space scope for [space].
  static SearchScope<Space> spaceScope(
          SearchIndex<Room, Space> index, Space space) =>
      SearchScope.space(
          space,
          index.spaceOf(space)?.path ?? [space],
          index.spaceOf(space) == null
              ? space.displayName
              : index.spaceLabel(index.spaceOf(space)!));

  static List<Widget> slivers(
    BuildContext context, {
    required SearchIndex<Room, Space> index,
    required SearchResults<Room, Space> results,
    required SearchScope<Space>? scope,
    required String query,
    required Set<Object> expanded,
    required Room? selected,
    required NewHomeSearchActions actions,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget header(String text, {Widget? action, IconData? icon}) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
          child: Row(spacing: 4, children: [
            if (icon != null) Icon(icon, size: 14, color: scheme.primary),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: scheme.onSurfaceVariant)),
            ),
            if (action != null) action,
          ]),
        );

    Widget row(SearchHit<Room> hit, String reason, {String? line}) {
      final room = hit.room;
      final snippet = hit.snippet;
      final path = line ?? pathLine(room, index);
      return Semantics(
        label: reason,
        child: Container(
          key: ValueKey("NewHomeSearchRoom-${room.localId}"),
          margin: const EdgeInsets.fromLTRB(3, 2, 3, 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: room == selected
                    ? scheme.primary.withAlpha(140)
                    : Colors.transparent),
          ),
          child: RoomPanel(room,
              nameHighlight:
                  hit.start < 0 ? null : (start: hit.start, end: hit.end),
              searchLine: snippet?.text ?? path,
              searchLineHighlight: snippet == null
                  ? null
                  : (start: snippet.start, end: snippet.end),
              shouldShowAvatarForRoom: actions.accountHint,
              leadingMenuItems: actions.menu(room),
              onTap: () => actions.open(room)),
        ),
      );
    }

    Widget more(Object key, int total) {
      final open = expanded.contains(key);
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: ValueKey("NewHomeSearchMore-$key"),
          onPressed: () => actions.expand(key),
          child: Text(open ? "Show less" : "Show ${total - groupRows} more"),
        ),
      );
    }

    List<Widget> group(Object key, List<SearchHit<Room>> hits, String reason,
            {String? line}) =>
        [
          for (final hit
              in hits.take(expanded.contains(key) ? hits.length : groupRows))
            row(hit, reason, line: line),
          if (hits.length > groupRows) more(key, hits.length),
        ];

    Widget spaceRow(SearchSpace<Space> space) => ListTile(
          key: ValueKey("NewHomeSearchSpace-${space.space.localId}"),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          leading: tiamat.Avatar(
              radius: 14,
              image: space.space.avatar,
              placeholderText: space.name,
              placeholderColor: space.space.color),
          title: Text("Open ${index.spaceLabel(space)}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: space.path.length > 1
              ? Text(
                  [
                    for (final s in space.path.take(space.path.length - 1))
                      s.displayName
                  ].join(" › "),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
              : null,
          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
          onTap: () => EventBus.openSpace
              .add((space.space.identifier, space.space.client.identifier)),
        );

    final scoped = scope?.space;
    final scopedSpace = scoped == null ? null : index.spaceOf(scoped);
    final children = <Widget>[
      if (scope?.space != null) ...[
        breadcrumb(context, index, scope!, actions),
        if (scopedSpace != null) spaceRow(scopedSpace),
      ],
      if (results.names.isNotEmpty) ...[
        if (query.trim().isNotEmpty) header("NAME"),
        for (final hit in results.names)
          row(hit, hit.start < 0 ? "Matched person" : "Matched name"),
      ],
      for (final g in results.inSpaces) ...[
        header("IN ${g.label}",
            icon: Icons.workspaces_outline,
            action: g.hits.length > groupRows
                ? TextButton(
                    key: ValueKey("NewHomeSearchScope-${g.key.localId}"),
                    onPressed: () => actions.scopeTo(spaceScope(index, g.key)),
                    child: Text("all ${g.hits.length} ›"))
                : null),
        ...group(g.key, g.hits, "In ${g.label}"),
      ],
      for (final g in results.tagged) ...[
        header("TAGGED ${g.label}",
            icon: Icons.label_outline_rounded,
            action: g.hits.length > groupRows
                ? TextButton(
                    key: ValueKey("NewHomeSearchScopeTag-${g.key}"),
                    onPressed: () =>
                        actions.scopeTo(SearchScope.tag(g.key, g.label)),
                    child: Text("all ${g.hits.length} ›"))
                : null),
        ...group(g.key, g.hits, "Tagged ${g.label}"),
      ],
      if (results.topics.isNotEmpty) ...[
        header("TOPIC"),
        ...group(SearchResults.topicsKey, results.topics, "Topic matches"),
      ],
      if (results.spaces.isNotEmpty && scope?.space == null) ...[
        header("SPACES"),
        for (final s in results.spaces) spaceRow(s),
      ],
      if (results.isEmpty && scopedSpace == null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: tiamat.Text.labelLow(query.trim().isEmpty
              ? "Nothing here."
              : "No conversations match \"${query.trim()}\"."),
        ),
      if (trailing?.call(context, query) case final extra?) extra,
    ];
    return [
      SliverToBoxAdapter(child: chips(context, index, results, scope, actions)),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
        sliver: SliverList.list(children: children),
      ),
    ];
  }

  /// A room's second line: its space path ("Nether › Software
  /// Development"); a DM's or standalone room's, nothing.
  static String? pathLine(Room room, SearchIndex<Room, Space> index) {
    final names = index.docOf(room)?.pathNames ?? const [];
    return names.isEmpty ? null : names.join(" › ");
  }

  /// "All results › Nether › Software Development": each part but the last
  /// widens the search to it.
  static Widget breadcrumb(BuildContext context, SearchIndex<Room, Space> index,
      SearchScope<Space> scope, NewHomeSearchActions actions) {
    final scheme = Theme.of(context).colorScheme;
    Widget crumb(String text, VoidCallback? onTap, {Key? key}) => InkWell(
          key: key,
          mouseCursor: onTap == null
              ? MouseCursor.defer
              : WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: onTap == null ? FontWeight.w700 : null,
                    color: onTap == null ? scheme.onSurface : scheme.primary)),
          ),
        );
    final sep = Text(" › ",
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant));
    final path = scope.path;
    return Padding(
      key: const ValueKey("NewHomeSearchBreadcrumb"),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        crumb("All results", () => actions.scopeTo(null),
            key: const ValueKey("NewHomeSearchAllResults")),
        for (var i = 0; i < path.length; i++) ...[
          sep,
          crumb(
              path[i].displayName,
              i == path.length - 1
                  ? null
                  : () => actions.scopeTo(spaceScope(index, path[i]))),
        ],
      ]),
    );
  }

  /// DMs n, Rooms n, then the matched spaces (subspaces, in a space scope)
  /// and tags with their counts; tap one to scope to it.
  static Widget chips(
      BuildContext context,
      SearchIndex<Room, Space> index,
      SearchResults<Room, Space> results,
      SearchScope<Space>? scope,
      NewHomeSearchActions actions) {
    final kinds = scope == null;
    final items = <Widget>[
      if (kinds && results.directMessages > 0)
        chip(context, "DMs ${results.directMessages}", Icons.person_outline,
            () => actions.scopeTo(const SearchScope.kind(true)),
            key: "dms"),
      if (kinds && results.rooms > 0)
        chip(context, "Rooms ${results.rooms}", Icons.tag_rounded,
            () => actions.scopeTo(const SearchScope.kind(false)),
            key: "rooms"),
      for (final (space, count) in results.spaceChips)
        chip(
            context,
            "${index.spaceLabel(space)} $count",
            Icons.workspaces_outline,
            () => actions.scopeTo(spaceScope(index, space.space)),
            key: "space-${space.space.localId}"),
      if (scope?.tag == null)
        for (final (tag, name, count) in results.tagChips)
          chip(context, "$name $count", Icons.label_outline_rounded,
              () => actions.scopeTo(SearchScope.tag(tag, name)),
              key: "tag-$tag"),
    ];
    if (items.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 40,
      child: ListView(
        key: const ValueKey("NewHomeSearchChips"),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
        children: [
          for (final item in items)
            Padding(padding: const EdgeInsets.only(right: 6), child: item),
        ],
      ),
    );
  }

  static Widget chip(
          BuildContext context, String label, IconData icon, VoidCallback onTap,
          {required String key}) =>
      ActionChip(
        key: ValueKey("NewHomeSearchChip-$key"),
        mouseCursor: WidgetStateMouseCursor.clickable,
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        onPressed: onTap,
      );
}
