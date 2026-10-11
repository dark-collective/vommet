import 'dart:async';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/role.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import '../../client/room.dart';

class RoomMemberList extends StatefulWidget {
  const RoomMemberList(this.room,
      {this.leading = const [], this.listPadding = EdgeInsets.zero, super.key});
  final Room room;

  /// Vommet: slivers above the members in the same scroll view (the room
  /// banner, the label), so they scroll or collapse with the list.
  final List<Widget> leading;
  final EdgeInsets listPadding;

  @override
  State<RoomMemberList> createState() => _RoomMemberListState();

  static AdaptiveContextMenu userContextMenu(BuildContext context,
      {required String userId,
      required String userDisplayName,
      required Room room,
      required Widget child,
      required bool isSelf,
      Function? onUserKicked,
      Function? onUserBanned,
      Function? onUserRoleChanged}) {
    return AdaptiveContextMenu(
      items: [
        if (room.permissions.canChangeRoles)
          tiamat.ContextMenuItem(
              text: "Set Role",
              icon: Icons.shield,
              onPressed: () async {
                ErrorUtils.tryRun(context, () async {
                  var role = await AdaptiveDialog.pickOne(
                    context,
                    title: "Pick Role for $userDisplayName",
                    items: room.availableRoles,
                    itemBuilder: (context, item, callback) {
                      return SizedBox(
                        height: 50,
                        child: tiamat.TextButton(
                          item.name,
                          icon: item.icon,
                          onTap: callback,
                        ),
                      );
                    },
                  );

                  if (role != null) {
                    await room.setMemberRole(userId, role);
                    onUserRoleChanged?.call();
                  }
                });
              }),
        if (room.permissions.canKick && !isSelf)
          tiamat.ContextMenuItem(
              text: "Kick",
              icon: Icons.subdirectory_arrow_left_rounded,
              color: ColorScheme.of(context).error,
              onPressed: () async {
                if (await AdaptiveDialog.confirmation(context,
                        prompt:
                            "Are you sure you want to kick $userDisplayName from the room?") ==
                    true) {
                  ErrorUtils.tryRun(context, () async {
                    await room.kickUser(userId);
                    onUserKicked?.call();
                  });
                }
              }),
        if (room.permissions.canBan && !isSelf)
          tiamat.ContextMenuItem(
              text: "Ban",
              icon: Icons.shield,
              color: ColorScheme.of(context).error,
              onPressed: () async {
                if (await AdaptiveDialog.confirmation(context,
                        prompt:
                            "Are you sure you want to ban $userDisplayName from the room?") ==
                    true) {
                  ErrorUtils.tryRun(context, () async {
                    await room.banUser(userId);
                    onUserBanned?.call();
                  });
                }
              }),
      ],
      child: child,
    );
  }
}

class _RoomMemberListState extends State<RoomMemberList> {
  late List<Member> roomMembers;
  List<(Member, Role)>? importantMembers;
  bool loadingMoreMembers = false;
  bool isDirectMessageRoom = false;

  DirectMessagesComponent? directMessages;

  int limit = 100;

  StreamSubscription? _presenceSub;
  Timer? _presenceDebounce;
  StreamSubscription? _callSub;
  Timer? _callRefresh;
  Map<String, MemberActivity> _activities = const {};

  VoipRoomComponent? get _voip => widget.room.getComponent<VoipRoomComponent>();

  /// Vommet: who is in the room's call ("In voice"), and, while we are in it
  /// too, who is sharing their screen. Part of the Discord-style layout
  /// experiment.
  Map<String, MemberActivity> currentActivities() {
    final voip = _voip;
    if (voip == null || !preferences.experimentBannerLayout.value) {
      return const {};
    }
    final result = <String, MemberActivity>{
      for (final id in voip.getCurrentParticipants())
        id: MemberActivity.inVoice,
    };
    final session = voip.currentSession;
    if (session != null) {
      for (final stream in session.streams) {
        if (stream.type == VoipStreamType.screenshare) {
          result[stream.streamUserId] = MemberActivity.sharingScreen;
        }
      }
      final self = widget.room.client.self?.identifier;
      if (session.isSharingScreen && self != null) {
        result[self] = MemberActivity.sharingScreen;
      }
    }
    return result;
  }

