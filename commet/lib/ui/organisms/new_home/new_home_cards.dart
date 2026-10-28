// Vommet (New Home step 3): the Card library. Overview's in-place customize
// mode on desktop (dashed cards you drag around, a library panel on the
// right to drag new cards from), the full-screen reorder list and library
// sheet on phones, and the Space card's picker. The layout itself is
// new_home_layout.dart; the cards are drawn in new_home_overview.dart.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_editor.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_section.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms_settings.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/new_home_tabs.dart';
import 'package:commet/ui/organisms/new_home/new_home_tags.dart';
import 'package:commet/ui/organisms/new_home/new_home_text.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What the library says about each card type.
class CardInfo {
  const CardInfo(this.type, this.label, this.icon, this.color, this.description,
      {required this.short});

  final String type;
  final String label;
  final IconData icon;
  final Color color;

  /// The library tile's line.
  final String description;

  /// The phone customize list's second line for cards without settings.
  final String short;

  bool get multi => HomeLayout.multiTypes.contains(type);

  static const List<CardInfo> all = [
    CardInfo(
        HomeLayout.deepSearch,
        "Deep Search",
        Icons.search_rounded,
        Color(0xff9b84ee),
        "Search messages, files and links across your chats.",
        short: "Search messages, files and links"),
    CardInfo(HomeLayout.recent, "Recent activity", Icons.history_rounded,
        Color(0xff5b8def), "Rooms and DMs with the newest messages.",
        short: "Newest messages first"),
    CardInfo(HomeLayout.favourites, "Favorites", Icons.star_rounded,
        Color(0xfff0b232), "Rooms you marked as favorite.",
        short: "Rooms you marked as favorite"),
    CardInfo(HomeLayout.otherRooms, "Rooms", Icons.tag_rounded,
        Color(0xff7f8ea3), "Standalone rooms, rooms in spaces, or both.",
        short: "Standalone rooms, rooms in spaces, or both"),
    CardInfo(HomeLayout.unread, "Unread", Icons.mark_chat_unread_rounded,
        Color(0xffda373c), "Every room with unread messages.",
        short: "Rooms with unread messages"),
    CardInfo(
        HomeLayout.mentions,
        "Mentions & highlights",
        Icons.alternate_email_rounded,
        Color(0xffe0569b),
        "Messages that mention you or your keywords.",
        short: "Mentions and keywords"),
    CardInfo(HomeLayout.invites, "Invites", Icons.mail_rounded,
        Color(0xff3fb37f), "Room and DM invites waiting for you.",
        short: "Room and DM invites"),
    CardInfo(HomeLayout.activeNow, "Active Now", Icons.graphic_eq_rounded,
        Color(0xff23a55a), "Contacts in calls, and their status.",
        short: "Contacts in calls, and their status"),
    CardInfo(
        HomeLayout.liveCalls,
        "Live calls",
        Icons.call_rounded,
        Color(0xff23a55a),
        "Rooms with a call going on now, with a Join button.",
        short: "Rooms with a call going on"),
    CardInfo(HomeLayout.lowPriority, "Low priority", Icons.south_rounded,
        Color(0xff8a8f99), "Rooms you marked low priority.",
        short: "Rooms you marked low priority"),
    CardInfo(HomeLayout.spaceCard, "Space", Icons.workspaces_rounded,
        Color(0xff8a3d6b), "The rooms of one space you pick.",
        short: "The rooms of one space"),
    CardInfo(HomeLayout.contacts, "Contacts", Icons.contacts_rounded,
        Color(0xff4a8fb5), "Your contacts, online first.",
        short: "Your contacts, online first"),
    CardInfo(
        HomeLayout.peoplePage,
        "People",
        Icons.people_alt_rounded,
        Color(0xff3fb37f),
        "The whole People page: contacts, requests, invites.",
        short: "Contacts, requests, invites"),
    CardInfo(HomeLayout.roomsPage, "Rooms browser", Icons.tag_rounded,
        Color(0xff7f8ea3), "The whole Rooms page: chips, spaces, search.",
        short: "Chips, spaces, search"),
    CardInfo(
        HomeLayout.dmsPage,
        "Direct messages",
        Icons.chat_bubble_rounded,
        Color(0xff5b8def),
        "Every direct message, newest first, with its last message.",
        short: "Every DM, newest first"),
    CardInfo(HomeLayout.tagCard, "Tags", Icons.label_rounded, Color(0xff5865f2),
        "All your tags, or the ones you pick, with their rooms.",
        short: "Rooms with your tags"),
    // A Tags card set to All my tags.
    CardInfo(
        HomeLayout.allTagsCard,
        "Tags",
        Icons.label_rounded,
        Color(0xff5865f2),
        "All your tags, or the ones you pick, with their rooms.",
        short: "Rooms with your tags"),
    CardInfo(HomeLayout.textCard, "Text", Icons.notes_rounded,
        Color(0xffc28a2c), "Your own words, images and links.",
        short: "Your own text"),
  ];

