import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/components/petname/petname_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/friends/friends_model.dart';
import 'package:commet/ui/organisms/friends/linked_accounts.dart';
import 'package:commet/ui/organisms/new_home/new_home_page_preview.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_store.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const Color _green = Color(0xff3ba55d);
const Color _away = Color(0xfffaa61a);

/// The People page's chip, kept while the app runs.
final ValueNotifier<PeopleTab> newHomePeopleTab =
    ValueNotifier(PeopleTab.contacts);

/// One contact on one account's list.
class _Contact {
  _Contact(this.client, this.userId);
  final Client client;
  final String userId;
  Profile? profile;
  UserPresence presence = UserPresence(UserPresenceStatus.unknown);

  String get key => "${client.identifier}|$userId";

  String get name =>
      client.getComponent<PetNameComponent>()?.getPetName(userId) ??
      profile?.displayName ??
      userId;

  /// The person's other linked accounts, set on the main one (Vommet
  /// issue 638); empty for a plain entry.
  List<_Contact> others = const [];

  List<_Contact> get accounts => [this, ...others];

  /// The account whose status the person shows: the most active one.
  _Contact get active =>
      FriendsModel.mostActive(accounts, (c) => c.presence.status);

  /// The person's status: their most active account's.
  UserPresenceStatus get status => active.presence.status;
  String? get statusMessage => active.presence.message?.message;

  /// [statusMessage], naming the server when the status comes from an
  /// account other than the main one.
  String? get subtitle {
    final line = PeopleModel.contactSubtitle(status, statusMessage);
    if (active == this || line == null) return line;
    return "$line · on ${active.userId.split(":").skip(1).join(":")}";
  }
}

/// Vommet (New Home step 2): People. Contacts (your private list, sorted by
/// presence, with Active Now on wide windows), Invites (direct-message
/// invites received and sent) and Blocked (the account's ignore list).
/// The contact list is the same private account data as the Friends tab
/// (`im.nether.vommet.friends`), shown here as contacts.
class PeopleView extends StatefulWidget {
  const PeopleView({
    super.key,
    required this.clientManager,
    required this.filterClient,
    required this.phone,
    this.only,
    this.preview,
    this.onSeeAll,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final bool phone;

  /// As a card beside other cards (Vommet issue 782): only this many
  /// contacts, no search, suggestions or Active Now panel, and "See all"
  /// calls [onSeeAll].
  final int? preview;
  final VoidCallback? onSeeAll;

  /// Only this part, without the Contacts / Invites / Blocked buttons: a
  /// People card set to one part (Home tab views, Vommet issue 674).
  final PeopleTab? only;

  /// The part a People card's "part" setting names, or null for all.
  static PeopleTab? partOf(String part) =>
      PeopleTab.values.where((t) => t.name == part).firstOrNull;

  @override
  State<PeopleView> createState() => _PeopleViewState();
}

/// Contacts with their profiles and presence, and the calls they're in,
/// for the People page and the Overview's Active Now and Contacts cards.
mixin _PeopleData<T extends StatefulWidget> on State<T> {
  final Map<String, _Contact> contacts = {};
  final Map<String, Profile?> profiles = {};
  final List<StreamSubscription> _peopleSubs = [];
  final List<StreamSubscription> roomSubs = [];
  Timer? roomRefresh;
  Client? filterClient;

  ClientManager get peopleManager;

  List<Client> get clients => [
        for (final c in peopleManager.clients)
          if (c.isLoggedIn() &&
              (filterClient == null || c == filterClient) &&
              c.getComponent<FriendsComponent>() != null)
            c
      ];

  /// Starts following contacts, presence and calls; call from initState.
  void startPeople(Client? filter) {
    filterClient = filter;
    _peopleSubs.add(EventBus.setFilterClient.stream.listen((client) {
      filterClient = client;
      _watch();
    }));
    _watch();
    // Rooms (and their calls) come and go; pick up new ones now and then.
    roomRefresh =
        Timer.periodic(const Duration(seconds: 30), (_) => _watchRooms());
  }

  /// Stops what [startPeople] started; call from dispose.
  void stopPeople() {
    for (final s in [..._peopleSubs, ...roomSubs, ...clientSubs]) {
      s.cancel();
    }
    roomRefresh?.cancel();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }

  final List<StreamSubscription> clientSubs = [];

  void _watch() {
    for (final s in clientSubs) {
      s.cancel();
    }
    clientSubs.clear();
    for (final client in clients) {
      clientSubs.add(client
          .getComponent<FriendsComponent>()!
          .onFriendsChanged
          .listen((_) => _loadContacts()));
      final presence = client.getComponent<UserPresenceComponent>();
      if (presence != null) {
        clientSubs.add(presence.onPresenceChanged.listen((e) {
          final c = contacts["${client.identifier}|${e.$1}"];
          if (c == null || !mounted) return;
          setState(() => c.presence = e.$2);
        }));
      }
      final blocking = client.getComponent<UserBlockingComponent>();
      if (blocking != null) {
        clientSubs.add(blocking.onChanged.listen((_) => rebuild()));
      }
    }
    _loadContacts();
    _watchRooms();
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
        roomSubs.add(activities.onSessionsChanged.listen((_) => rebuild()));
      }
    }
    rebuild();
  }

