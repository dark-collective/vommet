// Vommet (New Home): the Customize Home editor (Vommet issues 604 and 607).
// Desktop: a panel beside the live Home with the tabs (reorder, ⋯ Rename
// and icon / Duplicate / Remove, + New tab), a Side list | Main page switch
// (the part being edited gets a dashed outline, the other part dims) and a
// separate library for each part. Phones and narrow windows: the same
// editor full screen, with tab chips, handles and bottom sheets. Three
// first-time tips show the first time it opens; Show tips replays them.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_settings.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tab_icon.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/new_home_tags.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Whether the first-time tips were seen (or skipped).
final BoolPreference homeTipsSeen =
    BoolPreference("vommet_home_tips_seen", defaultValue: false);

/// Which part of the edited tab the editor works on.
enum HomeEditPart { side, main }

/// The part the editor works on; the other part of Home dims.
final ValueNotifier<HomeEditPart> newHomeEditPart =
    ValueNotifier(HomeEditPart.side);

/// Desktop: whether the editor panel shows its tips.
final ValueNotifier<bool> _desktopTips = ValueNotifier(false);

/// Opens Customize Home: the panel beside Home on desktop, the full-screen
/// editor on phones and narrow windows. [addCard] starts on the main page
/// with its library open ("Add a card").
void customizeHome(BuildContext context,
    {required bool phone,
    required ClientManager clientManager,
    bool addCard = false}) {
  if (addCard) newHomeEditPart.value = HomeEditPart.main;
  final firstTime = !homeTipsSeen.value;
  if (phone || MediaQuery.sizeOf(context).width < 900) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NewHomeEditorScreen(
            clientManager: clientManager,
            addCard: addCard,
            showTips: firstTime && !addCard)));
    return;
  }
  _desktopTips.value = firstTime && !addCard;
  newHomeCustomizing.value = true;
  if (addCard) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigator.currentContext;
      if (ctx != null) showAddCard(ctx, clientManager, phone: false);
    });
  }
}

/// A part's name, for the switch and the list's label.
String partLabel(HomeEditPart part) =>
    part == HomeEditPart.side ? "Side list" : "Views";

String _possessive(String name) => name.endsWith("s") ? "$name’" : "$name’s";

// ---------------------------------------------------------------------------
// Editing actions, shared by the desktop panel and the phone screen.

HomeLayoutStore get _store => HomeLayoutStore.instance;

void _selectTab(String id) => newHomeTab.value = id;

void _saveTab(HomeTab tab) =>
    _store.saveTabs(_store.tabs.value.replaceTab(tab));

