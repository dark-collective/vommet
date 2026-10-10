import 'dart:async';

import 'package:commet/client/components/user_presence/user_presence_component.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:commet/utils/animation/ring_shaker.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

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
  late List<StreamSubscription> subs;

  @override
  void initState() {
    subs = [
      widget.session.onStateChanged.listen((_) => setState(() {})),
      widget.session.onConnectionStateChanged.listen((_) => setState(() {})),
      preferences.onSettingChanged.listen((_) => setState(() {})),
    ];

    super.initState();
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
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
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      EventBus.doOpenRoom(session.roomId,
                          clientId: session.client.identifier);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                    color: color, fontWeight: FontWeight.w600)),
                        Text(session.roomName,
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
                        ? "Noise suppression: on"
                        : "Noise suppression: off",
                    color: noiseSuppressionOn
                        ? ColorScheme.of(context).primary
                        : ColorScheme.of(context)
                            .onSurface
                            .withValues(alpha: 0.5),
                    onPressed: toggleNoiseSuppression,
                  ),
                iconButton(
                  icon: Icons.call_end_rounded,
                  tooltip: "Disconnect",
                  color: ColorScheme.of(context).error,
                  onPressed: session.hangUpCall,
                ),
              ],
            ),
            Row(
              spacing: 6,
              children: [
                wideButton(
                  icon: session.isCameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  tooltip: session.isCameraEnabled
                      ? "Turn off camera"
                      : "Turn on camera",
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
                        ? "Stop sharing your screen"
                        : "Share your screen",
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

  (String, Color) statusText(BuildContext context, VoipState state) =>
      switch (state) {
        VoipState.connected => (
            "Voice Connected",
            UserPresenceStatus.online.getColor()
          ),
        VoipState.incoming => ("Incoming Call", Colors.amber),
        VoipState.ended => ("Disconnected", ColorScheme.of(context).error),
        _ => ("Connecting…", Colors.amber),
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