  void _loadContacts() {
    final seen = <String>{};
    for (final client in clients) {
      for (final id in client.getComponent<FriendsComponent>()!.friends) {
        final c = _Contact(client, id);
        seen.add(c.key);
        if (contacts.containsKey(c.key)) continue;
        contacts[c.key] = c;
        _fetch(c);
      }
    }
    contacts.removeWhere((key, _) => !seen.contains(key));
    _linkPeople();
    rebuild();
  }

  /// Linked accounts' keys mapped to their person's main account key.
  Map<String, String> mainKeys = {};

  void _linkPeople() {
    final keys = <String, String>{};
    for (final c in contacts.values) {
      c.others = const [];
    }
    for (final client in clients) {
      keys.addAll(FriendsModel.mainKeys(client.identifier,
          client.getComponent<FriendsComponent>()!.linkedPeople));
    }
    for (final MapEntry(key: alt, value: main) in keys.entries) {
      final m = contacts[main];
      final a = contacts[alt];
      if (m == null || a == null) continue;
      m.others = [...m.others, a];
    }
    mainKeys = keys;
  }

  /// One entry per person: linked accounts show as their main account.
  Iterable<_Contact> get people =>
      contacts.values.where((c) => !mainKeys.containsKey(c.key));

  /// A contact row for [c], with its Message, Accounts, Link and Remove.
  Widget contactRow(BuildContext context, _Contact c,
          {required Key key, required bool compact, required double radius}) =>
      _ContactRow(
        key: key,
        name: c.name,
        userId: c.userId,
        status: c.status,
        subtitle: c.subtitle,
        accountCount: c.accounts.length,
        avatar: _Avatar(
            name: c.name, profile: c.profile, status: c.status, radius: radius),
        compact: compact,
        onTap: () =>
            UserProfile.show(context, client: c.client, userId: c.userId),
        onMessage: () => messageContact(context, c),
        onAccounts: () => LinkedAccounts.showAccounts(context,
            client: c.client,
            name: c.name,
            accounts: [
              for (final a in c.accounts)
                LinkedAccount(
                    a.userId,
                    PeopleModel.contactSubtitle(
                            a.presence.status, a.presence.message?.message) ??
                        (a.presence.status == UserPresenceStatus.offline
                            ? "Offline"
                            : "Presence unknown"),
                    main: a == c)
            ],
            candidates: linkCandidates(c)),
        onLink: () => LinkedAccounts.linkAnother(context,
            client: c.client,
            mainId: c.userId,
            name: c.name,
            candidates: linkCandidates(c)),
        onRemove: () => attempt(
            "remove the contact",
            () => c.client
                .getComponent<FriendsComponent>()!
                .removeFriends([for (final a in c.accounts) a.userId])),
      );

  /// The account's other contacts (ID, name) that [c] could link with.
  List<(String, String)> linkCandidates(_Contact c) {
    final own = {for (final a in c.accounts) a.key};
    return [
      for (final o in people)
        if (o.client == c.client && !own.contains(o.key)) (o.userId, o.name)
    ];
  }

  Future<void> _fetch(_Contact c) async {
    final presence = c.client.getComponent<UserPresenceComponent>();
    c.profile = await profile(c.client, c.userId);
    try {
      if (presence != null) {
        c.presence = await presence.getUserPresence(c.userId);
      }
    } catch (_) {}
    rebuild();
  }

  /// A person's profile, fetched once per account.
  Future<Profile?> profile(Client client, String userId) async {
    final key = "${client.identifier}|$userId";
    if (profiles.containsKey(key)) return profiles[key];
    profiles[key] = null;
    try {
      final p =
          await client.getComponent<UserProfileComponent>()?.getProfile(userId);
      profiles[key] = p;
      rebuild();
      return p;
    } catch (_) {
      return null;
    }
  }

  /// A name for anyone: your pet name for them, their profile name, their
  /// Matrix ID.
  String nameOf(Client client, String userId) {
    final pet = client.getComponent<PetNameComponent>()?.getPetName(userId);
    if (pet != null) return pet;
    final key = "${client.identifier}|$userId";
    final contact = contacts[key];
    if (contact?.profile?.displayName case final n?) return n;
    if (!profiles.containsKey(key)) profile(client, userId);
    return profiles[key]?.displayName ?? userId;
  }

  Profile? profileOf(Client client, String userId) {
    final key = "${client.identifier}|$userId";
    if (!profiles.containsKey(key)) profile(client, userId);
    return contacts[key]?.profile ?? profiles[key];
  }

  /// Calls with a contact in them, from the MatrixRTC sessions in rooms you
  /// share, keyed by "account|room"; people as "account|user".
  Map<String, Room> callRooms = {};

