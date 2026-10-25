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
import 'package:commet/ui/organisms/new_home/new_home_dms.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_live_calls.dart';
import 'package:commet/ui/organisms/new_home/new_home_people.dart';
import 'package:commet/ui/organisms/new_home/new_home_rooms.dart';
import 'package:commet/ui/organisms/new_home/new_home_text.dart';
import 'package:commet/ui/organisms/new_home/room_tags.dart';
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
/// ⋯ menu to set it up, move it or remove it. The header's "Customize" (and
/// "Add a card" at the bottom) switches to customize mode on desktop (dashed
/// cards, drag and drop, the library panel beside it) or opens the reorder
/// list on phones.
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
    // Favourites and Invites only show when they have something, outside
    // customize mode.
    final noInvites = invitations().isEmpty;
    final cards = [
      for (final card in layout.visible)
        if (editing ||
            (card.type != HomeLayout.favourites || favourites.isNotEmpty) &&
                (card.type != HomeLayout.invites || !noInvites))
          card
    ];
    cardKeys.removeWhere((id, _) => !cards.any((c) => c.id == id));
    final hidden = layout.hidden.length;

    if (editing) return buildCustomizing(context, layout, cards, favourites);

    // A main page holding just People or the Rooms browser: the page itself.
    if (layout.soleWholePage case final page?) {
      return wholePageBlock(page.type, manager, filterClient,
          phone: widget.phone, part: page.part);
    }

    // Slivers, so a long card (Standalone rooms on a big account) only
    // builds the rows on screen; the look is the old ListView + Column
    // (8 px around, 12 px under each card). Flat on purpose: inside a
    // SliverMainAxisGroup, the slivers after a long card are placed on
    // screen for focus order, so Tab would jump past the unbuilt rows.
    const side = 8.0;
    final slivers = <Widget>[
      const SliverToBoxAdapter(child: SizedBox(height: side)),
      // Invites without an Invites card anywhere: at the top of the first
      // tab, as on the old Overview.
      if (store.tabs.value.tabs.firstOrNull?.id == store.current.id &&
          store.tabs.value.tabHolding(HomeLayout.invites) == null)
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: side),
            sliver:
                SliverToBoxAdapter(child: IncomingInvitationsWidget(manager))),
      for (final card in cards)
        SliverPadding(
          key: ValueKey("NewHomeCard-${card.id}"),
          padding: const EdgeInsets.fromLTRB(side, 0, side, 12),
          sliver: switch (buildCard(context, layout, card, favourites)) {
            final NewHomeCard built when built.lazyRows =>
              NewHomeCardSliver(built),
            final built => SliverToBoxAdapter(child: built),
          },
        ),
      if (hidden > 0)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(side, 2, side, 4),
          sliver: SliverToBoxAdapter(
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
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(side, 4, side, 12 + side),
        sliver: SliverToBoxAdapter(
          child: AddCardTile(
              onTap: () => customizeOverview(context,
                  phone: widget.phone,
                  clientManager: manager,
                  openLibrary: true)),
        ),
      ),
    ];

    return CustomScrollView(slivers: slivers);
  }

  /// The cards fill the page's width, so one-line previews run as far as
  /// the window allows. Customize mode only (it measures and drags whole
  /// cards); the normal Overview is the same look in slivers.
  Widget frame(List<Widget> children) => ListView(
        padding: const EdgeInsets.all(8),
        children: [
          Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children),
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
        LibraryTileDrag(:final type) =>
          canAddFromLibrary(store.layout.value, type),
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
    // lazy: the rows are built as they scroll into view (room lists).
    NewHomeCard frame(
            {required List<Widget> children,
            String? empty,
            Widget? leading,
            bool lazy = false}) =>
        NewHomeCard(
          title: cardTitle(manager, card),
          leading: leading,
          menu: menu,
          empty: empty,
          customizing: customizing,
          lazyRows: lazy,
          subtitle: customizing ? cardSummary(card) : null,
          onSettings: card.configurable
              ? () => editCardSettings(context, manager, card)
              : null,
          onRemove: () => store.save(store.layout.value.remove(card.id)),
          children: children,
        );

    List<Widget> rows(List<Room> rooms, String prefix,
        {bool collapse = true,
        void Function(Room room)? onTap,
        String? group,
        Widget Function(Room room)? trailing}) {
      const limit = NewHomeOverview.collapsedCount;
      final key = group == null ? card.id : "${card.id}/$group";
      final all = !collapse || expanded.contains(key);
      return [
        for (final room in all ? rooms : rooms.take(limit))
          if (trailing == null)
            RoomPanel(room,
                key: ValueKey("$prefix${room.localId}"),
                shouldShowAvatarForRoom: showAvatar,
                onTap: onTap == null ? null : () => onTap(room))
          else
            Row(key: ValueKey("$prefix${room.localId}"), children: [
              Expanded(
                  child: RoomPanel(room,
                      shouldShowAvatarForRoom: showAvatar,
                      onTap: onTap == null ? null : () => onTap(room))),
              trailing(room),
            ]),
        if (collapse && rooms.length > limit)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey("NewHomeShowMore-$key"),
              onPressed: () => setState(() {
                if (!expanded.remove(key)) expanded.add(key);
              }),
              child: Text(expanded.contains(key)
                  ? "Show less"
                  : "Show ${rooms.length - limit} more"),
            ),
          ),
      ];
    }

    switch (card.type) {
      case HomeLayout.recent:
        return frame(
          lazy: true,
          empty: card.unreadOnly ? "No unread rooms." : "No recent activity.",
          children: rows(recentRooms(card), "new-home-recent-${card.id}_",
              collapse: false),
        );
      case HomeLayout.favourites:
        return frame(
          lazy: true,
          empty: "Rooms you mark as favorite show here.",
          children: rows(favourites, "new-home-favourite_",
              collapse: false,
              onTap: (room) => EventBus.doOpenRoom(room.identifier,
                  clientId: room.client.identifier, openInSpace: false)),
        );
      case HomeLayout.otherRooms:
        return frame(
          lazy: true,
          empty: "Rooms you're in that aren't part of any space show here.",
          children: rows(otherRooms(), "new-home-other_", collapse: false),
        );
      case HomeLayout.unread:
        return frame(
          lazy: true,
          empty: "You're all caught up.",
          children: rows(roomsOf(roomHasUnread), "new-home-unread_"),
        );
      case HomeLayout.mentions:
        return frame(
          lazy: true,
          empty: "No unread mentions.",
          children: rows(
              roomsOf((r) => r.displayHighlightedNotificationCount > 0),
              "new-home-mentions_"),
        );
      case HomeLayout.lowPriority:
        return frame(
          lazy: true,
          empty: "Rooms you mark as low priority show here.",
          children: rows(roomsOf(isLowPriority), "new-home-low_"),
        );
      case HomeLayout.invites:
        return frame(
          lazy: true,
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
      case HomeLayout.liveCalls:
        return frame(
            leading: Icon(Icons.call_rounded,
                size: 18, color: Colors.green.shade400),
            children: [
              NewHomeLiveCallsCardBody(
                  key: ValueKey("new-home-live-calls_${card.id}"),
                  clientManager: manager,
                  filterClient: filterClient,
                  card: card),
            ]);
      case HomeLayout.textCard:
        return frame(children: [
          NewHomeTextCardBody(
              key: ValueKey("new-home-text_${card.id}"),
              clientManager: manager,
              card: card),
        ]);
      case HomeLayout.contacts:
        return frame(children: [
          NewHomeContactsCardBody(
              key: ValueKey("new-home-contacts_${filterClient?.identifier}"),
              clientManager: manager,
              filterClient: filterClient),
        ]);
      case HomeLayout.peoplePage:
      case HomeLayout.roomsPage:
      case HomeLayout.dmsPage:
        // Beside other cards: the page in a box about a screen tall, which
        // scrolls by itself. In customize mode a short, inert preview.
        final height = customizing
            ? 220.0
            : (MediaQuery.sizeOf(context).height * 0.8).clamp(420.0, 900.0);
        final page = SizedBox(
          height: height,
          child: wholePageBlock(card.type, manager, filterClient,
              phone: widget.phone, part: card.part),
        );
        return frame(children: [
          customizing ? IgnorePointer(child: page) : page,
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
          lazy: true,
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
      case HomeLayout.tagCard:
      case HomeLayout.allTagsCard:
        return tagsCard(context, card, frame, rows);
      default:
        return const SizedBox.shrink();
    }
  }

  /// The Tags card: All my tags or the picked tags, a section per tag or
  /// one list (newest first, each room once, with its tags as chips).
  Widget tagsCard(
      BuildContext context,
      HomeCard card,
      NewHomeCard Function(
              {required List<Widget> children,
              String? empty,
              Widget? leading,
              bool lazy})
          frame,
      List<Widget> Function(List<Room> rooms, String prefix,
              {bool collapse,
              void Function(Room room)? onTap,
              String? group,
              Widget Function(Room room)? trailing})
          rows) {
    final scheme = Theme.of(context).colorScheme;
    final all = card.type == HomeLayout.allTagsCard;
    final tags = all ? userTagsIn(manager) : card.tags;
    final leading = Icon(Icons.label_rounded, size: 18, color: scheme.primary);
    if (tags.isEmpty) {
      return frame(
          leading: leading,
          empty: all
              ? "Rooms you tag show here. Add a tag from a room's menu (Tags)."
              : "Pick tags for this card in its settings.",
          children: const []);
    }
    bool keep(Room r) => !card.unreadOnly || roomHasUnread(r);
    final empty = tags.length == 1
        ? "No rooms have the tag ${tagName(tags.single)} yet. Add it from a "
            "room's menu (Tags)."
        : "No rooms have these tags yet. Add one from a room's menu (Tags).";
    if (card.tagList || tags.length == 1) {
      final rooms =
          roomsOf((r) => keep(r) && tags.any((t) => roomHasTag(r, t)));
      return frame(
        lazy: true,
        leading: leading,
        empty: empty,
        children: rows(rooms, "new-home-tag-${card.id}_",
            trailing: tags.length == 1
                ? null
                : (room) => TagChips([
                      for (final t in tags)
                        if (roomHasTag(room, t)) t
                    ])),
      );
    }
    final groups = [
      for (final tag in tags)
        (tag, roomsOf((r) => keep(r) && roomHasTag(r, tag)))
    ].where((g) => g.$2.isNotEmpty).toList();
    return frame(
      lazy: true,
      leading: leading,
      empty: empty,
      children: [
        for (final (tag, rooms) in groups) ...[
          Padding(
            key: ValueKey("new-home-all-tags-${card.id}-$tag"),
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
            child: Row(spacing: 6, children: [
              Icon(Icons.label_outline_rounded,
                  size: 15, color: scheme.primary),
              Expanded(
                child: Text(tagName(tag),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
              ),
              Text("${rooms.length}",
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ]),
          ),
          ...rows(rooms, "new-home-all-tags-${card.id}-${tag}_", group: tag),
        ],
      ],
    );
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
          case "copy":
            copyTextPreset(card);
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
        if (card.type == HomeLayout.textCard && card.preset != null)
          menuItem("copy", Icons.content_copy_rounded, "Make a copy"),
        if (card.type == HomeLayout.otherRooms)
          menuItem("new_room", Icons.add_rounded, "New room…"),
        menuItem("up", Icons.arrow_upward_rounded, "Move up", enabled: up),
        menuItem("down", Icons.arrow_downward_rounded, "Move down",
            enabled: down),
        menuItem("hide", Icons.close_rounded, "Remove card"),
        menuItem(
            "customize", Icons.dashboard_customize_rounded, "Customize Home…"),
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

/// A whole page placed on a main page: People (contacts, requests,
/// invites) or the Rooms browser.
Widget wholePageBlock(String type, ClientManager manager, Client? filter,
        {required bool phone, String part = HomeCard.allParts}) =>
    switch (type) {
      HomeLayout.peoplePage => PeopleView(
          key: ValueKey("NewHomePeoplePage-$part"),
          clientManager: manager,
          filterClient: filter,
          phone: phone,
          only: PeopleView.partOf(part)),
      HomeLayout.dmsPage => NewHomeDirectMessages(
          key: const ValueKey("NewHomeDmsPage"),
          clientManager: manager,
          filterClient: filter,
          phone: phone),
      HomeLayout.roomsPage => NewHomeRooms(
          key: const ValueKey("NewHomeRoomsPage"),
          clientManager: manager,
          filterClient: filter,
          phone: phone),
      _ => const SizedBox.shrink(),
    };

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
    this.lazyRows = false,
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

  /// The rows are a list of rooms (or invites) that can be long: on the
  /// Overview the card is a [NewHomeCardSliver], which builds only the rows
  /// near the screen. Customize mode keeps the plain box (and ignores this).
  final bool lazyRows;

  BoxDecoration decoration(BuildContext context) => BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.surface,
      boxShadow: Theme.of(context).extension<ShadowSettings>()?.shadows);

  /// The note shown instead of rows, if any.
  Widget? emptyNote() => children.isEmpty && empty != null
      ? Padding(
          padding: const EdgeInsets.all(8), child: tiamat.Text.labelLow(empty!))
      : null;

  /// One row, 2 px above and below.
  static Widget row(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(0, 2, 0, 2), child: child);

  /// The header line (handle, title, ⋯ or settings and ✕).
  Widget header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

    return Padding(
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
    );
  }

  static const Widget separator = Padding(
    padding: EdgeInsets.fromLTRB(0, 4, 0, 0),
    child: tiamat.Seperator(padding: 0),
  );

  @override
  Widget build(BuildContext context) {
    final content = emptyNote() ??
        Column(children: [for (final child in children) row(child)]);

    return Container(
      decoration: decoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header(context),
        separator,
        Padding(
          padding: const EdgeInsets.all(8),
          child: customizing ? IgnorePointer(child: content) : content,
        ),
      ]),
    );
  }
}

