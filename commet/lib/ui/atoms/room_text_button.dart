import 'dart:async';

import 'package:commet/client/components/activities/activities_component.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/history_reload/history_reload_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/room_avatar_badge.dart';
import 'package:commet/ui/atoms/dot_indicator.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/atoms/sidebar_pin_menu.dart';
import 'package:commet/ui/atoms/tiny_pill.dart';
import 'package:commet/ui/atoms/room_view_mode.dart';
import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/room_settings_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/text_utils.dart';
import 'package:commet_calendar_widget/calendar.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomTextButton extends StatefulWidget {
  const RoomTextButton(
    this.room, {
    this.highlight = false,
    this.onTap,
    this.extraMenuItems = const [],
    super.key,
  });
  final bool highlight;
  final Room room;
  final Function(Room room, {bool bypassSpecialRoomType})? onTap;

  /// Appended to the room's context menu (e.g. "Remove from <space>").
  final List<ContextMenuItem> extraMenuItems;

  @override
  State<RoomTextButton> createState() => _RoomTextButtonState();

  static List<ContextMenuItem> createRoomContextMenuItems(
      BuildContext context, Room room) {
    var voipRoom = room.getComponent<VoipRoomComponent>();
    // Vommet: switch a chat to/from a direct message (and back).
    var directMessages = room.client.getComponent<DirectMessagesComponent>();
    var isDirectMessage = directMessages?.isRoomDirectMessage(room) == true;
    var canBeDirectMessage = !isDirectMessage &&
        directMessages?.directMessageCandidate(room) != null;
    return [
      // Vommet: "Open Chat" first for voice rooms, like Discord.
      if (room.isSpecialRoomType && preferences.experimentVoiceRoomChat.value)
        ContextMenuItem(
            text: "Open Chat",
            icon: Icons.chat_bubble_outline,
            onPressed: () => EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier, bypassSpecialRoomType: true)),
      ContextMenuItem(
          text: "Mark as Read",
          icon: Icons.visibility,
          tooltip: "Clear this room's unread count and notifications",
          onPressed: () => room.markAsRead()),
      if (!room.isFavorite)
        ContextMenuItem(
            text: "Set as Favorite",
            icon: Icons.favorite,
            tooltip: "Pin this room to the top of your room list",
            onPressed: () => room.setAsFavorite(true)),
      if (room.isFavorite)
        ContextMenuItem(
            text: "Unfavorite",
            icon: Icons.heart_broken_outlined,
            tooltip: "Stop pinning this room to the top of your room list",
            onPressed: () => room.setAsFavorite(false)),
      if (room.isSpecialRoomType && !preferences.experimentVoiceRoomChat.value)
        ContextMenuItem(
            text: "Open as Text Chat",
            icon: Icons.tag,
            tooltip:
                "Open the room's messages instead of its call or other view",
            onPressed: () => EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier, bypassSpecialRoomType: true)),
      if (voipRoom != null && preferences.developerMode.value)
        ContextMenuItem(
          text: "Clear Membership Status",
          icon: Icons.call_end,
          tooltip: "Developer: remove stale call memberships in this room",
          onPressed: () => voipRoom.clearAllCallMembershipStatus(),
        ),
      if (canBeDirectMessage)
        ContextMenuItem(
            text: "Mark as Direct Message",
            icon: Icons.person,
            tooltip:
                "List this chat under Direct Messages, in every app you use. "
                "Only for chats with one other person. You can undo this",
            onPressed: () => directMessages!.setDirectMessage(room, true)),
      if (isDirectMessage)
        ContextMenuItem(
            text: "Not a Direct Message",
            icon: Icons.group,
            tooltip:
                "Move this chat out of Direct Messages, in every app you use. "
                "Nothing else about the chat changes",
            onPressed: () => directMessages!.setDirectMessage(room, false)),
      ContextMenuItem(
          text: "Settings",
          icon: Icons.settings,
          tooltip: "Name, picture, permissions, encryption and more",
          onPressed: () {
            NavigationUtils.navigateTo(
                context,
                RoomSettingsPage(
                  room: room,
                ));
          }),
      ...sidebarPinMenuItems(room),
      // Vommet: load the room's history again, for when it has a gap.
      if (room.getComponent<HistoryReloadComponent>() != null)
        ContextMenuItem(
            text: "Reload History",
            icon: Icons.history,
            onPressed: () =>
                room.getComponent<HistoryReloadComponent>()?.reloadHistory()),
    ];
  }
}

class _RoomTextButtonState extends State<RoomTextButton> {
  late List<StreamSubscription> subs;

  /// Vommet: the pointer is over this row (for the voice room chat button).
  bool hovering = false;
  CalendarRoom? calendarRoom;
  ActivitiesComponent? activities;
  List<RoomActivitySession>? activitySessions;
  List<MatrixCalendarEventState>? calendarEvents;

