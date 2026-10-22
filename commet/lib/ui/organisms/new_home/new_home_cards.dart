// Vommet (New Home step 3): the Card library. Overview's in-place customize
// mode on desktop (dashed cards you drag around, a library panel on the
// right to drag new cards from), the full-screen reorder list and library
// sheet on phones, and the Space card's picker. The layout itself is
// new_home_layout.dart; the cards are drawn in new_home_overview.dart.
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
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
    CardInfo(HomeLayout.recent, "Recent activity", Icons.history_rounded,
        Color(0xff5b8def), "Rooms and DMs with the newest messages.",
        short: "Newest messages first"),
    CardInfo(HomeLayout.favourites, "Favourites", Icons.star_rounded,
        Color(0xfff0b232), "Rooms you marked as favourite.",
        short: "Rooms you marked as favourite"),
    CardInfo(HomeLayout.otherRooms, "Standalone rooms", Icons.tag_rounded,
        Color(0xff7f8ea3), "Rooms that aren't in any space.",
        short: "Rooms that aren't part of a space"),
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
    CardInfo(HomeLayout.lowPriority, "Low priority", Icons.south_rounded,
        Color(0xff8a8f99), "Rooms you marked low priority.",
        short: "Rooms you marked low priority"),
    CardInfo(HomeLayout.spaceCard, "Space", Icons.workspaces_rounded,
        Color(0xff8a3d6b), "The rooms of one space you pick.",
        short: "The rooms of one space"),
    CardInfo(HomeLayout.contacts, "Contacts", Icons.contacts_rounded,
        Color(0xff4a8fb5), "Your contacts, online first.",
        short: "Your contacts, online first"),
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

/// "Customize Overview…": customize mode in place on desktop, the reorder
/// list on phones.
void customizeOverview(BuildContext context,
    {required bool phone, required ClientManager clientManager}) {
  // A narrow desktop window has no room for the library panel.
  if (phone || MediaQuery.sizeOf(context).width < 900) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NewHomeCustomizeScreen(clientManager: clientManager)));
    return;
  }
  newHomePage.value = NewHomePage.overview;
  newHomeCustomizing.value = true;
}

/// Adds a card of [type] at [gap] (the end when null); the Space card asks
/// which space first.
Future<void> addCardFromLibrary(
    BuildContext context, ClientManager manager, String type,
    {int? gap}) async {
  final store = HomeLayoutStore.instance;
  final layout = store.layout.value;
  if (type == HomeLayout.spaceCard) {
    final card = await showSpaceCardDialog(context, manager,
        card: layout.newCard(HomeLayout.spaceCard));
    if (card == null) return;
    await store.save(store.layout.value.insert(card, gap: gap));
    return;
  }
  await store.save(layout.add(type, gap: gap));
}

