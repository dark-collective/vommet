import 'dart:async';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/ui/molecules/room_call_button.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: "Call in progress — Join" above the chat of an ordinary room when
/// people are in an Element Call / Element X call there (experiment).
class RoomCallBar extends StatefulWidget {
  const RoomCallBar(this.room, {super.key});
  final Room room;

  @override
  State<RoomCallBar> createState() => _RoomCallBarState();
}

class _RoomCallBarState extends State<RoomCallBar> {
  String get roomCallBarNoPermission => Intl.message("No permission to join",
      name: "roomCallBarNoPermission",
      desc:
          "Call bar above a room's messages while a call is going on: shown instead of the Join button");

  String get roomCallBarNeedsE2eeCalls => Intl.message(
      "Turn on Encrypted Element Call in Settings › Experiments to join",
      name: "roomCallBarNeedsE2eeCalls",
      desc:
          "Call bar above a room's messages while a call is going on: shown instead of the Join button in an encrypted room");

  String roomCallBarPeopleInCall(int count) => Intl.plural(count,
      one: "1 person in a call",
      other: "$count people in a call",
      args: [count],
      name: "roomCallBarPeopleInCall",
      desc:
          "Call bar above a room's messages while a call is going on: how many people are in the call");

  RoomCallComponent? component;
  StreamSubscription? sub;
  Timer? expiryCheck;
  List<String> participants = [];
  bool joining = false;

  @override
  void initState() {
    super.initState();
    attach();
  }

  @override
  void didUpdateWidget(covariant RoomCallBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      detach();
      attach();
    }
  }

  void attach() {
    component = widget.room.getComponent<RoomCallComponent>();
    participants = component?.getCurrentParticipants() ?? [];
    sub = component?.onParticipantsChanged.listen((_) => refresh());
    // Memberships also lapse by time (`expires`), without a sync.
    expiryCheck = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  void detach() {
    sub?.cancel();
    expiryCheck?.cancel();
    joining = false;
  }

  void refresh() {
    if (!mounted) return;
    setState(() {
      participants = component?.getCurrentParticipants() ?? [];
    });
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  Future<void> join() async {
    setState(() => joining = true);
    await RoomCallActions.joinOrStart(context, widget.room, start: false);
    if (mounted) setState(() => joining = false);
  }

  @override
  Widget build(BuildContext context) {
    if (component == null ||
        participants.isEmpty ||
        !preferences.experimentRoomCalls.value) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final e2eeBlocked = widget.room.isE2EE &&
        !preferences.experimentEnableE2eeElementCall.value;
    final shown = participants.take(5).toList();

    final Widget action;
    if (!component!.canJoinCall) {
      action = tiamat.Text.labelLow(roomCallBarNoPermission);
    } else if (e2eeBlocked) {
      action = tiamat.Text.labelLow(roomCallBarNeedsE2eeCalls);
    } else {
      action = tiamat.Button(
        text: CommonStrings.promptJoin,
        isLoading: joining,
        onTap: join,
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.call, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            for (final id in shown)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Builder(builder: (context) {
                  final member = widget.room.getMemberOrFallback(id);
                  return Tooltip(
                    message: member.displayName,
                    child: tiamat.Avatar(
                      radius: 12,
                      image: member.avatar,
                      placeholderColor: member.defaultColor,
                      placeholderText: member.displayName,
                    ),
                  );
                }),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: tiamat.Text.label(
                roomCallBarPeopleInCall(participants.length),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: action),
          ],
        ),
      ),
    );
  }
}

/// Vommet: joining or starting a text-room call, shared by the call bar and
/// the room's Call button.
class RoomCallActions {
  static String get roomCallE2eeOffTitle => Intl.message(
      "Encrypted calls are off",
      name: "roomCallE2eeOffTitle",
      desc:
          "Title of the dialog shown when trying to call in an encrypted room with encrypted calls off");

  static String get roomCallE2eeOffBody => Intl.message(
      "This room is encrypted. Turn on Encrypted Element Call in Settings › Experiments to call here.",
      name: "roomCallE2eeOffBody",
      desc:
          "Body of the dialog shown when trying to call in an encrypted room with encrypted calls off");

  /// Whether the room's Call button should start/join a MatrixRTC call
  /// (instead of a legacy 1:1 call in DMs).
  static bool usesRoomCalls(Room room) =>
      preferences.experimentRoomCalls.value &&
      room.getComponent<RoomCallComponent>() != null;

  /// How many people are in the room's call.
  static int participants(Room room) =>
      room.getComponent<RoomCallComponent>()?.getCurrentParticipants().length ??
      0;

  /// Vommet: what the room's Call button shows (see RoomCallButtonState).
  static RoomCallButtonState stateOf(Room room) {
    final component = room.getComponent<RoomCallComponent>();
    return RoomCallButtonState.of(
      inCallHere: clientManager?.callManager
              .getCallInRoom(room.client, room.identifier) !=
          null,
      encryptedCallsOff:
          room.isE2EE && !preferences.experimentEnableE2eeElementCall.value,
      canJoin: component?.canJoinCall ?? false,
      participants: component?.getCurrentParticipants().length ?? 0,
      blocked: blockedDm(room),
    );
  }

  /// Vommet: a DM with someone you've blocked (block-users experiment).
  static bool blockedDm(Room room) {
    if (!preferences.experimentBlockUsers.value) return false;
    final partner = room.client
        .getComponent<DirectMessagesComponent>()
        ?.getDirectMessagePartnerId(room);
    if (partner == null) return false;
    return room.client
            .getComponent<UserBlockingComponent>()
            ?.isBlocked(partner) ??
        false;
  }

  static Future<void> joinOrStart(BuildContext context, Room room,
      {required bool start}) async {
    final component = room.getComponent<RoomCallComponent>();
    if (component == null) return;

    if (room.isE2EE && !preferences.experimentEnableE2eeElementCall.value) {
      await AdaptiveDialog.show(context,
          title: roomCallE2eeOffTitle,
          builder: (_) => tiamat.Text.label(roomCallE2eeOffBody));
      return;
    }
    if (!component.canJoinCall) {
      await RoomCallButtonActions.explainLocked(context, component.permissions);
      return;
    }

    try {
      if (start) {
        await component.startCall();
      } else {
        await component.joinCall();
      }
    } catch (e, s) {
      if (context.mounted) await AdaptiveDialog.showError(context, e, s);
    }
  }
}
