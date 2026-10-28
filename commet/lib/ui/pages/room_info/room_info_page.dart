import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/role.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/direct_messages/dm_shape_notifier.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/components/room_banner/room_banner_component.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_role.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/molecules/room_call_button.dart';
import 'package:commet/ui/molecules/room_tags_dialog.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_editor.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/organisms/room_members_list/index_shared_counts.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/pages/room_info/dm_cards.dart';
import 'package:commet/ui/pages/room_info/room_info_dialog.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/ui/pages/room_info/room_info_notifications.dart';
import 'package:commet/ui/molecules/thread_read_scope_settings.dart';
import 'package:commet/ui/molecules/thread_reply_notify_settings.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:commet/ui/pages/room_info/room_info_settings_pages.dart';
import 'package:commet/ui/pages/room_info/room_info_shared_pages.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/bridges/room_bridges_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/calendar/room_calendar_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:commet/ui/pages/settings/room_settings_page.dart';
import 'package:commet/utils/dm_shape.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Where Room info opens: at the top, or at its Room settings section (the
/// menus' "Room settings" items).
enum RoomInfoSection { about, settings }

/// How Room info opens: the old Room settings page (experiment off), the
/// phone page, or the desktop dialog.
enum RoomInfoRoute { oldSettings, page, dialog }

RoomInfoRoute roomInfoRoute(
        {required bool experiment, required bool desktop}) =>
    !experiment
        ? RoomInfoRoute.oldSettings
        : desktop
            ? RoomInfoRoute.dialog
            : RoomInfoRoute.page;

/// Vommet (New room info page): opens Room info for [room], or with the
/// experiment off the old Room settings page, as before.
void openRoomInfo(BuildContext context, Room room,
    {Space? contextSpace,
    VoidCallback? onLeaveRoom,
    RoomInfoSection section = RoomInfoSection.about}) {
  final route = roomInfoRoute(
      experiment: roomInfoPageEnabled,
      desktop: MediaQuery.of(context).layout == LayoutType.desktop);
  switch (route) {
    case RoomInfoRoute.oldSettings:
      NavigationUtils.navigateTo(
          context,
          RoomSettingsPage(
              room: room,
              contextSpace: contextSpace,
              onLeaveRoom: onLeaveRoom));
    case RoomInfoRoute.dialog:
      showRoomInfoDialog(context, room,
          contextSpace: contextSpace,
          onLeaveRoom: onLeaveRoom,
          section: section);
    case RoomInfoRoute.page:
      NavigationUtils.navigateTo(
          context,
          RoomInfoPage(
              room: room,
              contextSpace: contextSpace,
              onLeaveRoom: onLeaveRoom,
              section: section));
  }
}

/// Whether [room] shows as a direct chat (a person page): live, by the
/// direct-chat rules (a direct chat that became a group shows as a room).
bool roomInfoIsDirectChat(Room room) => DmShapes.showsPerson(room);

String? roomInfoPartnerId(Room room) => DmShapes.of(room).partnerId;

/// Rebuilds [builder] whenever the room, its members, banner, pins or
/// direct-chat shape change.
class RoomInfoListener extends StatefulWidget {
  const RoomInfoListener(
      {required this.room, required this.builder, super.key});
  final Room room;
  final WidgetBuilder builder;

  @override
  State<RoomInfoListener> createState() => _RoomInfoListenerState();
}

class _RoomInfoListenerState extends State<RoomInfoListener> {
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    void changed(_) {
      if (mounted) setState(() {});
    }

    _subs.addAll([
      room.onUpdate.listen(changed),
      room.onMembersChanged.listen(changed),
      if (room.getComponent<RoomBannerComponent>() case final b?)
        b.onBannerChanged.listen(changed),
      if (room.getComponent<PinnedMessagesComponent>() case final p?)
        p.onPinsChanged.listen(changed),
    ]);
    RoomTranslation.instance.addListener(_rebuild);
    _shape = DmShapeNotifier.of(room)..addListener(_rebuild);
  }

  late final DmShapeNotifier _shape;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    RoomTranslation.instance.removeListener(_rebuild);
    _shape.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// The phone page: one scrolling page, the same for everyone.