/// Removes tab [tab] with an Undo (never the last one).
void removeHomeTab(BuildContext context, HomeTab tab) {
  final before = _store.tabs.value;
  if (!before.canRemove(tab.id)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final index = before.tabs.indexOf(tab);
  final next = before.removeTab(tab.id);
  _store.saveTabs(next);
  if (newHomeTab.value == tab.id && next.tabs.isNotEmpty) {
    _selectTab(next.tabs[(index - 1).clamp(0, next.tabs.length - 1)].id);
  }
  messenger?.showSnackBar(SnackBar(
    content: Text("Removed the ${tab.name} tab."),
    action: SnackBarAction(
        label: "Undo",
        onPressed: () {
          _store.saveTabs(before);
          _selectTab(tab.id);
        }),
  ));
}

void duplicateHomeTab(HomeTab tab) {
  final before = _store.tabs.value;
  final next = before.duplicateTab(tab.id);
  _store.saveTabs(next);
  final copy = next.tabs[next.tabs.indexWhere((t) => t.id == tab.id) + 1];
  _selectTab(copy.id);
}

/// "+ New tab": the New tab sheet, then the new tab is shown.
Future<void> newHomeTabFlow(BuildContext context, {required bool phone}) async {
  final result = await showTabForm(context, phone: phone);
  if (result == null) return;
  final (next, id) = _store.tabs.value.createTab(
      name: result.name,
      icon: result.icon,
      copyOf: result.copyOf,
      restore: result.restore,
      after: _store.current.id,
      rail: result.rail);
  await _store.saveTabs(next);
  _selectTab(id);
}

/// "Rename and icon…".
Future<void> renameHomeTab(BuildContext context, HomeTab tab,
    {required bool phone}) async {
  final result = await showTabForm(context, phone: phone, editing: tab);
  if (result == null) return;
  final latest = _store.tabs.value.tab(tab.id);
  if (latest == null) return;
  _saveTab(latest.copyWith(
      name: HomeTabs.cleanName(result.name), icon: result.icon));
  if (result.rail != tabInRail(latest)) {
    await setTabInRail(latest.id, result.rail);
  }
}

void moveHomeTab(HomeTab tab, int gap) =>
    _store.saveTabs(_store.tabs.value.moveTab(tab.id, gap));

void shiftHomeTab(HomeTab tab, int direction) =>
    _store.saveTabs(_store.tabs.value.shiftTab(tab.id, direction));

// ---------------------------------------------------------------------------
// The two libraries.

/// "+ Add a section": Rooms (its settings sheet), then its presets
/// Standalone rooms and A space's rooms (asks which spaces), then the
/// sections the side list can still take. Under "Your tags": Tags (asks
/// which), and a section for each of your tags.
Future<void> showAddSection(BuildContext context, ClientManager manager,
    {required bool phone}) async {
  final tab = _store.current;
  final counts = userTagCounts(manager.rooms.map(roomTagsOf));
  final picked = await _showLibrary<String>(
    context,
    phone: phone,
    title: "Add a section",
    subtitle: "To ${_possessive(tab.name)} side list",
    groups: [
      (
        null,
        [
          const _LibraryEntry(
              _roomsEntry,
              "Rooms",
              Icons.tag_rounded,
              "Standalone rooms, rooms in spaces, or both, in the order you "
                  "pick",
              isNew: true),
          for (final type in [
            HomeSection.standalone,
            HomeSection.spaceSection,
            for (final type in HomeSection.knownTypes)
              if (type != HomeSection.tagSection &&
                  type != HomeSection.allTags &&
                  type != HomeSection.standalone &&
                  type != HomeSection.spaceSection)
                type,
          ])
            _LibraryEntry(type, sectionLabel(type), sectionIcon(type),
                sectionDescription(type),
                added: !tab.canAddSection(type)),
        ]
      ),
      (
        "Your tags",
        [
          _LibraryEntry(
              HomeSection.tagSection,
              sectionLabel(HomeSection.tagSection),
              sectionIcon(HomeSection.tagSection),
              sectionDescription(HomeSection.tagSection)),
          for (final tag in userTagsOf(manager.rooms.map(roomTagsOf)))
            _LibraryEntry("$tagLibraryPrefix$tag", tagName(tag),
                Icons.label_outline_rounded, tagRoomCount(counts[tag] ?? 0),
                added: tab.side.any((s) =>
                    s.type == HomeSection.tagSection &&
                    s.tags.length == 1 &&
                    s.tag == tag)),
        ]
      ),
    ],
    footer: _tagsFooter,
  );
  if (picked == null || !context.mounted) return;
  final tag = picked.startsWith(tagLibraryPrefix)
      ? picked.substring(tagLibraryPrefix.length)
      : null;
  final type = tag == null
      ? (picked == _roomsEntry ? HomeSection.standalone : picked)
      : HomeSection.tagSection;
  final id = tab.newSectionId(type);
  var section = HomeSection(id,
      type: id == type ? null : type, tags: [if (tag != null) tag]);
  if (type == HomeSection.tagSection && tag == null) {
    final choice = await showTagsDialog(context, manager,
        initial: const TagsChoice(all: true), section: true);
    if (choice == null) return;
    section = choice.applyToSection(section);
  }
  if (picked == _roomsEntry) {
    final result = await showRoomsSettings(context, manager,
        initial: RoomsFilter.everything,
        dmsAbove: tab.side.any((s) => s.type == HomeSection.directMessages));
    if (result == null) return;
    section = section.copyWith(rooms: result.filter, name: result.name ?? "");
  }
  if (type == HomeSection.spaceSection) {
    // One space: the A space's rooms section older versions know; more: a
    // Rooms section of only those spaces.
    final spaces = await pickSpaces(context, manager,
        initial: const [], title: "Which spaces?");
    if (spaces == null || spaces.isEmpty) return;
    final roomsId = _store.current.newSectionId(HomeSection.standalone);
    section = spaces.length == 1
        ? section.copyWith(
            space: spaces.single.space, spaceClient: spaces.single.client)
        : HomeSection(roomsId,
            type: roomsId == HomeSection.standalone
                ? null
                : HomeSection.standalone,
            rooms: RoomsFilter(
                standalone: false,
                spaces: RoomsFilter.spacesOnly,
                spaceList: spaces));
  }
  final latest = _store.current;
  _saveTab(latest.addSection(section));
}

/// "+ Add a card": the cards, then the full-size cards. Added at the
/// bottom of the shown view.
Future<void> showAddCard(BuildContext context, ClientManager manager,
    {required bool phone}) async {
  final layout = _store.layout.value;
  _LibraryEntry entry(CardInfo info) =>
      _LibraryEntry(info.type, info.label, info.icon, info.short,
          color: info.color, added: !canAddFromLibrary(layout, info.type));
  final type = await _showLibrary<String>(
    context,
    phone: phone,
    title: "Add a card",
    subtitle: _store.current.views.length > 1
        ? "To the ${_store.currentView.name} view"
        : "To ${_possessive(_store.current.name)} main area",
    groups: [
      ("Cards", [for (final info in CardInfo.cards) entry(info)]),
      (
        "Full-size cards",
        [for (final type in HomeLayout.wholePageTypes) entry(CardInfo.of(type))]
      ),
      ("Your tags", [for (final info in tagCardInfos(manager)) entry(info)]),
    ],
    footer: _tagsFooter,
  );
  if (type == null || !context.mounted) return;
  await addCardFromLibrary(context, manager, type);
}

const String _tagsFooter = "Tag a room from its menu (Tags). Your tags are "
    "saved in Matrix, so other apps such as Nheko show them too.";

/// The library's "Your tags": the Tags card, then a one-tag Tags card per
/// tag.
List<CardInfo> tagCardInfos(ClientManager manager) {
  final counts = userTagCounts(manager.rooms.map(roomTagsOf));
  final tag = CardInfo.of(HomeLayout.tagCard);
  return [
    tag,
    for (final t in userTagsOf(manager.rooms.map(roomTagsOf)))
      CardInfo("$tagLibraryPrefix$t", tagName(t), Icons.label_outline_rounded,
          tag.color, tagRoomCount(counts[t] ?? 0),
          short: tagRoomCount(counts[t] ?? 0)),
  ];
}

/// The library's Rooms entry (a Rooms section set up in its sheet).
const String _roomsEntry = "rooms:new";

class _LibraryEntry {
  const _LibraryEntry(this.value, this.label, this.icon, this.description,
      {this.added = false, this.color, this.isNew = false});
  final String value;
  final String label;
  final IconData icon;
  final String description;
  final bool added;
  final Color? color;

  /// Marked NEW.
  final bool isNew;
}

/// A library: a dialog on desktop, a bottom sheet on phones. Returns the
/// picked entry's value.
Future<T?> _showLibrary<T>(BuildContext context,
    {required bool phone,
    required String title,
    required String subtitle,
    required List<(String?, List<_LibraryEntry>)> groups,
    String? footer}) {
  Widget list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        for (final (heading, entries) in groups) ...[
          if (heading != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(heading.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: scheme.onSurfaceVariant)),
            ),
          for (final e in entries)
            ListTile(
              key: ValueKey("NewHomeLibrary-${e.value}"),
              enabled: !e.added,
              leading: Icon(e.icon, color: e.color ?? scheme.onSurfaceVariant),
              title: Text(e.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(e.description),
              trailing: e.added
                  ? Text("added",
                      style: TextStyle(color: scheme.onSurfaceVariant))
                  : e.isNew
                      ? Text("NEW",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: scheme.primary))
                      : null,
              onTap: () => Navigator.of(context).pop(e.value),
            ),
        ],
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(footer,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget header(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );

  if (phone) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SafeArea(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header(context),
                Flexible(child: list(context)),
              ]),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header(context),
              Flexible(child: list(context)),
            ]),
      ),
    ),
  );
}

