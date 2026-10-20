import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/components/petname/petname_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/friends/friends_model.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const Color _green = Color(0xff3ba55d);

/// One person on one account's list.
class _Friend {
  _Friend(this.client, this.userId);
  final Client client;
  final String userId;
  Profile? profile;
  UserPresence presence = UserPresence(UserPresenceStatus.unknown);

  String get key => "${client.identifier}|$userId";

  String get name =>
      client.getComponent<PetNameComponent>()?.getPetName(userId) ??
      profile?.displayName ??
      userId;

  bool get online =>
      presence.status == UserPresenceStatus.online ||
      presence.status == UserPresenceStatus.unavailable;
}

/// Vommet: the Friends tab on Home (Vommet issue 93): your list with
/// presence, Active Now (calls with a friend in them) and suggestions from
/// your DMs. The list is private account data, shared by your devices.
class FriendsView extends StatefulWidget {
  const FriendsView({required this.phone, super.key});
  final bool phone;

  @override
  State<FriendsView> createState() => _FriendsViewState();
}

class _FriendsViewState extends State<FriendsView> {
  final Map<String, _Friend> friends = {};
  final List<StreamSubscription> subs = [];
  final List<StreamSubscription> roomSubs = [];
  Timer? roomRefresh;
  bool onlineOnly = true;
  String search = "";

  List<Client> get clients => [
        for (final c in clientManager?.clients ?? <Client>[])
          if (c.isLoggedIn() && c.getComponent<FriendsComponent>() != null) c
      ];

  @override
  void initState() {
    super.initState();
    for (final client in clients) {
      subs.add(client
          .getComponent<FriendsComponent>()!
          .onFriendsChanged
          .listen((_) => _loadFriends()));
      final presence = client.getComponent<UserPresenceComponent>();
      if (presence != null) {
        subs.add(presence.onPresenceChanged.listen((e) {
          final f = friends["${client.identifier}|${e.$1}"];
          if (f == null || !mounted) return;
          setState(() => f.presence = e.$2);
        }));
      }
    }
    _loadFriends();
    _watchRooms();
    // Rooms come and go; pick up new ones now and then.
    roomRefresh =
        Timer.periodic(const Duration(seconds: 30), (_) => _watchRooms());
  }

  @override
  void dispose() {
    for (final s in [...subs, ...roomSubs]) {
      s.cancel();
    }
    roomRefresh?.cancel();
    super.dispose();
  }

  void _watchRooms() {
    for (final s in roomSubs) {
      s.cancel();
    }
    roomSubs.clear();
    for (final client in clients) {
      for (final room in client.rooms) {
        final activities = room.getComponent<ActivitiesComponent>();
        if (activities == null) continue;
        roomSubs.add(activities.onSessionsChanged.listen((_) {
          if (mounted) setState(() {});
        }));
      }
    }
    if (mounted) setState(() {});
  }

  void _loadFriends() {
    final seen = <String>{};
    for (final client in clients) {
      for (final id in client.getComponent<FriendsComponent>()!.friends) {
        final f = _Friend(client, id);
        seen.add(f.key);
        if (friends.containsKey(f.key)) continue;
        friends[f.key] = f;
        _fetch(f);
      }
    }
    friends.removeWhere((key, _) => !seen.contains(key));
    if (mounted) setState(() {});
  }

