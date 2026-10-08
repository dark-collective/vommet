import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum ScreenShareAudioKind { none, system, app }

/// Vommet: which audio a screen share carries, chosen independently of the
/// shared window or screen (like Vesktop). Only Linux offers a choice; our
/// flutter-webrtc fork records each app's playback stream on its own there.
class ScreenShareAudio {
  final ScreenShareAudioKind kind;

  /// Stream property that identifies the chosen app ([ScreenShareAudioKind.app]):
  /// `application.process.binary` when the app reports one, else
  /// `application.name` (native PipeWire apps such as Spotify or mpv only
  /// report the name).
  final String prop;
  final String value;

  /// Shown in the picker.
  final String label;

  const ScreenShareAudio._(this.kind,
      {this.prop = "", this.value = "", this.label = ""});

  static const none = ScreenShareAudio._(ScreenShareAudioKind.none);

  /// Every app except Vommet and other voice chat apps (see
  /// [voiceChatApps]), so call audio is never sent back into a call.
  static const system = ScreenShareAudio._(ScreenShareAudioKind.system);

  const ScreenShareAudio.app(String prop, String value, String label)
      : this._(ScreenShareAudioKind.app,
            prop: prop, value: value, label: label);

  /// Whether the user can pick which audio to share.
  static bool get canChoose => PlatformUtils.isLinux;

  /// Kept for the rest of the session so the next share starts from it.
  static ScreenShareAudio lastChoice = system;

  /// `application.name`s left out of "All apps": their playback is usually
  /// another call. Element joined to the same call on the same computer
  /// otherwise feeds the call back into itself (a howling loop, 10-07).
  /// "WEBRTC VoiceEngine" is libwebrtc's own playback (other native WebRTC
  /// clients). Each can still be picked on its own.
  static const voiceChatApps = [
    "WEBRTC VoiceEngine",
    "Element",
    "Element Nightly",
    "Commet",
    "Vommet",
    "Nheko",
    "NeoChat",
    "Fractal",
    "Discord",
    "discord",
    "vesktop",
    "Vesktop",
    "WebCord",
    "Legcord",
    "legcord",
    "ArmCord",
    "Mumble",
    "TeamSpeak",
    "TeamSpeak 3",
    "ZOOM VoiceEngine",
    "Microsoft Teams",
    "teams-for-linux",
  ];

  /// Options for the fork's `Helper.screenCaptureAudioOptions`.
  Map<String, dynamic>? toCaptureOptions() => switch (kind) {
        ScreenShareAudioKind.app => {
            'include': [
              {prop: value}
            ],
          },
        ScreenShareAudioKind.system => {
            'exclude': [
              for (final name in voiceChatApps) {'application.name': name}
            ],
          },
        ScreenShareAudioKind.none => null,
      };

  /// Apps currently playing audio, one entry per program, without Vommet.
  static Future<List<ScreenShareAudio>> listApps() async {
    try {
      final sources = await Helper.getLoopbackAudioSources();
      final apps = <String, ScreenShareAudio>{};
      for (final s in sources) {
        if (s['isSelf'] == true) continue;
        final binary = s['binary'] as String? ?? '';
        final name = s['applicationName'] as String? ?? '';
        final app = binary.isNotEmpty
            ? ScreenShareAudio.app("application.process.binary", binary,
                name.isEmpty ? binary : name)
            : name.isNotEmpty
                ? ScreenShareAudio.app("application.name", name, name)
                : null;
        if (app != null)
          apps.putIfAbsent("${app.prop}=${app.value}", () => app);
      }
      return apps.values.toList()
        ..sort(
            (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    } catch (e, s) {
      Log.onError(e, s, content: "Could not list apps playing audio");
      return [];
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenShareAudio &&
      other.kind == kind &&
      other.prop == prop &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, prop, value);
}
