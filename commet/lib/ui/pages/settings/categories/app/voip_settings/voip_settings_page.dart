import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/ui/pages/settings/categories/app/string_preference_options.dart';
import 'package:commet/ui/pages/settings/categories/app/voip_settings/push_to_talk_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/voip_settings/stun_fallback_server_field.dart';
import 'package:commet/ui/pages/settings/categories/app/voip_settings/voip_debug_settings.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipSettingsPage extends StatefulWidget {
  const VoipSettingsPage({super.key});

  @override
  State<VoipSettingsPage> createState() => _VoipSettingsPage();
}

class _VoipSettingsPage extends State<VoipSettingsPage> {
  StreamSubscription? sub;

  List<webrtc.MediaDeviceInfo>? devices;

  List<webrtc.MediaDeviceInfo>? microphones = [];
  List<webrtc.MediaDeviceInfo>? speakers = [];
  List<webrtc.MediaDeviceInfo>? cameras = [];

  String get headerVoipSettingsCallConnection => Intl.message("Call Connection",
      name: "headerVoipSettingsCallConnection",
      desc:
          "Header for the settings tile containing configuration relating to the initial connection of a call");

  String get headerVoipSettingsOverlay => Intl.message("Overlay",
      name: "headerVoipSettingsOverlay",
      desc:
          "Header for the settings tile containing configuration for the voip overlay");

  String get labelVoipSettingsStunFallback => Intl.message("Use STUN Fallback",
      name: "labelVoipSettingsStunFallback",
      desc:
          "label for the setting to enable STUN callback for connecting calls");

  String labelVoipSettingsStunFallbackDescription(String stunServer) =>
      Intl.message(
          "Calls cannot be connected without a STUN server. If your homeserver does not provide a STUN server, fall back to using '${stunServer}'. Your IP address will be revealed to this server when establishing calls",
          args: [stunServer],
          name: "labelVoipSettingsStunFallbackDescription");

  String get headerVoipSettingsDevices => Intl.message("Devices",
      name: "headerVoipSettingsDevices",
      desc:
          "Header for settings tile containing device configuration, for default audio / video inputs");

  String get headerVoipSettingsStreamSettings => Intl.message("Stream Settings",
      name: "headerVoipSettingsStreamSettings",
      desc: "Header for settings tile containing stream quality configuration");

  String get labelVoipUseSimulcast => Intl.message("Use Simulcast",
      name: "labelVoipUseSimulcast",
      desc: "label for setting toggle to enable use of Simulcast");

  String get labelVoipUseSimulcastDescription => Intl.message(
      "Uploads your streams at multiple different levels of quality, so other users can decide which to use. This will use more bandwidth and system resources.",
      name: "labelVoipUseSimulcastDescription",
      desc: "description for setting toggle to enable use of Simulcast");

  String get labelVoipStreamMaximumBitrate => Intl.message(
      "Stream Maximum Bitrate",
      name: "labelVoipStreamMaximumBitrate",
      desc:
          "label for setting slider to set the maximum bitrate that can be used when streaming");

  String get labelVoipStreamMaximumBitrateDescription => Intl.message(
        "Determines the overall quality of your stream. Higher is better, but also uses more resources",
        name: "labelVoipStreamMaximumBitrateDescription",
      );

  String get labelVoipStreamFramerate => Intl.message("Stream Framerate",
      name: "labelVoipStreamFramerate",
      desc:
          "label for setting slider to set the framerate at which the screen should be captured when streaming");

  String get labelVoipStreamFramerateDescription => Intl.message(
        "Target frames per second for screen sharing. Higher has smoother motion, but maybe reduce visual clarity.",
        name: "labelVoipStreamFramerateDescription",
      );

  String get labelVoipStreamPreferredCodec => Intl.message(
        "Preferred Stream Codec",
        name: "labelVoipStreamPreferredCodec",
      );

  String get labelVoipStreamPreferredCodecDescription => Intl.message(
      "Choose which format to encode your stream in. Different codecs may run faster on certain devices, and may be unsupported on others. Most devices should support vp8 and h264.",
      name: "labelVoipStreamPreferredCodecDescription",
      desc:
          "Explains the preferred stream codec setting. This is just a preference, and the picked codec may not be used if the user's device does not support it");

  String get labelVoipStreamResolution => Intl.message(
        "Stream Resolution",
        name: "labelVoipStreamResolution",
      );

  String get labelVoipStreamResolutionDescription => Intl.message(
        "The resolution of your stream, higher is better",
        name: "labelVoipStreamResolutionDescription",
      );

  String get headerVoipSettingsAudioSettings => Intl.message("Audio settings",
      name: "headerVoipSettingsAudioSettings",
      desc:
          "Header for settings tile containing stream audio quality configuration");

  String get labelVoipAudioBitrateSettings => Intl.message("Audio bitrate",
      name: "labelVoipAudioBitrateSettings",
      desc:
          "label for the slider to adjust the bitrate of outgoing audio on a call");

