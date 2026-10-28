// Vommet (New Home): a Rooms section's (or the Rooms card's) settings
// sheet: its name, which rooms it holds (standalone rooms, rooms in all,
// only some or all but some spaces, the spaces themselves, direct
// messages), a tag filter, the order, and whether rows name their space.
// A bottom sheet on phones, a dialog elsewhere.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the settings sheet saves.
class RoomsSettings {
  const RoomsSettings(this.filter, this.name);
  final RoomsFilter filter;

  /// A name of its own; null names it after what it holds.
  final String? name;
}

/// Asks for a Rooms section's ([card] false) or card's settings. Returns
/// them, or null when closed without Done. [dmsAbove]: a Direct messages
/// section above takes the DMs anyway.
Future<RoomsSettings?> showRoomsSettings(
  BuildContext context,
  ClientManager manager, {
  required RoomsFilter initial,
  String? name,
  bool card = false,
  bool dmsAbove = false,
}) {
  Widget form(BuildContext context) => RoomsSettingsForm(
      manager: manager,
      initial: initial,
      name: name,
      card: card,
      dmsAbove: dmsAbove);
  if (MediaQuery.of(context).mobile) {
    return showModalBottomSheet<RoomsSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SafeArea(child: form(context)),
      ),
    );
  }
  return showDialog<RoomsSettings>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
        child: form(context),
      ),
    ),
  );
}

class RoomsSettingsForm extends StatefulWidget {
  const RoomsSettingsForm({
    super.key,
    required this.manager,
    required this.initial,
    this.name,
    this.card = false,
    this.dmsAbove = false,
  });

  final ClientManager manager;
  final RoomsFilter initial;
  final String? name;
  final bool card;
  final bool dmsAbove;

  @override
  State<RoomsSettingsForm> createState() => _RoomsSettingsFormState();
}

class _RoomsSettingsFormState extends State<RoomsSettingsForm> {
  late RoomsFilter filter = widget.initial;
  late final TextEditingController name =
      TextEditingController(text: widget.name ?? "");

  /// The mode "Rooms in spaces" goes back to when ticked again.
  late String spacesMode = widget.initial.spaces ?? RoomsFilter.spacesAll;

  ClientManager get manager => widget.manager;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  String? get typedName => name.text.trim().isEmpty ? null : name.text.trim();

  String spaceName(SpaceRef ref) =>
      NewHomeSpaceIndex.of(manager, null).spaceOf(manager, ref)?.displayName ??
      "(space you left)";

  String spacesChip() {
    final list = filter.spaceList;
    String names() =>
        list.length == 1 ? spaceName(list.single) : "${list.length} spaces";
    return switch (filter.spaces ?? spacesMode) {
      RoomsFilter.spacesOnly => list.isEmpty ? "Only these spaces…" : names(),
      RoomsFilter.spacesExcept =>
        list.isEmpty ? "All except these…" : "All except ${names()}",
      _ => "All spaces",
    };
  }

  Future<void> pickMode() async {
    final box = context.findRenderObject() as RenderBox?;
    final mode = await showMenu<String>(
      context: context,
      position: box == null
          ? const RelativeRect.fromLTRB(0, 0, 0, 0)
          : RelativeRect.fromLTRB(
              box.size.width / 2, box.size.height / 3, box.size.width / 2, 0),
      items: const [
        PopupMenuItem(value: RoomsFilter.spacesAll, child: Text("All spaces")),
        PopupMenuItem(
            value: RoomsFilter.spacesOnly, child: Text("Only these spaces…")),
        PopupMenuItem(
            value: RoomsFilter.spacesExcept, child: Text("All except these…")),
      ],
    );
    if (mode == null || !mounted) return;
    if (mode == RoomsFilter.spacesAll) {
      setState(() {
        spacesMode = mode;
        filter = filter.copyWith(spaces: mode, spaceList: const []);
      });
      return;
    }
    final picked = await pickSpaces(context, manager,
        initial: filter.spaces == mode ? filter.spaceList : const [],
        title: mode == RoomsFilter.spacesOnly
            ? "Only these spaces"
            : "All spaces except");
    if (picked == null || !mounted) return;
    setState(() {
      spacesMode = mode;
      filter = filter.copyWith(spaces: mode, spaceList: picked);
    });
  }

