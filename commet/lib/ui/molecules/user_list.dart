import 'dart:async';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/matrix/power_level_tags.dart';
import 'package:commet/client/role.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/shimmer_loading.dart';
import 'package:commet/ui/molecules/member_find.dart';
import 'package:commet/ui/molecules/name_history_view.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart'
    show DashedOutline;
import 'package:commet/ui/organisms/share_history/share_history.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_banned_users.dart'
    show BannedUsersView;
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import '../../client/room.dart';
import 'package:commet/config/room_layout_options.dart';

class RoomMemberList extends StatefulWidget {
  const RoomMemberList(
    this.room, {
    this.leading = const [],
    this.trailing = const [],
    this.listPadding = EdgeInsets.zero,
    this.controller,
    this.scrollBehavior,
    this.directMessage,
    this.findBox = false,
    this.onInvite,
    super.key,
  });
  final Room room;

  /// Vommet: the find box, pinned under [leading] (with the invite button
  /// when [onInvite] is set; it gets the typed text, or null).
  final bool findBox;
  final void Function(String? query)? onInvite;

  /// Vommet ("New room info page"): shows the room as a direct chat (the
  /// other person's profile) or as a list, following who is in it now; null
  /// asks m.direct once.
  final bool? directMessage;

  /// Vommet: for a scrollbar drawn by the parent (ScrollbarBelowHeader).
  final ScrollController? controller;
  final ScrollBehavior? scrollBehavior;

  /// Vommet: slivers above the members in the same scroll view (the room
  /// banner, the label), so they scroll or collapse with the list.
  final List<Widget> leading;

  /// Vommet: slivers below the members (a DM's "Shared in this chat").
  final List<Widget> trailing;
  final EdgeInsets listPadding;

  @override
  State<RoomMemberList> createState() => _RoomMemberListState();