  List<CallFacts> get calls {
    final result = <CallFacts>[];
    final rooms = <String, Room>{};
    for (final client in clients) {
      final listed = client.getComponent<FriendsComponent>()!.friends;
      if (listed.isEmpty) continue;
      final self = client.self?.identifier;
      for (final room in client.rooms) {
        final sessions =
            room.getComponent<ActivitiesComponent>()?.getSessions() ?? const [];
        for (final session in sessions) {
          if (session.thirdparty) continue;
          final people = session.participants.where((p) => p != self).toSet();
          final contactsIn = people.where(listed.contains).toList()..sort();
          if (contactsIn.isEmpty) continue;
          DateTime? lastJoined;
          for (final p in contactsIn) {
            final at = session.joinedAt[p];
            if (at != null && (lastJoined == null || at.isAfter(lastJoined))) {
              lastJoined = at;
            }
          }
          final key = "${client.identifier}|${room.identifier}";
          rooms[key] = room;
          // A person with several accounts counts once, as their main.
          final persons = <String>{
            for (final p in contactsIn)
              mainKeys["${client.identifier}|$p"] ?? "${client.identifier}|$p"
          };
          result.add(CallFacts(
            roomKey: key,
            roomName: _isDm(room) ? "a DM" : room.displayName,
            lastJoined: lastJoined,
            participants: [
              for (final p in people) "${client.identifier}|$p",
            ],
            contactsIn: persons.toList(),
          ));
        }
      }
    }
    callRooms = rooms;
    return result;
  }

  static bool _isDm(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ==
      true;

  List<ActiveNowEntry> get activeNow => PeopleModel.activeNow(calls, [
        for (final c in people)
          ContactFacts(c.key, c.name, c.status, statusMessage: c.statusMessage)
      ]);

  /// Runs [action], reporting a failure instead of throwing.
  Future<void> attempt(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Log.w("People: couldn't $what: $e");
      if (!mounted) return;
      final text = e is InviteCancelNotAllowed
          ? InviteCancelNotAllowed.message
          : "Couldn't $what.";
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  /// Opens [c]'s direct message (made if there is none), asking which
  /// account when they have several.
  void messageContact(BuildContext context, _Contact c) =>
      LinkedAccounts.message(context,
          client: c.client,
          clients: peopleManager.clients,
          name: c.name,
          accounts: [for (final a in c.accounts) a.userId],
          open: (id) => LinkedAccounts.openDm(context,
              client: c.client, clients: peopleManager.clients, userId: id));

  void joinVoice(VoiceActivity activity) {
    final room = callRooms[activity.roomKey];
    if (room == null) return;
    EventBus.doOpenRoom(room.identifier, clientId: room.client.identifier);
  }

  /// Vommet issue 811: tapping an Active Now card. One person not in a
  /// call: their DM. In a call, or several people: a choice of "Join
  /// voice" and "Message <name>" for each (the first six).
  Future<void> tapActive(BuildContext context, List<_Contact> people,
      ContactActivity activity) async {
    switch (PeopleModel.activeTap(people.length,
        inVoice: activity is VoiceActivity)) {
      case ActiveTap.nothing:
        return;
      case ActiveTap.message:
        messageContact(context, people.first);
        return;
      case ActiveTap.choose:
        break;
    }
    const most = 6;
    final picked = await AdaptiveDialog.show<Object>(
      context,
      title: PeopleModel.activeNowTitle([for (final p in people) p.name],
          activity is VoiceActivity ? activity.others : 0),
      builder: (dialog) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (activity is VoiceActivity)
          ListTile(
            key: const ValueKey("NewHomeActiveChoiceJoin"),
            leading: const Icon(Icons.volume_up_rounded, color: _green),
            title: Text("Join voice in ${activity.roomName}"),
            onTap: () => Navigator.of(dialog).pop(activity),
          ),
        for (final p in people.take(most))
          ListTile(
            key: ValueKey("NewHomeActiveChoiceMessage-${p.key}"),
            leading: const Icon(Icons.chat_bubble_outline_rounded),
            title: Text("Message ${p.name}"),
            onTap: () => Navigator.of(dialog).pop(p),
          ),
        if (people.length > most)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text("and ${people.length - most} more on the People page",
                style: TextStyle(
                    fontSize: 12,
                    color: ColorScheme.of(dialog).onSurfaceVariant)),
          ),
      ]),
    );
    if (!context.mounted) return;
    switch (picked) {
      case final VoiceActivity voice:
        joinVoice(voice);
      case final _Contact person:
        messageContact(context, person);
    }
  }

  Widget activeCard(BuildContext context, ActiveNowEntry entry) {
    final scheme = ColorScheme.of(context);
    final people = [
      for (final key in entry.userIds)
        if (contacts[key] case final c?) c
    ];
    final activity = entry.activity;
    final others = activity is VoiceActivity ? activity.others : 0;
    final title =
        PeopleModel.activeNowTitle([for (final p in people) p.name], others);

    final (IconData? icon, String line) = switch (activity) {
      VoiceActivity(:final roomName) => (
          Icons.volume_up_rounded,
          "In voice · $roomName"
        ),
      StatusActivity(:final message) => (null, message),
      PresenceActivity(:final status) => (
          null,
          status == UserPresenceStatus.online ? "Online" : "Away"
        ),
    };

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.surfaceContainerHighest)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey("NewHomeActiveCard-${entry.userIds.join(",")}"),
        onTap:
            people.isEmpty ? null : () => tapActive(context, people, activity),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                            left: i * 18.0,
                            child: _Avatar(
                                name: people[i].name,
                                profile: people[i].profile,
                                status: people[i].status,
                                radius: 13)),
                    ]),
                  ),
                  Expanded(
                      child: Text(title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700))),
                ]),
                Row(spacing: 6, children: [
                  if (icon != null) Icon(icon, size: 16, color: _green),
                  Expanded(
                      child: Text(line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant))),
                ]),
                if (activity is VoiceActivity)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      key: ValueKey("NewHomeActiveJoin-${activity.roomKey}"),
                      style: TextButton.styleFrom(
                          backgroundColor: _green.withAlpha(45),
                          foregroundColor: const Color(0xff7fe0a3)),
                      onPressed: () => joinVoice(activity),
                      child: const Text("Join"),
                    ),
                  ),
              ]),
        ),
      ),
    );
  }
}

