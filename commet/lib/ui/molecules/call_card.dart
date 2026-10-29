import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/utils/animation/ring_shaker.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: one call as a card in the call panel (experiment_call_cards).
/// The room's name comes first, then its space and, with several accounts,
/// which account you're in it with. Only the focused call is open: its
/// microphone and headphones (this call's own mute and deafen), camera and
/// screen share. A folded call shows a red mark when you're muted or
/// deafened there; tap it to bring it forward.
class CallCard extends StatefulWidget {
  const CallCard({required this.session, super.key});
  final VoipSession session;

  @override
  State<CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<CallCard> {
  String get callCardMuted => Intl.message("Muted",
      name: "callCardMuted",
      desc:
          "Call card in the calls panel: screen reader label for the muted icon");

  String get callCardDeafened => Intl.message("Deafened",
      name: "callCardDeafened",
      desc:
          "Call card in the calls panel: screen reader label for the deafened icon");

  String get callCardShowControls => Intl.message("Show this call's controls",
      name: "callCardShowControls",
      desc:
          "Call card in the calls panel: tooltip on the button that expands the card");

  String get callCardLeave => Intl.message("Leave this call",
      name: "callCardLeave",
      desc: "Call card in the calls panel: tooltip on the hang up button");

  String get callCardMute => Intl.message("Mute in this call",
      name: "callCardMute",
      desc: "Call card in the calls panel: tooltip on the mute button");

  String get callCardUnmute => Intl.message("Unmute in this call",
      name: "callCardUnmute",
      desc:
          "Call card in the calls panel: tooltip on the mute button while muted");

  String get callCardDeafen => Intl.message("Deafen in this call",
      name: "callCardDeafen",
      desc: "Call card in the calls panel: tooltip on the deafen button");

  String get callCardUndeafen => Intl.message("Undeafen in this call",
      name: "callCardUndeafen",
      desc:
          "Call card in the calls panel: tooltip on the deafen button while deafened");

  String get callCardVoiceConnected => Intl.message("Voice connected",
      name: "callCardVoiceConnected",
      desc: "Call card in the calls panel: status of a connected call");

  String get callCardIncomingCall => Intl.message("Incoming call",
      name: "callCardIncomingCall",
      desc: "Call card in the calls panel: status of a ringing call");

  String callCardAsAccount(String name) => Intl.message("as $name",
      args: [name],
      name: "callCardAsAccount",
      desc:
          "Call card in the calls panel: which of your accounts is in the call, when you are signed in to several; name is the account's display name");

  late final List<StreamSubscription> subs;

  VoipSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    subs = [
      session.onStateChanged.listen((_) => setState(() {})),
      session.onConnectionStateChanged.listen((_) => setState(() {})),
      preferences.onSettingChanged.listen((_) => setState(() {})),
      clientManager!.callManager.onSelfAudioChanged
          .listen((_) => setState(() {})),
    ];
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  bool get focused => clientManager!.callManager.focusedCall == session;
  bool get muted => clientManager!.callManager.isMutedIn(session);
  bool get deafened => clientManager!.callManager.isDeafenedIn(session);

  /// The most specific space the room is in (a subspace over its parent).
  Space? get space {
    final spaces = session.client.spaces
        .where((s) => s.containsRoom(session.roomId))
        .toList();
    return spaces.where((s) => !s.isTopLevel).firstOrNull ?? spaces.firstOrNull;
  }

  bool get severalAccounts => (clientManager?.clients.length ?? 0) > 1;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final open = focused;
    final background =
        open ? scheme.surfaceContainerHigh : scheme.surfaceContainer;
    final room = session.client.getRoom(session.roomId);
    final (status, statusColor) = statusOf(context);
    final account = session.client.self;

    final details = [
      if (session.state != VoipState.connected) status,
      if (space != null) space!.displayName,
      if (severalAccounts && account != null)
        callCardAsAccount(account.displayName),
    ];
    final subtitle = details.isEmpty ? status : details.join(" · ");

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border(
            left: BorderSide(
                color: open ? statusColor : Colors.transparent, width: 3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ringing(roomIcon(room, account, background)),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                clientManager!.callManager.focusCall(session);
                EventBus.doOpenRoom(session.roomId,
                    clientId: session.client.identifier);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room?.displayName ?? session.roomName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface)),
                  Row(children: [
                    if (!open && (deafened || muted)) ...[
                      Icon(deafened ? Icons.headset_off : Icons.mic_off,
                          size: 13,
                          color: scheme.error,
                          semanticLabel:
                              deafened ? callCardDeafened : callCardMuted),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          if (open && VoiceFilter.isEnabled)
            iconButton(
              icon: Icons.graphic_eq_rounded,
              tooltip: noiseSuppressionOn
                  ? CallControlStrings.callControlNoiseSuppressionOn
                  : CallControlStrings.callControlNoiseSuppressionOff,
              color: noiseSuppressionOn
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.5),
              onPressed: toggleNoiseSuppression,
            ),
          if (!open)
            iconButton(
              icon: Icons.unfold_more,
              tooltip: callCardShowControls,
              color: scheme.onSurfaceVariant,
              onPressed: () async =>
                  clientManager!.callManager.focusCall(session),
            ),
          iconButton(
            icon: Icons.call_end_rounded,
            tooltip: callCardLeave,
            color: scheme.error,
            onPressed: session.hangUpCall,
          ),
        ]),
        if (open && session.state != VoipState.incoming) ...[
          const SizedBox(height: 8),
          Row(spacing: 6, children: [
            // Vommet issue 422: push to talk's pill stands in for mute.
            if (preferences.voipPushToTalk.value)
              Expanded(
                  flex: 2,
                  child: Center(child: TalkButton(session, height: 32)))
            else
              wideButton(
                icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                tooltip: muted ? callCardUnmute : callCardMute,
                off: muted,
                onPressed: () async =>
                    clientManager!.callManager.toggleMuteIn(session),
              ),
            wideButton(
              icon: deafened ? Icons.headset_off_rounded : Icons.headphones,
              tooltip: deafened ? callCardUndeafen : callCardDeafen,
              off: deafened,
              onPressed: () async =>
                  clientManager!.callManager.toggleDeafenIn(session),
            ),
            wideButton(
              icon: session.isCameraEnabled
                  ? Icons.videocam_rounded
                  : Icons.videocam_off_rounded,
              tooltip: session.isCameraEnabled
                  ? CallControlStrings.callControlTurnOffCamera
                  : CallControlStrings.callControlTurnOnCamera,
              active: session.isCameraEnabled,
              onPressed: session.isCameraEnabled
                  ? session.stopCamera
                  : () => session.setCamera(null),
            ),
            if (session.supportsScreenshare)
              wideButton(
                icon: session.isSharingScreen
                    ? Icons.stop_screen_share_rounded
                    : Icons.screen_share_rounded,
                tooltip: session.isSharingScreen
                    ? CallControlStrings.callControlStopSharingScreen
                    : CallControlStrings.callControlShareScreen,
                active: session.isSharingScreen,
                onPressed:
                    session.isSharingScreen ? session.stopScreenshare : share,
              ),
          ]),
        ],
      ]),
    );
  }

  /// The room's picture, with the account's on its corner when you're
  /// signed in more than once.
  Widget roomIcon(Room? room, Profile? account, Color background) {
    final picture = tiamat.Avatar(
      radius: 15,
      image: room?.avatar,
      placeholderColor: room?.defaultColor ?? Colors.grey,
      placeholderText: room?.displayName ?? session.roomName,
    );
    if (!severalAccounts || account == null) {
      return SizedBox(width: 36, height: 36, child: Center(child: picture));
    }
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, top: 0, child: picture),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(color: background, shape: BoxShape.circle),
            child: tiamat.Avatar(
              radius: 8,
              image: account.avatar,
              placeholderColor: account.defaultColor,
              placeholderText: account.displayName,
            ),
          ),
        ),
      ]),
    );
  }

  Widget ringing(Widget child) => session.state == VoipState.incoming
      ? RingShakerAnimation(child: child)
      : child;

  (String, Color) statusOf(BuildContext context) => switch (session.state) {
        VoipState.connected => (
            callCardVoiceConnected,
            UserPresenceStatus.online.getColor()
          ),
        VoipState.incoming => (callCardIncomingCall, Colors.amber),
        VoipState.ended => (
            CallControlStrings.callStatusDisconnected,
            ColorScheme.of(context).error
          ),
        _ => (CallControlStrings.callStatusConnecting, Colors.amber),
      };

  bool get noiseSuppressionOn =>
      preferences.voipNoiseSuppression.value != "off";

  Future<void> toggleNoiseSuppression() async {
    if (noiseSuppressionOn) {
      await preferences.voipNoiseSuppressionLastOn
          .set(preferences.voipNoiseSuppression.value);
      await preferences.voipNoiseSuppression.set("off");
      await VoiceFilter.apply(mode: "off");
    } else {
      final mode = preferences.voipNoiseSuppressionLastOn.value;
      await preferences.voipNoiseSuppression.set(mode);
      await VoiceFilter.apply(mode: mode);
    }
  }

  Future<void> share() async {
    final source = await session.pickScreenCapture(context);
    if (source != null) await session.setScreenShare(source);
  }

  Widget iconButton({
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onPressed,
    Color? color,
  }) =>
      Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 32,
          height: 32,
          child: tiamat.IconButton(
              icon: icon, size: 18, iconColor: color, onPressed: onPressed),
        ),
      );

  /// [off]: a red "you've turned this off" state (mute, deafen); [active]:
  /// the highlighted "on" state (camera, screen share).
  Widget wideButton({
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onPressed,
    bool active = false,
    bool off = false,
  }) {
    final scheme = ColorScheme.of(context);
    final background = off
        ? scheme.error.withValues(alpha: 0.18)
        : active
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6);
    final foreground = off
        ? scheme.error
        : active
            ? scheme.onPrimaryContainer
            : scheme.onSurface;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: SizedBox(
                height: 32, child: Icon(icon, size: 20, color: foreground)),
          ),
        ),
      ),
    );
  }
}

