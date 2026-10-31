import 'package:commet/client/client.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:commet/client/components/threads/thread_component.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/molecules/room_call_button.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_editor.dart';
import 'package:commet/ui/organisms/room_quick_access_menu/room_quick_access_extras.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/utils/translation/room_translation.dart';
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

    // Vommet (issue 444): widgets in voice rooms too; WidgetCallGuard keeps
    // them out of the call.
    final bool hasWidgets = room.client.getComponent<WidgetComponent>() != null;

    // Vommet issue 680 phase 2, where translation runs.
    final translation = RoomTranslation.instance;

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
        if (hasWidgets)
          RoomQuickAccessMenuEntry(
              name: "Widgets",
              action: (context) => EventBus.openWidgets.add(null),
              icon: Icons.widgets),
      ],
      // Vommet issue 611: search opens in the chat (the header becomes the
      // search field), whether or not the side panel is shown. Phones have
      // the magnifier in the room header instead.
      if (canSearch && MediaQuery.of(context).desktop)
        RoomQuickAccessMenuEntry(
            name: CommonStrings.promptSearch,
            action: (context) => InChatSearch.of(room).toggle(),
            icon: Icons.search),
      if (translation.supported)
        RoomQuickAccessMenuEntry(
            name: translation.isOn(room.identifier)
                ? "Stop translating this room"
                : "Translate this room",
            action: (context) => translation.setOn(
                room.identifier, !translation.isOn(room.identifier)),
            icon: Icons.translate),
      // Vommet issue 746: a 1:1 chat's shared wallpaper. In the
      // Discord-style layout it's in the room's ▾ menu.
      if (ChatWallpaperEditor.availableIn(room) case final wallpaper?)
        RoomQuickAccessMenuEntry(
            name: ChatWallpaperEditor.chatWallpaperTitle,
            action: (context) => ChatWallpaperEditor.show(context, wallpaper),
            icon: Icons.wallpaper),
      if (MediaQuery.of(context).desktop)
        RoomQuickAccessMenuEntry(
            name: "Toggle Panel",
            action: (context) => EventBus.toggleRoomSidePanel.add(null),
            // Vommet: the arrow follows what's on screen; a narrow window
            // hides the member list whatever the setting says.
            icon: RoomChatLayout.panelShownOf(context) ??
                    !preferences.hideRoomSidePanel.value
                ? Icons.chevron_right
                : Icons.chevron_left),
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

/// Vommet issue 592: on phones a DM's header shows its call button beside
/// [drawerButton] (the chevron opening the member drawer), so calling isn't
/// hidden in the drawer. Other rooms keep just [drawerButton].
Widget phoneRoomHeaderMenu(
    BuildContext context, Room room, Widget drawerButton) {
  final direct = room.client.getComponent<DirectMessagesComponent>();
  if (direct?.isRoomDirectMessage(room) != true) return drawerButton;
  final call = RoomQuickAccessMenu(room: room, context: context)
      .actions
      .where((e) => e.icon == Icons.call)
      .firstOrNull;
  if (call == null) return drawerButton;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 34,
        height: 34,
        child: KeyedSubtree(
          key: const ValueKey("room-header-call-button"),
          child: roomQuickAccessButton(context, call),
        ),
      ),
      drawerButton,
    ],
  );
}
