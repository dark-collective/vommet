// Vommet (New Home cards, round 4): the Tags card's and Tags section's
// settings. One dialog for both: All my tags or Pick tags (a checklist of
// your tags with their room counts), a section per tag or one list, and a
// name of its own. Opened from the card's settings, the side list editor,
// or when either is added from a library.
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter/material.dart';

/// What a Tags card or section shows.
class TagsChoice {
  const TagsChoice(
      {required this.all, this.tags = const [], this.list = false, this.name});

  /// All my tags; otherwise only [tags].
  final bool all;
  final List<String> tags;

  /// One list of rooms rather than a section per tag.
  final bool list;

  /// A name of its own; null shows the tag names.
  final String? name;

  bool get valid => all || tags.isNotEmpty;

  static TagsChoice ofCard(HomeCard card) => TagsChoice(
      all: card.type == HomeLayout.allTagsCard,
      tags: card.tags,
      list: card.tagList,
      name: card.name);

  static TagsChoice ofSection(HomeSection section) => TagsChoice(
      all: section.type == HomeSection.allTags,
      tags: section.tags,
      list: section.tagList,
      name: section.name);

  /// [card] showing this choice (its type says All my tags or Pick tags).
  HomeCard applyTo(HomeCard card) => card.copyWith(
      type: all ? HomeLayout.allTagsCard : HomeLayout.tagCard,
      tags: all ? const [] : tags,
      tagList: list,
      name: name ?? "");

  HomeSection applyToSection(HomeSection section) => section.copyWith(
      type: all ? HomeSection.allTags : HomeSection.tagSection,
      tags: all ? const [] : tags,
      tagList: list,
      name: name ?? "");
}

/// A side list section's name when it's a Tags section (or one tag of
/// it), else null.
String? tagSectionTitle(HomeSection section) {
  if (section.parent != null && section.tag != null) {
    return tagName(section.tag!);
  }
  if (section.type != HomeSection.tagSection &&
      section.type != HomeSection.allTags) {
    return null;
  }
  return tagsTitle(
      all: section.type == HomeSection.allTags,
      tags: section.tags,
      name: section.name);
}

/// Asks what a Tags card ([section] false) or side list section shows.
/// Returns the choice, or null when cancelled.
Future<TagsChoice?> showTagsDialog(BuildContext context, ClientManager manager,
    {required TagsChoice initial, bool editing = false, bool section = false}) {
  final rooms = manager.rooms.map(roomTagsOf).toList();
  return showDialog<TagsChoice>(
    context: context,
    builder: (context) => TagsDialog(
      initial: initial,
      tags: userTagsOf(rooms),
      counts: userTagCounts(rooms),
      editing: editing,
      section: section,
    ),
  );
}

class TagsDialog extends StatefulWidget {
  const TagsDialog(
      {super.key,
      required this.initial,
      required this.tags,
      required this.counts,
      this.editing = false,
      this.section = false});

  final TagsChoice initial;

  /// Your tags, sorted by name.
  final List<String> tags;
  final Map<String, int> counts;
  final bool editing;
  final bool section;

  @override
  State<TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<TagsDialog> {
  late bool all = widget.initial.all;
  late List<String> picked = List.of(widget.initial.tags);
  late bool list = widget.initial.list;
  late final TextEditingController name =
      TextEditingController(text: widget.initial.name ?? "");

  /// Your tags, then any picked tag no room has any more.
  List<String> get options => [
        ...widget.tags,
        for (final t in widget.initial.tags)
          if (!widget.tags.contains(t)) t
      ];

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void toggle(String tag) => setState(() {
        if (!picked.remove(tag)) {
          // Picked tags keep the order of the list.
          final order = options;
          picked = [
            for (final t in order)
              if (picked.contains(t) || t == tag) t
          ];
        }
      });

  TagsChoice get choice => TagsChoice(
      all: all,
      tags: all ? const [] : picked,
      list: list,
      name: name.text.trim().isEmpty ? null : name.text.trim());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final what = widget.section ? "section" : "card";
    TextStyle heading() => TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: scheme.onSurfaceVariant);
    final tags = options;
    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(spacing: 10, children: [
                const CardIcon(HomeLayout.tagCard, size: 28),
                Expanded(
                    child: Text(widget.section ? "Tags section" : "Tags card",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                key: const ValueKey("NewHomeTagsMode"),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text("All my tags")),
                  ButtonSegment(value: false, label: Text("Pick tags")),
                ],
                selected: {all},
                onSelectionChanged: (v) => setState(() => all = v.first),
              ),
              const SizedBox(height: 10),
              if (all)
                Text("Every tag you use, including tags you add later.",
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
              else if (tags.isEmpty)
                Text(
                    "You don't have any tags yet. Tag a room from its menu "
                    "(Tags).",
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final tag in tags)
                      CheckboxListTile(
                        key: ValueKey("NewHomeTagsPick-$tag"),
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        controlAffinity: ListTileControlAffinity.leading,
                        value: picked.contains(tag),
                        onChanged: (_) => toggle(tag),
                        title: Text(tagName(tag),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        secondary: Text(tagRoomCount(widget.counts[tag] ?? 0),
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ),
                  ]),
                ),
              const SizedBox(height: 14),
              Text("SHOW AS", style: heading()),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeTagsSections"),
                  label: const Text("A section per tag"),
                  selected: !list,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => list = false),
                ),
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeTagsList"),
                  label: const Text("One list"),
                  selected: list,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => list = true),
                ),
              ]),
              const SizedBox(height: 14),
              Text(widget.section ? "SECTION NAME" : "CARD NAME",
                  style: heading()),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey("NewHomeTagsName"),
                controller: name,
                maxLength: 64,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: "",
                  border: const OutlineInputBorder(),
                  hintText: tagsTitle(all: all, tags: all ? const [] : picked),
                  helperText: "Leave it empty to name the $what after its "
                      "tags.",
                ),
              ),
              const SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel")),
                    FilledButton(
                      key: const ValueKey("NewHomeTagsConfirm"),
                      onPressed: choice.valid
                          ? () => Navigator.of(context).pop(choice)
                          : null,
                      child: Text(widget.editing ? "Save" : "Add $what"),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }
}
