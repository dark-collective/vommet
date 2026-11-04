import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_picker_view.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:commet/config/layout_config.dart';

/// Vommet issue 793: the Favorites card's "Add favorites…" picker. People
/// (your direct messages), rooms and spaces in one list with tickboxes;
/// ticked ones are favorites (the Matrix m.favourite tag, as "Favorite" in a
/// room's menu). Built on the Share / Forward picker's layout.
class NewHomeFavouritesPicker extends StatefulWidget {
  const NewHomeFavouritesPicker(
      {super.key, required this.clientManager, required this.filterClient});

  final ClientManager clientManager;
  final Client? filterClient;

  /// Shows the picker; true once favorites were changed.
  static Future<bool> show(BuildContext context, ClientManager manager,
      {Client? filterClient}) async {
    final changed = await AdaptiveDialog.show<bool>(
      context,
      title: "Add favorites",
      scrollable: false,
      builder: (context) => NewHomeFavouritesPicker(
          clientManager: manager, filterClient: filterClient),
    );
    return changed == true;
  }

  /// Whether [space] is a favorite.
  static bool spaceIsFavourite(Space space) =>
      space is MatrixSpace && space.matrixRoom.isFavourite;

  /// The filtered accounts' favorite spaces.
  static List<Space> favouriteSpaces(ClientManager manager, Client? filter) => [
        for (final space in filter?.spaces ?? manager.spaces)
          if (spaceIsFavourite(space)) space
      ];

  @override
  State<NewHomeFavouritesPicker> createState() =>
      _NewHomeFavouritesPickerState();
}

/// What the picker lists.
enum FavouriteKind { person, room, space }

/// One thing that can be a favorite.
class FavouriteCandidate {
  FavouriteCandidate.room(Room this.room, {required bool direct})
      : space = null,
        kind = direct ? FavouriteKind.person : FavouriteKind.room;
  FavouriteCandidate.space(Space this.space)
      : room = null,
        kind = FavouriteKind.space;

  final Room? room;
  final Space? space;
  final FavouriteKind kind;

  String get id => room?.localId ?? space!.localId;
  String get name => room?.displayName ?? space!.displayName;
  bool get isFavourite =>
      room?.isFavorite ?? NewHomeFavouritesPicker.spaceIsFavourite(space!);

  Future<void> setFavourite(bool favourite) async {
    if (room != null) return room!.setAsFavorite(favourite);
    final s = space;
    if (s is MatrixSpace) await s.matrixRoom.setFavourite(favourite);
  }
}

class _NewHomeFavouritesPickerState extends State<NewHomeFavouritesPicker> {
  static const _all = "all";

  late final List<FavouriteCandidate> candidates;

  /// Ticked now, by id; starts as the current favorites.
  final Map<String, FavouriteCandidate> ticked = {};
  String filter = _all;
  String query = "";
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final manager = widget.clientManager;
    final filterClient = widget.filterClient;
    bool direct(Room room) =>
        room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(room) ==
        true;
    candidates = [
      for (final room in filterClient?.rooms ?? manager.rooms)
        if (!hiddenFromNewHome(room))
          FavouriteCandidate.room(room, direct: direct(room)),
      for (final space in filterClient?.spaces ?? manager.spaces)
        FavouriteCandidate.space(space),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final c in candidates) {
      if (c.isFavourite) ticked[c.id] = c;
    }
  }

  /// Ticks that differ from the favorites as they are.
  List<FavouriteCandidate> get changes => [
        for (final c in candidates)
          if (ticked.containsKey(c.id) != c.isFavourite) c
      ];

  void toggle(FavouriteCandidate c) => setState(() {
        if (ticked.remove(c.id) == null) ticked[c.id] = c;
      });

  Future<void> save() async {
    final todo = changes;
    if (todo.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => saving = true);
    try {
      await Future.wait(
          [for (final c in todo) c.setFavourite(ticked.containsKey(c.id))]);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text("Couldn't change your favorites. Try again.")));
    }
  }

  static String headerOf(FavouriteKind kind) => switch (kind) {
        FavouriteKind.person => "People",
        FavouriteKind.room => "Rooms",
        FavouriteKind.space => "Spaces",
      };

  @override
  Widget build(BuildContext context) {
    final redaction = RedactionScope.of(context);
    final q = query.trim().toLowerCase();
    final shown = [
      for (final c in candidates)
        if ((filter == _all || filter == c.kind.name) &&
            (q.isEmpty || c.name.toLowerCase().contains(q)))
          c
    ];
    ForwardPickerRow row(FavouriteCandidate c) => ForwardPickerRow(
          title: c.room != null
              ? redaction.roomDisplayName(c.room!)
              : redaction.roomName(c.space!.displayName, c.space!.identifier),
          subtitle: c.kind == FavouriteKind.space
              ? "Space · ${c.space!.roomsWithChildren.length} rooms"
              : null,
          avatar: c.room?.avatar ?? c.space?.avatar,
          color: c.room?.defaultColor ?? c.space?.color,
          selected: ticked.containsKey(c.id),
          onTap: () => toggle(c),
          onLongPress: () => toggle(c),
        );
    final pending = changes.length;
    return SizedBox(
      width: 500,
      height: MediaQuery.of(context).desktop
          ? 500
          : MediaQuery.of(context).size.height * 0.6,
      child: ForwardPickerView(
        key: const ValueKey("NewHomeFavouritesPicker"),
        searchHint: CommonStrings.promptSearch,
        autofocus: MediaQuery.of(context).desktop,
        onQueryChanged: (v) => setState(() => query = v),
        chips: [
          const ForwardPickerChip(
              id: _all, name: "All", icon: Icons.all_inclusive),
          for (final kind in FavouriteKind.values)
            ForwardPickerChip(
                id: kind.name,
                name: headerOf(kind),
                icon: switch (kind) {
                  FavouriteKind.person => Icons.person,
                  FavouriteKind.room => Icons.tag_rounded,
                  FavouriteKind.space => Icons.workspaces_outline,
                }),
        ],
        selectedChip: filter,
        onChipSelected: (id) => setState(() => filter = id),
        breadcrumb: const [],
        onBreadcrumbSelected: (_) {},
        rows: [
          for (final kind in FavouriteKind.values)
            if (shown.any((c) => c.kind == kind)) ...[
              if (filter == _all) ForwardPickerRow.header(headerOf(kind)),
              for (final c in shown)
                if (c.kind == kind) row(c),
            ],
        ],
        emptyText: q.isEmpty ? "Nothing to add yet." : "Nothing matches.",
        actionLabel: saving
            ? "Saving…"
            : pending == 0
                ? "Done"
                : "Save · $pending ${pending == 1 ? "change" : "changes"}",
        onAction: saving ? null : save,
      ),
    );
  }
}