  static AdaptiveContextMenu userContextMenu(
    BuildContext context, {
    required String userId,
    required String userDisplayName,
    required Room room,
    required Widget child,
    required bool isSelf,
    Function? onUserKicked,
    Function? onUserBanned,
    Function? onUserRoleChanged,
  }) {
    // Vommet issue 475: the name in the dialogs follows redacted mode.
    final shownName = RedactionScope.of(context).name(userDisplayName, userId);
    return AdaptiveContextMenu(
      items: [
        // Vommet issue 744: their copy of this room's history, however they
        // join.
        if (!isSelf &&
            room is MatrixRoom &&
            ShareHistory.canShare(room, userId))
          tiamat.ContextMenuItem(
            text: ShareHistoryStrings.menuItem,
            icon: Icons.history,
            onPressed: () => ShareHistory.show(context, room, userId),
          ),
        if (room.permissions.canChangeRoles)
          tiamat.ContextMenuItem(
            text: "Set Role",
            icon: Icons.shield,
            onPressed: () async {
              ErrorUtils.tryRun(context, () async {
                var role = await AdaptiveDialog.pickOne(
                  context,
                  title: "Pick Role for $shownName",
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
            },
          ),
        // Vommet identity per place (R7): moderators see who is behind
        // the name shown here.
        ...NameHistoryView.menuItems(
          context,
          room: room,
          userId: userId,
          isSelf: isSelf,
        ),
        if (room.permissions.canKick && !isSelf)
          tiamat.ContextMenuItem(
            text: "Kick",
            icon: Icons.subdirectory_arrow_left_rounded,
            color: ColorScheme.of(context).error,
            onPressed: () async {
              if (await AdaptiveDialog.confirmation(
                    context,
                    prompt:
                        "Are you sure you want to kick $shownName from the room?",
                  ) ==
                  true) {
                ErrorUtils.tryRun(context, () async {
                  await room.kickUser(userId);
                  onUserKicked?.call();
                });
              }
            },
          ),
        if (room.permissions.canBan && !isSelf)
          tiamat.ContextMenuItem(
            text: "Ban",
            icon: Icons.shield,
            color: ColorScheme.of(context).error,
            onPressed: () async {
              if (await AdaptiveDialog.confirmation(
                    context,
                    prompt:
                        "Are you sure you want to ban $shownName from the room?",
                  ) ==
                  true) {
                ErrorUtils.tryRun(context, () async {
                  await room.banUser(userId);
                  onUserBanned?.call();
                });
              }
            },
          ),
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
  StreamSubscription? _membersSub;
  Timer? _membersDebounce;
  StreamSubscription? _hideOfflineSub;

  /// Vommet: the find box's text, its debounced query, and the picked
  /// membership chip.
  final _findController = TextEditingController();
  final _findFocus = FocusNode(debugLabel: "member-panel-find");
  Timer? _findDebounce;
  String _query = "";
  MemberMembership _membership = MemberMembership.joined;

  /// Lowercased names and IDs per membership, built on the first search
  /// and again after the members change.
  final Map<MemberMembership, List<MemberFindKey>> _findKeys = {};

  /// Vommet issue 762: members "Hide offline members" would leave out (or
  /// leaves out) in the last build, for the dashed row under the list.
  int _hideable = 0;

  /// Vommet issue 906: hidden members have no row, and a row is what asks
  /// the server for presence, so the hidden ones are looked up here, one at
  /// a time, each once per list.
  final Set<String> _presenceAsked = {};
  final List<String> _presenceQueue = [];
  bool _presenceLookupRunning = false;

  /// The dashed row's place at the end of the list; while that place is
  /// below the panel's bottom edge, a copy of the row sticks to the edge.
  final _toggleRowKey = GlobalKey();
  bool _pinToggleRow = false;
  bool _pinCheckScheduled = false;

  String memberListHiddenCount(int count) => Intl.message(
        "$count offline or unknown hidden",
        args: [count],
        name: "memberListHiddenCount",
        desc:
            "Member list: dashed row under the list while offline members are hidden",
      );

  String memberListHideableCount(int count) => Intl.message(
        "$count offline or unknown",
        args: [count],
        name: "memberListHideableCount",
        desc:
            "Member list: dashed row under the list while offline members are shown",
      );

  String get memberListShowOffline => Intl.message(
        "Show",
        name: "memberListShowOffline",
        desc: "Member list: button that shows the hidden offline members again",
      );

  String get memberListHideButton => Intl.message(
        "Hide",
        name: "memberListHideButton",
        desc: "Member list: button that hides offline members",
      );
  Map<String, MemberActivity> _activities = const {};

  VoipRoomComponent? get _voip => widget.room.getComponent<VoipRoomComponent>();

  /// Vommet: who is in the room's call ("In voice"), and, while we are in it
  /// too, who is sharing their screen. Shown while "Show who's in the call"
  /// (Layout settings) is on.
  Map<String, MemberActivity> currentActivities() {
    final voip = _voip;
    if (voip == null || !memberListCallActivity.value) {
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
    _membersSub?.cancel();
    _membersDebounce?.cancel();
    _hideOfflineSub?.cancel();
    _findDebounce?.cancel();
    _findController.dispose();
    _findFocus.dispose();
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
    // Vommet: members and roles that reach the room after the list opened
    // (a member fetch, history paging, someone joining) show up without
    // reopening it.
    _membersSub = widget.room.onMembersChanged.listen((_) {
      _membersDebounce?.cancel();
      _membersDebounce = Timer(
        const Duration(milliseconds: 300),
        refreshMembers,
      );
    });
    // Vommet issue 762: one setting for every room, also switched in
    // Layout settings.
    _hideOfflineSub = memberListHideOffline.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _findController.addListener(onFindChanged);
    getInitialUsers();
    isDirectMessageRoom = widget.directMessage ??
        widget.room.client
            .getComponent<DirectMessagesComponent>()
            ?.isRoomDirectMessage(widget.room) ??
        false;

    if (!widget.room.isMembersListComplete) {
      loadAllUsers();
    }

    super.initState();
  }

  @override
  void didUpdateWidget(covariant RoomMemberList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.directMessage case final direct?) isDirectMessageRoom = direct;
  }

  void getInitialUsers() {
    var users = widget.room.membersList();
    var important = widget.room.importantMembers();

    users.removeWhere(
      (element) => important.any((i) => i.$1.identifier == element.identifier),
    );

    roomMembers = users;
    importantMembers = important;
    _findKeys.clear();
  }

  /// Vommet: filters as the user types, after a short pause. The first
  /// keystroke in a room whose list is incomplete loads all members.
  void onFindChanged() {
    _findDebounce?.cancel();
    final text = _findController.text;
    if (text.trim().isEmpty) {
      if (_query.isNotEmpty) setState(() => _query = "");
      return;
    }
    if (!widget.room.isMembersListComplete && !loadingMoreMembers) {
      loadAllUsers();
    }
    _findDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  List<MemberFindKey> findKeys(MemberMembership membership) =>
      _findKeys.putIfAbsent(membership, () {
        final members = membership == MemberMembership.joined
            ? [...?importantMembers?.map((i) => i.$1), ...roomMembers]
            : widget.room.membersWithMembership(membership);
        return [for (final m in members) MemberFindKey(m)];
      });

  /// Vommet: rebuild the list from the room's current members and roles.
  /// While the room's own list is incomplete, members fetched earlier stay,
  /// unless the room now knows they left or were kicked or banned.
  void refreshMembers() {
    if (!mounted || loadingMoreMembers) return;
    var important = widget.room.importantMembers();
    var users = refreshedPlainMembers(
      current: widget.room.membersList(),
      previous: roomMembers,
      complete: widget.room.isMembersListComplete,
      hasLeft: widget.room.memberHasLeft,
      roleHolderIds: {for (final i in important) i.$1.identifier},
    );

    setState(() {
      roomMembers = users;
      importantMembers = important;
      _findKeys.clear();
    });
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
      (u) => important.any((i) => i.$1.identifier == u.identifier),
    );

    setState(() {
      roomMembers = users;
      loadingMoreMembers = false;
      importantMembers = important;
      _findKeys.clear();
    });
  }

  /// Vommet: Discord-style sections. Role holders (Owner, Admin, ...) who
  /// aren't offline get a section per role; everyone else online goes under
  /// "Online"; members whose presence the server doesn't share go under
  /// "Unknown" (many servers disable presence, so unknown isn't offline);
  /// everyone known to be offline goes last, under "Offline".
  List<_MemberSection> buildSections() {
    // The online/offline split is the Member list setting (Layout
    // settings); "By role" counts every member as "Members".
    final presence = memberListOnlineSections.value ? _presence : null;
    UserPresenceStatus statusOf(Member m) =>
        presence?.cachedPresence(m.identifier)?.status ??
        UserPresenceStatus.unknown;

    final sections = <_MemberSection>[];
    final byRole = <String, _MemberSection>{};
    final offline = <Member>[];
    for (final (member, role) in importantMembers ?? const <(Member, Role)>[]) {
      final status = statusOf(member);
      if (status == UserPresenceStatus.offline) {
        offline.add(member);
        continue;
      }
      final section = byRole.putIfAbsent(role.name, () {
        final section = _MemberSection(role.name, role: role);
        sections.add(section);
        return section;
      });
      section.members.add(member);
      if (presence != null && status == UserPresenceStatus.unknown) {
        section.unknownPresence.add(member.identifier);
      }
    }

    final online = _MemberSection("Online");
    // With presence on, "Unknown" is everyone whose server doesn't share it
    // (see MatrixUserPresenceComponent._presenceServers).
    final unknown = presence == null
        ? _MemberSection("Members")
        : _MemberSection("Unknown", hideable: true);
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
        _MemberSection("Offline", dimmed: true, hideable: true)
          ..members.addAll(offline),
      );
    }
    return sections;
  }

  /// Vommet: everyone in the room's call goes first, under "In call",
  /// whatever their presence says (people bridged from another chat have
  /// none and sat under Offline while live in the call); people sharing their
  /// screen lead it. [_activities] is empty unless the Discord-style layout
  /// is on, and then this changes nothing.
  List<_MemberSection> withInCallFirst(List<_MemberSection> sections) {
    if (_activities.isEmpty || isDirectMessageRoom) return sections;
    final inCall = _MemberSection("In call");
    final sharing = <Member>[];
    for (final section in sections) {
      section.members.removeWhere((member) {
        final activity = _activities[member.identifier];
        if (activity == null) return false;
        (activity == MemberActivity.sharingScreen ? sharing : inCall.members)
            .add(member);
        return true;
      });
    }
    if (sharing.isEmpty && inCall.members.isEmpty) return sections;
    inCall.members.insertAll(0, sharing);
    return [inCall, ...sections.where((s) => s.members.isNotEmpty)];
  }

  /// Vommet issue 762: "Hide offline members" works with the online/offline
  /// sections only ("By role" has no presence to go by), and never in DMs.
  bool get canHideOffline =>
      !isDirectMessageRoom &&
      memberListOnlineSections.value &&
      _presence != null;

  /// Vommet issue 762: counts the offline members and those whose presence
  /// is unknown, role holders included, into [_hideable], and leaves them
  /// out while "Hide offline members" is on. People in the call were moved
  /// to "In call" already and stay; so do you.
  List<_MemberSection> withoutOffline(List<_MemberSection> sections) {
    _hideable = 0;
    if (!canHideOffline) return sections;
    final hide = memberListHideOffline.value;
    final self = widget.room.client.self?.identifier;
    bool hideable(_MemberSection section, Member member) =>
        member.identifier != self &&
        (section.hideable ||
            section.unknownPresence.contains(member.identifier));
    for (final section in sections) {
      _hideable += section.members.where((m) => hideable(section, m)).length;
      if (hide) {
        section.members.removeWhere((m) {
          if (!hideable(section, m)) return false;
          queuePresenceLookup(m.identifier);
          return true;
        });
      }
    }
    if (_presenceQueue.isNotEmpty && !_presenceLookupRunning) {
      _presenceLookupRunning = true;
      Future.microtask(lookUpHiddenPresence);
    }
    return sections.where((s) => s.members.isNotEmpty).toList();
  }

  /// Vommet issue 906: queues a hidden member whose presence was never
  /// looked up (no cached presence at all).
  void queuePresenceLookup(String userId) {
    if (_presence?.cachedPresence(userId) != null) return;
    if (_presenceAsked.add(userId)) _presenceQueue.add(userId);
  }

  /// Vommet issue 906: looks up the queued members' presence, about ten a
  /// second so big rooms don't flood the server, and re-sorts the list
  /// after every ten and at the end. Stops when the list closes or the
  /// offline members are shown again (their rows ask for themselves).
  Future<void> lookUpHiddenPresence() async {
    var done = 0;
    while (
        _presenceQueue.isNotEmpty && mounted && memberListHideOffline.value) {
      final userId = _presenceQueue.removeAt(0);
      try {
        await _presence?.getUserPresence(userId);
      } catch (_) {}
      if (++done % 10 == 0 && mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _presenceLookupRunning = false;
    if (done % 10 != 0 && mounted) setState(() {});
  }

  /// Vommet issue 762: the dashed row under the list: "12 offline or
  /// unknown · Hide", or "12 offline or unknown hidden · Show".
  Widget buildHideOfflineRow(BuildContext context, {Key? key}) {
    final hidden = memberListHideOffline.value;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: DashedOutline(
        color: scheme.outlineVariant,
        radius: 12,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => memberListHideOffline.set(!hidden),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              child: Row(
                children: [
                  Icon(
                    hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hidden
                          ? memberListHiddenCount(_hideable)
                          : memberListHideableCount(_hideable),
                      overflow: TextOverflow.ellipsis,
                      style: style?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hidden ? memberListShowOffline : memberListHideButton,
                    style: style?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sticks the dashed row to the panel's bottom edge while its place at
  /// the end of the list is out of sight below it (or not built yet), so a
  /// long list never hides it.
  void schedulePinCheck() {
    if (_pinCheckScheduled) return;
    _pinCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinCheckScheduled = false;
      if (!mounted) return;
      final pin = toggleRowNeedsPin(_toggleRowKey.currentContext);
      if (pin != _pinToggleRow) setState(() => _pinToggleRow = pin);
    });
  }

  /// Headers and rows in display order, stopping after [limit] members.
  /// Returns whether members were left out.
  (List<_MemberItem>, bool) buildItems() {
    final items = <_MemberItem>[];
    var shown = 0;
    for (final section in withoutOffline(withInCallFirst(buildSections()))) {
      if (shown >= limit) return (items, true);
      if (!isDirectMessageRoom) items.add(_MemberItem.header(section));
      for (var i = 0; i < section.members.length; i++) {
        if (shown >= limit) return (items, true);
        items.add(
          _MemberItem.member(
            section,
            section.members[i],
            first: i == 0,
            last: i == section.members.length - 1,
          ),
        );
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
      memberList: true,
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
          // Vommet issue 602: the Profile tab's contact button.
          showContactButton: true,
        ),
      );
    }

    return RoomMemberList.userContextMenu(
      context,
      userId: member.identifier,
      room: widget.room,
      userDisplayName: member.displayName,
      isSelf: member.identifier == widget.room.client.self!.identifier,
      child: result,
      onUserBanned: () =>
          roomMembers.removeWhere((i) => i.identifier == member.identifier),
      onUserKicked: () =>
          roomMembers.removeWhere((i) => i.identifier == member.identifier),
      onUserRoleChanged: () => loadAllUsers(),
    );
  }

  Widget buildHeader(BuildContext context, _MemberSection section) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant);
    final role = section.role;
    // Vommet issue 67: a power level tag's colour (made readable on this
    // theme) and emoji or image icon.
    final tagColor = role?.color;
    final image = role?.image;
    final emoji = role?.emoji;
    final iconSize = (style?.fontSize ?? 14) + 4;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Row(
        children: [
          if (image != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Image(
                image: image,
                width: iconSize,
                height: iconSize,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const SizedBox.shrink(),
              ),
            )
          else if (emoji != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(emoji, style: style),
            ),
          Flexible(
            child: Text(
              "${section.title} — ${section.members.length}",
              style: tagColor == null
                  ? style
                  : style?.copyWith(
                      color: PowerLevelTags.readableColor(
                        tagColor,
                        colors.surface,
                        colors.onSurface,
                      ),
                    ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
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
        padding: EdgeInsets.fromLTRB(
          4,
          item.first ? 4 : 0,
          4,
          item.last ? 4 : 0,
        ),
        child: buildMember(context, item.member!),
      ),
    );
    if (item.section.dimmed) row = Opacity(opacity: 0.55, child: row);
    return row;
  }

  /// Vommet: the find box's row, pinned under the tabs (or the "Room
  /// members" label).
  Widget buildFindHeader(BuildContext context) {
    final onInvite = widget.onInvite;
    return SliverPersistentHeader(
      key: const ValueKey("member-panel-find-header"),
      pinned: true,
      delegate: MemberFindHeaderDelegate(
        MemberFindRow(
          controller: _findController,
          focusNode: _findFocus,
          memberCount: widget.room.memberCount,
          onInvite: onInvite == null ? null : () => onInvite(null),
        ),
      ),
    );
  }

  /// Vommet: while the find box holds text, one flat list of the members
  /// with the picked membership whose name or ID matches.
  List<Widget> buildFindResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant);
    final canBan = widget.room.permissions.canBan;
    if (!canBan &&
        (_membership == MemberMembership.banned ||
            _membership == MemberMembership.left)) {
      _membership = MemberMembership.joined;
    }
    final keys = findKeys(_membership);
    final matches = memberFindMatches(_query, keys);
    final joinedMatches = _membership == MemberMembership.joined
        ? matches.length
        : memberFindMatches(_query, findKeys(MemberMembership.joined)).length;
    final invite = widget.onInvite != null &&
        memberFindOffersInvite(
          query: _query,
          joinedMatches: joinedMatches,
          canInvite: true,
        );
    final roles = {
      for (final (member, role) in importantMembers ?? const <(Member, Role)>[])
        member.identifier: role,
    };
    final total = _membership == MemberMembership.joined
        ? max(widget.room.memberCount, keys.length)
        : keys.length;
    return [
      SliverPadding(
        padding: widget.listPadding,
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final m in memberFindChips(canBan: canBan))
                    ChoiceChip(
                      key: ValueKey("member-panel-find-chip-${m.name}"),
                      label: Text(MemberFindStrings.chip(m)),
                      selected: _membership == m,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _membership = m),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                child: Text(
                  key: const ValueKey("member-panel-find-count"),
                  MemberFindStrings.memberFindCount(
                    MemberFindStrings.formatCount(matches.length),
                    MemberFindStrings.formatCount(total),
                  ),
                  style: label,
                ),
              ),
              if (loadingMoreMembers)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text(
                    MemberFindStrings.memberFindLoadingAll,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (invite) buildInviteResult(context),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: widget.listPadding,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildFindResult(
              context,
              matches[index],
              roles[matches[index].member.identifier],
            ),
            childCount: matches.length,
          ),
        ),
      ),
    ];
  }

  /// "Invite @x:y" / "Invite "name"…": opens the invite dialog with the
  /// query typed in.
  Widget buildInviteResult(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _query;
    return Material(
      key: const ValueKey("member-panel-find-invite"),
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => widget.onInvite?.call(query),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.person_add_alt_1,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memberFindIsUserId(query)
                          ? MemberFindStrings.memberFindInviteUserId(query)
                          : MemberFindStrings.memberFindInviteName(query),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                    ),
                    Text(
                      MemberFindStrings.memberFindNotInRoom,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A find result: name and Matrix ID with the match highlighted, the
  /// role or "Banned" tag; tap and menu as a normal row.
  Widget buildFindResult(
    BuildContext context,
    MemberFindMatch match,
    Role? role,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final member = match.member;
    final redaction = RedactionScope.of(context);
    final name = redaction.name(member.displayName, member.identifier);
    final redacted = name != member.displayName;
    final banned = _membership == MemberMembership.banned;
    final tag = banned ? MemberFindStrings.memberFindBanned : role?.name;
    final tagColor = banned ? scheme.error : scheme.onSurfaceVariant;
    Widget row = Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey("member-panel-find-result-${member.identifier}"),
        borderRadius: BorderRadius.circular(8),
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => UserProfile.show(
          context,
          client: widget.room.client,
          userId: member.identifier,
          room: widget.room,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: member.defaultColor,
                backgroundImage: redacted ? null : member.avatar,
                child: member.avatar == null || redacted
                    ? Text(
                        name.characters.firstOrNull?.toUpperCase() ?? "",
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MemberFindHighlight(
                      name,
                      range: redacted ? null : match.nameRange,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
                    ),
                    if (!redaction.redactsNames)
                      MemberFindHighlight(
                        member.identifier,
                        range: match.idRange,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
              if (tag != null)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tagColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    tag,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tagColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (banned) {
      return AdaptiveContextMenu(
        items: [
          if (widget.room.permissions.canBan)
            tiamat.ContextMenuItem(
              text: BannedUsersView.labelUnban,
              icon: Icons.lock_open,
              onPressed: () => unban(member),
            ),
        ],
        child: row,
      );
    }
    return RoomMemberList.userContextMenu(
      context,
      userId: member.identifier,
      room: widget.room,
      userDisplayName: member.displayName,
      isSelf: member.identifier == widget.room.client.self?.identifier,
      child: row,
      onUserBanned: refreshMembers,
      onUserKicked: refreshMembers,
      onUserRoleChanged: () => loadAllUsers(),
    );
  }

  Future<void> unban(Member member) async {
    final name = RedactionScope.of(
      context,
    ).name(member.displayName, member.identifier);
    if (await AdaptiveDialog.confirmation(
          context,
          prompt: MemberFindStrings.memberFindUnbanPrompt(name),
          confirmationText: BannedUsersView.labelUnban,
        ) !=
        true) {
      return;
    }
    if (!mounted) return;
    await ErrorUtils.tryRun(context, () async {
      await widget.room.unbanUser(member.identifier);
      if (mounted) setState(() => _findKeys.remove(MemberMembership.banned));
    });
  }

  @override
  Widget build(BuildContext context) {
    _activities = currentActivities();
    final finding = widget.findBox && _query.isNotEmpty;
    final (items, more) = finding ? (<_MemberItem>[], false) : buildItems();
    final hideRow = !finding && canHideOffline && _hideable > 0;

    final view = CustomScrollView(
      controller: widget.controller,
      scrollBehavior: widget.scrollBehavior,
      slivers: [
        ...widget.leading,
        if (widget.findBox) buildFindHeader(context),
        if (finding) ...buildFindResults(context),
        if (!finding)
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
        if (hideRow)
          SliverPadding(
            padding: widget.listPadding,
            sliver: SliverToBoxAdapter(
              child: buildHideOfflineRow(context, key: _toggleRowKey),
            ),
          ),
        ...widget.trailing,
      ],
    );
    if (!hideRow) return view;

    schedulePinCheck();
    return NotificationListener<Notification>(
      onNotification: (notification) {
        if (notification is ScrollNotification ||
            notification is ScrollMetricsNotification) {
          schedulePinCheck();
        }
        return false;
      },
      child: Stack(
        children: [
          view,
          if (_pinToggleRow)
            Positioned(
              left: widget.listPadding.left,
              right: widget.listPadding.right,
              bottom: 0,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: buildHideOfflineRow(context),
              ),
            ),
        ],
      ),
    );
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
            ),
        ],
      ),
    );
  }
}

/// Vommet: the member list's plain (non-role) members after a refresh: the
/// room's [current] members, plus, while the room's own list isn't
/// [complete], the [previous] ones it doesn't hold, except people it knows
/// left or were kicked or banned ([hasLeft]); they stayed until the app
/// restarted (Vommet issue 341). Role holders have their own sections.
List<Member> refreshedPlainMembers({
  required List<Member> current,
  required List<Member> previous,
  required bool complete,
  required bool Function(String identifier) hasLeft,
  required Set<String> roleHolderIds,
}) {
  final users = [...current];
  if (!complete) {
    final ids = {for (final u in users) u.identifier};
    users.addAll(
      previous.where(
        (m) => !ids.contains(m.identifier) && !hasLeft(m.identifier),
      ),
    );
  }
  users.removeWhere((u) => roleHolderIds.contains(u.identifier));
  return users;
}

/// Vommet: one section of the member list ("Owner — 1", "Online — 12").
class _MemberSection {
  _MemberSection(
    this.title, {
    this.dimmed = false,
    this.hideable = false,
    this.role,
  });
  final String title;

  /// Vommet issue 67: the role of a role section, for its tag colour and icon.
  final Role? role;
  final bool dimmed;

  /// Vommet issue 762: a section "Hide offline members" leaves out
  /// (Unknown, Offline).
  final bool hideable;
  final List<Member> members = [];

  /// Vommet issue 762: role holders here whose presence is unknown, which
  /// "Hide offline members" leaves out too.
  final Set<String> unknownPresence = {};
}

class _MemberItem {
  _MemberItem.header(this.section)
      : member = null,
        first = false,
        last = false;
  _MemberItem.member(
    this.section,
    Member this.member, {
    required this.first,
    required this.last,
  });
  final _MemberSection section;
  final Member? member;
  final bool first;
  final bool last;
}

/// Vommet issue 806: whether the dashed "Hide offline members" row at [row]
/// (its place at the end of the list) is cut off below the viewport, so its
/// copy should stick to the bottom edge. Goes by the row's sliver geometry:
/// a viewport places slivers it doesn't paint at its top, so measuring the
/// row's painted position said "on screen" while it was far below (the row
/// was missing on open and flickered while scrolling). Not built yet = pin.
bool toggleRowNeedsPin(BuildContext? row) {
  RenderObject? node = row?.findRenderObject();
  while (node != null && node is! RenderSliver) {
    node = node.parent;
  }
  if (node is! RenderSliver || !node.attached) return true;
  final geometry = node.geometry;
  if (geometry == null) return true;
  // Scrolled past above (only trailing slivers could follow it there).
  if (node.constraints.scrollOffset > 0) return false;
  return !geometry.visible ||
      geometry.paintExtent < geometry.scrollExtent - 0.5;
}
