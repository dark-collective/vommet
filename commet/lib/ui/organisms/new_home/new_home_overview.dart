import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/molecules/invitation_display.dart';
import 'package:commet/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:commet/ui/organisms/invitation_view/invite_preview_page.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_people.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/vommet_unread.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (New Home): Overview, a stack of cards in the old Home's panel
/// style. By default Recent activity, Favourites (when you have any) and
/// Standalone rooms; the Card library (step 3) adds more. Each card has a
/// ⋯ menu to set it up, move it or remove it; "Customize Overview…" switches
/// to customize mode on desktop (dashed cards, drag and drop, the library
/// panel beside it) or opens the reorder list on phones.
class NewHomeOverview extends StatefulWidget {
  const NewHomeOverview({
    super.key,
    required this.clientManager,
    required this.filterClient,
    required this.phone,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final bool phone;

  /// Rows a list card shows before "Show N more" (the cards added in step
  /// 3; step 1's cards show everything, as before).
  static const int collapsedCount = 10;

  @override
  State<NewHomeOverview> createState() => _NewHomeOverviewState();
}

class _NewHomeOverviewState extends State<NewHomeOverview> {
  final List<StreamSubscription> subs = [];
  final List<StreamSubscription> clientSubs = [];
  Client? filterClient;
  Timer? pending;

  /// Customize mode: where a drop would land (a visible gap), if anywhere.
  int? dropGap;

  /// Cards showing all their rows ("Show N more" pressed), by card id.
  final Set<String> expanded = {};

  /// Each card's box, to find the drop gap under the pointer.
  final Map<String, GlobalKey> cardKeys = {};

  ClientManager get manager => widget.clientManager;
  HomeLayoutStore get store => HomeLayoutStore.instance;
  bool get customizing => !widget.phone && newHomeCustomizing.value;

  @override
  void initState() {
    super.initState();
    filterClient = widget.filterClient;
    subs.addAll([
      manager.onSync.stream.listen((_) => refreshSoon()),
      manager.onClientRemoved.stream.listen((_) => clientsChanged()),
      manager.onClientAdded.stream.listen((_) => clientsChanged()),
      manager.onSpaceUpdated.stream.listen((_) => refreshSoon()),
      EventBus.setFilterClient.stream.listen((client) {
        filterClient = client;
        refreshNow();
      }),
    ]);
    store.layout.addListener(refreshNow);
    newHomeCustomizing.addListener(customizingChanged);
    listenToClients();
  }

  @override
  void didUpdateWidget(covariant NewHomeOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterClient != widget.filterClient) {
      filterClient = widget.filterClient;
    }
  }

  @override
  void dispose() {
    for (final s in [...subs, ...clientSubs]) {
      s.cancel();
    }
    pending?.cancel();
    store.layout.removeListener(refreshNow);
    newHomeCustomizing.removeListener(customizingChanged);
    super.dispose();
  }

  /// Favourites and invitations change outside the sync's room updates.
  void listenToClients() {
    for (final s in clientSubs) {
      s.cancel();
    }
    clientSubs.clear();
    for (final client in manager.clients) {
      clientSubs.addAll([
        client.favoriteRooms.onAdd.listen((_) => refreshSoon()),
        client.favoriteRooms.onRemove.listen((_) => refreshSoon()),
      ]);
      final invitations = client.getComponent<InvitationComponent>();
      if (invitations != null) {
        clientSubs.add(
            invitations.invitations.onListUpdated.listen((_) => refreshNow()));
      }
    }
  }

  /// Like the old Home: wait a second after a sync, then redraw.
  void refreshSoon() {
    pending ??= Timer(const Duration(seconds: 1), () {
      pending = null;
      refreshNow();
    });
  }

  void refreshNow() {
    if (!mounted) return;
    setState(() {});
  }

  void customizingChanged() {
    dropGap = null;
    refreshNow();
  }

  void clientsChanged() {
    if (!mounted) return;
    listenToClients();
    refreshNow();
  }

  bool inFilter(Room room) =>
      (filterClient == null || room.client == filterClient) &&
      !hiddenFromNewHome(room);

  Iterable<Room> get roomsInFilter =>
      (filterClient?.rooms ?? manager.rooms).where(inFilter);

  static bool isDirectMessage(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ==
      true;

  static DateTime? lastEventOf(Room room) =>
      room.lastEvent == null ? null : room.lastEventTimestamp;

  static bool isLowPriority(Room room) =>
      room is MatrixRoom &&
      room.matrixRoom.tags[matrix.TagType.lowPriority] != null;

  static bool isVoice(Room room) =>
      room.getComponent<VoipRoomComponent>() != null;

  List<Room> recentRooms(HomeCard card) => recentActivity<Room>(
        roomsInFilter,
        card,
        lastEvent: lastEventOf,
        isDirectMessage: isDirectMessage,
        isMuted: (r) => r.pushRule == PushRule.dontNotify,
        isUnread: (r) =>
            r.notificationCount > 0 || r.highlightedNotificationCount > 0,
      );

  List<Room> favouriteRooms() => [
        for (final client in manager.clients)
          for (final room in client.favoriteRooms)
            if (inFilter(room)) room
      ];

  List<Room> otherRooms() =>
      manager.singleRooms(filterClient: filterClient).where(inFilter).toList()
        ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));