  Future<void> pickTags() async {
    final picked = await pickRoomTags(context, manager, initial: filter.tags);
    if (picked == null || !mounted) return;
    setState(() => filter = filter.copyWith(tags: picked));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    TextStyle heading() => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: scheme.onSurfaceVariant);
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    Widget check(
            String key, String label, bool value, void Function(bool) onChanged,
            {String? subtitle, Widget? trailing}) =>
        CheckboxListTile(
          key: ValueKey("NewHomeRooms-$key"),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: (v) => setState(() => onChanged(v ?? false)),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle == null ? null : Text(subtitle, style: muted),
          secondary: trailing,
        );
    final inSpaces = filter.spaces != null;
    final nothing = !filter.standalone && !inSpaces && !filter.dms;
    final tagNames = [for (final t in filter.tags) tagName(t)].join(", ");

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(spacing: 10, children: [
            const CardIcon(HomeLayout.otherRooms, size: 28),
            Expanded(
                child: Text(widget.card ? "Rooms card" : "Rooms section",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: "Close",
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop()),
          ]),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              const SizedBox(height: 8),
              Text("NAME", style: heading()),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey("NewHomeRoomsName"),
                controller: name,
                maxLength: 64,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: "",
                  border: const OutlineInputBorder(),
                  hintText: roomsSectionLabel(filter, onlySpace: spaceName),
                ),
              ),
              const SizedBox(height: 14),
              Text("WHICH ROOMS", style: heading()),
              check("standalone", "Standalone rooms", filter.standalone,
                  (v) => filter = filter.copyWith(standalone: v),
                  subtitle: "Rooms that aren't part of a space"),
              check(
                "spaces",
                "Rooms in spaces",
                inSpaces,
                (v) => filter = v
                    ? filter.copyWith(spaces: spacesMode)
                    : filter.copyWith(clearSpaces: true, spaceRows: false),
                trailing: inSpaces
                    ? ActionChip(
                        key: const ValueKey("NewHomeRoomsSpacesMode"),
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: Text(spacesChip(),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded, size: 18),
                        ]),
                        onPressed: pickMode,
                      )
                    : null,
              ),
              if (inSpaces)
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: check(
                      "spaceRows",
                      "The spaces themselves",
                      filter.spaceRows,
                      (v) => filter = filter.copyWith(spaceRows: v),
                      subtitle: "A row per space; tap it to open the space"),
                ),
              check("dms", "Direct messages too", filter.dms,
                  (v) => filter = filter.copyWith(dms: v),
                  subtitle: widget.dmsAbove
                      ? "Off when a DMs section is above"
                      : null),
              if (nothing)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text("Pick at least one kind of room.",
                      style: TextStyle(fontSize: 12.5, color: scheme.error)),
                ),
              const SizedBox(height: 14),
              Text("ONLY ROOMS WITH THESE TAGS", style: heading()),
              ListTile(
                key: const ValueKey("NewHomeRoomsTags"),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(Icons.label_outline_rounded,
                    color: scheme.onSurfaceVariant),
                title: Text(filter.tags.isEmpty ? "Any tags" : tagNames,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: pickTags,
              ),
              const SizedBox(height: 10),
              Text("ORDER", style: heading()),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                key: const ValueKey("NewHomeRoomsOrder"),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: RoomsFilter.orderStandaloneFirst,
                      label: Text("Standalone first")),
                  ButtonSegment(
                      value: RoomsFilter.orderSpacesFirst,
                      label: Text("Spaces first")),
                  ButtonSegment(
                      value: RoomsFilter.orderNewest, label: Text("Newest")),
                ],
                selected: {filter.order},
                onSelectionChanged: (v) =>
                    setState(() => filter = filter.copyWith(order: v.first)),
              ),
              const SizedBox(height: 4),
              Text(
                  filter.order == RoomsFilter.orderNewest
                      ? "Every room newest first."
                      : "Spaces follow the space rail; rooms newest first.",
                  style: muted),
              const SizedBox(height: 6),
              SwitchListTile(
                key: const ValueKey("NewHomeRoomsSpaceNames"),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text("Show space names",
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text("After each room's name, muted", style: muted),
                value: filter.spaceNames,
                onChanged: (v) =>
                    setState(() => filter = filter.copyWith(spaceNames: v)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const ValueKey("NewHomeRoomsDone"),
              onPressed: nothing
                  ? null
                  : () => Navigator.of(context)
                      .pop(RoomsSettings(filter, typedName)),
              child: const Text("Done"),
            ),
          ),
        ],
      ),
    );
  }
}