/// A [NewHomeCard] as a sliver: the same box, header and rows, but the rows
/// are built only when they scroll near the screen, so a card listing a big
/// account's rooms doesn't keep a live row per room.
class NewHomeCardSliver extends StatelessWidget {
  const NewHomeCardSliver(this.card, {super.key});

  final NewHomeCard card;

  @override
  Widget build(BuildContext context) {
    final rows = card.children;
    // One flat list: the header, then the rows (or the empty note), with
    // the box's 8 px padding above the first row and below the last.
    return DecoratedSliver(
      decoration: card.decoration(context),
      sliver: SliverList.builder(
        itemCount: rows.isEmpty ? 2 : rows.length + 1,
        addSemanticIndexes: false,
        // An item holding the keyboard focus stays built when scrolled
        // away, so focus stays where it was, as in the Column.
        itemBuilder: (context, i) => _KeepAliveWhileFocused(child: item(i)),
      ),
    );
  }

  Widget item(int i) {
    final rows = card.children;
    if (i == 0) {
      return Builder(
          builder: (context) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [card.header(context), NewHomeCard.separator]));
    }
    if (rows.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(8),
          child: card.emptyNote() ?? const Column(children: []));
    }
    // Centred like the Column's children, and like them matched by
    // position when the list changes (the box's rows sit in unkeyed
    // paddings).
    return Padding(
      padding:
          EdgeInsets.fromLTRB(8, i == 1 ? 8 : 0, 8, i == rows.length ? 8 : 0),
      child: Center(child: NewHomeCard.row(rows[i - 1])),
    );
  }
}