  List<Room> roomsOf(bool Function(Room room) include) =>
      roomsWhere<Room>(roomsInFilter, include: include, lastEvent: lastEventOf);

  List<(InvitationComponent, Invitation)> invitations() => [
        for (final client in manager.clients)
          if (filterClient == null || client == filterClient)
            if (client.getComponent<InvitationComponent>() case final comp?)
              for (final invite in comp.invitations) (comp, invite)
      ];

  bool showAvatar(Room room) =>
      manager.clients.where((c) => c.hasRoom(room.identifier)).length > 1;

  GlobalKey keyOf(String id) => cardKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final layout = store.layout.value;
    final favourites = favouriteRooms();
    final editing = customizing;
    final cards = [
      for (final card in layout.visible)
        if (editing ||
            card.type != HomeLayout.favourites ||
            favourites.isNotEmpty)
          card
    ];
    cardKeys.removeWhere((id, _) => !cards.any((c) => c.id == id));
    final hidden = layout.hidden.length;

    if (editing) return buildCustomizing(context, layout, cards, favourites);

    final children = <Widget>[
      if (!layout.shows(HomeLayout.invites)) IncomingInvitationsWidget(manager),
      for (final card in cards)
        Padding(
          key: ValueKey("NewHomeCard-${card.id}"),
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: buildCard(context, layout, card, favourites),
        ),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 4),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 4,
              children: [
                Icon(Icons.visibility_off_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                tiamat.Text.labelLow(
                    hidden == 1 ? "1 hidden card" : "$hidden hidden cards"),
                tiamat.Text.labelLow(" · "),
                TextButton(
                    key: const ValueKey("NewHomeAddBack"),
                    onPressed: () => store.save(layout.showAll()),
                    child: const Text("Add back")),
              ]),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: TextButton.icon(
            key: const ValueKey("NewHomeCustomizeOverview"),
            onPressed: () => customizeOverview(context,
                phone: widget.phone, clientManager: manager),
            icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
            label: const Text("Customize Overview…"),
          ),
        ),
      ),
    ];

    return frame(children);
  }

  Widget frame(List<Widget> children) => ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ),
          ),
        ],
      );

  /// Customize mode: dashed cards with a handle and ✕, drop lines between
  /// them; library tiles drop in, cards drop back onto the library.
  Widget buildCustomizing(BuildContext context, HomeLayout layout,
      List<HomeCard> cards, List<Room> favourites) {
    Widget gap(int i) => SizedBox(
          height: 14,
          child: Center(child: dropGap == i ? const DropLine() : null),
        );

    return DragTarget<CardDrag>(
      onWillAcceptWithDetails: (details) => switch (details.data) {
        LibraryTileDrag(:final type) => store.layout.value.canAdd(type) ||
            store.layout.value.hidden.any((c) => c.type == type),
        OverviewCardDrag() => true,
      },
      onMove: (details) {
        final next = gapAt(details.offset, cards);
        if (next != dropGap) setState(() => dropGap = next);
      },
      onLeave: (_) => setState(() => dropGap = null),
      onAcceptWithDetails: (details) {
        final at = dropGap ?? gapAt(details.offset, cards);
        setState(() => dropGap = null);
        switch (details.data) {
          case LibraryTileDrag(:final type):
            addCardFromLibrary(context, manager, type, gap: at);
          case OverviewCardDrag(:final id):
            store.save(store.layout.value.moveTo(id, at));
        }
      },
      builder: (context, candidates, _) => frame([
        for (var i = 0; i < cards.length; i++) ...[
          gap(i),
          customizableCard(context, layout, cards[i], favourites),
        ],
        gap(cards.length),
        if (cards.isEmpty)
          DashedOutline(
            child: SizedBox(
              height: 120,
              child: Center(
                  child: tiamat.Text.labelLow(
                      "Drag cards here from the Card library.")),
            ),
          ),
        // Room to drop below the last card.
        const SizedBox(height: 160),
      ]),
    );
  }

  /// The visible gap nearest the pointer: above the first card whose middle
  /// is below it, else at the end.
  int gapAt(Offset pointer, List<HomeCard> cards) {
    for (var i = 0; i < cards.length; i++) {
      final box = cardKeys[cards[i].id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (pointer.dy < top + box.size.height / 2) return i;
    }
    return cards.length;
  }

  Widget customizableCard(BuildContext context, HomeLayout layout,
      HomeCard card, List<Room> favourites) {
    final body =
        buildCard(context, layout, card, favourites, customizing: true);
    return Draggable<CardDrag>(
      key: ValueKey("NewHomeCard-${card.id}"),
      data: OverviewCardDrag(card.id),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: CardDragFeedback(
          type: card.type,
          title: cardTitle(manager, card),
          subtitle: cardSubtitle(card)),
      childWhenDragging: Opacity(
          opacity: 0.35,
          child: DashedOutline(
              child: KeyedSubtree(key: keyOf(card.id), child: body))),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: DashedOutline(
            child: KeyedSubtree(key: keyOf(card.id), child: body)),
      ),
    );
  }

  Widget buildCard(BuildContext context, HomeLayout layout, HomeCard card,
      List<Room> favourites,
      {bool customizing = false}) {
    final menu = cardMenu(context, layout, card);
    NewHomeCard frame(
            {required List<Widget> children, String? empty, Widget? leading}) =>
        NewHomeCard(
          title: cardTitle(manager, card),
          leading: leading,
          menu: menu,
          empty: empty,
          customizing: customizing,
          subtitle: customizing ? cardSummary(card) : null,
          onSettings: card.configurable
              ? () => editCardSettings(context, manager, card)
              : null,
          onRemove: () => store.save(store.layout.value.remove(card.id)),
          children: children,
        );

    List<Widget> rows(List<Room> rooms, String prefix,
        {bool collapse = true, void Function(Room room)? onTap}) {
      const limit = NewHomeOverview.collapsedCount;
      final all = !collapse || expanded.contains(card.id);
      return [
        for (final room in all ? rooms : rooms.take(limit))
          RoomPanel(room,
              key: ValueKey("$prefix${room.localId}"),
              shouldShowAvatarForRoom: showAvatar,
              onTap: onTap == null ? null : () => onTap(room)),
        if (collapse && rooms.length > limit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey("NewHomeShowMore-${card.id}"),
              onPressed: () => setState(() {
                if (!expanded.remove(card.id)) expanded.add(card.id);
              }),
              child: Text(expanded.contains(card.id)
                  ? "Show less"
                  : "Show ${rooms.length - limit} more"),
            ),
          ),
      ];
    }

    switch (card.type) {
      case HomeLayout.recent:
        return frame(
          empty: card.unreadOnly ? "No unread rooms." : "No recent activity.",
          children: rows(recentRooms(card), "new-home-recent-${card.id}_",
              collapse: false),
        );
      case HomeLayout.favourites:
        return frame(
          empty: "Rooms you mark as favourite show here.",
          children: rows(favourites, "new-home-favourite_",
              collapse: false,
              onTap: (room) => EventBus.doOpenRoom(room.identifier,
                  clientId: room.client.identifier, openInSpace: false)),
        );
      case HomeLayout.otherRooms:
        return frame(
          empty: "Rooms you're in that aren't part of any space show here.",
          children: rows(otherRooms(), "new-home-other_", collapse: false),
        );
      case HomeLayout.unread:
        return frame(
          empty: "You're all caught up.",
          children: rows(roomsOf(roomHasUnread), "new-home-unread_"),
        );
      case HomeLayout.mentions:
        return frame(
          empty: "No unread mentions.",
          children: rows(
              roomsOf((r) => r.displayHighlightedNotificationCount > 0),
              "new-home-mentions_"),
        );
      case HomeLayout.lowPriority:
        return frame(
          empty: "Rooms you mark as low priority show here.",
          children: rows(roomsOf(isLowPriority), "new-home-low_"),
        );
      case HomeLayout.invites:
        return frame(
          empty: "No invites waiting for you.",
          children: [
            for (final (comp, invite) in invitations())
              InvitationDisplay(
                invite,
                key: ValueKey(
                    "new-home-invite_${comp.client.identifier}_${invite.roomId}"),
                acceptInvitation: comp.acceptInvitation,
                rejectInvitation: comp.rejectInvitation,
                onTap: (invitation) => InvitePreviewPage.open(context,
                    component: comp, invitation: invitation),
              ),
          ],
        );
      case HomeLayout.activeNow:
        return frame(children: [
          NewHomeActiveNowCardBody(
              key: ValueKey("new-home-active_${filterClient?.identifier}"),
              clientManager: manager,
              filterClient: filterClient),
        ]);
      case HomeLayout.contacts:
        return frame(children: [
          NewHomeContactsCardBody(
              key: ValueKey("new-home-contacts_${filterClient?.identifier}"),
              clientManager: manager,
              filterClient: filterClient),
        ]);
      case HomeLayout.spaceCard:
        final space = spaceOfCard(manager, card);
        if (space == null) {
          return frame(
              empty: card.space == null
                  ? "Pick a space in the card's settings."
                  : "This space isn't available. You may have left it.",
              children: const []);
        }
        final rooms = spaceCardRooms<Room>(
          space.roomsWithChildren.where(inFilter),
          card,
          lastEvent: lastEventOf,
          isUnread: roomHasUnread,
          isVoice: isVoice,
        );
        return frame(
          leading: tiamat.Avatar(
            radius: 9,
            image: space.avatar,
            placeholderText: space.displayName,
            placeholderColor: space.color,
          ),
          empty: card.unreadOnly
              ? "Nothing unread in ${space.displayName}."
              : "No rooms to show.",
          children: rows(rooms, "new-home-space-${card.id}_"),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget cardMenu(BuildContext context, HomeLayout layout, HomeCard card) {
    final up = layout.canMoveUp(card.id);
    final down = layout.canMoveDown(card.id);
    return PopupMenuButton<String>(
      key: ValueKey("NewHomeCardMenu-${card.id}"),
      tooltip: "Card options",
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: Icon(Icons.more_horiz_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (action) {
        switch (action) {
          case "settings":
            editCardSettings(context, manager, card);
          case "new_room":
            GetOrCreateRoom.show(null, context,
                pickExisting: false, showAllRoomTypes: true);
          case "up":
            store.save(layout.move(card.id, -1));
          case "down":
            store.save(layout.move(card.id, 1));
          case "hide":
            store.save(layout.remove(card.id));
          case "customize":
            customizeOverview(context,
                phone: widget.phone, clientManager: manager);
        }
      },
      itemBuilder: (context) => [
        if (card.configurable)
          menuItem("settings", Icons.tune_rounded, "Settings…"),
        if (card.type == HomeLayout.otherRooms)
          menuItem("new_room", Icons.add_rounded, "New room…"),
        menuItem("up", Icons.arrow_upward_rounded, "Move up", enabled: up),
        menuItem("down", Icons.arrow_downward_rounded, "Move down",
            enabled: down),
        menuItem("hide", Icons.close_rounded, "Remove card"),
        menuItem("customize", Icons.dashboard_customize_rounded,
            "Customize Overview…"),
      ],
    );
  }

  PopupMenuItem<String> menuItem(String value, IconData icon, String label,
          {bool enabled = true}) =>
      PopupMenuItem(
        value: value,
        enabled: enabled,
        child: Row(spacing: 12, children: [
          Icon(icon, size: 18),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

/// One Overview card: the old Home panel look (tiamat Panel: radius 10,
/// header label, separator, 8 px padding, rows 2 px apart) with a ⋯ menu
/// in the header line. In customize mode the header gets a drag handle, the
/// card's settings line, a settings button and ✕, and the rows stop taking
/// taps.
class NewHomeCard extends StatelessWidget {
  const NewHomeCard({
    super.key,
    required this.title,
    required this.menu,
    required this.children,
    this.empty,
    this.leading,
    this.customizing = false,
    this.subtitle,
    this.onSettings,
    this.onRemove,
  });

  final String title;
  final Widget menu;
  final List<Widget> children;
  final String? empty;

  /// Before the title (the Space card's space picture).
  final Widget? leading;

  final bool customizing;

  /// Customize mode: what the card's settings show ("Top 5").
  final String? subtitle;
  final VoidCallback? onSettings;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadows = Theme.of(context).extension<ShadowSettings>();
    Widget small(IconData icon, String tooltip, VoidCallback onTap, Key key) =>
        SizedBox(
          width: 28,
          height: 18,
          child: OverflowBox(
            maxHeight: 32,
            maxWidth: 32,
            child: IconButton(
              key: key,
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: Icon(icon, color: scheme.onSurfaceVariant),
              onPressed: onTap,
            ),
          ),
        );

    final content = children.isEmpty && empty != null
        ? Padding(
            padding: const EdgeInsets.all(8),
            child: tiamat.Text.labelLow(empty!))
        : Column(children: [
            for (final child in children)
              Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 2), child: child)
          ]);

    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: scheme.surface,
          boxShadow: shadows?.shadows),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(spacing: 6, children: [
            if (customizing)
              Icon(Icons.drag_indicator_rounded,
                  size: 16, color: scheme.onSurfaceVariant),
            if (leading != null) leading!,
            Expanded(
              child: Row(spacing: 6, children: [
                Flexible(
                    child: tiamat.Text.labelLow(title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (customizing && subtitle != null)
                  Flexible(
                    child: Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant.withAlpha(170))),
                  ),
              ]),
            ),
            if (customizing) ...[
              if (onSettings != null)
                small(Icons.tune_rounded, "Card settings", onSettings!,
                    const ValueKey("NewHomeCardSettings")),
              if (onRemove != null)
                small(Icons.close_rounded, "Remove card", onRemove!,
                    const ValueKey("NewHomeCardRemove")),
            ] else
              SizedBox(
                width: 24,
                height: 18,
                child: OverflowBox(maxHeight: 32, maxWidth: 32, child: menu),
              ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
          child: tiamat.Seperator(padding: 0),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: customizing ? IgnorePointer(child: content) : content,
        ),
      ]),
    );
  }
}

/// Recent activity's settings: how many rooms, and which.
class RecentActivitySettings extends StatefulWidget {
  const RecentActivitySettings(
      {super.key, required this.card, required this.onChanged});

  final HomeCard card;
  final void Function(HomeCard card) onChanged;

  @override
  State<RecentActivitySettings> createState() => _RecentActivitySettingsState();
}

class _RecentActivitySettingsState extends State<RecentActivitySettings> {
  late HomeCard card = widget.card;

  void update(HomeCard next) {
    setState(() => card = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    const title = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700);

    Widget toggle(String key, String label, String hint, bool value,
            void Function(bool) onChanged) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(label, style: title),
                    Text(hint, style: sub),
                  ]),
            ),
            Switch(
                key: ValueKey("NewHomeRecent-$key"),
                value: value,
                onChanged: onChanged),
          ]),
        );

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Expanded(
                    child: Text("Recent Activity",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              Text("Card settings · Overview",
                  style: sub.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Text("Show", style: title)),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final n in HomeLayout.counts)
                      ButtonSegment(
                          value: n,
                          label: Text("$n", key: ValueKey("NewHomeCount-$n")))
                  ],
                  selected: {card.count},
                  emptySelectionAllowed: true,
                  onSelectionChanged: (s) {
                    if (s.isNotEmpty) update(card.copyWith(count: s.first));
                  },
                ),
              ]),
              Text("rooms, newest message first", style: sub),
              const Divider(height: 24),
              toggle(
                  "dms",
                  "Include direct messages",
                  "DMs appear next to rooms",
                  card.dms,
                  (v) => update(card.copyWith(dms: v))),
              toggle(
                  "muted",
                  "Include muted rooms",
                  "Rooms you muted can still show here",
                  card.muted,
                  (v) => update(card.copyWith(muted: v))),
              toggle("unread", "Unread only", "Hide rooms you've already read",
                  card.unreadOnly, (v) => update(card.copyWith(unreadOnly: v))),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: tiamat.Button(
                    text: "Done", onTap: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