class RoomInfoPage extends StatefulWidget {
  const RoomInfoPage({
    required this.room,
    this.contextSpace,
    this.onLeaveRoom,
    this.section = RoomInfoSection.about,
    super.key,
  });

  final Room room;
  final Space? contextSpace;
  final VoidCallback? onLeaveRoom;
  final RoomInfoSection section;

  @override
  State<RoomInfoPage> createState() => _RoomInfoPageState();
}

class _RoomInfoPageState extends State<RoomInfoPage> {
  final settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.section == RoomInfoSection.settings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = settingsKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, alignment: 0.02);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        titleSpacing: 0,
        title: ValueListenableBuilder<DmShape>(
            valueListenable: DmShapeNotifier.of(room),
            builder: (context, _, __) =>
                Text(roomInfoIsDirectChat(room) ? "Chat info" : "Room info")),
        actions: [
          IconButton(
              tooltip: "Share room link",
              icon: const Icon(Icons.ios_share),
              onPressed: () => RoomInfoActions.shareLink(context, room)),
          if (room.permissions.canEditAppearance)
            IconButton(
                tooltip: "Edit room profile",
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => RoomInfoActions.editProfile(context, room)),
        ],
      ),
      body: RoomInfoListener(
        room: room,
        builder: (context) => SingleChildScrollView(
          key: ValueKey("room-info-page-${room.localId}"),
          padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RoomInfoHeader(room, contextSpace: widget.contextSpace),
              DmShapeCard(room),
              RoomInfoQuickActions(room),
              RoomInfoShared(room),
              RoomInfoMembers(room),
              RoomInfoForYou(room, contextSpace: widget.contextSpace),
              KeyedSubtree(
                key: settingsKey,
                child: RoomInfoRoomSettings(room,
                    contextSpace: widget.contextSpace),
              ),
              RoomInfoFooter(room, onLeaveRoom: widget.onLeaveRoom),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the rows and buttons do.
class RoomInfoActions {
  static String link(Room room) {
    final alias = room is MatrixRoom ? room.matrixRoom.canonicalAlias : "";
    return "https://matrix.to/#/${alias.isNotEmpty ? alias : room.identifier}";
  }

  static void shareLink(BuildContext context, Room room) {
    Clipboard.setData(ClipboardData(text: link(room)));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text("Room link copied")));
  }

  static void editProfile(BuildContext context, Room room) {
    InfoSubPage.open(
        context,
        InfoSubPage(
            title: "Room profile",
            subtitle: forEveryoneSubtitle(room),
            child: RoomAppearanceSettingsPage(room: room)));
  }

  static void search(BuildContext context, Room room) {
    closeRoomInfoToChat(context);
    InChatSearch.of(room).open();
  }

  static bool canInvite(Room room) => room.permissions.canInviteUser;

  /// The call action, or null where this room can't call.
  static VoidCallback? call(BuildContext context, Room room,
      {CallType type = CallType.voice}) {
    if (RoomCallActions.usesRoomCalls(room)) {
      return () {
        closeRoomInfoToChat(context);
        RoomCallButtonActions.onTap(context, room);
      };
    }
    final voip = room.client.getComponent<VoipComponent>();
    if (voip != null && roomInfoIsDirectChat(room)) {
      return () {
        closeRoomInfoToChat(context);
        voip.startCall(room.identifier, type);
      };
    }
    return null;
  }

  static Future<void> report(BuildContext context, Room room) async {
    if (room is! MatrixRoom) return;
    final reason = await AdaptiveDialog.textPrompt(context,
        title: "Report room",
        submitText: "Report",
        hintText: "What's wrong with this room? Your homeserver's admins see "
            "this",
        multiline: true,
        dangerous: true);
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await room.matrixRoom.client.request(matrix.RequestType.POST,
          "/client/v3/rooms/${Uri.encodeComponent(room.identifier)}/report",
          data: {"reason": reason.trim()});
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text("Reported to your homeserver")));
      }
    } catch (e, trace) {
      if (context.mounted) {
        AdaptiveDialog.showError(context, e, trace);
      }
    }
  }

  static Future<void> leave(BuildContext context, Room room,
      {VoidCallback? onLeaveRoom}) async {
    await RoomMenu.leave(context, room, onConfirmed: () {
      if (context.mounted) closeRoomInfoToChat(context);
      onLeaveRoom?.call();
    });
  }
}