/// "Restore defaults", with an Undo.
void restoreDefaultCards(BuildContext context) {
  final store = HomeLayoutStore.instance;
  final before = store.layout.value;
  store.save(before.restoreDefaults());
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: const Text("Overview is back to its default cards."),
    action: SnackBarAction(label: "Undo", onPressed: () => store.save(before)),
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

/// Desktop: the Card library panel beside Overview in customize mode.
/// Tiles drag into Overview (or click to add at the bottom); a card dragged
/// back here is removed. Footer: Restore defaults and Done.
class NewHomeCardLibraryPanel extends StatefulWidget {
  const NewHomeCardLibraryPanel({super.key, required this.clientManager});

  final ClientManager clientManager;

  static const double width = 380;

  @override
  State<NewHomeCardLibraryPanel> createState() =>
      _NewHomeCardLibraryPanelState();
}

class _NewHomeCardLibraryPanelState extends State<NewHomeCardLibraryPanel> {
  HomeLayoutStore get store => HomeLayoutStore.instance;

  @override
  void initState() {
    super.initState();
    store.layout.addListener(rebuild);
  }

  @override
  void dispose() {
    store.layout.removeListener(rebuild);
    super.dispose();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = store.layout.value;
    return DragTarget<CardDrag>(
      onWillAcceptWithDetails: (d) => d.data is OverviewCardDrag,
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is OverviewCardDrag) {
          store.save(store.layout.value.remove(data.id));
        }
      },
      builder: (context, candidates, _) => Container(
        key: const ValueKey("NewHomeCardLibrary"),
        width: NewHomeCardLibraryPanel.width,
        decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? Color.alphaBlend(
                    scheme.error.withAlpha(25), scheme.surfaceContainerLow)
                : scheme.surfaceContainerLow,
            border: Border(
                left: BorderSide(color: scheme.surfaceContainerHighest))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: scheme.surfaceContainerHighest))),
            child: Row(spacing: 10, children: [
              Icon(Icons.dashboard_customize_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
              const Text("Card library",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                Text(
                    candidates.isNotEmpty
                        ? "Drop here to remove the card."
                        : "Drag a card into Overview to add it. Drag a card "
                            "back here to remove it.",
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.92,
                  children: [
                    for (final info in CardInfo.all)
                      _LibraryTile(
                        info: info,
                        added: !layout.canAdd(info.type) &&
                            !layout.hidden.any((c) => c.type == info.type),
                        onAdd: () => addCardFromLibrary(
                            context, widget.clientManager, info.type),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 16, 12),
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: scheme.surfaceContainerHighest))),
            child: Row(children: [
              TextButton.icon(
                key: const ValueKey("NewHomeRestoreDefaults"),
                onPressed: () => restoreDefaultCards(context),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text("Restore defaults"),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey("NewHomeCustomizeDone"),
                onPressed: () => newHomeCustomizing.value = false,
                child: const Text("Done"),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A library tile: a small preview, the name, a line, and whether it can
/// be added (again).
class _LibraryTile extends StatelessWidget {
  const _LibraryTile(
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
                Text(added ? "In Overview" : "Drag to add",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
            ]),
      ),
    );
    if (added) return KeyedSubtree(key: _key, child: tile);
    return Tooltip(
      message: "Drag into Overview, or click to add it at the bottom",
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
                  key: const ValueKey("NewHomeSpaceAll"),
                  label: const Text("All rooms"),
                  selected: !card.unreadOnly,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => card = card.copyWith(unreadOnly: false)),
                ),
                ChoiceChip(
                  key: const ValueKey("NewHomeSpaceUnread"),
                  label: const Text("Unread only"),
                  selected: card.unreadOnly,
                  showCheckmark: false,
                  onSelected: (_) =>
                      setState(() => card = card.copyWith(unreadOnly: true)),
                ),
                FilterChip(
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

/// Opens a card's settings: Recent activity's dialog, or the Space picker
/// in edit mode.
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
  }
}

/// Phones: "Customize Overview", full screen. Press and hold a handle to
/// reorder, ✕ removes, Add card opens the library sheet.
class NewHomeCustomizeScreen extends StatefulWidget {
  const NewHomeCustomizeScreen({super.key, required this.clientManager});

  final ClientManager clientManager;

  @override
  State<NewHomeCustomizeScreen> createState() => _NewHomeCustomizeScreenState();
}

class _NewHomeCustomizeScreenState extends State<NewHomeCustomizeScreen> {
  HomeLayoutStore get store => HomeLayoutStore.instance;

  @override
  void initState() {
    super.initState();
    store.layout.addListener(rebuild);
  }

  @override
  void dispose() {
    store.layout.removeListener(rebuild);
    super.dispose();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layout = store.layout.value;
    final cards = layout.visible;
    return Scaffold(
      backgroundColor: scheme.surfaceContainer,
      appBar: AppBar(
        backgroundColor: scheme.surfaceContainerLow,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).maybePop()),
        title: const Text("Customize Overview",
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
              key: const ValueKey("NewHomeCustomizeDone"),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text("Done")),
        ],
      ),
      body: ScaledSafeArea(
        top: false,
        child: ReorderableListView.builder(
          key: const ValueKey("NewHomeCustomizeList"),
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
                "Press and hold a handle to reorder. The ✕ removes a card.",
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
          footer: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey("NewHomeAddCard"),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    onPressed: () =>
                        showCardLibrarySheet(context, widget.clientManager),
                    child: const Text("Add card"),
                  ),
                  TextButton.icon(
                    key: const ValueKey("NewHomeRestoreDefaults"),
                    onPressed: () => restoreDefaultCards(context),
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text("Restore defaults"),
                  ),
                ]),
          ),
          itemCount: cards.length,
          onReorder: (from, to) {
            if (from < 0 || from >= cards.length) return;
            store.save(layout.moveTo(cards[from].id, to));
          },
          itemBuilder: (context, i) {
            final card = cards[i];
            return Padding(
              key: ValueKey("NewHomeCustomizeRow-${card.id}"),
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                  child: Row(spacing: 8, children: [
                    ReorderableDelayedDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle_rounded,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
                    CardIcon(card.type),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(cardTitle(widget.clientManager, card),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(cardSubtitle(card),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant)),
                          ]),
                    ),
                    if (card.configurable)
                      IconButton(
                        key: ValueKey("NewHomeCardSettings-${card.id}"),
                        tooltip: "Card settings",
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: () => editCardSettings(
                            context, widget.clientManager, card),
                      ),
                    IconButton(
                      key: ValueKey("NewHomeCardRemove-${card.id}"),
                      tooltip: "Remove card",
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => store.save(layout.remove(card.id)),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Phones: the Card library as a bottom sheet; Add puts a card at the
/// bottom of Overview.
Future<void> showCardLibrarySheet(BuildContext context, ClientManager manager) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => ValueListenableBuilder(
        valueListenable: HomeLayoutStore.instance.layout,
        builder: (context, layout, _) {
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            key: const ValueKey("NewHomeLibrarySheet"),
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(spacing: 10, children: [
                Icon(Icons.dashboard_customize_rounded,
                    color: scheme.onSurfaceVariant),
                const Text("Card library",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Text("Tap Add to put a card at the bottom of Overview.",
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              for (final info in CardInfo.all) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(spacing: 12, children: [
                    CardIcon(info.type),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(info.label,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(info.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant)),
                            if (info.multi)
                              Text("Can add more than once",
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.primary)),
                          ]),
                    ),
                    if (!layout.canAdd(info.type) &&
                        !layout.hidden.any((c) => c.type == info.type))
                      Row(
                          key: ValueKey("NewHomeLibraryAdded-${info.type}"),
                          mainAxisSize: MainAxisSize.min,
                          spacing: 4,
                          children: [
                            Icon(Icons.check_rounded,
                                size: 18, color: scheme.onSurfaceVariant),
                            Text("Added",
                                style:
                                    TextStyle(color: scheme.onSurfaceVariant)),
                          ])
                    else
                      FilledButton.tonal(
                        key: ValueKey("NewHomeLibraryAdd-${info.type}"),
                        onPressed: () async {
                          await addCardFromLibrary(context, manager, info.type);
                          if (info.type == HomeLayout.spaceCard &&
                              sheetContext.mounted) {
                            Navigator.of(sheetContext).maybePop();
                          }
                        },
                        child: const Text("Add"),
                      ),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