/// Picks one of your spaces (subspaces too) for "A space's rooms".
Future<Space?> pickSpace(BuildContext context, ClientManager manager) {
  final spaces = [...manager.spaces]..sort((a, b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  final accounts = manager.clients.length;
  return showDialog<Space>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text("Which space?"),
      children: [
        if (spaces.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text("You're not in any spaces yet."),
          ),
        for (final space in spaces)
          SimpleDialogOption(
            key: ValueKey("NewHomePickSpace-${space.identifier}"),
            onPressed: () => Navigator.of(context).pop(space),
            child: Row(spacing: 12, children: [
              tiamat.Avatar(
                radius: 14,
                image: space.avatar,
                placeholderText: space.displayName,
                placeholderColor: space.color,
              ),
              Expanded(
                child: Text(
                    accounts > 1
                        ? "${space.displayName} · ${space.client.self?.identifier ?? ""}"
                        : space.displayName,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
      ],
    ),
  );
}

/// A side list section's icon.
IconData sectionIcon(String type) => switch (type) {
      HomeSection.favourites => Icons.star_rounded,
      HomeSection.recent => Icons.history_rounded,
      HomeSection.directMessages => Icons.chat_bubble_rounded,
      HomeSection.voice => Icons.volume_up_rounded,
      HomeSection.liveVoice => Icons.graphic_eq_rounded,
      HomeSection.liveCalls => Icons.call_rounded,
      HomeSection.photos => Icons.photo_library_rounded,
      HomeSection.standalone => Icons.tag_rounded,
      HomeSection.spaceSection => Icons.workspaces_rounded,
      HomeSection.lowPriority => Icons.south_rounded,
      HomeSection.tagSection => Icons.label_rounded,
      HomeSection.allTags => Icons.label_rounded,
      _ => Icons.list_rounded,
    };

/// A side list section's line in the library.
String sectionDescription(String type) => switch (type) {
      HomeSection.favourites => "Rooms and people you marked as favourite",
      HomeSection.recent => "Rooms and DMs together, newest first",
      HomeSection.directMessages => "Your direct messages, newest first",
      HomeSection.voice => "Every voice room",
      HomeSection.liveVoice => "Voice rooms while a call is on",
      HomeSection.liveCalls => "Every room with a call going on",
      HomeSection.photos => "Your photo albums",
      HomeSection.standalone => "Rooms that aren't part of a space",
      HomeSection.spaceSection => "The rooms of one space you pick",
      HomeSection.lowPriority => "Rooms you marked low priority",
      HomeSection.tagSection => "All your tags, or the ones you pick",
      HomeSection.allTags => "All your tags, or the ones you pick",
      _ => "",
    };

// ---------------------------------------------------------------------------
// The New tab / Rename and icon form.

class TabFormResult {
  const TabFormResult(this.name, this.icon,
      {this.copyOf, this.restore, this.rail = false});
  final String name;
  final String icon;

  /// A button for the tab in the sidebar, under Home.
  final bool rail;
  final String? copyOf;
  final String? restore;
}

/// The New tab sheet (or, with [editing], Rename and icon): a dialog on
/// desktop, a bottom sheet on phones.
Future<TabFormResult?> showTabForm(BuildContext context,
    {required bool phone, HomeTab? editing}) {
  final form = HomeTabForm(
    editing: editing,
    current: _store.current,
    removedDefaults: [
      for (final id in _store.tabs.value.removedDefaults)
        HomeTabs.defaultTab(id)!
    ],
  );
  if (phone) {
    return showModalBottomSheet<TabFormResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(child: SingleChildScrollView(child: form)),
      ),
    );
  }
  return showDialog<TabFormResult>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(child: form),
      ),
    ),
  );
}

class HomeTabForm extends StatefulWidget {
  const HomeTabForm(
      {super.key,
      required this.current,
      required this.removedDefaults,
      this.editing});

  /// The tab shown now ("A copy of …").
  final HomeTab current;

  /// Default tabs that were removed ("A removed default tab").
  final List<HomeTab> removedDefaults;

  /// Rename and icon instead of New tab.
  final HomeTab? editing;

  @override
  State<HomeTabForm> createState() => _HomeTabFormState();
}

class _HomeTabFormState extends State<HomeTabForm> {
  late final TextEditingController name =
      TextEditingController(text: widget.editing?.name ?? "");
  late String icon = widget.editing?.icon ?? HomeTabs.icons[3];
  late bool rail = widget.editing != null && tabInRail(widget.editing!);
  bool uploading = false;

  /// "empty", "copy" or a removed default tab's id.
  String start = "empty";

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void pickStart(String value) {
    setState(() {
      start = value;
      final restored = HomeTabs.defaultTab(value);
      if (restored != null) {
        name.text = restored.name;
        icon = restored.icon;
        rail = tabInRail(restored);
      }
    });
  }

