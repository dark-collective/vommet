import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 422: on a phone, the call you're in stays reachable from
/// other rooms. A slim bar under the room header names the call (tap it to
/// go back), with hold to talk (or mute when push to talk is off), camera
/// and hang up. Hidden in the call's own room, which has the call bar.
class OngoingCallStrip extends StatefulWidget {
  const OngoingCallStrip({this.currentRoom, super.key});

  /// The room on screen, or null on a space's page.
  final Room? currentRoom;

  static String ongoingCallIn(String room) => Intl.message("In call in $room",
      args: [room],
      name: "ongoingCallIn",
      desc:
          "Phone: bar at the top of other rooms while you're in a call; room is the call's room name. Tap it to go back to the call");

  static String get ongoingCallBack => Intl.message("Go back to the call",
      name: "ongoingCallBack",
      desc:
          "Phone: screen reader label and tooltip on the call's name in the bar at the top of other rooms during a call");

  /// The call to show over [room], or null when there's none or the call is
  /// in that room.
  static VoipSession? callFor(Room? room) {
    final call = clientManager?.callManager.focusedCall;
    if (call == null || call.state == VoipState.ended) return null;
    if (room != null &&
        call.roomId == room.identifier &&
        call.client == room.client) {
      return null;
    }
    return call;
  }

  @override
  State<OngoingCallStrip> createState() => _OngoingCallStripState();
}

class _OngoingCallStripState extends State<OngoingCallStrip> {
  late final List<StreamSubscription> subs;
  List<StreamSubscription> sessionSubs = [];
  VoipSession? watched;

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final callManager = clientManager!.callManager;
    subs = [
      callManager.currentSessions.onListUpdated.listen((_) => refresh()),
      callManager.onSelfAudioChanged.listen((_) => refresh()),
      preferences.onSettingChanged.listen((_) => refresh()),
    ];
  }

  /// Follows the shown call's state (camera, connection).
  void watch(VoipSession? session) {
    if (session == watched) return;
    for (final sub in sessionSubs) {
      sub.cancel();
    }
    watched = session;
    sessionSubs = session == null
        ? []
        : [
            session.onStateChanged.listen((_) => refresh()),
            session.onConnectionStateChanged.listen((_) => refresh()),
          ];
  }

  @override
  void dispose() {
    for (final sub in [...subs, ...sessionSubs]) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = OngoingCallStrip.callFor(widget.currentRoom);
    watch(session);
    if (session == null) return const SizedBox.shrink();

    final callManager = clientManager!.callManager;
    final scheme = ColorScheme.of(context);
    const green = Color(0xff23a55a);
    final connected = session.state == VoipState.connected;
    final room = session.client.getRoom(session.roomId);
    final muted = callManager.isMutedIn(session);
    final pushToTalk = preferences.voipPushToTalk.value;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      padding: const EdgeInsets.fromLTRB(10, 2, 8, 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            green.withValues(alpha: 0.10), scheme.surfaceContainer),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: green.withValues(alpha: 0.6)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: OngoingCallStrip.ongoingCallBack,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(4),
            onTap: () {
              callManager.focusCall(session);
              EventBus.doOpenRoom(session.roomId,
                  clientId: session.client.identifier);
            },
            child: SizedBox(
              height: 32,
              child: Row(spacing: 8, children: [
                Icon(Icons.circle,
                    size: 9, color: connected ? green : Colors.amber),
                Expanded(
                  child: Text(
                      OngoingCallStrip.ongoingCallIn(
                          room?.displayName ?? session.roomName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        ),
        Row(spacing: 6, children: [
          Expanded(
            child: pushToTalk
                ? Center(child: TalkButton(session, height: 34))
                : button(
                    icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    tooltip: muted
                        ? CallControlStrings.callControlUnmute
                        : CallControlStrings.callControlMute,
                    background: muted
                        ? scheme.error.withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    foreground: muted ? scheme.error : scheme.onSurface,
                    onPressed: () async => callManager.toggleMuteIn(session),
                  ),
          ),
          SizedBox(
            width: 52,
            child: button(
              icon: session.isCameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              tooltip: session.isCameraEnabled
                  ? CallControlStrings.callControlTurnOffCamera
                  : CallControlStrings.callControlTurnOnCamera,
              background: session.isCameraEnabled
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              foreground: session.isCameraEnabled
                  ? scheme.onPrimaryContainer
                  : scheme.onSurface,
              onPressed: session.isCameraEnabled
                  ? session.stopCamera
                  : () => session.setCamera(null),
            ),
          ),
          SizedBox(
            width: 52,
            child: button(
              icon: Icons.call_end_rounded,
              tooltip: CallControlStrings.callControlLeaveCall,
              background: scheme.error,
              foreground: scheme.onError,
              onPressed: session.hangUpCall,
            ),
          ),
        ]),
      ]),
    );
  }

  Widget button({
    required IconData icon,
    required String tooltip,
    required Color background,
    required Color foreground,
    required Future<void> Function() onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
              height: 34, child: Icon(icon, size: 20, color: foreground)),
        ),
      ),
    );
  }
}
