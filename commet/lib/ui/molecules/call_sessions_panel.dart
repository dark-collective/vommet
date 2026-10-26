import 'dart:async';

import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/utils/animation/ring_shaker.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';

class CallSessionsPanel extends StatefulWidget {
  const CallSessionsPanel({this.height = 50, super.key});
  final double height;
  @override
  State<CallSessionsPanel> createState() => _CallSessionsPanelState();
}

class _CallSessionsPanelState extends State<CallSessionsPanel> {
  StreamSubscription? sub;

  /// Vommet: switches between the cards and the old panel when
  /// experiment_call_cards is toggled.
  StreamSubscription? settingsSub;

  @override
  void initState() {
    sub = clientManager!.callManager.currentSessions.onListUpdated.listen((_) {
      setState(() {});
    });
    settingsSub = preferences.onSettingChanged.listen((_) {
      if (mounted) setState(() {});
    });

    super.initState();
  }

  @override
  void dispose() {
    sub?.cancel();
    settingsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: a card per call, each with its own mute and deafen.
    if (preferences.experimentCallCards.value) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        for (final session in clientManager!.callManager.currentSessions)
          CallCard(key: ValueKey(session.sessionId), session: session),
      ]);
    }
    return Container(
      decoration: BoxDecoration(
          color: ColorScheme.of(context).surfaceTint.withAlpha(10),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          for (var entry in clientManager!.callManager.currentSessions)
            ClipRRect(
              borderRadius: BorderRadiusGeometry.circular(8),
              child: CallSessionPanel(
                session: entry,
                height: widget.height,
              ),
            ),
        ],
      ),
    );
  }
}

class CallSessionPanel extends StatefulWidget {
  const CallSessionPanel({required this.session, this.height = 40, super.key});
  final VoipSession session;
  final double height;
  @override
  State<CallSessionPanel> createState() => _CallSessionPanelState();
}

class _CallSessionPanelState extends State<CallSessionPanel> {
  String get callPanelDisconnect => Intl.message("Disconnect",
      name: "callPanelDisconnect",
      desc: "Calls panel: tooltip on the hang up button");

  String get callPanelVoiceConnected => Intl.message("Voice connected",
      name: "callPanelVoiceConnected",
      desc: "Calls panel: status of a connected call");

  String get callPanelIncomingCall => Intl.message("Incoming call",
      name: "callPanelIncomingCall",
      desc: "Calls panel: status of a ringing call");

  // Vommet issue 776.
  String get callPanelSavingData => Intl.message("Saving data",
      name: "callPanelSavingData",
      desc: "Shown in a call while 'Use less data for calls' is in effect");

  String get callPanelSavingDataTooltip => Intl.message(
      "Using less data for this call. Change it in Settings › Data and storage.",
      name: "callPanelSavingDataTooltip",
      desc: "Tooltip on the 'Saving data' label in a call");

  late List<StreamSubscription> subs;

  @override
  void initState() {
    subs = [
      widget.session.onStateChanged.listen((_) => setState(() {})),
      widget.session.onConnectionStateChanged.listen((_) => setState(() {})),
      preferences.onSettingChanged.listen((_) => setState(() {})),
    ];
    CallDataSaver.active.addListener(_onDataSaver);

    super.initState();
  }

  void _onDataSaver() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CallDataSaver.active.removeListener(_onDataSaver);
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  /// The call's room name, redacted like the room list (Vommet issue 475).
  String _roomName(BuildContext context, VoipSession session) {
    final redaction = RedactionScope.of(context);
    final room = session.client.getRoom(session.roomId);
    return room == null
        ? redaction.roomName(session.roomName, session.roomId)
        : redaction.roomDisplayName(room, name: session.roomName);
  }

  // Vommet: laid out like Discord's "Voice Connected" panel: status and
  // room on top with noise suppression and hang up, then camera and screen
  // share. Mute and deafen live in the user panel below (SelfVoiceControls).
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final (status, color) = statusText(context, session.state);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Row(
              children: [
                pickAnimation(
                    entry: session,
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(Icons.signal_cellular_alt_rounded,
                          color: color, size: 20),
                    )),
                Expanded(
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      EventBus.doOpenRoom(session.roomId,
                          clientId: session.client.identifier);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: color,
                                        fontWeight: FontWeight.w600)),
                          ),
                          // Vommet issue 776: "Use less data for calls".
                          if (session.state == VoipState.connected &&
                              CallDataSaver.isActive)
                            savingDataChip(context),
                        ]),
                        // Vommet issue 475: redacted mode.
                        Text(_roomName(context, session),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: ColorScheme.of(context)
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                if (VoiceFilter.isEnabled)
                  iconButton(
                    icon: Icons.graphic_eq_rounded,
                    tooltip: noiseSuppressionOn
                        ? CallControlStrings.callControlNoiseSuppressionOn
                        : CallControlStrings.callControlNoiseSuppressionOff,
                    color: noiseSuppressionOn
                        ? ColorScheme.of(context).primary
                        : ColorScheme.of(context)
                            .onSurface
                            .withValues(alpha: 0.5),
                    onPressed: toggleNoiseSuppression,
                  ),
                iconButton(
                  icon: Icons.call_end_rounded,
                  tooltip: callPanelDisconnect,
                  color: ColorScheme.of(context).error,
                  onPressed: session.hangUpCall,
                ),
              ],
            ),
            Row(
              spacing: 6,
              children: [
                // Vommet issue 422: with push to talk on, hold to talk here
                // too, so you can talk from outside the call's room.
                if (preferences.voipPushToTalk.value)
                  Expanded(
                      flex: 2,
                      child: Center(child: TalkButton(session, height: 32))),
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
                    onPressed: session.isSharingScreen
                        ? session.stopScreenshare
                        : pickScreenShare,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget savingDataChip(BuildContext context) {
    final scheme = ColorScheme.of(context);
    return Tooltip(
      message: callPanelSavingDataTooltip,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
          Icon(Icons.data_saver_on_rounded,
              size: 12, color: scheme.onSecondaryContainer),
          Text(callPanelSavingData,
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer)),
        ]),
      ),
    );
  }

  (String, Color) statusText(BuildContext context, VoipState state) =>
      switch (state) {
        VoipState.connected => (
            callPanelVoiceConnected,
            UserPresenceStatus.online.getColor()
          ),
        VoipState.incoming => (callPanelIncomingCall, Colors.amber),
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

  Future<void> pickScreenShare() async {
    final source = await widget.session.pickScreenCapture(context);
    if (source != null) {
      await widget.session.setScreenShare(source);
    }
  }

  Widget iconButton({
    required IconData icon,
    required String tooltip,
    required Future<void> Function() onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: tiamat.IconButton(
            icon: icon, size: 18, iconColor: color, onPressed: onPressed),
      ),
    );
  }

  Widget wideButton({
    required IconData icon,
    required String tooltip,
    required bool active,
    required Future<void> Function() onPressed,
  }) {
    final scheme = ColorScheme.of(context);
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: SizedBox(
              height: 32,
              child: Icon(icon,
                  size: 20,
                  color: active ? scheme.onPrimaryContainer : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  Widget pickAnimation({required VoipSession entry, required Widget child}) {
    if (entry.state == VoipState.incoming) {
      return RingShakerAnimation(child: child);
    }

    return child;
  }
}