class _PeopleViewState extends State<PeopleView> with _PeopleData {
  final TextEditingController searchController = TextEditingController();
  String search = "";

  NewHomeInvites get invites => NewHomeInvites.instance;
  PeopleTab get tab => widget.only ?? newHomePeopleTab.value;

  @override
  ClientManager get peopleManager => widget.clientManager;

  @override
  void initState() {
    super.initState();
    invites.attach(widget.clientManager);
    invites.refreshSoon();
    newHomePeopleTab.addListener(rebuild);
    invites.received.addListener(rebuild);
    invites.sent.addListener(rebuild);
    startPeople(widget.filterClient);
  }

  @override
  void dispose() {
    stopPeople();
    newHomePeopleTab.removeListener(rebuild);
    invites.received.removeListener(rebuild);
    invites.sent.removeListener(rebuild);
    searchController.dispose();
    super.dispose();
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

  Future<void> addContactDialog() async {
    final client = clients.firstOrNull;
    if (client == null) return;
    final id = await AdaptiveDialog.show<String>(
      context,
      title: "Add contact",
      builder: (context) => _AddContactForm(client),
    );
    if (id == null) return;
    await client.getComponent<FriendsComponent>()!.addFriends([id]);
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final entries = activeNow;
    final wide = !phone && MediaQuery.sizeOf(context).width > 1100;
    final received = invites.received.value
        .where((i) => filterClient == null || i.client == filterClient)
        .toList();
    final sent = invites.sent.value
        .where((i) => filterClient == null || i.client == filterClient)
        .toList();

    final content = switch (tab) {
      PeopleTab.contacts => contactsPane(context),
      PeopleTab.invites => invitesPane(context, received, sent),
      PeopleTab.blocked => blockedPane(context),
    };

    final preview = widget.preview != null;
    final list = ListView(
      shrinkWrap: preview,
      physics: preview ? const NeverScrollableScrollPhysics() : null,
      padding: preview
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(horizontal: phone ? 10 : 20, vertical: 12),
      children: [
        if (widget.only == null || tab == PeopleTab.contacts)
          chipsRow(context, received.length),
        ...content,
      ],
    );

    if (preview ||
        !wide ||
        entries.isEmpty ||
        (widget.only != null && tab != PeopleTab.contacts)) {
      return list;
    }

    final scheme = ColorScheme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: list),
      Container(
        key: const ValueKey("NewHomeActiveNow"),
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
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: activeCard(context, e),
              ),
            Text(
                "Calls with at least one contact, in rooms you share, and "
                "status messages.",
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    ]);
  }

  Widget chipsRow(BuildContext context, int receivedCount) {
    final phone = widget.phone;
    final chips = Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
      for (final t
          in widget.only == null ? PeopleTab.values : const <PeopleTab>[])
        ChoiceChip(
          mouseCursor: WidgetStateMouseCursor.clickable,
          key: ValueKey("NewHomePeopleChip-${t.name}"),
          label: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            Text(t.label),
            if (t == PeopleTab.invites && receivedCount > 0)
              NotificationBadge(receivedCount,
                  key: const ValueKey("NewHomePeopleInvitesBadge")),
          ]),
          selected: tab == t,
          showCheckmark: false,
          onSelected: (_) => newHomePeopleTab.value = t,
        ),
    ]);
    return Row(children: [
      Expanded(
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: chips),
      ),
      if (tab == PeopleTab.contacts)
        phone
            ? IconButton(
                key: const ValueKey("NewHomePeopleAdd"),
                tooltip: "Add contact",
                icon: const Icon(Icons.person_add_alt_1_rounded),
                onPressed: addContactDialog)
            : tiamat.Button(
                key: const ValueKey("NewHomePeopleAdd"),
                text: "Add contact",
                onTap: addContactDialog,
              ),
    ]);
  }

  Widget searchField() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 38,
          child: TextField(
            key: const ValueKey("NewHomePeopleSearch"),
            controller: searchController,
            textAlignVertical: TextAlignVertical.center,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: ColorScheme.of(context).surfaceContainerLowest,
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: "Search contacts",
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
      );

  List<Widget> contactsPane(BuildContext context) {
    final q = search.trim();
    final shown = people
        .where((c) => c.accounts
            .any((a) => PeopleModel.matchesPerson(q, a.name, a.userId)))
        .toList()
      ..sort((a, b) => PeopleModel.compareContacts(
          a.status, a.name, a.userId, b.status, b.name, b.userId));
    final suggested = suggestions;
    final preview = widget.preview;
    if (preview != null) {
      return [
        _SectionLabel("Contacts — ${shown.length}"),
        if (contacts.isEmpty)
          const _Hint("No contacts yet. Add people from your DMs, or by their "
              "Matrix ID.")
        else if (shown.isEmpty)
          const _Hint("No matches."),
        for (final c in shown.take(preview))
          contactRow(context, c,
              key: ValueKey("NewHomeContact-${c.key}"),
              compact: widget.phone,
              radius: 18),
        if (shown.length > preview || suggested.isNotEmpty)
          NewHomeSeeAll(total: shown.length, onTap: widget.onSeeAll ?? () {}),
      ];
    }
    return [
      searchField(),
      _SectionLabel("Contacts — ${shown.length}"),
      if (contacts.isEmpty)
        const _Hint(
            "No contacts yet. Add people from your DMs below, or by their "
            "Matrix ID. Only you see your contacts; they aren't told.")
      else if (shown.isEmpty)
        const _Hint("No matches."),
      for (final c in shown)
        contactRow(context, c,
            key: ValueKey("NewHomeContact-${c.key}"),
            compact: widget.phone,
            radius: 18),
      if (suggested.isNotEmpty) ...[
        Row(children: [
          const Expanded(child: _SectionLabel("Suggestions from your DMs")),
          TextButton(
            onPressed: () => attempt("add the contacts", () async {
              for (final client in clients) {
                await client.getComponent<FriendsComponent>()!.addFriends([
                  for (final (c, id) in suggested)
                    if (c == client) id
                ]);
              }
            }),
            child: const Text("Add all"),
          ),
        ]),
        for (final (client, id) in suggested.take(8))
          _Suggestion(client, id,
              onAdd: () => attempt(
                  "add the contact",
                  () => client
                      .getComponent<FriendsComponent>()!
                      .addFriends([id]))),
      ],
    ];
  }

  List<Widget> invitesPane(BuildContext context, List<AccountInvite> received,
      List<AccountSentInvite> sent) {
    final now = DateTime.now();
    final phone = widget.phone;
    return [
      const _Note("Matrix has no friend requests. These are direct-message "
          "invites."),
      _SectionLabel("Received — ${received.length}"),
      if (received.isEmpty) const _Hint("No invites waiting for you."),
      for (final i in received)
        _InviteRow(
          key: ValueKey("NewHomeInvite-${i.invite.facts.roomId}"),
          avatar: _Avatar(
              name: nameOf(i.client, i.invite.facts.inviterId ?? "?"),
              profile: i.invite.facts.inviterId == null
                  ? null
                  : profileOf(i.client, i.invite.facts.inviterId!),
              radius: 18),
          name: i.invite.facts.inviterId == null
              ? "Someone"
              : nameOf(i.client, i.invite.facts.inviterId!),
          notAContact: i.invite.notAContact,
          line: PeopleModel.receivedLine(i.invite, now),
          compact: phone,
          actions: [
            if (phone) ...[
              IconButton(
                  key: ValueKey("NewHomeInviteAccept-${i.invite.facts.roomId}"),
                  tooltip: "Accept",
                  color: _green,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => attempt(
                      "accept the invite", () => NewHomeInvites.accept(i))),
              IconButton(
                  key:
                      ValueKey("NewHomeInviteDecline-${i.invite.facts.roomId}"),
                  tooltip: "Decline",
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => attempt(
                      "decline the invite", () => NewHomeInvites.decline(i))),
            ] else ...[
              FilledButton(
                  key: ValueKey("NewHomeInviteAccept-${i.invite.facts.roomId}"),
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  onPressed: () => attempt(
                      "accept the invite", () => NewHomeInvites.accept(i)),
                  child: const Text("Accept")),
              OutlinedButton(
                  key:
                      ValueKey("NewHomeInviteDecline-${i.invite.facts.roomId}"),
                  onPressed: () => attempt(
                      "decline the invite", () => NewHomeInvites.decline(i)),
                  child: const Text("Decline")),
            ],
            PopupMenuButton<String>(
              tooltip: "More",
              icon: const Icon(Icons.more_vert_rounded, size: 18),
              onSelected: (value) {
                final inviter = i.invite.facts.inviterId;
                switch (value) {
                  case "profile":
                    if (inviter != null) {
                      UserProfile.show(context,
                          client: i.client, userId: inviter);
                    }
                  case "block":
                    attempt(
                        "block them", () => NewHomeInvites.blockAndDecline(i));
                }
              },
              itemBuilder: (_) => [
                if (i.invite.facts.inviterId != null)
                  const PopupMenuItem(
                      value: "profile", child: Text("View profile")),
                if (i.invite.notAContact &&
                    i.invite.facts.inviterId != null &&
                    i.client.getComponent<UserBlockingComponent>() != null)
                  const PopupMenuItem(
                      value: "block", child: Text("Block and decline")),
              ],
            ),
          ],
        ),
      _SectionLabel("Sent — ${sent.length}"),
      if (sent.isEmpty)
        const _Hint("Nobody is waiting to join a DM you started."),
      for (final s in sent)
        _InviteRow(
          key: ValueKey("NewHomeSent-${s.invite.roomId}-${s.invite.userId}"),
          avatar: _Avatar(
              name: nameOf(s.client, s.invite.userId),
              profile: profileOf(s.client, s.invite.userId),
              radius: 18),
          name: nameOf(s.client, s.invite.userId),
          notAContact: false,
          line: PeopleModel.sentLine(s.invite, now),
          compact: phone,
          actions: [
            OutlinedButton(
                key: ValueKey(
                    "NewHomeSentCancel-${s.invite.roomId}-${s.invite.userId}"),
                onPressed: () => attempt(
                    "cancel the invite", () => NewHomeInvites.cancel(s)),
                child: const Text("Cancel")),
          ],
        ),
    ];
  }

  List<Widget> blockedPane(BuildContext context) {
    final blocked = <(Client, String)>[
      for (final client in clients)
        for (final id
            in client.getComponent<UserBlockingComponent>()?.blockedUsers ??
                const <String>[])
          (client, id)
    ];
    return [
      const _Note("Blocked people can't message or invite you; they aren't "
          "told."),
      _SectionLabel("Blocked — ${blocked.length}"),
      if (blocked.isEmpty) const _Hint("You haven't blocked anyone."),
      for (final (client, id) in blocked)
        _InviteRow(
          key: ValueKey("NewHomeBlocked-$id"),
          avatar: _Avatar(
              name: nameOf(client, id),
              profile: profileOf(client, id),
              radius: 18),
          name: nameOf(client, id),
          notAContact: false,
          line: id,
          compact: widget.phone,
          actions: [
            OutlinedButton(
                key: ValueKey("NewHomeUnblock-$id"),
                onPressed: () => attempt(
                    "unblock them",
                    () => client
                        .getComponent<UserBlockingComponent>()!
                        .unblock(id)),
                child: const Text("Unblock")),
          ],
        ),
    ];
  }
}