/// Vommet: call control texts shared by the call card, the calls panel,
/// the compact call strip, the voice controls and the stream viewer.
class CallControlStrings {
  static String get callControlMute => Intl.message("Mute",
      name: "callControlMute",
      desc: "Call controls: tooltip on the button that mutes your microphone");

  static String get callControlUnmute => Intl.message("Unmute",
      name: "callControlUnmute",
      desc:
          "Call controls: tooltip on the button that unmutes your microphone");

  static String get callControlDeafen => Intl.message("Deafen",
      name: "callControlDeafen",
      desc:
          "Call controls: tooltip on the button that stops you hearing the call");

  static String get callControlUndeafen => Intl.message("Undeafen",
      name: "callControlUndeafen",
      desc:
          "Call controls: tooltip on the button that lets you hear the call again");

  static String get callControlTurnOnCamera => Intl.message("Turn on camera",
      name: "callControlTurnOnCamera",
      desc: "Call controls: tooltip on the camera button");

  static String get callControlTurnOffCamera => Intl.message("Turn off camera",
      name: "callControlTurnOffCamera",
      desc: "Call controls: tooltip on the camera button");

  static String get callControlShareScreen => Intl.message("Share your screen",
      name: "callControlShareScreen",
      desc: "Call controls: tooltip on the screen share button");

  static String get callControlStopSharingScreen => Intl.message(
      "Stop sharing your screen",
      name: "callControlStopSharingScreen",
      desc: "Call controls: tooltip on the screen share button while sharing");

  static String get callControlNoiseSuppressionOn => Intl.message(
      "Noise suppression: on",
      name: "callControlNoiseSuppressionOn",
      desc:
          "Call controls: tooltip on the noise suppression toggle while it is on");

  static String get callControlNoiseSuppressionOff => Intl.message(
      "Noise suppression: off",
      name: "callControlNoiseSuppressionOff",
      desc:
          "Call controls: tooltip on the noise suppression toggle while it is off");

  static String get callControlLeaveCall => Intl.message("Leave call",
      name: "callControlLeaveCall",
      desc: "Call controls: tooltip on the hang up button");

  static String get callStatusConnecting => Intl.message("Connecting…",
      name: "callStatusConnecting",
      desc: "Call status while the call is connecting");

  static String get callStatusDisconnected => Intl.message("Disconnected",
      name: "callStatusDisconnected", desc: "Call status after the call ended");
}