String _visibilityLabel(Room room) => switch (room.visibility) {
      RoomVisibilityPublic _ => "Public",
      RoomVisibilityRestricted _ => "Space members",
      RoomVisibilityKnock _ => "Ask to join",
      _ => "Invite only",
    };

int _memberCount(Room room) {
  if (room is MatrixRoom) {
    final joined = room.matrixRoom.summary.mJoinedMemberCount;
    if (joined != null && joined > 0) return joined;
  }
  return room.memberIds.length;
}

String? _historyLabel(Room room) {
  if (room is! MatrixRoom) return null;
  return switch (room.matrixRoom.historyVisibility) {
    matrix.HistoryVisibility.shared => "New members see history",
    matrix.HistoryVisibility.worldReadable => "Anyone can read",
    matrix.HistoryVisibility.invited => "History from their invite",
    matrix.HistoryVisibility.joined => "History from joining",
    null => null,
  };
}

/// The header: banner, avatar, name, address, badges, topic, and the line
/// with the space and member count.
class RoomInfoHeader extends StatefulWidget {
  const RoomInfoHeader(this.room, {this.contextSpace, super.key});
  final Room room;
  final Space? contextSpace;

  @override
  State<RoomInfoHeader> createState() => _RoomInfoHeaderState();
}

class _RoomInfoHeaderState extends State<RoomInfoHeader> {
  bool topicOpen = false;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final direct = roomInfoIsDirectChat(room);
    final partnerId = direct ? roomInfoPartnerId(room) : null;
    final partner =
        partnerId == null ? null : room.getMemberOrFallback(partnerId);
    final banner = room.getComponent<RoomBannerComponent>()?.banner;
    final name = partner?.displayName ?? room.displayName;
    final address = partner?.identifier ??
        (room is MatrixRoom ? room.matrixRoom.canonicalAlias : "");
    final topic = room.topic?.trim();
    final history = _historyLabel(room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InfoHeaderArt(
          banner: direct ? null : banner,
          image: partner?.avatar ?? room.avatar,
          placeholderText: name,
          placeholderColor: partner?.defaultColor ?? room.defaultColor,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(name,
              key: const ValueKey("room-info-name"),
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (address.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SelectableText(address,
                textAlign: TextAlign.center,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            _Pill(
                icon: room.isE2EE ? Icons.lock : Icons.lock_open,
                label: room.isE2EE ? "Encrypted" : "Not encrypted",
                color: room.isE2EE ? const Color(0xff4caf7d) : null),
            if (!direct)
              _Pill(
                  icon: RoomVisibility.icon(room.visibility),
                  label: _visibilityLabel(room)),
            if (history != null && !direct)
              _Pill(icon: Icons.history, label: history),
          ],
        ),
        if (topic != null && topic.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: GestureDetector(
              onTap: () => setState(() => topicOpen = !topicOpen),
              child: SelectableText(
                topic,
                key: const ValueKey("room-info-topic"),
                textAlign: TextAlign.center,
                maxLines: topicOpen ? null : 3,
                onTap: () => setState(() => topicOpen = !topicOpen),
                style: text.bodyMedium,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Text(
            [
              if (widget.contextSpace != null)
                "In ${widget.contextSpace!.displayName}",
              if (!direct) "${_memberCount(room)} members",
            ].join(" · "),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: c.withAlpha(36), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: c, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Notifications (the current level; a tap opens the levels), Search,
/// Invite, Call; in direct chats Notifications, Search, Call, Video.
class RoomInfoQuickActions extends StatelessWidget {
  const RoomInfoQuickActions(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) {
    final direct = roomInfoIsDirectChat(room);
    final call = RoomInfoActions.call(context, room);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Row(
        children: [
          RoomNotificationQuickAction(room,
              key: const ValueKey("room-info-notify")),
          InfoQuickAction(
            key: const ValueKey("room-info-search"),
            icon: Icons.search,
            label: "Search",
            onTap: InChatSearch.availableIn(room)
                ? () => RoomInfoActions.search(context, room)
                : null,
          ),
          if (direct) ...[
            InfoQuickAction(
                key: const ValueKey("room-info-call"),
                icon: Icons.call_outlined,
                label: "Call",
                onTap: call),
            InfoQuickAction(
                key: const ValueKey("room-info-video"),
                icon: Icons.videocam_outlined,
                label: "Video",
                onTap:
                    RoomInfoActions.call(context, room, type: CallType.video)),
          ] else ...[
            InfoQuickAction(
              key: const ValueKey("room-info-invite"),
              icon: Icons.person_add_alt_1_outlined,
              label: "Invite",
              onTap: RoomInfoActions.canInvite(room)
                  ? () => RoomMenu.invite(context, room)
                  : null,
            ),
            InfoQuickAction(
              key: const ValueKey("room-info-call"),
              icon: Icons.call_outlined,
              label: "Call",
              sublabel: RoomCallActions.participants(room) > 0
                  ? "${RoomCallActions.participants(room)} in call"
                  : null,
              active: RoomCallActions.participants(room) > 0,
              onTap: call,
            ),
          ],
        ],
      ),
    );
  }
}

/// "Shared in this room": Media (4 thumbnails), Files, Links, Pinned,
/// Threads, Widgets, Calendar. Each opens the side panel's view full screen.
class RoomInfoShared extends StatefulWidget {
  const RoomInfoShared(this.room, {super.key});
  final Room room;

  @override
  State<RoomInfoShared> createState() => _RoomInfoSharedState();
}

class _RoomInfoSharedState extends State<RoomInfoShared> {
  late final RoomAttachmentFeed feed;
  SharedContentCounts? indexCounts;
  StreamSubscription? _jumpSub;
  StreamSubscription? _openRoomSub;

  @override
  void initState() {
    super.initState();
    feed = RoomAttachmentFeed(widget.room)..addListener(_changed);
    feed.start();
    // Vommet issue 874: a preview's Jump to message or Forward shows the
    // chat, as from the Media tab.
    _jumpSub = EventBus.jumpToEvent.stream.listen((_) {
      if (mounted) closeRoomInfoToChat(context);
    });
    _openRoomSub = EventBus.openRoom.stream.listen((_) {
      if (mounted) closeRoomInfoToChat(context);
    });
    indexCounts = IndexSharedContentCounts.maybeFor(widget.room)
      ?..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _jumpSub?.cancel();
    _openRoomSub?.cancel();
    feed.removeListener(_changed);
    feed.dispose();
    indexCounts?.removeListener(_changed);
    indexCounts?.dispose();
    super.dispose();
  }

  String _count(SharedCategory category, int loaded) {
    final counts = indexCounts;
    if (counts != null) return counts.count(category).toString();
    if (feed.reachedStart) return "$loaded";
    return loaded == 0 ? "" : "$loaded+";
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final media = feed.media;
    final files =
        feed.filtered(RoomAttachmentKind.files, RoomAttachmentFilter.all);
    final pins = room.getComponent<PinnedMessagesComponent>();
    final calendar = room.getComponent<CalendarRoom>();
    final direct = roomInfoIsDirectChat(room);
    void open(Widget page) => InfoSubPage.open(context, page);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoSectionHeader(
            direct ? "Shared in this chat" : "Shared in this room"),
        InfoGroup([
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoRow(
                key: const ValueKey("room-info-media"),
                icon: Icons.photo_library_outlined,
                title: "Media",
                value: _count(SharedCategory.photosAndVideos, media.length),
                onTap: () => open(RoomAttachmentsPage(
                    room: room,
                    kind: RoomAttachmentKind.media,
                    title: "Media")),
              ),
              if (media.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 12, 12),
                  child: Row(
                    spacing: 6,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: i < media.length
                                ? RoomMediaTileActions(
                                    feed: feed,
                                    item: media[i],
                                    child: _Thumb(media[i].$2))
                                : const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          InfoRow(
            key: const ValueKey("room-info-files"),
            icon: Icons.insert_drive_file_outlined,
            title: "Files",
            value: _count(SharedCategory.files, files.length),
            onTap: () => open(RoomAttachmentsPage(
                room: room, kind: RoomAttachmentKind.files, title: "Files")),
          ),
          InfoRow(
            key: const ValueKey("room-info-links"),
            icon: Icons.link,
            title: "Links",
            value: _count(SharedCategory.links, feed.links.length),
            onTap: () => open(RoomAttachmentsPage(
                room: room, kind: RoomAttachmentKind.links, title: "Links")),
          ),
          if (pins != null)
            InfoRow(
              key: const ValueKey("room-info-pins"),
              icon: Icons.push_pin_outlined,
              title: "Pinned messages",
              value: "${pins.getPinnedMessages().length}",
              onTap: () => open(RoomPinnedPage(room)),
            ),
          InfoRow(
            key: const ValueKey("room-info-threads"),
            icon: Icons.forum_outlined,
            title: "Threads",
            onTap: () => open(RoomThreadsPage(room)),
          ),
          if (RoomWidgetsPage.availableIn(room))
            InfoRow(
              icon: Icons.widgets_outlined,
              title: "Widgets",
              onTap: () => open(RoomWidgetsPage(room)),
            ),
          if (calendar?.hasCalendar == true)
            InfoRow(
              icon: Icons.calendar_month_outlined,
              title: "Calendar",
              onTap: () {
                closeRoomInfoToChat(context);
                EventBus.openCalendar.add(null);
              },
            ),
        ]),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.attachment);
  final FileAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final video = a is VideoAttachment ? a : null;
    final preview = a is ImageAttachment ? a.image : video?.thumbnail;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: scheme.surfaceContainerHigh),
        // A spoiler stays covered here (the full grid can reveal it).
        if (preview != null && a.spoiler == null)
          Image(
              image: preview,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        if (video != null)
          const Center(
              child:
                  Icon(Icons.play_circle_fill, size: 26, color: Colors.white)),
      ]),
    );
  }
}

/// Members: the first five, admins and moderators first, then "See all".
class RoomInfoMembers extends StatelessWidget {
  const RoomInfoMembers(this.room, {super.key});
  final Room room;

  static String roleName(Role role) {
    if (role is MatrixRole) {
      if (role.powerLevel >= 150) return "Owner";
      if (role.powerLevel >= 100) return "Admin";
      if (role.powerLevel >= 50) return "Moderator";
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    final direct = roomInfoIsDirectChat(room);
    final partnerId = direct ? roomInfoPartnerId(room) : null;
    if (partnerId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoSectionHeader("Person"),
          InfoGroup([
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: UserPanel(
                  userId: partnerId,
                  client: room.client,
                  contextRoom: room,
                  isDirectMessage: true),
            ),
          ]),
        ],
      );
    }

    final important = [...room.importantMembers()]..sort((a, b) {
        final pa = a.$2 is MatrixRole ? (a.$2 as MatrixRole).powerLevel : 0;
        final pb = b.$2 is MatrixRole ? (b.$2 as MatrixRole).powerLevel : 0;
        return pb.compareTo(pa);
      });
    final shown = <(Member, String)>[];
    final seen = <String>{};
    for (final (member, role) in important) {
      if (shown.length >= 5) break;
      if (!room.memberIds.contains(member.identifier)) continue;
      if (seen.add(member.identifier)) shown.add((member, roleName(role)));
    }
    for (final member in room.membersList()) {
      if (shown.length >= 5) break;
      if (seen.add(member.identifier)) shown.add((member, ""));
    }
    final count = _memberCount(room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoSectionHeader("Members", caption: "$count"),
        InfoGroup([
          for (final (member, role) in shown)
            Row(children: [
              Expanded(
                child: UserPanel(
                    key: ValueKey("room-info-member-${member.identifier}"),
                    userId: member.identifier,
                    client: room.client,
                    contextRoom: room,
                    initialMember: member),
              ),
              if (role.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(role,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
            ]),
          InfoRow(
            key: const ValueKey("room-info-see-all-members"),
            icon: Icons.groups_outlined,
            title: "See all $count members",
            onTap: () => InfoSubPage.open(context, RoomMembersPage(room)),
          ),
        ]),
      ],
    );
  }
}

/// "Just for you": settings only the user sees.
class RoomInfoForYou extends StatelessWidget {
  const RoomInfoForYou(this.room, {this.contextSpace, super.key});
  final Room room;
  final Space? contextSpace;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => InfoSubPage.open(context, page);
    final matrixRoom = room is MatrixRoom ? room as MatrixRoom : null;
    final wallpaper = ChatWallpaperEditor.availableIn(room);
    final translation = RoomTranslation.instance;
    final follows = roomFollowsNotificationDefault(room);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoSectionHeader("Just for you",
            icon: Icons.person_outline, caption: "Only you see these."),
        InfoGroup([
          InfoRow(
            key: const ValueKey("room-info-notifications"),
            icon: Icons.notifications_outlined,
            title: "Notifications",
            value: follows
                ? "Default (${pushRuleLabel(room.pushRule)})"
                : pushRuleLabel(room.pushRule),
            onTap: () => open(RoomNotificationsPage(room)),
          ),
          // Vommet issues 804 and 805.
          if (matrixRoom != null) ThreadReadScopeRow(matrixRoom.matrixRoom),
          // Vommet issue 785.
          if (matrixRoom != null) ThreadReplyNotifyRow(matrixRoom.matrixRoom),
          InfoRow(
            icon: Icons.visibility_outlined,
            title: "Read receipts & typing",
            onTap: () => open(RoomReceiptsTypingPage(room)),
          ),
          if (matrixRoom != null)
            InfoRow(
              icon: Icons.preview_outlined,
              title: "Link previews",
              subtitle: "What you see in this room",
              onTap: () => open(RoomLinkPreviewsPage(matrixRoom)),
            ),
          if (room.client is MatrixClient && MatrixNicknames.enabled)
            InfoRow(
              icon: Icons.badge_outlined,
              title: "My nickname here",
              onTap: () => open(RoomNicknamePage(room, space: contextSpace)),
            ),
          if (wallpaper != null)
            InfoRow(
              icon: Icons.wallpaper_outlined,
              title: "Wallpaper",
              onTap: () => ChatWallpaperEditor.show(context, wallpaper),
            ),
          if (translation.supported)
            InfoRow(
              icon: Icons.translate,
              title: "Translation",
              value: translation.isOn(room.identifier) ? "On" : "Off",
              onTap: () => showRoomTranslationSheet(context, room),
            ),
          InfoRow(
            key: const ValueKey("room-info-organize"),
            icon: Icons.bookmark_border,
            title: "Organize",
            subtitle: "Favorite, tags, direct chat",
            value: room.isFavorite ? "Favorite" : null,
            onTap: () => open(RoomOrganizePage(room)),
          ),
          if (matrixRoom != null && room.isE2EE)
            InfoRow(
              icon: Icons.key_outlined,
              title: "Encryption for you",
              subtitle: "Whether people who join later can read your messages",
              onTap: () => open(RoomEncryptionForYouPage(matrixRoom)),
            ),
        ]),
      ],
    );
  }
}