/// A picture with a presence dot for online and away only (unknown is
/// never shown as offline).
class _Avatar extends StatelessWidget {
  const _Avatar(
      {required this.name, this.profile, this.status, required this.radius});
  final String name;
  final Profile? profile;
  final UserPresenceStatus? status;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final dot = s != null && PeopleModel.showsPresenceDot(s);
    final size = (radius * 0.6).clamp(8.0, 12.0);
    return Stack(clipBehavior: Clip.none, children: [
      tiamat.Avatar(
        radius: radius,
        image: profile?.avatar,
        placeholderText: name,
        placeholderColor: profile?.defaultColor,
      ),
      if (dot)
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: s == UserPresenceStatus.online ? _green : _away,
              shape: BoxShape.circle,
              border: Border.all(
                  color: ColorScheme.of(context).surfaceContainer, width: 2),
            ),
          ),
        ),
    ]);
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow(
      {super.key,
      required this.name,
      required this.userId,
      required this.status,
      required this.subtitle,
      required this.accountCount,
      required this.avatar,
      required this.compact,
      required this.onTap,
      required this.onMessage,
      required this.onAccounts,
      required this.onLink,
      required this.onRemove});
  final String name;
  final String userId;
  final UserPresenceStatus status;
  final String? subtitle;

  /// How many linked Matrix accounts the person has (Vommet issue 638).
  final int accountCount;
  final VoidCallback onAccounts;
  final VoidCallback onLink;
  final Widget avatar;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onMessage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final active = PeopleModel.showsPresenceDot(status);
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 9),
        child: Row(spacing: 12, children: [
          avatar,
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Row(spacing: 6, children: [
                    Flexible(
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: active
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant)),
                    ),
                    if (accountCount > 1) AccountsTag("$accountCount accounts"),
                    if (!compact)
                      Flexible(
                        child: Text(userId,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ]),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 1,
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
            onSelected: (v) => switch (v) {
              0 => onRemove(),
              1 => onAccounts(),
              _ => onLink(),
            },
            itemBuilder: (_) => [
              if (accountCount > 1)
                const PopupMenuItem(value: 1, child: Text("Accounts")),
              const PopupMenuItem(
                  value: 2, child: Text("Link another account")),
              const PopupMenuItem(value: 0, child: Text("Remove contact")),
            ],
          ),
        ]),
      ),
    );
  }
}