  void submit() {
    final text = name.text.trim();
    Navigator.of(context).pop(TabFormResult(
        text.isEmpty ? "New tab" : text, icon,
        copyOf: start == "copy" ? widget.current.id : null,
        restore: HomeTabs.defaultTab(start) != null ? start : null,
        rail: rail));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.editing != null;
    final label = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    Widget option(String value, String text) => RadioListTile<String>(
          key: ValueKey("NewHomeTabStart-$value"),
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: value,
          title: Text(text),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(editing ? "Rename and icon" : "New tab",
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Text("Name", style: label),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey("NewHomeTabName"),
            controller: name,
            autofocus: true,
            maxLength: HomeTabs.maxName,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => submit(),
            decoration: const InputDecoration(
                isDense: true,
                counterText: "",
                hintText: "Gaming, Work, Family…",
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          Text("Icon", style: label),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final name in [
              ...HomeTabs.icons,
              // One picked with More icons or uploaded stays in sight.
              if (!HomeTabs.icons.contains(icon)) icon,
            ])
              IconButton(
                key: ValueKey(HomeTabs.icons.contains(name)
                    ? "NewHomeTabIcon-$name"
                    : "NewHomeTabIcon-picked"),
                tooltip: HomeTabs.icons.contains(name) ? name : "Picked icon",
                isSelected: icon == name,
                style: IconButton.styleFrom(
                    backgroundColor: icon == name
                        ? scheme.primary.withAlpha(60)
                        : scheme.surfaceContainerHighest,
                    side: icon == name
                        ? BorderSide(color: scheme.primary, width: 1.5)
                        : null),
                icon: HomeTabIcon(name, size: 20),
                onPressed: () => setState(() => icon = name),
              ),
          ]),
          const SizedBox(height: 10),
          // Vommet issue 698: many more icons, emoji, or your own picture.
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey("NewHomeTabMoreIcons"),
              onPressed: uploading
                  ? null
                  : () async {
                      final picked =
                          await showHomeIconPicker(context, current: icon);
                      if (picked != null && mounted) {
                        setState(() => icon = picked);
                      }
                    },
              icon: const Icon(Icons.apps_rounded, size: 18),
              label: const Text("More icons"),
            ),
            OutlinedButton.icon(
              key: const ValueKey("NewHomeTabUploadIcon"),
              onPressed: uploading
                  ? null
                  : () async {
                      setState(() => uploading = true);
                      final uri = await uploadTabIconImage(context);
                      if (!mounted) return;
                      setState(() {
                        uploading = false;
                        if (uri != null) icon = uri;
                      });
                    },
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: const Text("Upload image"),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const ValueKey("NewHomeTabRail"),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: rail,
            onChanged: (on) => setState(() => rail = on),
            title: const Text("Show in sidebar"),
            subtitle: const Text("A button for this tab under Home"),
          ),
          if (!editing) ...[
            const SizedBox(height: 6),
            Text("Start with", style: label),
            RadioGroup<String>(
              groupValue: start,
              onChanged: (v) => pickStart(v ?? "empty"),
              child: Column(children: [
                option("empty", "An empty tab"),
                option("copy", "A copy of ${widget.current.name}"),
                for (final tab in widget.removedDefaults)
                  option(tab.id, "The default ${tab.name} tab (removed)"),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel")),
            FilledButton(
              key: const ValueKey("NewHomeTabSubmit"),
              onPressed: submit,
              child: Text(editing ? "Save" : "Create tab"),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// First-time tips.

/// The three tips, one at a time: Skip, Next, and "Start customizing" on
/// the last. [onDone] runs when skipped or finished.
class HomeTips extends StatefulWidget {
  const HomeTips({super.key, required this.onDone});
  final VoidCallback onDone;

  static const List<(String, String, IconData)> steps = [
    (
      "Home is made of tabs",
      "Overview, People and Rooms are where Home starts. Add your own, "
          "rename, reorder or remove them.",
      Icons.tab_rounded,
    ),
    (
      "Each tab has two parts",
      "The side list holds sections of rooms and people. The main area "
          "holds views: cards, or a full-size card like People.",
      Icons.vertical_split_rounded,
    ),
    (
      "You can’t break it",
      "Reset Home to default brings back the three starting tabs. Changes "
          "save to your account and reach all your devices.",
      Icons.restart_alt_rounded,
    ),
  ];

  @override
  State<HomeTips> createState() => _HomeTipsState();
}

class _HomeTipsState extends State<HomeTips> {
  int step = 0;

  void done() {
    homeTipsSeen.set(true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, text, icon) = HomeTips.steps[step];
    final last = step == HomeTips.steps.length - 1;
    return Padding(
      key: const ValueKey("NewHomeTips"),
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 88,
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 14),
            Text(title,
                key: ValueKey("NewHomeTip-$step"),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 14),
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  for (var i = 0; i < HomeTips.steps.length; i++)
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == step
                              ? scheme.primary
                              : scheme.outlineVariant),
                    ),
                ]),
            const SizedBox(height: 12),
            if (last)
              FilledButton(
                key: const ValueKey("NewHomeTipsStart"),
                onPressed: done,
                child: const Text("Start customizing"),
              )
            else
              Row(children: [
                TextButton(
                    key: const ValueKey("NewHomeTipsSkip"),
                    onPressed: done,
                    child: const Text("Skip")),
                const Spacer(),
                FilledButton(
                  key: const ValueKey("NewHomeTipsNext"),
                  onPressed: () => setState(() => step++),
                  child: const Text("Next"),
                ),
              ]),
          ]),
    );
  }
}

Future<void> _showTipsSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          SafeArea(child: HomeTips(onDone: () => Navigator.of(context).pop())),
    );

// ---------------------------------------------------------------------------
// The editor's parts.

/// The edited part's list: the side list's sections or the main page's
/// cards, with handles to reorder and a ⋯ menu each, then the add button.
class _PartList extends StatelessWidget {
  const _PartList(
      {required this.manager, required this.tab, required this.phone});

  final ClientManager manager;
  final HomeTab tab;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final part = newHomeEditPart.value;
    final side = part == HomeEditPart.side;
    final views = tab.views;
    final heading = (side
            ? "${_possessive(tab.name)} side list"
            : views.length > 1
                ? "Cards in ${_store.currentView.name}"
                : "${_possessive(tab.name)} cards")
        .toUpperCase();

