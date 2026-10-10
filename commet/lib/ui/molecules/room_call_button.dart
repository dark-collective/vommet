import 'dart:async';

import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: what the room's Call button shows.
enum RoomCallButtonState {
  /// Nobody is in a call: tap starts one.
  start,

  /// People are in a call: green, with how many; tap joins.
  join,

  /// This device is in the room's call.
  inCall,

  /// You can't post a call membership here: grey lock; tap explains.
  locked,

  /// An encrypted room without Encrypted Element Call on: grey lock; tap
  /// explains how to turn it on.
  needsEncryptedCalls;

  static RoomCallButtonState of(
      {required bool inCallHere,
      required bool encryptedCallsOff,
      required bool canJoin,
      required int participants}) {
    if (inCallHere) return inCall;
    if (encryptedCallsOff) return needsEncryptedCalls;
    if (!canJoin) return locked;
    return participants > 0 ? join : start;
  }

  String tooltip(int participants) => switch (this) {
        start => "Start a call",
        join => participants == 1
            ? "Join call · 1 person"
            : "Join call · $participants people",
        inCall => "You're in this call",
        locked => "You can't call in this room",
        needsEncryptedCalls => "Needs Encrypted Element Call",
      };
}

/// The Call button's icon, kept up to date as people join and leave and as
/// this device's own call starts and ends.
class RoomCallButtonIcon extends StatefulWidget {
  const RoomCallButtonIcon(this.room, {this.size = 20, super.key});
  final Room room;
  final double size;

  @override
  State<RoomCallButtonIcon> createState() => _RoomCallButtonIconState();
}

class _RoomCallButtonIconState extends State<RoomCallButtonIcon> {
  final List<StreamSubscription> subs = [];
  Timer? expiryCheck;

  @override
  void initState() {
    super.initState();
    attach();
  }

  @override
  void didUpdateWidget(covariant RoomCallButtonIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      detach();
      attach();
    }
  }

  void attach() {
    void refresh(_) {
      if (mounted) setState(() {});
    }

    final component = widget.room.getComponent<RoomCallComponent>();
    if (component != null) {
      subs.add(component.onParticipantsChanged.listen(refresh));
    }
    final sessions = clientManager?.callManager.currentSessions;
    if (sessions != null) {
      subs.add(sessions.onAdd.listen(refresh));
      subs.add(sessions.onRemove.listen(refresh));
    }
    // Memberships also lapse by time (`expires`), without a sync.
    expiryCheck = Timer.periodic(const Duration(minutes: 1), refresh);
  }

  void detach() {
    for (final sub in subs) {
      sub.cancel();
    }
    subs.clear();
    expiryCheck?.cancel();
  }

  @override
  void dispose() {
    detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = RoomCallActions.participants(widget.room);
    final state = RoomCallActions.stateOf(widget.room);
    return Tooltip(
      message: state.tooltip(count),
      child: RoomCallStateIcon(state, participants: count, size: widget.size),
    );
  }
}

/// The icon for a call button state (no listening; see RoomCallButtonIcon).
class RoomCallStateIcon extends StatelessWidget {
  const RoomCallStateIcon(this.state,
      {this.participants = 0, this.size = 20, super.key});
  final RoomCallButtonState state;
  final int participants;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final green = Colors.green.shade400;
    switch (state) {
      case RoomCallButtonState.start:
        return Icon(Icons.call, size: size, color: scheme.secondary);
      case RoomCallButtonState.join:
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.phone_in_talk, size: size, color: green),
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: green, borderRadius: BorderRadius.circular(8)),
              child: Text(participants > 99 ? "99+" : "$participants",
                  style: const TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: Colors.black,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ]);
      case RoomCallButtonState.inCall:
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
              color: green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(Icons.phone_in_talk, size: size - 4, color: green),
        );
      case RoomCallButtonState.locked:
      case RoomCallButtonState.needsEncryptedCalls:
        return Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.call,
              size: size, color: scheme.onSurface.withValues(alpha: 0.35)),
          Positioned(
              right: -6,
              bottom: -4,
              child:
                  Icon(Icons.lock, size: 12, color: scheme.onSurfaceVariant)),
        ]);
    }
  }
}

/// Vommet: the Call button's tap, by state.
class RoomCallButtonActions {
  static Future<void> onTap(BuildContext context, Room room) async {
    final component = room.getComponent<RoomCallComponent>();
    if (component == null) return;
    switch (RoomCallActions.stateOf(room)) {
      case RoomCallButtonState.inCall:
        return;
      case RoomCallButtonState.needsEncryptedCalls:
      case RoomCallButtonState.join:
        // joinOrStart explains the encrypted-room case itself.
        return RoomCallActions.joinOrStart(context, room, start: false);
      case RoomCallButtonState.locked:
        return explainLocked(context, component.permissions);
      case RoomCallButtonState.start:
        final permissions = component.permissions;
        if (permissions.othersBlocked && permissions.canChangePermissions) {
          final choice = await _askMembersCantJoin(context, permissions);
          if (choice == null || !context.mounted) return;
          if (choice) {
            try {
              await component.letEveryoneJoin();
            } catch (e, s) {
              if (context.mounted)
                await AdaptiveDialog.showError(context, e, s);
              return;
            }
          }
          if (!context.mounted) return;
        }
        return RoomCallActions.joinOrStart(context, room, start: true);
    }
  }

  static Future<void> explainLocked(
      BuildContext context, RoomCallPermissions p) {
    return AdaptiveDialog.show(context,
        title: "You can't call in this room",
        builder: (_) => tiamat.Text.label(
            "Starting or joining a call needs permission to post call "
            "membership. This room gives that to "
            "${RoomCallPermissions.levelName(p.requiredLevel)}; you have "
            "${p.ownLevel}. A room admin can change it in Room settings › "
            "Roles & permissions."));
  }

  /// True: let everyone join, then start. False: start anyway. Null: cancel.
  static Future<bool?> _askMembersCantJoin(
      BuildContext context, RoomCallPermissions p) {
    return AdaptiveDialog.show<bool>(context,
        title: "Members can't join this call",
        builder: (dialogContext) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tiamat.Text.label(
                    "Joining a call needs permission to post call membership, "
                    "and this room only gives that to "
                    "${RoomCallPermissions.levelName(p.requiredLevel)}. You "
                    "can call, but members won't be able to join you."),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text("Start anyway"),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text("Let everyone join, then start"),
                    ),
                  ],
                ),
              ],
            ));
  }
}