  /// The library's cards (whole pages and tag cards have groups of their
  /// own).
  static List<CardInfo> get cards => [
        for (final info in all)
          if (!HomeLayout.wholePageTypes.contains(info.type) &&
              !HomeLayout.tagTypes.contains(info.type))
            info
      ];

  static CardInfo of(String type) => all.firstWhere((i) => i.type == type,
      orElse: () => CardInfo(
          type, type, Icons.dashboard_rounded, const Color(0xff8a8f99), "",
          short: ""));
}

/// Desktop: whether Overview is in customize mode (dashed cards, library).
final ValueNotifier<bool> newHomeCustomizing = ValueNotifier(false);

/// What's being dragged in customize mode.
sealed class CardDrag {
  const CardDrag();
}

/// A library tile on its way into Overview.
class LibraryTileDrag extends CardDrag {
  const LibraryTileDrag(this.type);
  final String type;
}

/// An Overview card being moved, or dragged back to the library.
class OverviewCardDrag extends CardDrag {
  const OverviewCardDrag(this.id);
  final String id;
}

/// "Customize": Customize Home (the editor beside Home on desktop, full
/// screen on phones). [openLibrary] ("Add a card") starts on the main page
/// with its library open.
void customizeOverview(BuildContext context,
        {required bool phone,
        required ClientManager clientManager,
        bool openLibrary = false}) =>
    customizeHome(context,
        phone: phone, clientManager: clientManager, addCard: openLibrary);

/// Adds a card of [type] at [gap] (the end when null); the Space card asks
/// which space first, the Tags card which tags. `tag:<tag>` adds a Tags card
/// with that one tag.
Future<void> addCardFromLibrary(
    BuildContext context, ClientManager manager, String type,
    {int? gap}) async {
  final store = HomeLayoutStore.instance;
  final layout = store.layout.value;
  if (type.startsWith(tagLibraryPrefix)) {
    final card = layout
        .newCard(HomeLayout.tagCard)
        .copyWith(tags: [type.substring(tagLibraryPrefix.length)]);
    await store.save(layout.insert(card, gap: gap));
    return;
  }
  if (type == HomeLayout.tagCard || type == HomeLayout.allTagsCard) {
    final choice = await showTagsDialog(context, manager,
        initial: const TagsChoice(all: true));
    if (choice == null) return;
    final card = choice.applyTo(layout.newCard(HomeLayout.tagCard));
    await store.save(store.layout.value.insert(card, gap: gap));
    return;
  }
  if (type == HomeLayout.textCard) {
    final card = await showTextCardEditor(context, manager,
        card: layout.newCard(HomeLayout.textCard));
    if (card == null) return;
    await store.save(store.layout.value.insert(card, gap: gap));
    return;
  }
  if (type == HomeLayout.spaceCard) {
    final card = await showSpaceCardDialog(context, manager,
        card: layout.newCard(HomeLayout.spaceCard));
    if (card == null) return;
    await store.save(store.layout.value.insert(card, gap: gap));
    return;
  }
  await store.save(layout.add(type, gap: gap));
}

/// A library entry for one of your tags: `tag:<tag>`.
const String tagLibraryPrefix = "tag:";

/// A room's tags (`m.tag`), or none for rooms that aren't Matrix rooms.
Iterable<String> roomTagsOf(Room room) =>
    room is MatrixRoom ? room.matrixRoom.tags.keys : const [];