    Widget row(
            {required Key key,
            required int index,
            required Widget leading,
            required String title,
            String? subtitle,
            required List<PopupMenuEntry<String>> menu,
            required void Function(String action) onMenu}) =>
        Material(
          key: key,
          color: phone ? scheme.surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
              ),
              PopupMenuButton<String>(
                tooltip: "Options",
                icon: Icon(Icons.more_horiz_rounded,
                    color: scheme.onSurfaceVariant),
                onSelected: onMenu,
                itemBuilder: (_) => menu,
              ),
            ]),
          ),
        );

    PopupMenuItem<String> item(String value, String label) =>
        PopupMenuItem(value: value, child: Text(label));

    final List<Widget> rows;
    if (side) {
      final sections = tab.sections;
      rows = [
        for (var i = 0; i < sections.length; i++)
          row(
            key: ValueKey("NewHomeEditSection-${sections[i].id}"),
            index: i,
            leading: Icon(sectionIcon(sections[i].type),
                size: 18, color: scheme.onSurfaceVariant),
            title: sections[i].type == HomeSection.spaceSection
                ? spaceOfSection(manager, sections[i])?.displayName ??
                    "A space's rooms"
                : sections[i].type == HomeSection.standalone
                    ? roomsSectionLabel(sections[i].rooms,
                        name: sections[i].name,
                        onlySpace: (ref) => NewHomeSpaceIndex.of(manager, null)
                            .spaceOf(manager, ref)
                            ?.displayName)
                    : tagSectionTitle(sections[i]) ??
                        sectionLabel(sections[i].type),
            subtitle: sections[i].collapsed
                ? "Collapsed"
                : _isTagsSection(sections[i])
                    ? tagsSummary(
                        all: sections[i].type == HomeSection.allTags,
                        tags: sections[i].tags,
                        list: sections[i].tagList)
                    : null,
            menu: [
              item("collapse",
                  sections[i].collapsed ? "Show expanded" : "Show collapsed"),
              if (sections[i].type == HomeSection.spaceSection)
                item("space", "Change space…"),
              if (_isTagsSection(sections[i])) item("tags", "Settings…"),
              if (sections[i].type == HomeSection.standalone)
                item("rooms", "Settings…"),
              item("remove", "Remove"),
            ],
            onMenu: (action) async {
              final section = sections[i];
              switch (action) {
                case "collapse":
                  _saveTab(_store.current.replaceSection(
                      section.copyWith(collapsed: !section.collapsed)));
                case "space":
                  final space = await pickSpace(context, manager);
                  if (space == null) return;
                  _saveTab(_store.current.replaceSection(section.copyWith(
                      space: space.identifier,
                      spaceClient: space.client.identifier)));
                case "tags":
                  final choice = await showTagsDialog(context, manager,
                      initial: TagsChoice.ofSection(section),
                      editing: true,
                      section: true);
                  if (choice == null) return;
                  _saveTab(_store.current
                      .replaceSection(choice.applyToSection(section)));
                case "rooms":
                  final result = await showRoomsSettings(context, manager,
                      initial: section.rooms,
                      name: section.name,
                      dmsAbove: sections
                          .take(i)
                          .any((s) => s.type == HomeSection.directMessages));
                  if (result == null) return;
                  _saveTab(_store.current.replaceSection(section.copyWith(
                      rooms: result.filter, name: result.name ?? "")));
                case "remove":
                  _saveTab(_store.current.removeSection(section.id));
              }
            },
          ),
      ];
    } else {
      final cards = _store.layout.value.visible;
      rows = [
        for (var i = 0; i < cards.length; i++)
          row(
            key: ValueKey("NewHomeEditCard-${cards[i].id}"),
            index: i,
            leading: CardIcon(cards[i].type, size: 26),
            title: cardTitle(manager, cards[i]),
            subtitle: cardSubtitle(cards[i]),
            menu: [
              if (cards[i].configurable) item("settings", "Settings…"),
              item("remove", "Remove"),
            ],
            onMenu: (action) {
              switch (action) {
                case "settings":
                  editCardSettings(context, manager, cards[i]);
                case "remove":
                  _store.save(_store.layout.value.remove(cards[i].id));
              }
            },
          ),
      ];
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!side) _ViewList(manager: manager, tab: tab, phone: phone),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(heading,
            key: const ValueKey("NewHomeEditHeading"),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant)),
      ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
              side
                  ? "No sections yet: this tab's side list is empty."
                  : "No cards yet: this view is empty.",
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (from, to) {
          if (side) {
            final sections = tab.sections;
            _saveTab(_store.current.moveSection(sections[from].id, to));
          } else {
            final cards = _store.layout.value.visible;
            _store.save(_store.layout.value.moveTo(cards[from].id, to));
          }
        },
        children: [
          for (final r in rows)
            Padding(
                key: r.key,
                padding: EdgeInsets.only(bottom: phone ? 6 : 0),
                child: r),
        ],
      ),
      if (side || phone)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey(side ? "NewHomeAddSection" : "NewHomeAddCard"),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(side ? "Add a section" : "Add a card",
                style: const TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () => side
                ? showAddSection(context, manager, phone: phone)
                : showAddCard(context, manager, phone: phone),
          ),
        )
      else
        // Desktop: the card library right here, tiles drag onto the page
        // (or click to add at the bottom); a card dragged back is removed.
        _InlineCardLibrary(manager: manager),
    ]);
  }
}

