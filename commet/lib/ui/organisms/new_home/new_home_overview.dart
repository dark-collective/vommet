import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/ui/atoms/room_panel.dart';
import 'package:commet/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (New Home): Overview, a stack of cards in the old Home's panel
/// style: Recent activity, Favourites (when you have any) and Standalone
/// rooms, each with a ⋯ menu to set it up, move it or hide it.
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

  @override
  State<NewHomeOverview> createState() => _NewHomeOverviewState();
}

class _NewHomeOverviewState extends State<NewHomeOverview> {
  final List<StreamSubscription> subs = [];
  final List<StreamSubscription> favouriteSubs = [];
  Client? filterClient;
  Timer? pending;

  ClientManager get manager => widget.clientManager;
  HomeLayoutStore get store => HomeLayoutStore.instance;

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
    listenToFavourites();
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
    for (final s in [...subs, ...favouriteSubs]) {
      s.cancel();
    }
    pending?.cancel();
    store.layout.removeListener(refreshNow);
    super.dispose();
  }

  void listenToFavourites() {
    for (final s in favouriteSubs) {
      s.cancel();
    }
    favouriteSubs.clear();
    for (final client in manager.clients) {
      favouriteSubs.addAll([
        client.favoriteRooms.onAdd.listen((_) => refreshSoon()),
        client.favoriteRooms.onRemove.listen((_) => refreshSoon()),
      ]);
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

  void clientsChanged() {
    if (!mounted) return;
    listenToFavourites();
    refreshNow();
  }

  bool inFilter(Room room) =>
      (filterClient == null || room.client == filterClient) &&
      !hiddenFromNewHome(room);

  static bool isDirectMessage(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ==
      true;

  List<Room> recentRooms(HomeCard card) => recentActivity<Room>(
        (filterClient?.rooms ?? manager.rooms).where(inFilter),
        card,
        lastEvent: (r) => r.lastEvent == null ? null : r.lastEventTimestamp,
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

  bool showAvatar(Room room) =>
      manager.clients.where((c) => c.hasRoom(room.identifier)).length > 1;

  @override
  Widget build(BuildContext context) {
    final layout = store.layout.value;
    final favourites = favouriteRooms();
    final cards = [
      for (final card in layout.visible)
        if (card.id != HomeLayout.favourites || favourites.isNotEmpty) card
    ];
    final hidden = layout.hidden.length;

    final children = <Widget>[
      IncomingInvitationsWidget(manager),
      for (final card in cards)
        Padding(
          key: ValueKey("NewHomeCard-${card.id}"),
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: buildCard(context, layout, card, favourites),
        ),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
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
    ];

    return ListView(
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
  }

  Widget buildCard(BuildContext context, HomeLayout layout, HomeCard card,
      List<Room> favourites) {
    switch (card.id) {
      case HomeLayout.recent:
        final rooms = recentRooms(card);
        return NewHomeCard(
          title: "Recent Activity",
          menu: cardMenu(context, layout, card),
          empty: card.unreadOnly ? "No unread rooms." : "No recent activity.",
          children: [
            for (final room in rooms)
              RoomPanel(room,
                  key: ValueKey("new-home-recent_${room.localId}"),
                  shouldShowAvatarForRoom: showAvatar)
          ],
        );
      case HomeLayout.favourites:
        return NewHomeCard(
          title: "Favourites",
          menu: cardMenu(context, layout, card),
          children: [
            for (final room in favourites)
              RoomPanel(room,
                  key: ValueKey("new-home-favourite_${room.localId}"),
                  shouldShowAvatarForRoom: showAvatar,
                  onTap: () => EventBus.doOpenRoom(room.identifier,
                      clientId: room.client.identifier, openInSpace: false))
          ],
        );
      default:
        final rooms = otherRooms();
        return NewHomeCard(
          title: "Standalone rooms",
          menu: cardMenu(context, layout, card),
          empty: "Rooms you're in that aren't part of any space show here.",
          children: [
            for (final room in rooms)
              RoomPanel(room,
                  key: ValueKey("new-home-other_${room.localId}"),
                  shouldShowAvatarForRoom: showAvatar)
          ],
        );
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
            showRecentSettings(context, card);
          case "new_room":
            GetOrCreateRoom.show(null, context,
                pickExisting: false, showAllRoomTypes: true);
          case "up":
            store.save(layout.move(card.id, -1));
          case "down":
            store.save(layout.move(card.id, 1));
          case "hide":
            store.save(layout.hide(card.id));
        }
      },
      itemBuilder: (context) => [
        if (card.id == HomeLayout.recent)
          menuItem("settings", Icons.tune_rounded, "Settings…"),
        if (card.id == HomeLayout.otherRooms)
          menuItem("new_room", Icons.add_rounded, "New room…"),
        menuItem("up", Icons.arrow_upward_rounded, "Move up", enabled: up),
        menuItem("down", Icons.arrow_downward_rounded, "Move down",
            enabled: down),
        menuItem("hide", Icons.visibility_off_rounded, "Hide card"),
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

  void showRecentSettings(BuildContext context, HomeCard card) {
    showDialog(
      context: context,
      builder: (context) => RecentActivitySettings(
        card: card,
        onChanged: (next) => store.save(store.layout.value.replace(next)),
      ),
    );
  }
}

/// One Overview card: the old Home panel look (tiamat Panel: radius 10,
/// header label, separator, 8 px padding, rows 2 px apart) with a ⋯ menu
/// in the header line.
class NewHomeCard extends StatelessWidget {
  const NewHomeCard({
    super.key,
    required this.title,
    required this.menu,
    required this.children,
    this.empty,
  });

  final String title;
  final Widget menu;
  final List<Widget> children;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadows = Theme.of(context).extension<ShadowSettings>();
    return Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: scheme.surface,
          boxShadow: shadows?.shadows),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(children: [
            Expanded(
                child: tiamat.Text.labelLow(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
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
          child: children.isEmpty && empty != null
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: tiamat.Text.labelLow(empty!))
              : Column(children: [
                  for (final child in children)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                        child: child)
                ]),
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