/// A checklist of your spaces (subspaces too), [initial] ticked; a picked
/// space you've since left stays listed as "(space you left)" so you can
/// untick it. Returns the ticked ones, or null when cancelled.
Future<List<SpaceRef>?> pickSpaces(BuildContext context, ClientManager manager,
    {required List<SpaceRef> initial, String title = "Which spaces?"}) {
  final index = NewHomeSpaceIndex.of(manager, null);
  final spaces = [...manager.spaces]..sort((a, b) {
      final rail = (index.spaceRail[a.localId] ?? 1 << 30)
          .compareTo(index.spaceRail[b.localId] ?? 1 << 30);
      return rail != 0
          ? rail
          : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  final accounts = manager.clients.length;
  SpaceRef refOf(Space s) => SpaceRef(s.identifier, s.client.identifier);
  final gone = [
    for (final ref in initial)
      if (index.spaceOf(manager, ref) == null) ref
  ];
  return showDialog<List<SpaceRef>>(
    context: context,
    builder: (context) {
      final picked = [...initial];
      bool ticked(SpaceRef ref) => picked.any((p) =>
          p.space == ref.space && (p.client ?? ref.client) == ref.client);
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 400,
            child: spaces.isEmpty && gone.isEmpty
                ? const Text("You're not in any spaces yet.")
                : ListView(shrinkWrap: true, children: [
                    for (final space in spaces)
                      CheckboxListTile(
                        key: ValueKey("NewHomePickSpaces-${space.identifier}"),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: ticked(refOf(space)),
                        onChanged: (v) => setState(() {
                          final ref = refOf(space);
                          picked.removeWhere((p) =>
                              p.space == ref.space &&
                              (p.client ?? ref.client) == ref.client);
                          if (v == true) picked.add(ref);
                        }),
                        secondary: tiamat.Avatar(
                            radius: 14,
                            image: space.avatar,
                            placeholderText: space.displayName),
                        title: Text(space.displayName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: accounts > 1
                            ? Text(space.client.self?.identifier ?? "",
                                maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                      ),
                    for (final ref in gone)
                      CheckboxListTile(
                        key: ValueKey("NewHomePickSpaces-${ref.space}"),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: picked.contains(ref),
                        onChanged: (v) => setState(() {
                          picked.remove(ref);
                          if (v == true) picked.add(ref);
                        }),
                        title: const Text("(space you left)"),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel")),
            FilledButton(
                key: const ValueKey("NewHomePickSpacesDone"),
                onPressed: () => Navigator.of(context).pop(picked),
                child: const Text("Done")),
          ],
        ),
      );
    },
  );
}

/// A checklist of your tags with their room counts, [initial] ticked.
/// Returns the ticked ones (none: any tags), or null when cancelled.
Future<List<String>?> pickRoomTags(BuildContext context, ClientManager manager,
    {required List<String> initial}) {
  final roomTags = manager.rooms.map(roomTagsOf).toList();
  final counts = userTagCounts(roomTags);
  final tags = [
    ...userTagsOf(roomTags),
    for (final t in initial)
      if (!counts.containsKey(t)) t
  ];
  return showDialog<List<String>>(
    context: context,
    builder: (context) {
      final picked = [...initial];
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Only rooms with these tags"),
          content: SizedBox(
            width: 400,
            child: tags.isEmpty
                ? const Text("You don't have any tags yet. Tag a room from "
                    "its menu (Tags).")
                : ListView(shrinkWrap: true, children: [
                    for (final tag in tags)
                      CheckboxListTile(
                        key: ValueKey("NewHomeRoomsTag-$tag"),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: picked.contains(tag),
                        onChanged: (v) => setState(() {
                          picked.remove(tag);
                          if (v == true) {
                            // Picked tags keep the list's order.
                            final next = [...picked, tag];
                            picked
                              ..clear()
                              ..addAll(tags.where(next.contains));
                          }
                        }),
                        title: Text(tagName(tag),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        secondary: Text(tagRoomCount(counts[tag] ?? 0)),
                      ),
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel")),
            FilledButton(
                key: const ValueKey("NewHomeRoomsTagsDone"),
                onPressed: () => Navigator.of(context).pop(picked),
                child: const Text("Done")),
          ],
        ),
      );
    },
  );
}