/// Keeps a lazily built list item alive while something inside it has the
/// keyboard focus (like a text field in a ListView).
class _KeepAliveWhileFocused extends StatefulWidget {
  const _KeepAliveWhileFocused({required this.child});

  final Widget child;

  @override
  State<_KeepAliveWhileFocused> createState() => _KeepAliveWhileFocusedState();
}

class _KeepAliveWhileFocusedState extends State<_KeepAliveWhileFocused>
    with AutomaticKeepAliveClientMixin {
  bool focused = false;

  @override
  bool get wantKeepAlive => focused;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus == focused) return;
        focused = hasFocus;
        updateKeepAlive();
      },
      child: widget.child,
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
              Text("Card settings · ${HomeLayoutStore.instance.current.name}",
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

/// The dashed "＋ Add a card" tile at the bottom of Overview (not shown in
/// customize mode).
class AddCardTile extends StatelessWidget {
  const AddCardTile({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DashedOutline(
      color: scheme.outline,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          key: const ValueKey("NewHomeAddCardTile"),
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 6,
                children: [
                  Icon(Icons.add_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  Text("Add a card",
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                ]),
          ),
        ),
      ),
    );
  }
}

/// A room's tags as small chips (the Tags card's one list).
class TagChips extends StatelessWidget {
  const TagChips(this.tags, {super.key});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 4),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        for (final tag in tags.take(2))
          Container(
            constraints: const BoxConstraints(maxWidth: 90),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: scheme.primary.withAlpha(28),
                borderRadius: BorderRadius.circular(8)),
            child: Text(tagName(tag),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary)),
          ),
        if (tags.length > 2)
          Text("+${tags.length - 2}",
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