/// A received or sent invite, or a blocked person.
class _InviteRow extends StatelessWidget {
  const _InviteRow(
      {super.key,
      required this.avatar,
      required this.name,
      required this.notAContact,
      required this.line,
      required this.compact,
      required this.actions});
  final Widget avatar;
  final String name;
  final bool notAContact;
  final String line;
  final bool compact;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 6 : 8),
      child: Row(spacing: 12, children: [
        avatar,
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Row(spacing: 6, children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  if (notAContact) const _NotAContactTag(),
                ]),
                Text(line,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ]),
        ),
        Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: actions),
      ]),
    );
  }
}

class _NotAContactTag extends StatelessWidget {
  const _NotAContactTag();

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey("NewHomeNotAContact"),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: const Color(0xff2b2b2b),
            borderRadius: BorderRadius.circular(6)),
        child: const Text("Not a contact",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xffb0b0b0))),
      );
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ColorScheme.of(context).onSurfaceVariant)),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10)),
      child: Row(spacing: 8, children: [
        Icon(Icons.info_outline_rounded,
            size: 16, color: scheme.onSurfaceVariant),
        Expanded(
            child: Text(text,
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
      ]),
    );
  }
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

// The Add contact lookup, as the Friends tab's Add friend (same list, same
// checks), worded for contacts.