/// Favorite, tags, mark as read and the direct-chat switch (which is the
/// only place, besides Move to Rooms, that changes m.direct).
class RoomOrganizePage extends StatefulWidget {
  const RoomOrganizePage(this.room, {super.key});
  final Room room;

  @override
  State<RoomOrganizePage> createState() => _RoomOrganizePageState();
}

class _RoomOrganizePageState extends State<RoomOrganizePage> {
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final dm = room.client.getComponent<DirectMessagesComponent>();
    final isDm = dm?.isRoomDirectMessage(room) == true;
    final candidate = isDm ? null : dm?.directMessageCandidate(room);
    final partnerId = isDm ? dm?.getDirectMessagePartnerId(room) : candidate;
    final partnerName = partnerId == null
        ? null
        : room.getMemberOrFallback(partnerId).displayName;
    return InfoSubPage(
      title: "Organize",
      subtitle: forYouSubtitle(room),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoGroup([
            InfoSwitchRow(
              icon: Icons.star_border,
              title: "Favorite",
              value: room.isFavorite,
              onChanged: (value) async {
                await room.setAsFavorite(value);
                if (mounted) setState(() {});
              },
            ),
            if (canTagRoom(room))
              InfoRow(
                icon: Icons.label_outline,
                title: "Tags",
                subtitle: "Low priority, your own tags",
                onTap: () => showRoomTags(context, room),
              ),
            InfoRow(
              icon: Icons.mark_chat_read_outlined,
              title: "Mark as read",
              chevron: false,
              onTap: () {
                room.markAsRead();
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text("Marked as read")));
              },
            ),
            if (dm != null && (isDm || candidate != null))
              InfoSwitchRow(
                key: const ValueKey("room-info-direct-chat-switch"),
                icon: Icons.person_outline,
                title: partnerName == null
                    ? "Direct chat"
                    : "Direct chat with $partnerName",
                subtitle: "Shows with your direct messages, on all your apps",
                value: isDm,
                onChanged: (value) async {
                  await dm.setDirectMessage(room, value);
                  if (mounted) setState(() {});
                },
              ),
          ]),
        ],
      ),
    );
  }
}