  String get labelVoipAudioBitrateSettingsDescription => Intl.message(
      "Adjust the bitrate of your outgoing audio. Higher is better.",
      name: "labelVoipAudioBitrateSettingsDescription",
      desc:
          "describes the behavior for the slider to adjust the bitrate of outgoing audio on a call");

  String get labelVoipNoiseSuppression => Intl.message("Noise suppression",
      name: "labelVoipNoiseSuppression",
      desc:
          "label for the picker that chooses how microphone noise is removed");

  String get labelVoipNoiseSuppressionDescription => Intl.message(
      "Removes keyboard, fan, and other background noise from your microphone. Automatic picks the best one your computer can run.",
      name: "labelVoipNoiseSuppressionDescription",
      desc:
          "describes the picker that chooses how microphone noise is removed");

  String get labelVoipNoiseSuppressionOff => Intl.message("Basic",
      name: "labelVoipNoiseSuppressionOff",
      desc:
          "noise suppression option: only the call engine's built-in suppressor");

  String get labelVoipNoiseSuppressionStandard =>
      Intl.message("Standard (light on CPU)",
          name: "labelVoipNoiseSuppressionStandard",
          desc: "noise suppression option: RNNoise");

  String get labelVoipNoiseSuppressionBest =>
      Intl.message("Best (uses more CPU)",
          name: "labelVoipNoiseSuppressionBest",
          desc: "noise suppression option: DeepFilterNet3");

  String get labelVoipNoiseSuppressionAuto => Intl.message("Automatic",
      name: "labelVoipNoiseSuppressionAuto",
      desc:
          "noise suppression option: best when the computer is fast enough, otherwise standard");

