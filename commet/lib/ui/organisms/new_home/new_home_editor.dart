// Vommet (New Home): the Customize Home editor (Vommet issues 604 and 607).
// Desktop: a panel beside the live Home with the tabs (reorder, ⋯ Rename
// and icon / Duplicate / Remove, + New tab), a Side list | Main page switch
// (the part being edited gets a dashed outline, the other part dims) and a
// separate library for each part. Phones and narrow windows: the same
// editor full screen, with tab chips, handles and bottom sheets. Three
// first-time tips show the first time it opens; Show tips replays them.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_column.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:flutter/material.dart';
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
    part == HomeEditPart.side ? "Side list" : "Main page";

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
  if (newHomeTab.value == tab.id) {
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

/// "+ Add a section": the sections the side list can still take (a space's
/// rooms any number of times); the space one asks which space. Under
/// "Your tags": All my tags, and a section for each of your tags.
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
          for (final type in HomeSection.knownTypes)
            if (type != HomeSection.tagSection && type != HomeSection.allTags)
              _LibraryEntry(type, sectionLabel(type), sectionIcon(type),
                  sectionDescription(type),
                  added: !tab.canAddSection(type)),
        ]
      ),
      (
        "Your tags",
        [
          _LibraryEntry(
              HomeSection.allTags,
              sectionLabel(HomeSection.allTags),
              sectionIcon(HomeSection.allTags),
              sectionDescription(HomeSection.allTags),
              added: !tab.canAddSection(HomeSection.allTags)),
          for (final tag in userTagsOf(manager.rooms.map(roomTagsOf)))
            _LibraryEntry("$tagLibraryPrefix$tag", tagName(tag),
                Icons.label_outline_rounded, tagRoomCount(counts[tag] ?? 0),
                added: tab.side.any(
                    (s) => s.type == HomeSection.tagSection && s.tag == tag)),
        ]
      ),
    ],
    footer: _tagsFooter,
  );
  if (picked == null || !context.mounted) return;
  final tag = picked.startsWith(tagLibraryPrefix)
      ? picked.substring(tagLibraryPrefix.length)
      : null;
  final type = tag == null ? picked : HomeSection.tagSection;
  final id = tab.newSectionId(type);
  var section = HomeSection(id, type: id == type ? null : type, tag: tag);
  if (type == HomeSection.spaceSection) {
    final space = await pickSpace(context, manager);
    if (space == null) return;
    section = section.copyWith(
        space: space.identifier, spaceClient: space.client.identifier);
  }
  final latest = _store.current;
  _saveTab(latest.addSection(section));
}

/// "+ Add a card": the cards, then the whole pages. Added at the bottom
/// of the main page.
Future<void> showAddCard(BuildContext context, ClientManager manager,
    {required bool phone}) async {
  final layout = _store.layout.value;
  _LibraryEntry entry(CardInfo info) =>
      _LibraryEntry(info.type, info.label, info.icon, info.short,
          color: info.color, added: !canAddFromLibrary(layout, info.type));
  final type = await _showLibrary<String>(
    context,
    phone: phone,
    title: "Add to the main page",
    subtitle: "Of ${_store.current.name}",
    groups: [
      ("Cards", [for (final info in CardInfo.cards) entry(info)]),
      (
        "Whole pages",
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

/// The library's "Your tags": All my tags, then a Tag card per tag.
List<CardInfo> tagCardInfos(ClientManager manager) {
  final counts = userTagCounts(manager.rooms.map(roomTagsOf));
  final tag = CardInfo.of(HomeLayout.tagCard);
  return [
    CardInfo.of(HomeLayout.allTagsCard),
    for (final t in userTagsOf(manager.rooms.map(roomTagsOf)))
      CardInfo("$tagLibraryPrefix$t", tagName(t), tag.icon, tag.color,
          tagRoomCount(counts[t] ?? 0),
          short: tagRoomCount(counts[t] ?? 0)),
  ];
}

class _LibraryEntry {
  const _LibraryEntry(this.value, this.label, this.icon, this.description,
      {this.added = false, this.color});
  final String value;
  final String label;
  final IconData icon;
  final String description;
  final bool added;
  final Color? color;
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
      HomeSection.photos => Icons.photo_library_rounded,
      HomeSection.standalone => Icons.tag_rounded,
      HomeSection.spaceSection => Icons.workspaces_rounded,
      HomeSection.lowPriority => Icons.south_rounded,
      HomeSection.tagSection => Icons.label_outline_rounded,
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
      HomeSection.photos => "Your photo albums",
      HomeSection.standalone => "Rooms that aren't part of a space",
      HomeSection.spaceSection => "The rooms of one space you pick",
      HomeSection.lowPriority => "Rooms you marked low priority",
      HomeSection.tagSection => "The rooms you gave one of your tags",
      HomeSection.allTags => "A section for each tag you use, new ones too",
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
            for (final name in HomeTabs.icons)
              IconButton(
                key: ValueKey("NewHomeTabIcon-$name"),
                tooltip: name,
                isSelected: icon == name,
                style: IconButton.styleFrom(
                    backgroundColor: icon == name
                        ? scheme.primary.withAlpha(60)
                        : scheme.surfaceContainerHighest,
                    side: icon == name
                        ? BorderSide(color: scheme.primary, width: 1.5)
                        : null),
                icon: Icon(homeTabIcon(name), size: 20),
                onPressed: () => setState(() => icon = name),
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
      "The side list holds sections of rooms and people. The main page "
          "holds cards and whole pages like People.",
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
    final heading = "${_possessive(tab.name)} ${partLabel(part).toLowerCase()}"
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
                : sections[i].type == HomeSection.tagSection &&
                        sections[i].tag != null
                    ? tagName(sections[i].tag!)
                    : sectionLabel(sections[i].type),
            subtitle: sections[i].collapsed ? "Collapsed" : null,
            menu: [
              item("collapse",
                  sections[i].collapsed ? "Show expanded" : "Show collapsed"),
              if (sections[i].type == HomeSection.spaceSection)
                item("space", "Change space…"),
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
                  : "No cards yet: this tab's main page is empty.",
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
          heading("Whole pages"),
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
class _PartSwitch extends StatelessWidget {
  const _PartSwitch();

  @override
  Widget build(BuildContext context) => SegmentedButton<HomeEditPart>(
        key: const ValueKey("NewHomeEditPart"),
        showSelectedIcon: false,
        segments: [
          for (final part in HomeEditPart.values)
            ButtonSegment(value: part, label: Text(partLabel(part))),
        ],
        selected: {newHomeEditPart.value},
        onSelectionChanged: (s) => newHomeEditPart.value = s.first,
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
    if (tabs.length > 1) ("remove", "Remove", Icons.delete_outline_rounded),
  ];
}

/// Rebuilds on any change the editor shows.
Widget _following(Widget Function(BuildContext context) builder) =>
    ListenableBuilder(
      listenable: Listenable.merge([_store.tabs, newHomeTab, newHomeEditPart]),
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
                    const _PartSwitch(),
                    _PartList(manager: clientManager, tab: tab, phone: false),
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
          Icon(homeTabIcon(tab.icon),
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
                        key: ValueKey("NewHomeTabChip-${t.id}"),
                        avatar: Icon(homeTabIcon(t.icon), size: 18),
                        label: Text(t.name),
                        selected: t.id == tab.id,
                        showCheckmark: false,
                        onSelected: (_) => _selectTab(t.id),
                      ),
                    ),
                  ActionChip(
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
              const _PartSwitch(),
              _PartList(manager: widget.clientManager, tab: tab, phone: true),
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
