import 'dart:async';

import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Discord-style mute and deafen buttons for the user panel, each with
/// a menu for picking the device and reaching voice settings. They work in
/// and out of a call (see [CallManager.isMuted]).
class SelfVoiceControls extends StatefulWidget {
  const SelfVoiceControls({this.size = 32, super.key});
  final double size;

  @override
  State<SelfVoiceControls> createState() => _SelfVoiceControlsState();
}

class _SelfVoiceControlsState extends State<SelfVoiceControls> {
  late List<StreamSubscription> subs;
  List<webrtc.MediaDeviceInfo> inputs = [];
  List<webrtc.MediaDeviceInfo> outputs = [];

  static const noiseSuppressionLabels = {
    "off": "Basic",
    "standard": "Standard",
    "best": "Best",
    "auto": "Automatic",
  };

  @override
  void initState() {
    final callManager = clientManager!.callManager;
    subs = [
      callManager.onSelfAudioChanged.listen((_) => setState(() {})),
      callManager.currentSessions.onListUpdated.listen((_) => setState(() {})),
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

  Future<void> loadDevices() async {
    final devices = await WebrtcDefaultDevices.getDevices();
    if (!mounted) return;
    setState(() {
      inputs = devices.where((d) => d.kind == "audioinput").toList();
      outputs = devices.where((d) => d.kind == "audiooutput").toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final callManager = clientManager!.callManager;
    final error = ColorScheme.of(context).error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        group(
          icon: callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: callManager.isMuted ? error : null,
          tooltip: callManager.isMuted ? "Unmute" : "Mute",
          onPressed: callManager.toggleMute,
          menuTooltip: "Input options",
          menu: inputMenu,
        ),
        group(
          icon: callManager.isDeafened
              ? Icons.headset_off_rounded
              : Icons.headset_rounded,
          color: callManager.isDeafened ? error : null,
          tooltip: callManager.isDeafened ? "Undeafen" : "Deafen",
          onPressed: callManager.toggleDeafen,
          menuTooltip: "Output options",
          menu: outputMenu,
        ),
      ],
    );
  }

  Widget group({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required String menuTooltip,
    required List<Widget> Function() menu,
    Color? color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: tooltip,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: tiamat.IconButton(
              icon: icon,
              size: widget.size * 0.55,
              iconColor: color,
              onPressed: onPressed,
            ),
          ),
        ),
        MenuAnchor(
          onOpen: loadDevices,
          menuChildren: menu(),
          builder: (context, controller, _) => Tooltip(
            message: menuTooltip,
            child: SizedBox(
              width: widget.size * 0.55,
              height: widget.size,
              child: tiamat.IconButton(
                icon: Icons.keyboard_arrow_down_rounded,
                size: widget.size * 0.45,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> inputMenu() => [
        if (!PlatformUtils.isAndroid) ...[
          header("Input device"),
          ...deviceItems(inputs, preferences.voipDefaultAudioInput.value,
              (label) async {
            await preferences.voipDefaultAudioInput.set(label);
            await WebrtcDefaultDevices.selectInputDevice();
          }),
        ],
        if (preferences.experimentQuickProfileControls.value &&
            VoiceFilter.supportsVolume) ...[
          const Divider(height: 8),
          header("Input volume"),
          _VolumeSlider(
            preference: preferences.voipMicrophoneVolume,
            // The filter takes the value once the slider is let go.
            onChangeEnd: (_) => VoiceFilter.apply(),
          ),
        ],
        if (VoiceFilter.isEnabled) ...[
          const Divider(height: 8),
          header("Noise suppression"),
          for (var mode in VoiceFilter.modes)
            item(
              noiseSuppressionLabels[mode] ?? mode,
              selected: preferences.voipNoiseSuppression.value == mode,
              onPressed: () async {
                await preferences.voipNoiseSuppression.set(mode);
                await VoiceFilter.apply(mode: mode);
              },
            ),
        ],
        const Divider(height: 8),
        voiceSettingsItem(),
      ];

  List<Widget> outputMenu() => [
        header("Output device"),
        ...deviceItems(outputs, preferences.voipDefaultAudioOutput.value,
            (label) async {
          await preferences.voipDefaultAudioOutput.set(label);
          await WebrtcDefaultDevices.selectOutputDevice();
        }),
        if (preferences.experimentQuickProfileControls.value) ...[
          const Divider(height: 8),
          header("Output volume"),
          _VolumeSlider(
            preference: preferences.voipOutputVolume,
            // Cheap to apply, so the call follows the slider as it moves.
            onChanged: (_) =>
                clientManager!.callManager.refreshPlaybackVolumes(),
          ),
        ],
        const Divider(height: 8),
        voiceSettingsItem(),
      ];

  List<Widget> deviceItems(List<webrtc.MediaDeviceInfo> devices,
          String? selected, Future<void> Function(String? label) select) =>
      [
        item("Default",
            selected: selected == null, onPressed: () => select(null)),
        for (var device in devices)
          item(device.label,
              selected: device.label == selected,
              onPressed: () => select(device.label)),
      ];

  Widget header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: tiamat.Text.labelLow(text),
      );

  Widget item(String label,
          {required bool selected, required VoidCallback onPressed}) =>
      MenuItemButton(
        leadingIcon: SizedBox(
          width: 20,
          child: selected ? const Icon(Icons.check_rounded, size: 18) : null,
        ),
        onPressed: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      );

  // As in Discord: the last entry, with the cog on the right.
  Widget voiceSettingsItem() => MenuItemButton(
        leadingIcon: const SizedBox(width: 20),
        trailingIcon: const Icon(Icons.settings_rounded, size: 18),
        onPressed: () => SettingsNavigation.openVoice(context),
        child: const Text("Voice Settings"),
      );
}

/// Discord's volume sliders: 0-200 %, stored in [preference].
class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider(
      {required this.preference, this.onChanged, this.onChangeEnd});
  final DoublePreference preference;
  final void Function(double)? onChanged;
  final void Function(double)? onChangeEnd;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  late double value = widget.preference.value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 2.0),
              max: 2.0,
              divisions: 40,
              label: "${(value * 100).round()}%",
              onChanged: (v) async {
                setState(() => value = v);
                if (widget.onChanged != null) {
                  await widget.preference.set(v);
                  widget.onChanged!(v);
                }
              },
              onChangeEnd: (v) async {
                await widget.preference.set(v);
                widget.onChangeEnd?.call(v);
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: Text("${(value * 100).round()}%",
                style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}
