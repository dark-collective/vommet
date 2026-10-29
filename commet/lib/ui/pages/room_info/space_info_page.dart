import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/space_banner/space_banner_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/space_join_picker/space_join_picker.dart';
import 'package:commet/ui/pages/manage_space_rooms/manage_space_rooms_page.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/ui/pages/room_info/room_info_notifications.dart';
import 'package:commet/ui/molecules/thread_read_scope_settings.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:commet/ui/pages/room_info/room_info_settings_pages.dart';
import 'package:commet/ui/pages/room_info/room_info_shared_pages.dart';
import 'package:commet/ui/pages/settings/categories/room/advanced/room_advanced_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/general/nickname_settings.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:commet/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/space/space_appearance_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/space/space_developer_settings_view.dart';
import 'package:commet/ui/pages/settings/categories/space/space_emoji_pack_settings.dart';
import 'package:commet/ui/pages/settings/space_settings_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet (New room info page): opens Space info for [space], or with the
/// experiment off the old Space settings page, as before. The same page on
/// phone and desktop.
void openSpaceInfo(BuildContext context, Space space) {
  NavigationUtils.navigateTo(
      context,
      roomInfoPageEnabled
          ? SpaceInfoPage(space: space)
          : SpaceSettingsPage(space: space));
}

/// The space as a room, for the settings views shared with rooms.
MatrixRoom? _spaceAsRoom(Space space) => switch (space) {
      MatrixSpace s => MatrixRoom(
          space.client as MatrixClient, s.matrixRoom, s.matrixRoom.client),
      _ => null,
    };

String _spaceLink(Space space) {
  final alias = space is MatrixSpace ? space.matrixRoom.canonicalAlias : "";
  return "https://matrix.to/#/${alias.isNotEmpty ? alias : space.identifier}";
}

class SpaceInfoPage extends StatefulWidget {
  const SpaceInfoPage({required this.space, super.key});
  final Space space;

  @override
  State<SpaceInfoPage> createState() => _SpaceInfoPageState();
}

class _SpaceInfoPageState extends State<SpaceInfoPage> {
  final List<StreamSubscription> _subs = [];
  late final MatrixRoom? asRoom = _spaceAsRoom(widget.space);