class _AddContactForm extends StatefulWidget {
  const _AddContactForm(this.client);
  final Client client;

  @override
  State<_AddContactForm> createState() => _AddContactFormState();
}

/// Looks people up as you type, DM partners first, then the homeserver's
/// user directory, and checks a typed Matrix ID exists, so a typo can't add
/// the wrong person or nobody.
class _AddContactFormState extends State<_AddContactForm> {
  final controller = TextEditingController();
  final debouncer = Debouncer(delay: const Duration(milliseconds: 350));
  List<(String, String)> directory = [];
  bool searching = false;
  String? checkedId;
  bool? exists;
  bool checking = false;
  int lookupSeq = 0;

  FriendsComponent get component =>
      widget.client.getComponent<FriendsComponent>()!;

  Map<String, String> get dmPartners {
    final dms = widget.client.getComponent<DirectMessagesComponent>();
    final petnames = widget.client.getComponent<PetNameComponent>();
    return {
      for (final room in dms?.directMessageRooms ?? <Room>[])
        if (dms!.getDirectMessagePartnerId(room) case final id?)
          id: petnames?.getPetName(id) ?? room.displayName,
    };
  }

  @override
  void dispose() {
    debouncer.cancel();
    controller.dispose();
    super.dispose();
  }

  void onChanged(String text) {
    final term = FriendsModel.directoryTerm(text);
    final id = text.trim();
    // A new lookup supersedes any still in flight, whatever order the
    // answers come back in (Vommet issue 736).
    final seq = ++lookupSeq;
    setState(() {
      directory =
          term.length >= 2 ? FriendsModel.stillMatching(text, directory) : [];
      searching = term.length >= 2;
      checkedId = FriendsModel.isUserId(id) ? id : null;
      exists = null;
      checking = checkedId != null;
    });
    debouncer.cancel();
    if (term.length >= 2) debouncer.run(() => lookup(text, seq));
  }

  Future<void> lookup(String text, int seq) async {
    final id = text.trim();
    final checkTyped = FriendsModel.isUserId(id);
    final results =
        await component.searchDirectory(FriendsModel.directoryTerm(text));
    if (!mounted || seq != lookupSeq) return;
    setState(() {
      directory = results;
      searching = false;
    });
    if (checkTyped && !results.any((r) => r.$1 == id)) {
      final found = await component.accountExists(id);
      if (!mounted || seq != lookupSeq) return;
      setState(() {
        exists = found;
        checking = false;
      });
    } else if (checkTyped) {
      setState(() {
        exists = true;
        checking = false;
      });
    }
  }

  void pick(String userId) => Navigator.of(context).pop(userId);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final text = controller.text.trim();
    final rows = FriendsModel.lookup(text,
        dmPartners: dmPartners,
        directory: directory,
        friends: component.friends,
        selfId: widget.client.self?.identifier);
    final typedId = FriendsModel.isUserId(text) ? text : null;
    final typedListed = typedId != null && rows.any((r) => r.userId == typedId);

    return SizedBox(
      width: 420,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            const Text("Only you see your contacts. They aren't told."),
            TextField(
              key: const ValueKey("NewHomeAddContactField"),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: "Name or @name:server.org",
                suffixIcon: searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
              onChanged: onChanged,
              onSubmitted: (_) {
                // Enter only adds an exact, known-good match, never a guess.
                final exact = rows
                    .where((r) => r.userId == typedId && !r.alreadyFriend)
                    .firstOrNull;
                if (exact != null) {
                  pick(exact.userId);
                } else if (typedId != null && !typedListed && exists == true) {
                  pick(typedId);
                }
              },
            ),
            if (text.isEmpty && rows.isNotEmpty)
              const _SectionLabel("People you have DMs with"),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(shrinkWrap: true, children: [
                for (final c in rows)
                  _CandidateRow(widget.client, c, onAdd: () => pick(c.userId)),
                if (typedId != null && !typedListed)
                  _TypedIdRow(typedId,
                      checking: checking && checkedId == typedId,
                      exists: checkedId == typedId ? exists : null,
                      alreadyContact: component.friends.contains(typedId),
                      onAdd: () => pick(typedId)),
              ]),
            ),
            if (text.isNotEmpty &&
                rows.isEmpty &&
                typedId == null &&
                !searching)
              Text(
                  "Nobody found. Try their full Matrix ID, like @name:server.org.",
                  style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow(this.client, this.candidate, {required this.onAdd});
  final Client client;
  final FriendCandidate candidate;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final c = candidate;
    final dms = client.getComponent<DirectMessagesComponent>();
    final room = c.fromDm
        ? dms?.directMessageRooms
            .where((r) => dms.getDirectMessagePartnerId(r) == c.userId)
            .firstOrNull
        : null;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(10),
      onTap: c.alreadyFriend ? null : onAdd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(spacing: 10, children: [
          room != null
              ? tiamat.Avatar(
                  radius: 16,
                  image: room.avatar,
                  placeholderText: c.name,
                  placeholderColor: room.defaultColor)
              : _ProfileAvatar(client, c.userId, c.name,
                  key: ValueKey(c.userId)),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(spacing: 6, children: [
                Flexible(
                  child: Text(c.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (c.fromDm) const _Tag("DM"),
              ]),
              Text(c.userId,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ]),
          ),
          c.alreadyFriend
              ? Text("Contact",
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
              : TextButton(onPressed: onAdd, child: const Text("Add")),
        ]),
      ),
    );
  }
}

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar(this.client, this.userId, this.name, {super.key});
  final Client client;
  final String userId;
  final String name;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  Profile? profile;

  @override
  void initState() {
    super.initState();
    widget.client
        .getComponent<UserProfileComponent>()
        ?.getProfile(widget.userId)
        .then((p) {
      if (mounted) setState(() => profile = p);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) => tiamat.Avatar(
        radius: 16,
        image: profile?.avatar,
        placeholderText: widget.name,
        placeholderColor: profile?.defaultColor,
      );
}

class _TypedIdRow extends StatelessWidget {
  const _TypedIdRow(this.userId,
      {required this.checking,
      required this.exists,
      required this.alreadyContact,
      required this.onAdd});
  final String userId;
  final bool checking;
  final bool? exists;
  final bool alreadyContact;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final (icon, color, note) = switch ((checking, exists)) {
      (true, _) => (
          Icons.hourglass_empty_rounded,
          scheme.onSurfaceVariant,
          "Checking this account…"
        ),
      (_, true) => (Icons.check_circle_rounded, _green, "Account found"),
      (_, false) => (
          Icons.error_rounded,
          scheme.error,
          "No account with this ID. Check the spelling."
        ),
      _ => (
          Icons.help_rounded,
          scheme.onSurfaceVariant,
          "Couldn't check this account. Add it only if you're sure."
        ),
    };
    final canAdd = !checking && exists != false && !alreadyContact;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(spacing: 10, children: [
        SizedBox(width: 32, child: Icon(icon, size: 22, color: color)),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(userId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(alreadyContact ? "Already a contact" : note,
                style: TextStyle(
                    fontSize: 12.5,
                    color: exists == false
                        ? scheme.error
                        : scheme.onSurfaceVariant)),
          ]),
        ),
        TextButton(onPressed: canAdd ? onAdd : null, child: const Text("Add")),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
          color: scheme.primary.withAlpha(40),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: scheme.primary)),
    );
  }
}