/// Whether [room] has room tag [tag].
bool roomHasTag(Room room, String tag) =>
    room is MatrixRoom && room.matrixRoom.tags.containsKey(tag);

/// Every one of your tags on your rooms, sorted by name.
List<String> userTagsIn(ClientManager manager) =>
    userTagsOf(manager.rooms.map(roomTagsOf));

/// "N rooms" for one of your tags.
String tagRoomCount(int count) => count == 1 ? "1 room" : "$count rooms";

/// Whether the library can still add [type] to [layout]: a one-tag Tags
/// card once per tag (`tag:<tag>`), every other card as [HomeLayout.canAdd] says (or
/// a hidden step-1 card coming back).
bool canAddFromLibrary(HomeLayout layout, String type) {
  if (type.startsWith(tagLibraryPrefix)) {
    final tag = type.substring(tagLibraryPrefix.length);
    return !layout.visible.any((c) =>
        c.type == HomeLayout.tagCard && c.tags.length == 1 && c.tag == tag);
  }
  return layout.canAdd(type) || layout.hidden.any((c) => c.type == type);
}

/// "Reset Home to default": asks, then brings back the default tabs
/// (Overview, People, Rooms) with their default contents, with an Undo.
Future<void> resetHome(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final confirmed = await AdaptiveDialog.confirmation(context,
      title: "Reset Home to default?",
      prompt: "Home goes back to Overview, People and Rooms with their "
          "default side lists and pages. Your other tabs are removed.",
      confirmationText: "Reset",
      cancelText: CommonStrings.promptCancel,
      dangerous: true);
  if (confirmed != true) return;
  final store = HomeLayoutStore.instance;
  final before = store.tabs.value;
  final shown = newHomeTab.value;
  await store.saveTabs(before.reset(), label: "reset Home to default");
  newHomeTab.value = HomeTabs.overview;
  messenger?.showSnackBar(SnackBar(
    content: const Text("Home is back to its default tabs."),
    action: SnackBarAction(
        label: "Undo",
        onPressed: () {
          store.saveTabs(before);
          newHomeTab.value = shown;
        }),
  ));
}

/// The space a Space card shows, or null when it's gone (left, or not
/// loaded yet).
Space? spaceOfCard(ClientManager manager, HomeCard card) {
  final id = card.space;
  if (id == null) return null;
  final spaces = manager.spaces.where((s) => s.identifier == id).toList();
  return spaces
          .where((s) =>
              card.spaceClient == null ||
              s.client.identifier == card.spaceClient)
          .firstOrNull ??
      spaces.firstOrNull;
}

/// A card's name as Overview shows it (a Space card takes its space's name).
String cardTitle(ClientManager manager, HomeCard card) {
  if (card.type == HomeLayout.recent) return "Recent Activity";
  if (card.type == HomeLayout.spaceCard) {
    return spaceOfCard(manager, card)?.displayName ?? "Space";
  }
  if (HomeLayout.tagTypes.contains(card.type)) {
    return tagsTitle(
        all: card.type == HomeLayout.allTagsCard,
        tags: card.tags,
        name: card.name);
  }
  if (card.type == HomeLayout.textCard) {
    return textContentOf(card)?.title ?? card.name ?? "Text";
  }
  if (card.type == HomeLayout.otherRooms) {
    return roomsSectionLabel(card.rooms,
        name: card.name,
        onlySpace: (ref) => NewHomeSpaceIndex.of(manager, null)
            .spaceOf(manager, ref)
            ?.displayName);
  }
  return CardInfo.of(card.type).label;
}

/// A card's second line in the customize lists.
String cardSubtitle(HomeCard card) =>
    cardSummary(card) ?? CardInfo.of(card.type).short;

/// A small square with the card type's icon.
class CardIcon extends StatelessWidget {
  const CardIcon(this.type, {super.key, this.size = 40});
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final info = CardInfo.of(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: info.color.withAlpha(50),
          borderRadius: BorderRadius.circular(size / 4)),
      child: Icon(info.icon, size: size * 0.55, color: info.color),
    );
  }
}