  Future<void> _fetch(_Friend f) async {
    final profiles = f.client.getComponent<UserProfileComponent>();
    final presence = f.client.getComponent<UserPresenceComponent>();
    try {
      f.profile = await profiles?.getProfile(f.userId);
    } catch (_) {}
    try {
      if (presence != null)
        f.presence = await presence.getUserPresence(f.userId);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  List<(Client, String)> get suggestions {
    final result = <(Client, String)>[];
    for (final client in clients) {
      final dms = client.getComponent<DirectMessagesComponent>();
      if (dms == null) continue;
      final partners = dms.directMessageRooms
          .map(dms.getDirectMessagePartnerId)
          .whereType<String>();
      final listed = client.getComponent<FriendsComponent>()!.friends;
      for (final id in FriendsModel.suggestions(
          partners, listed, client.self?.identifier)) {
        result.add((client, id));
      }
    }
    return result;
  }

  List<(Client, ActiveCall)> get activeCalls {
    final result = <(Client, ActiveCall)>[];
    for (final client in clients) {
      final listed = client.getComponent<FriendsComponent>()!.friends;
      if (listed.isEmpty) continue;
      for (final call in FriendsModel.activeNow(
          client.rooms, listed, client.self?.identifier)) {
        result.add((client, call));
      }
    }
    return result;
  }

  Future<void> _openDm(Client client, String userId) async {
    final dms = client.getComponent<DirectMessagesComponent>();
    if (dms == null) return;
    final existing = dms.directMessageRooms
        .where((r) => dms.getDirectMessagePartnerId(r) == userId);
    final room = existing.isNotEmpty
        ? existing.first
        : await dms.createDirectMessage(userId);
    if (room != null) {
      EventBus.doOpenRoom(room.identifier, clientId: client.identifier);
    }
  }

  Future<void> _addFriendDialog() async {
    final client = clients.firstOrNull;
    if (client == null) return;
    final id = await AdaptiveDialog.show<String>(
      context,
      title: "Add friend",
      builder: (context) => const _AddFriendForm(),
    );
    if (id == null) return;
    await client.getComponent<FriendsComponent>()!.addFriends([id]);
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final calls = activeCalls;
    final query = search.trim().toLowerCase();
    final all = friends.values
        .where((f) =>
            query.isEmpty ||
            f.name.toLowerCase().contains(query) ||
            f.userId.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final shown = onlineOnly ? all.where((f) => f.online).toList() : all;
    final suggested = suggestions;
    final wide = !phone && MediaQuery.sizeOf(context).width > 1100;

    final list = ListView(
      padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 20, vertical: 12),
      children: [
        Row(spacing: 8, children: [
          _Chip("Online",
              selected: onlineOnly,
              onTap: () => setState(() => onlineOnly = true)),
          _Chip("All",
              selected: !onlineOnly,
              onTap: () => setState(() => onlineOnly = false)),
          const Spacer(),
          if (!phone) SizedBox(width: 240, child: _searchField()),
          tiamat.Button(
            text: "Add friend",
            onTap: _addFriendDialog,
          ),
        ]),
        if (phone)
          Padding(
              padding: const EdgeInsets.only(top: 10), child: _searchField()),
        if (!wide && calls.isNotEmpty) ...[
          const _SectionLabel("Active now"),
          SizedBox(
            height: 140,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final (client, call) in calls)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                      width: 240,
                      child: _ActiveCallCard(client, call, friends)),
                ),
            ]),
          ),
        ],
        _SectionLabel(
            "${onlineOnly ? "Online" : "All friends"} — ${shown.length}"),
        if (friends.isEmpty)
          const _Hint(
              "Your friends list is empty. Add people from your DMs below, or "
              "by their Matrix ID. Only you see your list.")
        else if (shown.isEmpty)
          _Hint(
              onlineOnly ? "None of your friends are online." : "No matches."),
        for (final f in shown)
          _FriendRow(
            f,
            compact: phone,
            onMessage: () => _openDm(f.client, f.userId),
            onRemove: () => f.client
                .getComponent<FriendsComponent>()!
                .removeFriend(f.userId),
          ),
        if (suggested.isNotEmpty) ...[
          Row(children: [
            const Expanded(child: _SectionLabel("Suggestions from your DMs")),
            TextButton(
              onPressed: () async {
                for (final client in clients) {
                  await client.getComponent<FriendsComponent>()!.addFriends([
                    for (final (c, id) in suggested)
                      if (c == client) id
                  ]);
                }
              },
              child: const Text("Add all"),
            ),
          ]),
          for (final (client, id) in suggested.take(8))
            _Suggestion(client, id,
                onAdd: () =>
                    client.getComponent<FriendsComponent>()!.addFriends([id])),
        ],
      ],
    );

    if (!wide) return list;

    final scheme = ColorScheme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: list),
      Container(
        width: 300,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(
                left: BorderSide(color: scheme.surfaceContainerHighest))),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          children: [
            const Text("Active Now",
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final (client, call) in calls)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActiveCallCard(client, call, friends),
              ),
            Text(
                calls.isEmpty
                    ? "Nobody on your list is in a call right now."
                    : "Only calls with at least one friend, in rooms you share.",
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    ]);
  }

  Widget _searchField() => TextField(
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: "Search friends",
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => setState(() => search = v),
      );
}

class _AddFriendForm extends StatefulWidget {
  const _AddFriendForm();

  @override
  State<_AddFriendForm> createState() => _AddFriendFormState();
}

class _AddFriendFormState extends State<_AddFriendForm> {
  final controller = TextEditingController();
  String? error;

