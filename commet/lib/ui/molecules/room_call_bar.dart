import 'dart:async';

import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: "Call in progress — Join" above the chat of an ordinary room when
/// people are in an Element Call / Element X call there (experiment).
class RoomCallBar extends StatefulWidget {
  const RoomCallBar(this.room, {super.key});
  final Room room;

  @override
  State<RoomCallBar> createState() => _RoomCallBarState();
}

class _RoomCallBarState extends State<RoomCallBar> {
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
      action = const tiamat.Text.labelLow("No permission to join");
    } else if (e2eeBlocked) {
      action = const tiamat.Text.labelLow(
          "Turn on Encrypted Element Call in Settings › Experiments to join");
    } else {
      action = tiamat.Button(
        text: "Join",
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
                participants.length == 1
                    ? "1 person in a call"
                    : "${participants.length} people in a call",
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
  /// Whether the room's Call button should start/join a MatrixRTC call
  /// (instead of a legacy 1:1 call in DMs).
  static bool usesRoomCalls(Room room) =>
      preferences.experimentRoomCalls.value &&
      room.getComponent<RoomCallComponent>() != null;

  static Future<void> joinOrStart(BuildContext context, Room room,
      {required bool start}) async {
    final component = room.getComponent<RoomCallComponent>();
    if (component == null) return;

    if (room.isE2EE && !preferences.experimentEnableE2eeElementCall.value) {
      await AdaptiveDialog.show(context,
          title: "Encrypted calls are off",
          builder: (_) => const tiamat.Text.label(
              "This room is encrypted. Turn on Encrypted Element Call in "
              "Settings › Experiments to call here."));
      return;
    }
    if (!component.canJoinCall) {
      await AdaptiveDialog.show(context,
          title: "Can't call here",
          builder: (_) => const tiamat.Text.label(
              "You don't have permission to join calls in this room."));
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