/// Dashed rounded outline for cards in customize mode.
class DashedOutline extends StatelessWidget {
  const DashedOutline(
      {super.key, required this.child, this.color, this.radius = 10});
  final Widget child;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _DashPainter(
            color ?? Theme.of(context).colorScheme.primary.withAlpha(200),
            radius),
        child: child,
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) =>
      old.color != color || old.radius != radius;
}

/// The drop indicator: a line with a dot at each end.
class DropLine extends StatelessWidget {
  const DropLine({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    Widget dot() => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2)),
        );
    return SizedBox(
      key: const ValueKey("NewHomeDropLine"),
      height: 10,
      child: Row(children: [
        dot(),
        Expanded(child: Container(height: 3, color: color)),
        dot(),
      ]),
    );
  }
}

/// What a dragged card or tile looks like under the pointer.
class CardDragFeedback extends StatelessWidget {
  const CardDragFeedback(
      {super.key, required this.type, required this.title, this.subtitle});
  final String type;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Transform.translate(
      offset: const Offset(-24, -24),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.primary, width: 1.5),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6))
              ]),
          child: Row(spacing: 10, children: [
            CardIcon(type, size: 32),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A library tile: a small preview, the name, a line, and whether it can
/// be added (again).
class LibraryTile extends StatelessWidget {
  const LibraryTile(
      {required this.info, required this.added, required this.onAdd});
  final CardInfo info;

  /// Already on Overview, and there can only be one.
  final bool added;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = Opacity(
      opacity: added ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.surfaceContainerHighest)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              _Preview(info.color),
              Row(spacing: 6, children: [
                Icon(info.icon, size: 16, color: info.color),
                Expanded(
                    child: Text(info.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700))),
                if (added)
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
              ]),
              Expanded(
                child: Text(info.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
              if (info.multi)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: scheme.primary.withAlpha(40),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text("Can add more than once",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary)),
                )
              else
                Text(added ? "On this page" : "Drag to add",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
            ]),
      ),
    );
    if (added) return KeyedSubtree(key: _key, child: tile);
    return Tooltip(
      message: "Drag onto the page, or click to add it at the bottom",
      waitDuration: const Duration(milliseconds: 600),
      child: Draggable<CardDrag>(
        key: _key,
        data: LibraryTileDrag(info.type),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: CardDragFeedback(
            type: info.type, title: info.label, subtitle: info.description),
        childWhenDragging:
            DashedOutline(child: Opacity(opacity: 0.4, child: tile)),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: GestureDetector(onTap: onAdd, child: tile),
        ),
      ),
    );
  }

  Key get _key => ValueKey("NewHomeLibraryTile-${info.type}");
}

/// Three rows of dots and lines in the card's colour.
class _Preview extends StatelessWidget {
  const _Preview(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(int i, double width) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(spacing: 6, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: color.withAlpha(255 - i * 70), shape: BoxShape.circle),
            ),
            Container(
              width: width,
              height: 4,
              decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withAlpha(90),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row(0, 56),
        row(1, 40),
        row(2, 64),
      ]),
    );
  }
}

/// Picks the space a Space card shows and what it shows. Returns [card]
/// with the picks, or null when cancelled.
Future<HomeCard?> showSpaceCardDialog(
    BuildContext context, ClientManager manager,
    {required HomeCard card, bool editing = false}) {
  return showDialog<HomeCard>(
    context: context,
    builder: (context) =>
        SpaceCardDialog(manager: manager, card: card, editing: editing),
  );
}

class SpaceCardDialog extends StatefulWidget {
  const SpaceCardDialog(
      {super.key,
      required this.manager,
      required this.card,
      this.editing = false});

  final ClientManager manager;
  final HomeCard card;
  final bool editing;

  @override
  State<SpaceCardDialog> createState() => _SpaceCardDialogState();
}

class _SpaceCardDialogState extends State<SpaceCardDialog> {
  late HomeCard card = widget.card;