  UserPresenceComponent? get _presence =>
      widget.room.client.getComponent<UserPresenceComponent>();

  @override
  void dispose() {
    _presenceSub?.cancel();
    _presenceDebounce?.cancel();
    _callSub?.cancel();
    _callRefresh?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    // Vommet: re-sort into online/offline sections as presence arrives.
    _presenceSub = _presence?.onPresenceChanged.listen((_) {
      _presenceDebounce?.cancel();
      _presenceDebounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() {});
      });
    });
    // Vommet: show who joins or leaves the call; screen sharing only shows
    // in our own session, so look again every few seconds while in one.
    _callSub = _voip?.onParticipantsChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _callRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _voip?.currentSession != null) setState(() {});
    });
    getInitialUsers();
    isDirectMessageRoom = widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;

    if (!widget.room.isMembersListComplete) {
      loadAllUsers();
    }

    super.initState();
  }

  void getInitialUsers() {
    var users = widget.room.membersList();
    var important = widget.room.importantMembers();

    users.removeWhere((element) =>
        important.any((i) => i.$1.identifier == element.identifier));

    roomMembers = users;
    importantMembers = important;
  }

  Future<void> loadAllUsers() async {
    setState(() {
      loadingMoreMembers = true;
    });

    var users = await widget.room.fetchMembersList();
    // Vommet: the list may have closed while the members were fetched.
    if (!mounted) return;
    var important = widget.room.importantMembers();

    // Vommet: drop every role holder from the plain list, by id (upstream
    // compared objects, only within the first [limit], so some appeared
    // twice).
    users.removeWhere(
        (u) => important.any((i) => i.$1.identifier == u.identifier));

    setState(() {
      roomMembers = users;
      loadingMoreMembers = false;
      importantMembers = important;
    });
  }

  /// Vommet: Discord-style sections. Role holders (Owner, Admin, ...) who
  /// aren't offline get a section per role; everyone else online goes under
  /// "Online"; members whose presence the server doesn't share go under
  /// "Unknown" (many servers disable presence, so unknown isn't offline);
  /// everyone known to be offline goes last, under "Offline".
  List<_MemberSection> buildSections() {
    // The online/offline split is part of the Discord-style layout
    // experiment; without it every member counts as "Members".
    final presence =
        preferences.experimentBannerLayout.value ? _presence : null;
    UserPresenceStatus statusOf(Member m) =>
        presence?.cachedPresence(m.identifier)?.status ??
        UserPresenceStatus.unknown;

    final sections = <_MemberSection>[];
    final byRole = <String, _MemberSection>{};
    final offline = <Member>[];
    for (final (member, role) in importantMembers ?? const <(Member, Role)>[]) {
      if (statusOf(member) == UserPresenceStatus.offline) {
        offline.add(member);
        continue;
      }
      byRole
          .putIfAbsent(role.name, () {
            final section = _MemberSection(role.name);
            sections.add(section);
            return section;
          })
          .members
          .add(member);
    }

    final online = _MemberSection("Online");
    // With presence on, "Unknown" is everyone whose server doesn't share it
    // (see MatrixUserPresenceComponent._presenceServers).
    final unknown = _MemberSection(presence == null ? "Members" : "Unknown");
    for (final member in roomMembers) {
      switch (statusOf(member)) {
        case UserPresenceStatus.offline:
          offline.add(member);
        case UserPresenceStatus.unknown:
          unknown.members.add(member);
        case UserPresenceStatus.online || UserPresenceStatus.unavailable:
          online.members.add(member);
      }
    }
    if (online.members.isNotEmpty) sections.add(online);
    if (unknown.members.isNotEmpty) sections.add(unknown);
    if (offline.isNotEmpty) {
      sections.add(
          _MemberSection("Offline", dimmed: true)..members.addAll(offline));
    }
    return sections;
  }

  /// Headers and rows in display order, stopping after [limit] members.
  /// Returns whether members were left out.
  (List<_MemberItem>, bool) buildItems() {
    final items = <_MemberItem>[];
    var shown = 0;
    for (final section in buildSections()) {
      if (shown >= limit) return (items, true);
      if (!isDirectMessageRoom) items.add(_MemberItem.header(section));
      for (var i = 0; i < section.members.length; i++) {
        if (shown >= limit) return (items, true);
        items.add(_MemberItem.member(section, section.members[i],
            first: i == 0, last: i == section.members.length - 1));
        shown++;
      }
    }
    return (items, false);
  }

  Widget buildMember(BuildContext context, Member member) {
    Widget result = UserPanel(
      key: ValueKey("room-user-list-user-${member.identifier}"),
      client: widget.room.client,
      initialMember: member,
      contextRoom: widget.room,
      userId: member.identifier,
      activity: _activities[member.identifier],
    );

    if (isDirectMessageRoom) {
      if (member.identifier == widget.room.client.self?.identifier) {
        return const SizedBox(height: 0);
      }
      result = Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: UserProfile(
          maxBioHeight: double.infinity,
          doSafeArea: false,
          key: ValueKey("room-user-list-user-${member.identifier}"),
          userId: member.identifier,
          bannerHeight: MediaQuery.of(context).mobile ? 200 : 120,
          client: widget.room.client,
          showMessageButton: false,
        ),
      );
    }

    return RoomMemberList.userContextMenu(context,
        userId: member.identifier,
        room: widget.room,
        userDisplayName: member.displayName,
        isSelf: member.identifier == widget.room.client.self!.identifier,
        child: result,
        onUserBanned: () =>
            roomMembers.removeWhere((i) => i.identifier == member.identifier),
        onUserKicked: () =>
            roomMembers.removeWhere((i) => i.identifier == member.identifier),
        onUserRoleChanged: () => loadAllUsers());
  }

  Widget buildHeader(BuildContext context, _MemberSection section) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Text(
        "${section.title} — ${section.members.length}",
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget buildRow(BuildContext context, _MemberItem item) {
    const radius = Radius.circular(12);
    Widget row = DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.only(
          topLeft: item.first ? radius : Radius.zero,
          topRight: item.first ? radius : Radius.zero,
          bottomLeft: item.last ? radius : Radius.zero,
          bottomRight: item.last ? radius : Radius.zero,
        ),
      ),
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(4, item.first ? 4 : 0, 4, item.last ? 4 : 0),
        child: buildMember(context, item.member!),
      ),
    );
    if (item.section.dimmed) row = Opacity(opacity: 0.55, child: row);
    return row;
  }

  @override
  Widget build(BuildContext context) {
    _activities = currentActivities();
    final (items, more) = buildItems();

    return CustomScrollView(slivers: [
      ...widget.leading,
      SliverPadding(
        padding: widget.listPadding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index < items.length) {
              final item = items[index];
              if (item.member == null)
                return buildHeader(context, item.section);
              if (isDirectMessageRoom)
                return buildMember(context, item.member!);
              return buildRow(context, item);
            }

            if (loadingMoreMembers && index == items.length) {
              return buildLoadingDisplay();
            }

            if (more && index == items.length) {
              // Vommet: load the next batch once the end of the list is built
              // (it nears the screen), instead of a "+N More" button.
              final before = limit;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && limit == before) {
                  setState(() => limit += 50);
                }
              });
              return buildLoadingDisplay();
            }

            return null;
          }),
        ),
      ),
    ]);
  }

  Widget buildLoadingDisplay() {
    return Shimmer(
      linearGradient: Shimmer.harshGradient,
      child: Column(
        children: [
          for (var i = 0; i < 15; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
              child: UserPanelView(
                displayName: "$i",
                shimmer: true,
                random: Random(i).nextDouble(),
              ),
            )
        ],
      ),
    );
  }
}

/// Vommet: one section of the member list ("Owner — 1", "Online — 12").
class _MemberSection {
  _MemberSection(this.title, {this.dimmed = false});
  final String title;
  final bool dimmed;
  final List<Member> members = [];
}

class _MemberItem {
  _MemberItem.header(this.section)
      : member = null,
        first = false,
        last = false;
  _MemberItem.member(this.section, Member this.member,
      {required this.first, required this.last});
  final _MemberSection section;
  final Member? member;
  final bool first;
  final bool last;
}
