import 'package:commet/client/client.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/molecules/room_call_button.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_extras.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomQuickAccessMenu {
  final Room room;
  late final List<RoomQuickAccessMenuEntry> actions;

  RoomQuickAccessMenu({required this.room, required BuildContext context}) {
    final bool canSearch =
        room.client.getComponent<EventSearchComponent>() != null;

    final invitation = room.client.getComponent<InvitationComponent>();

    final bool supportsPinnedMessages =
        room.getComponent<PinnedMessagesComponent>() != null;

    final bool supportsThreads =
        room.client.getComponent<ThreadsComponent>() != null;

    final calls = room.client.getComponent<VoipComponent>();
    final direct = room.client.getComponent<DirectMessagesComponent>();
    final calendar = room.getComponent<CalendarRoom>();
    // Vommet: with "Calls in text rooms", Call starts (or joins) an Element
    // Call compatible call in any ordinary room, DMs included; Element X
    // can't answer legacy 1:1 calls. Commet (and Vommet without the
    // experiment) can't join those, so DMs keep the legacy call as
    // "Classic call".
    final bool roomCalls = RoomCallActions.usesRoomCalls(room);
    final bool canCall =
        calls != null && direct?.isRoomDirectMessage(room) == true;

    final bool isVoipRoom = room.getComponent<VoipRoomComponent>() != null;

    // Dont show widgets in Voip room. If the widget uses MatrixRTC,
    // it seems to interfere with the ongoing call...
    final bool hasWidgets = isVoipRoom == false &&
        room.client.getComponent<WidgetComponent>() != null;

    actions = [
      if (invitation != null)
        RoomQuickAccessMenuEntry(
            name: "Invite",
            action: (context) => AdaptiveDialog.show(context,
                builder: (context) => SendInvitationWidget(
                      room.client,
                      invitation,
                      roomId: room.identifier,
                      displayName: room.displayName,
                      existingMembers: room.memberIds,
                    ),
                title: "Invite"),
            icon: Icons.person_add),
      if (roomCalls) _callEntry(room, classic: canCall ? calls : null),
      if (canCall && !roomCalls)
        RoomQuickAccessMenuEntry(
            name: "Call",
            action: (context) =>
                calls.startCall(room.identifier, CallType.voice),
            icon: Icons.call),
      if (preferences.hideRoomSidePanel.value == false ||
          MediaQuery.of(context).mobile) ...[
        if (calendar?.hasCalendar == true && calendar?.isCalendarRoom == false)
          RoomQuickAccessMenuEntry(
              name: "Calendar",
              action: (context) => EventBus.openCalendar.add(null),
              icon: Icons.calendar_month),
        if (supportsPinnedMessages)
          RoomQuickAccessMenuEntry(
              name: "Pinned Messages",
              action: (context) => EventBus.openPinnedMessages.add(null),
              icon: Icons.push_pin),
        if (supportsThreads)
          RoomQuickAccessMenuEntry(
              name: "Threads",
              action: (context) => EventBus.openThreadsList.add(null),
              icon: Icons.forum_outlined),
        if (canSearch)
          RoomQuickAccessMenuEntry(
              name: CommonStrings.promptSearch,
              action: (context) => EventBus.startSearch.add(null),
              icon: Icons.search),
        if (hasWidgets && !PlatformUtils.isWeb)
          RoomQuickAccessMenuEntry(
              name: "Widgets",
              action: (context) => EventBus.openWidgets.add(null),
              icon: Icons.widgets),
      ],
      if (MediaQuery.of(context).desktop)
        RoomQuickAccessMenuEntry(
            name: "Toggle Panel",
            action: (context) => EventBus.toggleRoomSidePanel.add(null),
            icon: preferences.hideRoomSidePanel.value
                ? Icons.chevron_left
                : Icons.chevron_right),
    ];
  }
}

/// Vommet: the room-call button, showing whether a call is on, whether
/// you're in it, or that you can't call (RoomCallButtonIcon). In DMs the
/// legacy 1:1 call is offered beside it as "Classic call (older clients)",
/// on right-click or long-press and in the ▾ menu, so DMs show one call
/// button.
RoomQuickAccessMenuEntry _callEntry(Room room, {VoipComponent? classic}) {
  final entry = RoomQuickAccessMenuEntry(
      name: "Call",
      action: (context) => RoomCallButtonActions.onTap(context, room),
      icon: Icons.call);
  RoomQuickAccessExtras.setIcon(
      entry, (context, size) => RoomCallButtonIcon(room, size: size));
  if (classic != null) {
    RoomQuickAccessExtras.setSecondary(entry, [
      RoomQuickAccessMenuEntry(
          name: "Classic call (older clients)",
          action: (context) =>
              classic.startCall(room.identifier, CallType.voice),
          icon: Icons.phone_callback),
    ]);
  }
  return entry;
}

/// Vommet: an action as the views draw it: its button, with any secondary
/// entries on right-click or long-press.
Widget roomQuickAccessButton(
    BuildContext context, RoomQuickAccessMenuEntry entry,
    {double size = 20}) {
  final secondary = RoomQuickAccessExtras.secondary(entry);
  return AdaptiveContextMenu(
    items: [
      for (final s in secondary)
        tiamat.ContextMenuItem(
            text: s.name,
            icon: s.icon,
            onPressed: () => s.action?.call(context)),
    ],
    child: RoomQuickAccessExtras.button(context, entry, size: size),
  );
}

class RoomQuickAccessMenuEntry {
  final String name;
  final Function(BuildContext context)? action;
  final IconData icon;

  RoomQuickAccessMenuEntry(
      {required this.name, required this.action, required this.icon});
}