  List<Space> get spaces {
    final list = widget.manager.spaces.toList();
    list.sort((a, b) {
      if (a.isTopLevel != b.isTopLevel) return a.isTopLevel ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  bool picked(Space s) =>
      card.space == s.identifier &&
      (card.spaceClient == null || card.spaceClient == s.client.identifier);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = spaces;
    final multiAccount = widget.manager.clients.length > 1;
    final hasPick = list.any(picked);
    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(spacing: 10, children: [
                const CardIcon(HomeLayout.spaceCard, size: 28),
                Expanded(
                    child: Text(
                        widget.editing ? "Space card" : "Add a Space card",
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              Text("Pick the space whose rooms this card shows.",
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text("You aren't in any spaces yet.",
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      )
                    : ListView(shrinkWrap: true, children: [
                        for (final s in list)
                          _SpaceOption(
                            key: ValueKey("NewHomeSpacePick-${s.identifier}"),
                            space: s,
                            selected: picked(s),
                            showAccount: multiAccount,
                            onTap: () => setState(() => card = card.copyWith(
                                space: s.identifier,
                                spaceClient: s.client.identifier)),
                          ),
                      ]),
              ),
              const SizedBox(height: 14),
              Text("SHOW",
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeSpaceAll"),
                  label: const Text("All rooms"),
                  selected: !card.unreadOnly,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => card = card.copyWith(unreadOnly: false)),
                ),
                ChoiceChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeSpaceUnread"),
                  label: const Text("Unread only"),
                  selected: card.unreadOnly,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => card = card.copyWith(unreadOnly: true)),
                ),
                FilterChip(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  key: const ValueKey("NewHomeSpaceVoice"),
                  label: const Text("Include voice rooms"),
                  selected: card.voice,
                  onSelected: (v) =>
                      setState(() => card = card.copyWith(voice: v)),
                ),
              ]),
              const SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: 8,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("Cancel")),
                    FilledButton(
                      key: const ValueKey("NewHomeSpaceConfirm"),
                      onPressed: hasPick
                          ? () => Navigator.of(context).pop(card)
                          : null,
                      child: Text(widget.editing ? "Save" : "Add card"),
                    ),
                  ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpaceOption extends StatelessWidget {
  const _SpaceOption(
      {super.key,
      required this.space,
      required this.selected,
      required this.showAccount,
      required this.onTap});
  final Space space;
  final bool selected;
  final bool showAccount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rooms = space.roomsWithChildren.toSet().length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? scheme.primary.withAlpha(30) : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: selected ? scheme.primary : Colors.transparent)),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(spacing: 12, children: [
              tiamat.Avatar(
                radius: 18,
                image: space.avatar,
                placeholderText: space.displayName,
                placeholderColor: space.color,
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(space.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (showAccount)
                        Text(space.client.identifier,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
              ),
              Text(rooms == 1 ? "1 room" : "$rooms rooms",
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
              Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Opens a card's settings: Recent activity's dialog, the Space picker in
/// edit mode, the Tags card's tags, or the Rooms card's sheet.
Future<void> editCardSettings(
    BuildContext context, ClientManager manager, HomeCard card) async {
  final store = HomeLayoutStore.instance;
  if (card.type == HomeLayout.recent) {
    await showDialog(
      context: context,
      builder: (context) => RecentActivitySettings(
        card: card,
        onChanged: (next) => store.save(store.layout.value.replace(next)),
      ),
    );
    return;
  }
  if (card.type == HomeLayout.spaceCard) {
    final next =
        await showSpaceCardDialog(context, manager, card: card, editing: true);
    if (next == null) return;
    await store.save(store.layout.value.replace(next));
    return;
  }
  if (card.type == HomeLayout.liveCalls) {
    await editLiveCallsSettings(context, manager, card);
    return;
  }
  if (card.type == HomeLayout.textCard) {
    await editTextCard(context, manager, card);
    return;
  }
  if (card.type == HomeLayout.otherRooms) {
    final result = await showRoomsSettings(context, manager,
        initial: card.rooms, name: card.name, card: true);
    if (result == null) return;
    final latest =
        store.layout.value.cards.where((c) => c.id == card.id).firstOrNull ??
            card;
    await store.save(store.layout.value.replace(
        latest.copyWith(rooms: result.filter, name: result.name ?? "")));
    return;
  }
  if (HomeLayout.tagTypes.contains(card.type)) {
    final choice = await showTagsDialog(context, manager,
        initial: TagsChoice.ofCard(card), editing: true);
    if (choice == null) return;
    await store.save(store.layout.value.replace(choice.applyTo(card)));
  }
}