/// "Room settings": shown to everyone, read-only (with a lock) where the
/// user can't change a row.
class RoomInfoRoomSettings extends StatelessWidget {
  const RoomInfoRoomSettings(this.room, {this.contextSpace, super.key});
  final Room room;
  final Space? contextSpace;

  @override
  Widget build(BuildContext context) {
    void open(Widget page) => InfoSubPage.open(context, page);
    final p = room.permissions;
    final matrixRoom = room is MatrixRoom ? room as MatrixRoom : null;
    final emoticons = room.getComponent<RoomEmoticonComponent>();
    final calendar = room.getComponent<CalendarRoom>();
    final bridges = matrixRoom == null
        ? const []
        : matrixRoomBridges(matrixRoom.matrixRoom);
    final direct = roomInfoIsDirectChat(room);
    final admins = <String>{};
    final mods = <String>{};
    for (final (member, role) in room.importantMembers()) {
      if (role is! MatrixRole) continue;
      if (role.powerLevel >= 100) {
        admins.add(member.identifier);
      } else if (role.powerLevel >= 50) {
        mods.add(member.identifier);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoSectionHeader(direct ? "Chat settings" : "Room settings",
            icon: Icons.groups_outlined,
            caption: "Changes here apply to everyone."),
        InfoGroup([
          InfoRow(
            key: const ValueKey("room-info-room-profile"),
            icon: Icons.edit_outlined,
            title: "Room profile",
            subtitle: "Name, topic, avatar, banner",
            locked: !p.canEditAppearance && !p.canEditTopic,
            onTap: () => RoomInfoActions.editProfile(context, room),
          ),
          InfoRow(
            key: const ValueKey("room-info-privacy"),
            icon: Icons.shield_outlined,
            title: "Privacy & access",
            subtitle: "Who can join, history, guests, encryption",
            value: _visibilityLabel(room),
            locked: !p.canEditRoomSecurity && !p.canChangeVisibility,
            onTap: () =>
                open(RoomPrivacyAccessPage(room, contextSpace: contextSpace)),
          ),
          if (matrixRoom != null)
            InfoRow(
              icon: Icons.alternate_email,
              title: "Addresses & directory",
              value: matrixRoom.matrixRoom.canonicalAlias.isEmpty
                  ? "None"
                  : matrixRoom.matrixRoom.canonicalAlias,
              onTap: () => open(RoomAddressesPage(matrixRoom)),
            ),
          if (matrixRoom != null)
            InfoRow(
              key: const ValueKey("room-info-roles"),
              icon: Icons.admin_panel_settings_outlined,
              title: "Roles & permissions",
              subtitle: "Who can post, invite, call, change settings; bans",
              value: [
                if (admins.isNotEmpty)
                  "${admins.length} admin${admins.length == 1 ? "" : "s"}",
                if (mods.isNotEmpty)
                  "${mods.length} mod${mods.length == 1 ? "" : "s"}",
              ].join(" · "),
              locked: !p.canChangeRoles,
              onTap: () => open(InfoSubPage(
                  title: "Roles & permissions",
                  subtitle: forEveryoneSubtitle(room),
                  scrollable: false,
                  child: MatrixRoomPermissionsPage(matrixRoom.matrixRoom,
                      showCalendarPermissions: calendar?.hasCalendar == true))),
            ),
          if (emoticons != null &&
              (p.canEditRoomEmoticons || emoticons.ownedPacks.isNotEmpty))
            InfoRow(
              icon: Icons.emoji_emotions_outlined,
              title: "Emoji & stickers",
              locked: !p.canEditRoomEmoticons,
              onTap: () => open(InfoSubPage(
                  title: "Emoji & stickers",
                  subtitle: forEveryoneSubtitle(room),
                  child: RoomEmojiPackSettingsPage(room))),
            ),
          if (bridges.isNotEmpty)
            InfoRow(
              icon: Icons.hub_outlined,
              title: "Bridges",
              value: "${bridges.length}",
              onTap: () => open(InfoSubPage(
                  title: "Bridges",
                  subtitle: room.displayName,
                  child:
                      MatrixRoomBridgesSettingsPage(matrixRoom!.matrixRoom))),
            ),
          if (calendar?.hasCalendar == true)
            InfoRow(
              icon: Icons.event_repeat_outlined,
              title: "Calendar sync",
              onTap: () => open(InfoSubPage(
                  title: "Calendar sync",
                  subtitle: room.displayName,
                  child: RoomCalendarSettingsPage(calendar!))),
            ),
          if (matrixRoom != null)
            InfoRow(
              icon: Icons.link_outlined,
              title: "Link previews (room default)",
              onTap: () => open(RoomLinkPreviewsPage(matrixRoom)),
            ),
          InfoRow(
            key: const ValueKey("room-info-advanced"),
            icon: Icons.code,
            title: "Advanced",
            subtitle: "Room ID, version, upgrade, reload history",
            onTap: () =>
                open(RoomAdvancedPage(room, contextSpace: contextSpace)),
          ),
        ]),
      ],
    );
  }
}

/// Share room link, Report room, Leave room.
class RoomInfoFooter extends StatelessWidget {
  const RoomInfoFooter(this.room, {this.onLeaveRoom, super.key});
  final Room room;
  final VoidCallback? onLeaveRoom;

  @override
  Widget build(BuildContext context) {
    final direct = roomInfoIsDirectChat(room);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: InfoGroup([
        InfoRow(
          icon: Icons.share_outlined,
          title: "Share room link",
          subtitle: RoomInfoActions.link(room),
          chevron: false,
          onTap: () => RoomInfoActions.shareLink(context, room),
        ),
        if (room is MatrixRoom)
          InfoRow(
            icon: Icons.flag_outlined,
            title: "Report room",
            danger: true,
            onTap: () => RoomInfoActions.report(context, room),
          ),
        InfoRow(
          key: const ValueKey("room-info-leave"),
          icon: Icons.logout,
          title: direct ? "Leave chat" : "Leave room",
          danger: true,
          onTap: () =>
              RoomInfoActions.leave(context, room, onLeaveRoom: onLeaveRoom),
        ),
      ]),
    );
  }
}