/// Vommet (New Home step 3): the Overview's Active Now card, the same
/// entries as the People page's Active Now panel.
class NewHomeActiveNowCardBody extends StatefulWidget {
  const NewHomeActiveNowCardBody(
      {super.key, required this.clientManager, required this.filterClient});

  final ClientManager clientManager;
  final Client? filterClient;

  @override
  State<NewHomeActiveNowCardBody> createState() => _ActiveNowCardState();
}

class _ActiveNowCardState extends State<NewHomeActiveNowCardBody>
    with _PeopleData {
  @override
  ClientManager get peopleManager => widget.clientManager;

  @override
  void initState() {
    super.initState();
    startPeople(widget.filterClient);
  }

  @override
  void dispose() {
    stopPeople();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = PeopleModel.mostRecentFirst(
        activeNow, (key) => contacts[key]?.presence.lastActive);
    if (entries.isEmpty) {
      return const _Hint("Nobody's active right now. Contacts who are online "
          "or in a call show here.");
    }
    // One row, most recent first; swipe sideways for more (Vommet issue
    // 673). On a phone a card leaves part of the next one showing.
    return LayoutBuilder(builder: (context, constraints) {
      final width =
          constraints.maxWidth < 300 ? constraints.maxWidth * 0.85 : 260.0;
      return SingleChildScrollView(
        key: const ValueKey("NewHomeActiveNowRow"),
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, e) in entries.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            SizedBox(width: width, child: activeCard(context, e)),
          ],
        ]),
      );
    });
  }
}

/// Vommet (New Home step 3): the Overview's Contacts card, your contacts
/// online first, the People page's order.
class NewHomeContactsCardBody extends StatefulWidget {
  const NewHomeContactsCardBody(
      {super.key, required this.clientManager, required this.filterClient});

  final ClientManager clientManager;
  final Client? filterClient;

  /// Rows shown before "Show N more".
  static const int collapsedCount = 8;

  @override
  State<NewHomeContactsCardBody> createState() => _ContactsCardState();
}

class _ContactsCardState extends State<NewHomeContactsCardBody>
    with _PeopleData {
  bool expanded = false;

  @override
  ClientManager get peopleManager => widget.clientManager;

  @override
  void initState() {
    super.initState();
    startPeople(widget.filterClient);
  }

  @override
  void dispose() {
    stopPeople();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = people.toList()
      ..sort((a, b) => PeopleModel.compareContacts(
          a.status, a.name, a.userId, b.status, b.name, b.userId));
    if (shown.isEmpty) {
      return const _Hint("No contacts yet. Add people on the People page.");
    }
    const limit = NewHomeContactsCardBody.collapsedCount;
    final rows = expanded ? shown : shown.take(limit).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in rows)
        contactRow(context, c,
            key: ValueKey("NewHomeCardContact-${c.key}"),
            compact: true,
            radius: 16),
      if (shown.length > limit)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => expanded = !expanded),
            child: Text(
                expanded ? "Show less" : "Show ${shown.length - limit} more"),
          ),
        ),
    ]);
  }
}
