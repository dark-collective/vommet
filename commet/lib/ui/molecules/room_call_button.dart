import 'dart:async';

import 'package:commet/client/components/room_call/room_call_component.dart';
import 'package:commet/client/components/user_blocking/user_blocking_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

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
  needsEncryptedCalls,

  /// Vommet: a DM with someone you've blocked: grey; tap explains.
  blocked,

  /// Vommet ("New room info page"): a direct chat whose other person left:
  /// grey; tap explains.
  partnerLeft;

  /// Whether a tap starts or joins a call (the hand cursor, Vommet issue
  /// 695); the other states only explain or do nothing.
  bool get callable => this == start || this == join;

  static RoomCallButtonState of(
      {required bool inCallHere,
      required bool encryptedCallsOff,
      required bool canJoin,
      required int participants,
      bool blocked = false,
      bool partnerLeft = false}) {
    if (inCallHere) return inCall;
    if (blocked) return RoomCallButtonState.blocked;
    if (partnerLeft) return RoomCallButtonState.partnerLeft;
    if (encryptedCallsOff) return needsEncryptedCalls;
    if (!canJoin) return locked;
    return participants > 0 ? join : start;
  }

  String tooltip(int participants) => switch (this) {
        start => RoomCallButtonActions.roomCallButtonStart,
        join => RoomCallButtonActions.roomCallButtonJoin(participants),
        inCall => RoomCallButtonActions.roomCallButtonInCall,
        locked => RoomCallButtonActions.roomCallButtonLocked,
        needsEncryptedCalls => RoomCallButtonActions.roomCallButtonNeedsE2ee,
        blocked => RoomCallButtonActions.roomCallButtonBlocked,
        partnerLeft => RoomCallButtonActions.roomCallButtonPartnerLeft,
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
    // Vommet ("New room info page"): so does the other person leaving or
    // coming back.
    if (roomInfoPageEnabled) {
      subs.add(widget.room.onMembersChanged.listen(refresh));
    }
    // Vommet: blocking or unblocking a DM partner greys or restores it.
    final blocking = widget.room.client.getComponent<UserBlockingComponent>();
    if (blocking != null) subs.add(blocking.onChanged.listen(refresh));
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
    final icon = _icon(context);
    // Vommet issue 695: the arrow while calling isn't possible here.
    if (state.callable) return icon;
    return MouseRegion(cursor: SystemMouseCursors.basic, child: icon);
  }

  Widget _icon(BuildContext context) {
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
      case RoomCallButtonState.blocked:
      case RoomCallButtonState.partnerLeft:
        return Icon(Icons.call,
            size: size, color: scheme.onSurface.withValues(alpha: 0.35));
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
  static String get roomCallButtonStart => Intl.message("Start a call",
      name: "roomCallButtonStart",
      desc: "Call button in a room's header: tooltip when nobody is in a call");

  static String roomCallButtonJoin(int count) => Intl.plural(count,
      one: "Join call · 1 person",
      other: "Join call · $count people",
      args: [count],
      name: "roomCallButtonJoin",
      desc:
          "Call button in a room's header: tooltip when people are in a call");

  static String get roomCallButtonInCall => Intl.message("You're in this call",
      name: "roomCallButtonInCall",
      desc: "Call button in a room's header: tooltip while you're in the call");

  static String get roomCallButtonLocked => Intl.message(
      "You can't call in this room",
      name: "roomCallButtonLocked",
      desc:
          "Call button in a room's header: tooltip and dialog title when you lack permission to call");

  static String get roomCallButtonNeedsE2ee => Intl.message(
      "Needs Encrypted Element Call",
      name: "roomCallButtonNeedsE2ee",
      desc:
          "Call button in a room's header: tooltip in an encrypted room while encrypted calls are off");

  static String get roomCallButtonBlocked => Intl.message(
      "You blocked this person",
      name: "roomCallButtonBlocked",
      desc:
          "Call button in a room's header: tooltip and dialog title in a direct message with someone you blocked");

  // Vommet ("New room info page"): experiment strings stay English.
  static String get roomCallButtonPartnerLeft => "They left this chat";

  static String get roomCallButtonPartnerLeftBody =>
      "Invite them back to call them here.";

  static String get roomCallButtonBlockedBody => Intl.message(
      "Unblock them from the bar under the chat to call.",
      name: "roomCallButtonBlockedBody",
      desc:
          "Call button in a room's header: body of the dialog in a direct message with someone you blocked");

  static String roomCallButtonLockedBody(String required, int own) => Intl.message(
      "Starting or joining a call needs the Join Call permission. This room gives it to $required; you have $own. A room admin can change it in Room settings › Permissions.",
      args: [required, own],
      name: "roomCallButtonLockedBody",
      desc:
          "Call button in a room's header: body of the dialog when you lack permission to call; required is a role name or power level, own is your power level number");

  static String get roomCallButtonMembersCantJoinTitle => Intl.message(
      "Members can't join this call",
      name: "roomCallButtonMembersCantJoinTitle",
      desc:
          "Call button in a room's header: title of the dialog before starting a call that members can't join");

  static String roomCallButtonMembersCantJoinBody(String required) => Intl.message(
      "Joining a call needs the Join Call permission, and this room only gives it to $required. You can call, but members won't be able to join you.",
      args: [required],
      name: "roomCallButtonMembersCantJoinBody",
      desc:
          "Call button in a room's header: body of the dialog before starting a call that members can't join; required is a role name or power level");

  static String get roomCallButtonStartAnyway => Intl.message("Start anyway",
      name: "roomCallButtonStartAnyway",
      desc:
          "Call button in a room's header: button that starts the call even though members can't join");

  static String get roomCallButtonLetEveryoneJoin => Intl.message(
      "Let everyone join, then start",
      name: "roomCallButtonLetEveryoneJoin",
      desc:
          "Call button in a room's header: button that changes the room's permissions so members can join, then starts the call");

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
      case RoomCallButtonState.blocked:
        await AdaptiveDialog.show(context,
            title: roomCallButtonBlocked,
            builder: (_) => tiamat.Text.label(roomCallButtonBlockedBody));
        return;
      case RoomCallButtonState.partnerLeft:
        return onTapPartnerLeft(context);
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

  /// Vommet ("New room info page"): why a direct chat's call is grey after
  /// the other person left.
  static Future<void> onTapPartnerLeft(BuildContext context) async {
    await AdaptiveDialog.show(context,
        title: roomCallButtonPartnerLeft,
        builder: (_) => tiamat.Text.label(roomCallButtonPartnerLeftBody));
  }

  static Future<void> explainLocked(
      BuildContext context, RoomCallPermissions p) {
    return AdaptiveDialog.show(context,
        title: roomCallButtonLocked,
        builder: (_) => tiamat.Text.label(roomCallButtonLockedBody(
            RoomCallPermissions.levelName(p.requiredLevel), p.ownLevel)));
  }

  /// True: let everyone join, then start. False: start anyway. Null: cancel.
  static Future<bool?> _askMembersCantJoin(
      BuildContext context, RoomCallPermissions p) {
    return AdaptiveDialog.show<bool>(context,
        title: roomCallButtonMembersCantJoinTitle,
        builder: (dialogContext) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tiamat.Text.label(roomCallButtonMembersCantJoinBody(
                    RoomCallPermissions.levelName(p.requiredLevel))),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text(roomCallButtonStartAnyway),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text(roomCallButtonLetEveryoneJoin),
                    ),
                  ],
                ),
              ],
            ));
  }
}