  @override
  void initState() {
    calendarRoom = widget.room.getComponent<CalendarRoom>();
    activities = widget.room.getComponent<ActivitiesComponent>();

    subs = [
      widget.room.onUpdate.listen(onRoomUpdate),
      if (calendarRoom != null)
        calendarRoom!.onEventsChanged.listen(onCalendarEventsChanged),
      if (activities != null)
        activities!.onSessionsChanged.listen(onSessionsChanged),
    ];

    if (activities != null) {
      activitySessions = activities?.getSessions();
      sortActivities();
    }

    if (calendarRoom?.calendar != null) {
      onCalendarEventsChanged(());
    }

    if (activitySessions?.isNotEmpty == true) {
      for (var activity in activitySessions!) {
        for (var participant in activity.participants) {
          widget.room.fetchMember(participant).then((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    }

    super.initState();
  }

  void onSessionsChanged(void event) {
    setState(() {
      activitySessions = activities?.getSessions();
      sortActivities();
    });
  }

  void sortActivities() {
    activitySessions?.sort(
        (a, b) => (a.thirdparty ? 1 : 0).compareTo(b.thirdparty ? 1 : 0));
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void onCalendarEventsChanged(void event) {
    setState(() {
      calendarEvents = calendarRoom!
          .getEventsOnDay(DateTime.now())
          .where((i) => i.isUnavailability == false)
          .toList();
    });
  }

  void onRoomUpdate(void event) {
    setState(() {});
  }

  static const double height = 37;

  @override
  Widget build(BuildContext context) {
    IconData defaultIcon = widget.room.icon;

    var color = Theme.of(context).colorScheme.secondary;

    if (widget.room.notificationCount > 0 ||
        widget.room.highlightedNotificationCount > 0 ||
        widget.highlight) {
      color = Theme.of(context).colorScheme.onSurface;
    }

    // Vommet: headphones that turn green while people are in the call.
    final occupancy = widget.room.getComponent<VoipRoomComponent>() != null
        ? VoiceRoomOccupancy.of(widget.room, activitySessions)
        : null;
    if (occupancy != null) defaultIcon = Icons.headphones;
    final iconColor =
        occupancy?.occupied == true ? VoiceRoomOccupancy.green : color;
    if (occupancy?.includesYou == true) color = VoiceRoomOccupancy.green;

    bool showRoomIcons = preferences.showRoomAvatars.value;
    bool useGenericIcons = preferences.usePlaceholderRoomAvatars.value;

    bool shouldShowDefaultIcon = (!showRoomIcons && !useGenericIcons) ||
        (showRoomIcons && !useGenericIcons && widget.room.avatar == null);

    String displayName = widget.room.displayName;

    Color? avatarPlaceholderColor =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.defaultColor
            : null;

    String? avatarPlaceholderText =
        (showRoomIcons && useGenericIcons && widget.room.avatar == null) ||
                (!showRoomIcons && useGenericIcons)
            ? widget.room.displayName
            : null;

    bool startsWithEmoji =
        TextUtils.isEmoji(widget.room.displayName.characters.first);

    if (startsWithEmoji && widget.room.avatar == null) {
      shouldShowDefaultIcon = false;
      var emoji = displayName.characters.first;
      displayName = displayName.characters.skip(1).string.trim();
      avatarPlaceholderColor = Colors.transparent;
      avatarPlaceholderText = emoji;
    }
    var customBuilder = null;

    if (calendarEvents?.isNotEmpty == true) {
      customBuilder = buildEvents;
    }

    if (activitySessions?.isNotEmpty == true) {
      customBuilder = buildActivities;
    }

    Widget result = SizedBox(
      height: customBuilder == null ? height : null,
      child: tiamat.TextButton(
        displayName,
        customBuilder: customBuilder,
        highlighted: widget.highlight || occupancy?.includesYou == true,
        highlightColor: occupancy?.includesYou == true && !widget.highlight
            ? VoiceRoomOccupancy.green.withValues(alpha: 0.12)
            : null,
        icon: shouldShowDefaultIcon ? defaultIcon : null,
        avatar: showRoomIcons && widget.room.avatar != null
            ? widget.room.avatar
            : null,
        avatarRadius: 12,
        avatarBadge: roomAvatarBadge(widget.room),
        avatarBadgeColor:
            occupancy?.occupied == true ? VoiceRoomOccupancy.green : null,
        avatarPlaceholderColor: avatarPlaceholderColor,
        avatarPlaceholderText: avatarPlaceholderText,
        iconColor: iconColor,
        textColor: color,
        softwrap: false,
        onTap: () => widget.onTap?.call(widget.room),
        footer: withChatButton(occupancy?.occupied == true
            ? occupancy!.buildCount()
            : widget.room.displayHighlightedNotificationCount > 0
                ? NotificationBadge(
                    widget.room.displayHighlightedNotificationCount)
                : widget.room.displayNotificationCount > 0
                    ? const Padding(
                        padding: EdgeInsets.all(2.0), child: DotIndicator())
                    : null),
      ),
    );
    // Vommet: hovering shows a voice room's chat button.
    result = MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: result,
    );

    result = AdaptiveContextMenu(
      items: [
        ...RoomTextButton.createRoomContextMenuItems(context, widget.room),
        ...widget.extraMenuItems,
      ],
      child: result,
    );

    return result;
  }

  /// Vommet: [footer] with an "Open chat" button before it while a voice
  /// room's row is hovered (experiment `experiment_voice_room_chat`).
  Widget? withChatButton(Widget? footer) {
    if (!hovering || !RoomViewMode.offersChat(widget.room)) return footer;
    final scheme = Theme.of(context).colorScheme;
    final button = tiamat.Tooltip(
      text: "Open chat",
      child: SizedBox(
        width: 26,
        height: 26,
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () =>
                widget.onTap?.call(widget.room, bypassSpecialRoomType: true),
            child: Icon(Icons.chat_bubble_outline,
                size: 15, color: scheme.onSurface),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.only(right: 4), child: button),
        if (footer != null) footer,
      ],
    );
  }

  Widget buildActivities(Widget child, BuildContext context) {
    Iterable<RoomActivitySession> sessions = activitySessions!;

    if (activitySessions!.any((i) => i.thirdparty == false)) {
      sessions = activitySessions!.where((i) => i.thirdparty == false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: height, child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var activity in sessions)
                buildActivity(
                  activity,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildActivity(RoomActivitySession activity) {
    // Vommet: with the experiment, the call's people are a plain list under
    // the room (as on Discord) instead of a card.
    final plain = !activity.thirdparty &&
        preferences.experimentSidebarSubspaceGuides.value;
    if (plain) {
      return AdaptiveContextMenu(
        items: [
          tiamat.ContextMenuItem(
            text: "Clear Memberships",
            onPressed: () => activities!.clearMemberships(activity),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var participant in activity.participants)
                buildCallMember(participant, showActivityIcons: false),
            ],
          ),
        ),
      );
    }
    return AdaptiveContextMenu(
      items: [
        tiamat.ContextMenuItem(
          text: "Clear Memberships",
          onPressed: () {
            activities!.clearMemberships(activity);
          },
        ),
      ],
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: ColorScheme.of(context).surfaceTint.withAlpha(10),
            borderRadius: BorderRadius.circular(8)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: activity.associatedWidget == null
                ? null
                : () => onWidgetTapped(activity),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activity.thirdparty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                    child: Row(
                      spacing: 8,
                      children: [
                        SizedBox(
                            height: 20,
                            width: 20,
                            child: activity.icon.build(context)),
                        tiamat.Text.labelLow(activity.name),
                      ],
                    ),
                  ),
                if (activity.thirdparty)
                  tiamat.Seperator(
                    padding: 2,
                  ),
                for (var participant in activity.participants)
                  buildCallMember(participant,
                      showActivityIcons: activity.thirdparty == false),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEvents(Widget child, BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: height, child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 0, 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceDim.withAlpha(180),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  tiamat.Text.labelLow("Today: "),
                  for (var event in calendarEvents!) buildEvent(event),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildCallMember(String identifier, {bool showActivityIcons = true}) {
    var color = Theme.of(context).colorScheme.secondary;

    final member = widget.room.getMemberOrFallback(identifier);

    bool canShowActivityIcons = activitySessions != null && showActivityIcons;

    return SizedBox(
      height: height,
      child: tiamat.TextButton(
        member.displayName,
        textColor: color,
        avatar: member.avatar,
        avatarPlaceholderColor: member.defaultColor,
        avatarPlaceholderText: member.displayName,
        footer: canShowActivityIcons
            ? Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                child: Row(
                  children: [
                    for (var i in activitySessions!.where((i) =>
                        i.thirdparty == true &&
                        i.participants.contains(identifier)))
                      ClipRRect(
                        borderRadius: BorderRadiusGeometry.circular(4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: i.associatedWidget == null
                                ? null
                                : () => onWidgetTapped(i),
                            child: SizedBox(
                                height: 30,
                                width: 30,
                                child: Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: i.icon.build(context),
                                )),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  Widget buildEvent(MatrixCalendarEventState event) {
    var color =
        calendarRoom!.calendar!.config.getColorFromUser(event.senderId!);

    return TinyPill(
      event.data.title,
      background: calendarRoom!.calendar!.config.processEventColor(
        color,
        context,
      ),
      foreground: calendarRoom!.calendar!.config.processEventTextColor(
        color,
        context,
      ),
    );
  }

  Future<void> onWidgetTapped(RoomActivitySession activity) async {
    bool isInActivity = WidgetComponent.currentSessions.any(
      (element) =>
          element.info.type == activity.application &&
          widget.room == element.room,
    );

    if (isInActivity == false) {
      var confirm = await AdaptiveDialog.confirmation(context,
          prompt: "Open **${activity.associatedWidget!.name}**?");
      if (confirm == true) {
        WidgetComponent.runWidget(
            widget.room, context, activity.associatedWidget!);
      }
    } else {
      Log.i("Already has a widget in for this session");
    }
  }
}