  @override
  void initState() {
    super.initState();
    sub = preferences.onSettingChanged.listen((event) => setState(() {}));

    WebrtcDefaultDevices.getDevices().then((v) => setState(() {
          Log.i(v);
          devices = v;

          microphones = v.where((i) => i.kind == "audioinput").toList();
          speakers = v.where((i) => i.kind == "audiooutput").toList();
          cameras = v.where((i) => i.kind == "videoinput").toList();
        }));
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        // Vommet: voice activity or push to talk.
        const PushToTalkSettings(),
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: headerVoipSettingsCallConnection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              BooleanPreferenceToggle(
                preference: preferences.useFallbackTurnServer,
                title: labelVoipSettingsStunFallback,
                description: labelVoipSettingsStunFallbackDescription(
                    preferences.fallbackTurnServer.value),
              ),
              // Vommet: the fallback address is editable (Vommet issue 563).
              const StunFallbackServerField(),
            ],
          ),
        ),
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: headerVoipSettingsOverlay,
          child: BooleanPreferenceToggle(
            preference: preferences.useVoipOverlay,
            title: "Enable Overlay",
            description:
                "When in a call, add an overlay on your screen to show the call participants",
            onChanged: (p0) {
              if (p0 == false) {
                clientManager?.callManager.removeOverlay();
              } else {
                clientManager?.callManager.enableOverlayForExistingSessions();
              }
            },
          ),
        ),
        tiamat.Panel(
          header: headerVoipSettingsDevices,
          mode: tiamat.TileType.surfaceContainerLow,
          child: devicePicker(),
        ),
        tiamat.Panel(
            header: headerVoipSettingsAudioSettings,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(spacing: 12, children: [
              if (VoiceFilter.isEnabled) noiseSuppressionPicker(),
              DoublePreferenceSlider(
                preference: preferences.streamAudioBitrate,
                title: labelVoipAudioBitrateSettings,
                description: labelVoipAudioBitrateSettingsDescription,
                numDecimals: 0,
                min: 8,
                max: 128,
                units: "Kbps",
              ),
            ])),
        tiamat.Panel(
            header: headerVoipSettingsStreamSettings,
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  BooleanPreferenceToggle(
                      preference: preferences.doSimulcast,
                      title: labelVoipUseSimulcast,
                      description: labelVoipUseSimulcastDescription),
                  DoublePreferenceSlider(
                    preference: preferences.streamBitrate,
                    min: 1,
                    max: 32,
                    units: "Mbps",
                    title: labelVoipStreamMaximumBitrate,
                    description: labelVoipStreamMaximumBitrateDescription,
                  ),
                  DoublePreferenceSlider(
                    preference: preferences.streamFramerate,
                    min: 5,
                    max: 60,
                    numDecimals: 0,
                    units: "FPS",
                    title: labelVoipStreamFramerate,
                    description: labelVoipStreamFramerateDescription,
                  ),
                  StringPreferenceOptionsPicker(
                      preference: preferences.streamCodec,
                      title: labelVoipStreamPreferredCodec,
                      description: labelVoipStreamPreferredCodecDescription,
                      options: [
                        "h264",
                        "h265",
                        "vp9",
                        "vp8",
                        "av1",
                      ]),
                  if (preferences.developerMode.value)
                    StringPreferenceOptionsPicker(
                        preference: preferences.streamResolution,
                        title: labelVoipStreamResolution,
                        description: labelVoipStreamResolutionDescription,
                        options: [
                          "640x360",
                          "960x540",
                          "1280x720",
                          "1920x1080",
                          "2560x1440",
                        ])
                ])),
        if (preferences.developerMode.value)
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
            child: tiamat.Panel(
              header: "WebRTC Debug Menu",
              mode: tiamat.TileType.surfaceContainerLow,
              child: VoipDebugSettings(),
            ),
          ),
      ],
    );
  }

  Widget noiseSuppressionPicker() {
    final labels = {
      "off": labelVoipNoiseSuppressionOff,
      "standard": labelVoipNoiseSuppressionStandard,
      "best": labelVoipNoiseSuppressionBest,
      "auto": labelVoipNoiseSuppressionAuto,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(labelVoipNoiseSuppression),
        tiamat.Text.labelLow(labelVoipNoiseSuppressionDescription),
        tiamat.DropdownSelector<String>(
            items: VoiceFilter.modes,
            itemBuilder: (item) => tiamat.Text(labels[item] ?? item),
            onItemSelected: (item) async {
              if (item == null) return;
              await preferences.voipNoiseSuppression.set(item);
              await VoiceFilter.apply(mode: item);
              setState(() {});
            },
            value: preferences.voipNoiseSuppression.value),
      ],
    );
  }

  String get labelVoipInputVolume => Intl.message("Input volume",
      name: "labelVoipInputVolume",
      desc: "label for the slider that sets how loud your microphone is");

  String get labelVoipInputVolumeDescription =>
      Intl.message("How loud your microphone is to everyone else",
          name: "labelVoipInputVolumeDescription");

  String get labelVoipOutputVolume => Intl.message("Output volume",
      name: "labelVoipOutputVolume",
      desc:
          "label for the slider that sets the volume of everyone in your calls");

  String get labelVoipOutputVolumeDescription => Intl.message(
      "Turns down everyone in your calls and the audio of streams you watch. Each person's own volume still applies on top.",
      name: "labelVoipOutputVolumeDescription");

  String percent(double v) => "${(v * 100).round()}%";

  // Vommet: Discord's layout, each device with its volume under it; input
  // and output side by side when there's room.
  Widget devicePicker() {
    final input = [
      if (microphones != null && !PlatformUtils.isAndroid) inputPicker(),
      if (VoiceFilter.supportsVolume)
        DoublePreferenceSlider(
          preference: preferences.voipMicrophoneVolume,
          title: labelVoipInputVolume,
          description: labelVoipInputVolumeDescription,
          min: 0,
          max: 2,
          divisions: 40,
          numDecimals: 2,
          formatValue: percent,
          // The filter takes the value once the slider is let go.
          onChangeEnd: (_) => VoiceFilter.apply(),
        ),
    ];
    final output = [
      if (speakers != null) outputPicker(),
      DoublePreferenceSlider(
        preference: preferences.voipOutputVolume,
        title: labelVoipOutputVolume,
        description: labelVoipOutputVolumeDescription,
        min: 0,
        max: 2,
        divisions: 40,
        numDecimals: 2,
        formatValue: percent,
        onChanged: (_) => clientManager?.callManager.refreshPlaybackVolumes(),
      ),
    ];
    column(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: children);
    return LayoutBuilder(builder: (context, constraints) {
      if (input.isEmpty || constraints.maxWidth < 560) {
        return column([...input, ...output]);
      }
      return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Expanded(child: column(input)),
            Expanded(child: column(output)),
          ]);
    });
  }

  Widget inputPicker() => buildPicker(
        "Input Device",
        preferences.voipDefaultAudioInput.value,
        microphones!,
        onSelected: (device) async {
          await preferences.voipDefaultAudioInput.set(device?.label);

          WebrtcDefaultDevices.selectInputDevice();

          setState(() {});
        },
      );

  Widget outputPicker() => buildPicker(
        "Output Device",
        preferences.voipDefaultAudioOutput.value,
        speakers!,
        onSelected: (device) async {
          await preferences.voipDefaultAudioOutput.set(device?.label);

          WebrtcDefaultDevices.selectOutputDevice();
          setState(() {});
        },
      );

  Widget buildPicker(
      String label, String? selected, List<webrtc.MediaDeviceInfo> microphones,
      {Function(webrtc.MediaDeviceInfo? device)? onSelected}) {
    var selectedDevice =
        microphones.firstWhereOrNull((i) => i.label == selected);

    List<webrtc.MediaDeviceInfo?> items = [null, ...microphones];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(label),
        tiamat.DropdownSelector<webrtc.MediaDeviceInfo?>(
            items: items,
            onItemSelected: onSelected,
            itemBuilder: (item) {
              if (item == null) {
                return tiamat.Text.labelLow("No Default Selected");
              } else {
                return tiamat.Text(item.label);
              }
            },
            value: selectedDevice),
      ],
    );
  }
}