/// Customize with every tab removed.
class _NoTabsHint extends StatelessWidget {
  const _NoTabsHint();

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey("NewHomeEditNoTabs"),
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Text(
            "Home has no tabs. Add one with New tab, or bring back the "
            "default tabs with Reset Home to default.",
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// The tab's views, in order (the first opens): tap one to edit its cards
/// (Home shows it too), drag to reorder, ⋯ to rename or remove; then "Add
/// a view".
class _ViewList extends StatelessWidget {
  const _ViewList(
      {required this.manager, required this.tab, required this.phone});

  final ClientManager manager;
  final HomeTab tab;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final views = tab.views;
    final shown = _store.currentView.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
            "${_possessive(tab.name)} views".toUpperCase() +
                (views.length > 1 ? " · THE FIRST OPENS" : ""),
            key: const ValueKey("NewHomeEditViewsHeading"),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant)),
      ),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (from, to) =>
            _saveTab(_store.current.moveView(views[from].id, to)),
        children: [
          for (var i = 0; i < views.length; i++)
            Padding(
              key: ValueKey("NewHomeEditView-${views[i].id}"),
              padding: EdgeInsets.only(bottom: phone ? 6 : 2),
              child: _viewRow(context, scheme, views[i], i,
                  selected: views[i].id == shown, only: views.length == 1),
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey("NewHomeAddView"),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text("Add a view",
              style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => showAddView(context, phone: phone),
        ),
      ),
    ]);
  }

  Widget _viewRow(
      BuildContext context, ColorScheme scheme, HomeView view, int index,
      {required bool selected, required bool only}) {
    return Material(
      color: selected
          ? scheme.primary.withAlpha(40)
          : phone
              ? scheme.surfaceContainerLowest
              : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: () => _store.showView(tab.id, view.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(children: [
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(viewSummary(manager, view),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
            ),
            PopupMenuButton<String>(
              key: ValueKey("NewHomeEditViewMenu-${view.id}"),
              tooltip: "Options",
              icon: Icon(Icons.more_horiz_rounded,
                  color: scheme.onSurfaceVariant),
              onSelected: (action) async {
                switch (action) {
                  case "rename":
                    final name = await _askViewName(context, view.name);
                    if (name == null) return;
                    _saveTab(_store.current.renameView(view.id, name));
                  case "remove":
                    _saveTab(_store.current.removeView(view.id));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: "rename", child: Text("Rename…")),
                if (!only)
                  const PopupMenuItem(value: "remove", child: Text("Remove")),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// A view's line under its name: its full-size card, or how many cards.
String viewSummary(ClientManager manager, HomeView view) {
  final cards = view.main.visible;
  if (cards.length == 1 &&
      HomeLayout.wholePageTypes.contains(cards.first.type)) {
    final card = cards.first;
    final part = addViewChoices
        .where((c) => c.$3.type == card.type && c.$3.part == card.part)
        .firstOrNull;
    return "Full-size: ${part?.$2 ?? cardTitle(manager, card)}";
  }
  return switch (cards.length) {
    0 => "No cards yet",
    1 => "1 card",
    final n => "$n cards",
  };
}

/// The full-size cards "Add a view" offers: (value, view name, card).
/// People's parts each make their own view.
final List<(String, String, HomeCard)> addViewChoices = [
  ("dms", "Direct messages", const HomeCard(HomeLayout.dmsPage)),
  (
    "contacts",
    "Contacts",
    const HomeCard(HomeLayout.peoplePage, part: "contacts")
  ),
  (
    "invites",
    "Invites",
    const HomeCard(HomeLayout.peoplePage, part: "invites")
  ),
  (
    "blocked",
    "Blocked",
    const HomeCard(HomeLayout.peoplePage, part: "blocked")
  ),
  ("people", "People", const HomeCard(HomeLayout.peoplePage)),
  ("rooms", "Rooms", const HomeCard(HomeLayout.roomsPage)),
];

/// Whether [tab] already has a view of just [card].
bool tabHasViewOf(HomeTab tab, HomeCard card) => tab.views.any((v) {
      final cards = v.main.visible;
      return cards.length == 1 &&
          cards.first.type == card.type &&
          cards.first.part == card.part;
    });

/// The tab with a new view: a full-size card's ([choice], a value of
/// [addViewChoices]) or, for "cards", an empty one to add cards to.
/// Returns the tab and the new view's id.
(HomeTab, String) addViewTo(HomeTab tab, String choice) {
  final picked = addViewChoices.where((c) => c.$1 == choice).firstOrNull;
  final id = tab.newViewId(picked?.$1 ?? "cards");
  final view = HomeView(id,
      name: picked?.$2 ?? "Cards",
      main: HomeLayout([if (picked != null) picked.$3], inTab: true));
  return (tab.addView(view), id);
}

/// "+ Add a view": a full-size card, or a view of cards. The new view is
/// shown (a view of cards with the library open).
Future<void> showAddView(BuildContext context, {required bool phone}) async {
  final tab = _store.current;
  final picked = await _showLibrary<String>(
    context,
    phone: phone,
    title: "Add a view",
    subtitle: "To ${tab.name}",
    groups: [
      (
        "Full-size cards",
        [
          for (final (value, name, card) in addViewChoices)
            _LibraryEntry(
                "view-$value",
                name,
                CardInfo.of(card.type).icon,
                card.type == HomeLayout.peoplePage &&
                        card.part != HomeCard.allParts
                    ? "Part of the People page, full width"
                    : CardInfo.of(card.type).short,
                color: CardInfo.of(card.type).color,
                added: tabHasViewOf(tab, card)),
        ]
      ),
      (
        "Cards",
        [
          const _LibraryEntry(
              "view-cards",
              "A view of cards",
              Icons.dashboard_customize_rounded,
              "Recent, Unread, Mentions, Active Now and more, stacked"),
        ]
      ),
    ],
  );
  if (picked == null || !context.mounted) return;
  final latest = _store.current;
  final (next, id) = addViewTo(latest, picked.substring("view-".length));
  _saveTab(next);
  _store.showView(latest.id, id);
}

/// Asks for a view's new name.
Future<String?> _askViewName(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Rename view"),
      content: TextField(
        key: const ValueKey("NewHomeViewName"),
        controller: controller,
        autofocus: true,
        maxLength: HomeTabs.maxName,
        decoration: const InputDecoration(labelText: "Name"),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
        FilledButton(
            key: const ValueKey("NewHomeViewNameSave"),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text("Save")),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _InlineCardLibrary extends StatelessWidget {
  const _InlineCardLibrary({required this.manager});
  final ClientManager manager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = _store.layout.value;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Text(text.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.onSurfaceVariant)),
        );
    Widget grid(Iterable<CardInfo> infos) => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.92,
          children: [
            for (final info in infos)
              LibraryTile(
                info: info,
                added: !canAddFromLibrary(layout, info.type),
                onAdd: () => addCardFromLibrary(context, manager, info.type),
              ),
          ],
        );
    return Column(
        key: const ValueKey("NewHomeAddCard"),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading("Add a card"),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
                "Drag a card onto the page, or click it to add it at the "
                "bottom. Drag a card back here to remove it.",
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
          grid(CardInfo.cards),
          heading("Full-size cards"),
          grid([
            for (final type in HomeLayout.wholePageTypes) CardInfo.of(type)
          ]),
          heading("Your tags"),
          grid(tagCardInfos(manager)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(_tagsFooter,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ),
        ]);
  }
}

/// The Side list | Main page switch.
/// The Side list | Main page switch. It follows [newHomeEditPart] itself:
/// it's built const, so the editor rebuilding doesn't rebuild it, and a
/// stale selection would leave the other part unreachable.
class HomePartSwitch extends StatelessWidget {
  const HomePartSwitch({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: newHomeEditPart,
        builder: (context, selected, _) => SegmentedButton<HomeEditPart>(
          key: const ValueKey("NewHomeEditPart"),
          showSelectedIcon: false,
          segments: [
            for (final part in HomeEditPart.values)
              ButtonSegment(value: part, label: Text(partLabel(part))),
          ],
          selected: {selected},
          onSelectionChanged: (s) => newHomeEditPart.value = s.first,
        ),
      );
}

/// The ⋯ menu of a tab: Rename and icon, (Move left/right on phones),
/// Duplicate, Remove.
Future<void> _tabAction(BuildContext context, HomeTab tab, String action,
    {required bool phone}) async {
  switch (action) {
    case "rename":
      await renameHomeTab(context, tab, phone: phone);
    case "left":
      shiftHomeTab(tab, -1);
    case "right":
      shiftHomeTab(tab, 1);
    case "rail":
      await setTabInRail(tab.id, !tabInRail(tab));
    case "duplicate":
      duplicateHomeTab(tab);
    case "remove":
      removeHomeTab(context, tab);
  }
}

List<(String, String, IconData)> _tabActions(HomeTab tab,
    {required bool phone}) {
  final tabs = _store.tabs.value.tabs;
  final i = tabs.indexWhere((t) => t.id == tab.id);
  return [
    ("rename", "Rename and icon…", Icons.edit_rounded),
    tabInRail(tab)
        ? ("rail", "Hide from sidebar", Icons.push_pin_rounded)
        : ("rail", "Show in sidebar", Icons.push_pin_outlined),
    if (phone && i > 0) ("left", "Move left", Icons.arrow_back_rounded),
    if (phone && i < tabs.length - 1)
      ("right", "Move right", Icons.arrow_forward_rounded),
    ("duplicate", "Duplicate", Icons.copy_rounded),
    ("remove", "Remove", Icons.delete_outline_rounded),
  ];
}

/// Rebuilds on any change the editor shows.
Widget _following(Widget Function(BuildContext context) builder) =>
    ListenableBuilder(
      listenable: Listenable.merge(
          [_store.tabs, newHomeTab, newHomeEditPart, newHomeViews]),
      builder: (context, _) => builder(context),
    );

/// The footer: Reset Home to default, Show tips.
Widget _footer(BuildContext context, {required VoidCallback onTips}) {
  final scheme = Theme.of(context).colorScheme;
  return Row(children: [
    TextButton(
      key: const ValueKey("NewHomeResetHome"),
      style: TextButton.styleFrom(foregroundColor: scheme.error),
      onPressed: () => resetHome(context),
      child: const Text("Reset Home to default"),
    ),
    const Spacer(),
    TextButton(
      key: const ValueKey("NewHomeShowTips"),
      onPressed: onTips,
      child: const Text("Show tips"),
    ),
  ]);
}

/// "Save Home layout to": which account keeps Home's tabs on this device
/// (Vommet issue 647). Only with two or more accounts. One account only, as
/// the layout names the other accounts' spaces.
class HomeLayoutAccountPicker extends StatelessWidget {
  const HomeLayoutAccountPicker({super.key, required this.manager});

  final ClientManager manager;

  @override
  Widget build(BuildContext context) {
    final accounts = manager.clients.whereType<MatrixClient>().toList();
    if (accounts.length < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: _store.account,
      builder: (context, picked, _) => _list(scheme, accounts, picked),
    );
  }

  Widget _list(
      ColorScheme scheme, List<MatrixClient> accounts, MatrixClient? picked) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
          child: Text("SAVE HOME LAYOUT TO",
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: scheme.onSurfaceVariant)),
        ),
        for (final client in accounts)
          ListTile(
            key: ValueKey("NewHomeLayoutAccount-${client.identifier}"),
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            selected: identical(client, picked),
            selectedTileColor: scheme.primary.withAlpha(25),
            leading: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              Icon(
                  identical(client, picked)
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20),
              tiamat.Avatar(
                radius: 13,
                image: client.self?.avatar,
                placeholderText: client.self?.displayName ??
                    client.matrixClient.userID ??
                    "?",
                placeholderColor: client.self?.defaultColor,
              ),
            ]),
            title: Text(client.matrixClient.userID ?? client.identifier,
                overflow: TextOverflow.ellipsis),
            onTap: () => _store.useAccount(client),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text(
              "Devices that pick the same account share Home. It's saved "
              "only there, as it lists your other accounts' spaces.",
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Undo: one change at a time, back to how Home was when Customize opened.

/// What Undo would undo, for its tooltip.
String undoDescription(
        ({HomeTabs before, HomeTabs after, String? label}) change) =>
    change.label ??
    describeHomeChange(change.before, change.after,
        section: (s) => tagSectionTitle(s) ?? sectionLabel(s.type),
        card: (c) => CardInfo.of(c.type).label);

bool _isTagsSection(HomeSection s) =>
    s.type == HomeSection.tagSection || s.type == HomeSection.allTags;

/// Keeps Undo's history while Customize Home is on screen.
class HomeEditingScope extends StatefulWidget {
  const HomeEditingScope({super.key, required this.child});
  final Widget child;

  @override
  State<HomeEditingScope> createState() => _HomeEditingScopeState();
}

class _HomeEditingScopeState extends State<HomeEditingScope> {
  @override
  void initState() {
    super.initState();
    _store.beginEditing();
  }

  @override
  void dispose() {
    _store.endEditing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Customize Home's Undo button (an icon on phones), gray when there's
/// nothing to undo. Ctrl+Z (Cmd+Z) does the same while it's shown, except
/// in a text field.
class HomeUndoButton extends StatefulWidget {
  const HomeUndoButton({super.key, required this.phone});
  final bool phone;

  @override
  State<HomeUndoButton> createState() => _HomeUndoButtonState();
}

class _HomeUndoButtonState extends State<HomeUndoButton> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyZ) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (!(keys.isControlPressed || keys.isMetaPressed) ||
        keys.isShiftPressed ||
        keys.isAltPressed) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    if (_store.undoHistory.value.isEmpty) return false;
    _store.undo();
    return true;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _store.undoHistory,
        builder: (context, history, _) {
          final tooltip = history.isEmpty
              ? "Nothing to undo"
              : "Undo: ${undoDescription(history.last)}";
          final onPressed = history.isEmpty ? null : _store.undo;
          if (widget.phone) {
            return IconButton(
              key: const ValueKey("NewHomeUndo"),
              tooltip: tooltip,
              icon: const Icon(Icons.undo_rounded),
              onPressed: onPressed,
            );
          }
          return Tooltip(
            message: tooltip,
            child: TextButton.icon(
              key: const ValueKey("NewHomeUndo"),
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text("Undo",
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: onPressed,
            ),
          );
        },
      );
}

// ---------------------------------------------------------------------------
// Desktop: the panel beside the live Home.

class NewHomeEditorPanel extends StatelessWidget {
  const NewHomeEditorPanel({super.key, required this.clientManager});

  final ClientManager clientManager;

  static const double width = 360;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A card dragged off the page onto the panel is removed, as onto the
    // old Card library.
    return HomeEditingScope(child: _panel(context, scheme));
  }

  Widget _panel(BuildContext context, ColorScheme scheme) {
    return DragTarget<CardDrag>(
      onWillAcceptWithDetails: (d) => d.data is OverviewCardDrag,
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is OverviewCardDrag) {
          _store.save(_store.layout.value.remove(data.id));
        }
      },
      builder: (context, candidates, _) => Container(
        key: const ValueKey("NewHomeEditorPanel"),
        width: width,
        decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? Color.alphaBlend(
                    scheme.error.withAlpha(25), scheme.surfaceContainerLow)
                : scheme.surfaceContainerLow,
            border: Border(
                left: BorderSide(color: scheme.surfaceContainerHighest))),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 52,
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              decoration: BoxDecoration(
                  border: Border(
                      bottom:
                          BorderSide(color: scheme.surfaceContainerHighest))),
              child: Row(children: [
                const Expanded(
                  child: Text("Customize Home",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                const HomeUndoButton(phone: false),
                const SizedBox(width: 6),
                FilledButton(
                  key: const ValueKey("NewHomeCustomizeDone"),
                  onPressed: () => newHomeCustomizing.value = false,
                  child: const Text("Done"),
                ),
              ]),
            ),
            Expanded(
              child: _following((context) {
                final tab = _store.current;
                final tabs = _store.tabs.value.tabs;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                  children: [
                    if (candidates.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text("Drop here to remove the card.",
                            style: TextStyle(color: scheme.error)),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                      child: Text("TABS",
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: scheme.onSurfaceVariant)),
                    ),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (from, to) => moveHomeTab(tabs[from], to),
                      children: [
                        for (var i = 0; i < tabs.length; i++)
                          _TabRow(
                              key: ValueKey("NewHomeEditTab-${tabs[i].id}"),
                              tab: tabs[i],
                              index: i,
                              selected: tabs[i].id == tab.id),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey("NewHomeNewTab"),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text("New tab",
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        onPressed: () => newHomeTabFlow(context, phone: false),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_store.isEmpty)
                      const _NoTabsHint()
                    else ...[
                      const HomePartSwitch(),
                      _PartList(manager: clientManager, tab: tab, phone: false),
                    ],
                    HomeLayoutAccountPicker(manager: clientManager),
                  ],
                );
              }),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: scheme.surfaceContainerHighest))),
              child: _footer(context, onTips: () => _desktopTips.value = true),
            ),
          ]),
          // The tips: a small card over the panel.
          ValueListenableBuilder(
            valueListenable: _desktopTips,
            builder: (context, show, _) => !show
                ? const SizedBox.shrink()
                : Positioned(
                    left: 12,
                    right: 12,
                    top: 64,
                    child: Material(
                      elevation: 8,
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(14),
                      child: HomeTips(onDone: () => _desktopTips.value = false),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// A tab in the desktop panel's list: handle, icon, name, ⋯.
class _TabRow extends StatelessWidget {
  const _TabRow(
      {super.key,
      required this.tab,
      required this.index,
      required this.selected});

  final HomeTab tab;
  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(8),
        onTap: () => _selectTab(tab.id),
        child: Row(children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          HomeTabIcon(tab.icon,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tab.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ),
          IconButton(
            key: ValueKey("NewHomeTabRailToggle-${tab.id}"),
            tooltip: tabInRail(tab) ? "Hide from sidebar" : "Show in sidebar",
            visualDensity: VisualDensity.compact,
            isSelected: tabInRail(tab),
            icon: Icon(Icons.push_pin_outlined,
                size: 18, color: scheme.onSurfaceVariant),
            selectedIcon:
                Icon(Icons.push_pin_rounded, size: 18, color: scheme.primary),
            onPressed: () => setTabInRail(tab.id, !tabInRail(tab)),
          ),
          PopupMenuButton<String>(
            key: ValueKey("NewHomeTabMenu-${tab.id}"),
            tooltip: "Tab options",
            icon:
                Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant),
            onSelected: (action) =>
                _tabAction(context, tab, action, phone: false),
            itemBuilder: (_) => [
              for (final (value, label, icon) in _tabActions(tab, phone: false))
                PopupMenuItem(
                  value: value,
                  child: Row(spacing: 12, children: [
                    Icon(icon, size: 18),
                    Text(label),
                  ]),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phones: the same editor, full screen.

class NewHomeEditorScreen extends StatefulWidget {
  const NewHomeEditorScreen(
      {super.key,
      required this.clientManager,
      this.addCard = false,
      this.showTips = false});

  final ClientManager clientManager;

  /// Opens the main page's library right away ("Add a card").
  final bool addCard;

  /// Shows the first-time tips.
  final bool showTips;

  @override
  State<NewHomeEditorScreen> createState() => _NewHomeEditorScreenState();
}

class _NewHomeEditorScreenState extends State<NewHomeEditorScreen> {
  @override
  void initState() {
    super.initState();
    _store.beginEditing();
    if (widget.addCard || widget.showTips) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.addCard) {
          showAddCard(context, widget.clientManager, phone: true);
        } else {
          _showTipsSheet(context);
        }
      });
    }
  }

  @override
  void dispose() {
    _store.endEditing();
    super.dispose();
  }

  Future<void> chipMenu(HomeTab tab) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tab.name,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          for (final (value, label, icon) in _tabActions(tab, phone: true))
            ListTile(
              key: ValueKey("NewHomeTabAction-$value"),
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(value),
            ),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    await _tabAction(context, tab, action, phone: true);
  }

  /// Shows Home with the changes (they're saved as you go), with a way
  /// back into the editor.
  void preview() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final manager = widget.clientManager;
    Navigator.of(context).pop();
    newHomeShowPage.add(newHomeTab.value);
    messenger?.showSnackBar(SnackBar(
      content: const Text("Previewing Home"),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
          label: "Keep editing",
          onPressed: () {
            final ctx = navigator.currentContext;
            if (ctx == null) return;
            Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) => NewHomeEditorScreen(clientManager: manager)));
          }),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Customize Home",
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          const HomeUndoButton(phone: true),
          TextButton(
            key: const ValueKey("NewHomeCustomizeDone"),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Done",
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ScaledSafeArea(
        top: false,
        child: _following((context) {
          final tab = _store.current;
          final tabs = _store.tabs.value.tabs;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(spacing: 8, children: [
                  for (final t in tabs)
                    GestureDetector(
                      onLongPress: () => chipMenu(t),
                      child: ChoiceChip(
                        mouseCursor: WidgetStateMouseCursor.clickable,
                        key: ValueKey("NewHomeTabChip-${t.id}"),
                        avatar: HomeTabIcon(t.icon, size: 18),
                        label: Text(t.name),
                        selected: t.id == tab.id,
                        showCheckmark: false,
                        onSelected: (_) => _selectTab(t.id),
                      ),
                    ),
                  ActionChip(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    key: const ValueKey("NewHomeNewTab"),
                    tooltip: "New tab",
                    label: const Icon(Icons.add_rounded, size: 18),
                    onPressed: () => newHomeTabFlow(context, phone: true),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
                child: Text("Hold a tab to rename, move or remove it",
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ),
              if (_store.isEmpty)
                const _NoTabsHint()
              else ...[
                const HomePartSwitch(),
                _PartList(manager: widget.clientManager, tab: tab, phone: true),
              ],
              HomeLayoutAccountPicker(manager: widget.clientManager),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const ValueKey("NewHomePreview"),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text("Preview"),
                onPressed: preview,
              ),
              const SizedBox(height: 8),
              _footer(context, onTips: () => _showTipsSheet(context)),
            ],
          );
        }),
      ),
    );
  }
}

/// A dashed rounded outline around a group of slivers (the side list being
/// edited).
class DashedSliverOutline extends StatelessWidget {
  const DashedSliverOutline(
      {super.key, required this.slivers, this.padding = EdgeInsets.zero});

  final List<Widget> slivers;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: padding,
        sliver: DecoratedSliver(
          position: DecorationPosition.foreground,
          decoration: _DashedDecoration(
              Theme.of(context).colorScheme.primary.withAlpha(200)),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      );
}

class _DashedDecoration extends Decoration {
  const _DashedDecoration(this.color);
  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedBoxPainter(color);
}

class _DashedBoxPainter extends BoxPainter {
  _DashedBoxPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = (offset & size).deflate(1);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }
}