  void submit() {
    final id = controller.text.trim();
    if (!FriendsModel.isUserId(id)) {
      setState(() => error = "Enter a full Matrix ID, like @name:server.org");
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const Text("Only you see your friends list. They aren't told."),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                  hintText: "@name:server.org", errorText: error),
              onSubmitted: (_) => submit(),
            ),
            tiamat.Button(text: "Add", onTap: submit),
          ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ColorScheme.of(context).onSurfaceVariant)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text,
            style: TextStyle(color: ColorScheme.of(context).onSurfaceVariant)),
      );
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar(this.friend, this.radius);
  final _Friend friend;
  final double radius;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: AlignmentDirectional.bottomEnd,
        children: [
          tiamat.Avatar(
            radius: radius,
            image: friend.profile?.avatar,
            placeholderText: friend.name,
            placeholderColor: friend.profile?.defaultColor,
          ),
          UserPanelView.createPresenceIcon(context, friend.presence.status),
        ],
      );
}

class _FriendRow extends StatelessWidget {
  const _FriendRow(this.friend,
      {required this.compact, required this.onMessage, required this.onRemove});
  final _Friend friend;
  final bool compact;
  final VoidCallback onMessage;
  final VoidCallback onRemove;

  String get status => switch (friend.presence) {
        UserPresence(message: final m?) => m.message,
        UserPresence(status: UserPresenceStatus.online) => "Online",
        UserPresence(status: UserPresenceStatus.unavailable) => "Away",
        UserPresence(status: UserPresenceStatus.offline) => "Offline",
        _ => "Presence unknown",
      };

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => UserProfile.show(context,
          client: friend.client, userId: friend.userId),
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 9),
        child: Row(spacing: 12, children: [
          _FriendAvatar(friend, compact ? 16 : 18),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Row(spacing: 6, children: [
                    Flexible(
                      child: Text(friend.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: friend.online
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant)),
                    ),
                    if (!compact)
                      Flexible(
                        child: Text(friend.userId,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ]),
                  Text(status,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ]),
          ),
          IconButton(
            tooltip: "Message",
            icon: const Icon(Icons.chat_bubble_rounded, size: 18),
            onPressed: onMessage,
          ),
          PopupMenuButton<int>(
            tooltip: "More",
            icon: const Icon(Icons.more_vert_rounded, size: 18),
            onSelected: (_) => onRemove(),
            itemBuilder: (_) =>
                const [PopupMenuItem(value: 0, child: Text("Remove friend"))],
          ),
        ]),
      ),
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion(this.client, this.userId, {required this.onAdd});
  final Client client;
  final String userId;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final dms = client.getComponent<DirectMessagesComponent>();
    final room = dms?.directMessageRooms
        .where((r) => dms.getDirectMessagePartnerId(r) == userId)
        .firstOrNull;
    final name = client.getComponent<PetNameComponent>()?.getPetName(userId) ??
        room?.displayName ??
        userId;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.surfaceContainerHighest)),
      child: Row(spacing: 10, children: [
        tiamat.Avatar(
          radius: 14,
          image: room?.avatar,
          placeholderText: name,
          placeholderColor: room?.defaultColor,
        ),
        Expanded(
            child: Text("$name · you have a DM",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500))),
        TextButton(onPressed: onAdd, child: const Text("Add")),
      ]),
    );
  }
}

class _ActiveCallCard extends StatelessWidget {
  const _ActiveCallCard(this.client, this.call, this.friends);
  final Client client;
  final ActiveCall call;
  final Map<String, _Friend> friends;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final people = [
      for (final id in call.friendsIn)
        friends["${client.identifier}|$id"] ?? _Friend(client, id)
    ];
    final names = people.length <= 2
        ? people.map((f) => f.name).join(" and ")
        : "${people[0].name}, ${people[1].name} +${people.length - 2}";
    final others = call.participants.length - call.friendsIn.length;
    final isDm = client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(call.room) ??
        false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.surfaceContainerHighest)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Row(spacing: 8, children: [
              SizedBox(
                width: 18.0 * people.length.clamp(1, 3) + 10,
                height: 30,
                child: Stack(children: [
                  for (var i = 0; i < people.length.clamp(0, 3); i++)
                    Positioned(
                        left: i * 18.0, child: _FriendAvatar(people[i], 13)),
                ]),
              ),
              Expanded(
                  child: Text(others > 0 ? "$names +$others" : names,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700))),
            ]),
            Row(spacing: 6, children: [
              const Icon(Icons.volume_up_rounded, size: 16, color: _green),
              Expanded(
                  child: Text(isDm ? "Call · DM" : call.room.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant))),
            ]),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                    backgroundColor: _green.withAlpha(45),
                    foregroundColor: const Color(0xff7fe0a3)),
                onPressed: () => EventBus.doOpenRoom(call.room.identifier,
                    clientId: client.identifier),
                child: const Text("Go to call"),
              ),
            ),
          ]),
    );
  }
}