  Space get space => widget.space;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      space.onUpdate.listen((_) => _changed()),
      space.onChildRoomsUpdated.listen((_) => _changed()),
      space.onChildRoomPreviewsUpdated.listen((_) => _changed()),
    ]);
    if (space.childPreviews.isEmpty) {
      space.fetchChildren().then((_) => _changed()).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void shareLink() {
    Clipboard.setData(ClipboardData(text: _spaceLink(space)));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text("Space link copied")));
  }

  void editProfile() => InfoSubPage.open(
      context,
      InfoSubPage(
          title: "Space profile",
          subtitle: "${space.displayName} · applies to everyone",
          child: SpaceAppearanceSettingsPage(space: space)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        title: const Text("Space info"),
        actions: [
          IconButton(
              tooltip: "Share space link",
              icon: const Icon(Icons.ios_share),
              onPressed: shareLink),
          if (space.permissions.canEditAppearance)
            IconButton(
                tooltip: "Edit space profile",
                icon: const Icon(Icons.edit_outlined),
                onPressed: editProfile),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SpaceInfoHeader(space),
              const SizedBox(height: 14),
              _quickActions(context),
              ..._rooms(context),
              ..._members(context),
              ..._forYou(context),
              ..._settings(context),
              const SizedBox(height: 22),
              InfoGroup([
                InfoRow(
                  key: const ValueKey("space-info-leave"),
                  icon: Icons.logout,
                  title: "Leave space…",
                  subtitle: "Choose which rooms to leave too",
                  danger: true,
                  onTap: () => SpaceMenu.leave(context, space,
                      onConfirmed: () => closeRoomInfoToChat(context)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions(BuildContext context) {
    final rule = space.pushRule;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        NotificationQuickAction(
          key: const ValueKey("space-info-notifications"),
          pushRule: rule,
          onTap: () async {
            await SpaceMenu.notifications(context, space);
            _changed();
          },
        ),
        InfoQuickAction(
          key: const ValueKey("space-info-browse"),
          icon: Icons.travel_explore,
          label: "Browse",
          onTap: () => SpaceJoinPicker.browse(context, space),
        ),
        InfoQuickAction(
          key: const ValueKey("space-info-invite"),
          icon: Icons.person_add_alt_1,
          label: "Invite",
          onTap: space.permissions.canInviteUser
              ? () => SpaceMenu.invite(context, space)
              : null,
        ),
        if (space.permissions.canEditChildren)
          InfoQuickAction(
            key: const ValueKey("space-info-add-room"),
            icon: Icons.add_box_outlined,
            label: "Add room",
            onTap: () => SpaceMenu.addRoom(context, space),
          )
        else
          InfoQuickAction(
            icon: Icons.link,
            label: "Share",
            onTap: shareLink,
          ),
      ]),
    );
  }

  Set<String> get _suggested => space is MatrixSpace
      ? {
          for (final child in (space as MatrixSpace).matrixRoom.spaceChildren)
            if (child.suggested == true && child.roomId != null) child.roomId!,
        }
      : const {};

  List<Widget> _rooms(BuildContext context) {
    final suggested = _suggested;
    final joined = space.rooms;
    final joinedIds = {for (final r in joined) r.identifier};
    final previews = space.childPreviews
        .where((p) => !joinedIds.contains(p.roomId) && p.type == null)
        .toList();
    int rank(String id) => suggested.contains(id) ? 0 : 1;
    final sortedJoined = [...joined]
      ..sort((a, b) => rank(a.identifier).compareTo(rank(b.identifier)));
    previews.sort((a, b) => rank(a.roomId).compareTo(rank(b.roomId)));
    const shown = 6;
    final total = joined.length + previews.length;
    final rows = <Widget>[
      for (final room in sortedJoined.take(shown))
        _SpaceRoomRow(
          avatar: room.avatar,
          name: room.displayName,
          color: room.defaultColor,
          meta: [
            if (room.notificationCount > 0) "${room.notificationCount} new",
          ].join(" · "),
          suggested: suggested.contains(room.identifier),
          onTap: () {
            closeRoomInfoToChat(context);
            EventBus.doOpenRoom(room.identifier,
                clientId: space.client.identifier);
          },
        ),
      for (final preview
          in previews.take(shown - joined.length.clamp(0, shown)))
        _SpaceRoomRow(
          avatar: preview.avatar,
          name: preview.displayName,
          color: preview.color,
          meta:
              preview.numMembers == null ? "" : "${preview.numMembers} members",
          suggested: suggested.contains(preview.roomId),
          onJoin: () async {
            await space.client.joinRoomFromPreview(preview);
            _changed();
          },
        ),
      if (total > shown)
        InfoRow(
          icon: Icons.travel_explore,
          title: "See all $total rooms",
          onTap: () => SpaceJoinPicker.browse(context, space),
        ),
      if (space.permissions.canEditChildren &&
          preferences.experimentManageSpaceRooms.value)
        InfoRow(
          icon: Icons.account_tree_outlined,
          title: "Manage rooms",
          subtitle: "Add, remove, order, mark as suggested",
          onTap: () =>
              NavigationUtils.navigateTo(context, ManageSpaceRoomsPage(space)),
        ),
    ];
    return [
      InfoSectionHeader("Rooms", caption: "$total · ${joined.length} joined"),
      InfoGroup(rows),
    ];
  }

  List<Widget> _members(BuildContext context) {
    final room = asRoom;
    if (room == null) return const [];
    final count = (space as MatrixSpace).matrixRoom.summary.mJoinedMemberCount;
    return [
      const InfoSectionHeader("Members"),
      InfoGroup([
        InfoRow(
          icon: Icons.people_outline,
          title: count == null ? "See members" : "See all $count members",
          onTap: () => InfoSubPage.open(context, RoomMembersPage(room)),
        ),
      ]),
    ];
  }

  List<Widget> _forYou(BuildContext context) {
    final rows = <Widget>[
      InfoRow(
        icon: Icons.notifications_outlined,
        title: "Notifications for all rooms",
        value: pushRuleLabel(space.pushRule),
        onTap: () async {
          await SpaceMenu.notifications(context, space);
          _changed();
        },
      ),
      // Vommet issues 804 and 805.
      if (space case final MatrixSpace matrixSpace)
        ThreadReadScopeRow(matrixSpace.matrixRoom),
      if (space.client is MatrixClient && MatrixNicknames.enabled)
        InfoRow(
          icon: Icons.badge_outlined,
          title: "My nickname in this space",
          onTap: () => InfoSubPage.open(
              context,
              InfoSubPage(
                  title: "My nickname in this space",
                  subtitle: "${space.displayName} · just for you",
                  child: NicknameSettings(
                      client: space.client as MatrixClient,
                      roomId: space.identifier,
                      space: space))),
        ),
      if (space.roomsWithChildren.any((r) => r.notificationCount > 0))
        InfoRow(
          icon: Icons.mark_chat_read_outlined,
          title: "Mark space as read",
          chevron: false,
          onTap: () async {
            await SpaceMenu.markAsRead(space);
            _changed();
          },
        ),
    ];
    return [
      const InfoSectionHeader("Just for you", caption: "Only you see these."),
      InfoGroup(rows),
    ];
  }

  List<Widget> _settings(BuildContext context) {
    final room = asRoom;
    final emoticons = space.getComponent<SpaceEmoticonComponent>();
    final s = space;
    final rows = <Widget>[
      InfoRow(
        icon: Icons.edit_outlined,
        title: "Space profile",
        subtitle: "Name, picture, topic, banner",
        locked: !space.permissions.canEditAppearance,
        onTap: editProfile,
      ),
      if (room != null)
        InfoRow(
          icon: Icons.shield_outlined,
          title: "Privacy & access",
          value: switch (space.visibility) {
            RoomVisibilityPublic _ => "Public",
            RoomVisibilityRestricted _ => "Space members",
            RoomVisibilityKnock _ => "Ask to join",
            _ => "Invite only",
          },
          locked: !room.permissions.canChangeVisibility,
          onTap: () => InfoSubPage.open(
              context,
              InfoSubPage(
                  title: "Privacy & access",
                  subtitle: "${space.displayName} · applies to everyone",
                  scrollable: false,
                  child: RoomSecuritySettingsPage(
                      showEncryptionToggle: false, room: room))),
        ),
      if (room != null)
        InfoRow(
          icon: Icons.alternate_email,
          title: "Addresses & directory",
          onTap: () => InfoSubPage.open(context, RoomAddressesPage(room)),
        ),
      if (s is MatrixSpace)
        InfoRow(
          icon: Icons.admin_panel_settings_outlined,
          title: "Roles & permissions",
          subtitle: "Including who can manage the space's rooms",
          onTap: () => InfoSubPage.open(
              context,
              InfoSubPage(
                  title: "Roles & permissions",
                  subtitle: "${space.displayName} · applies to everyone",
                  scrollable: false,
                  child: MatrixRoomPermissionsPage(s.matrixRoom))),
        ),
      if (emoticons != null &&
          (space.permissions.canEditRoomEmoticons ||
              emoticons.ownedPacks.isNotEmpty))
        InfoRow(
          icon: Icons.emoji_emotions_outlined,
          title: "Emoji & stickers",
          onTap: () => InfoSubPage.open(
              context,
              InfoSubPage(
                  title: "Emoji & stickers",
                  subtitle: space.displayName,
                  child: SpaceEmojiPackSettings(space))),
        ),
      if (s is MatrixSpace)
        InfoRow(
          icon: Icons.code,
          title: "Advanced",
          subtitle: "Space ID and version",
          onTap: () => InfoSubPage.open(
              context,
              InfoSubPage(
                  title: "Advanced",
                  subtitle: space.displayName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RoomIdVersionPanel(
                          roomId: s.matrixRoom.id,
                          roomVersion: s.matrixRoom.roomVersion,
                          isSpace: true),
                      if (preferences.developerMode.value) ...[
                        const SizedBox(height: 10),
                        SpaceDeveloperSettingsView(space),
                      ],
                    ],
                  ))),
        ),
    ];
    return [
      const InfoSectionHeader("Space settings",
          caption: "Changes here apply to everyone."),
      InfoGroup(rows),
    ];
  }
}

/// Banner, picture, name, address, topic.
class SpaceInfoHeader extends StatelessWidget {
  const SpaceInfoHeader(this.space, {super.key});
  final Space space;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final banner = space.getComponent<SpaceBannerComponent>()?.banner;
    final alias = space is MatrixSpace
        ? (space as MatrixSpace).matrixRoom.canonicalAlias
        : "";
    final count = space is MatrixSpace
        ? (space as MatrixSpace).matrixRoom.summary.mJoinedMemberCount
        : null;
    final topic = space.topic.trim();
    final avatar = tiamat.Avatar(
      radius: 48,
      image: space.avatar,
      placeholderText: space.displayName,
      placeholderColor: space.color,
    );
    return Column(
      children: [
        if (banner != null)
          SizedBox(
            height: 200,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 140,
                  child: Image(image: banner, fit: BoxFit.cover)),
              Positioned(
                  left: 0,
                  right: 0,
                  top: 92,
                  child: Center(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: scheme.surface, width: 4)),
                          child: avatar))),
            ]),
          )
        else
          Padding(padding: const EdgeInsets.only(top: 12), child: avatar),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(space.displayName,
              key: const ValueKey("space-info-name"),
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            [
              if (alias.isNotEmpty) alias,
              "Space",
              if (count != null) "$count members",
            ].join("  ·  "),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (topic.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 0),
            child: SelectableText(topic,
                textAlign: TextAlign.center,
                maxLines: 4,
                style: text.bodyMedium),
          ),
      ],
    );
  }
}

class _SpaceRoomRow extends StatelessWidget {
  const _SpaceRoomRow({
    required this.avatar,
    required this.name,
    required this.color,
    required this.meta,
    required this.suggested,
    this.onTap,
    this.onJoin,
  });

  final ImageProvider? avatar;
  final String name;
  final Color color;
  final String meta;
  final bool suggested;
  final VoidCallback? onTap;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
        child: Row(children: [
          tiamat.Avatar(
              radius: 17,
              image: avatar,
              placeholderText: name,
              placeholderColor: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  if (suggested) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: scheme.primary.withAlpha(36),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text("Suggested",
                          style: text.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (onJoin != null)
            FilledButton(
              style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: onJoin,
              child: const Text("Join"),
            )
          else
            Icon(Icons.check_circle,
                size: 18, color: scheme.onSurfaceVariant.withAlpha(150)),
        ]),
      ),
    );
  }
}
