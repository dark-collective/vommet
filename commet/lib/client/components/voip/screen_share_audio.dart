import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum ScreenShareAudioKind { none, system, app }

/// Vommet: which audio a screen share carries, chosen independently of the
/// shared window or screen (like Vesktop). Linux and Windows offer a choice;
/// our flutter-webrtc fork records each app's playback on its own there
/// (Linux: PulseAudio/PipeWire streams; Windows: one WASAPI process-loopback
/// recording per app, mixed).
class ScreenShareAudio {
  final ScreenShareAudioKind kind;

  /// Stream property that identifies the chosen app ([ScreenShareAudioKind.app]):
  /// `application.process.binary` when the app reports one, else
  /// `application.name` (native PipeWire apps such as Spotify or mpv only
  /// report the name). On Windows the binary is the exe ("Spotify.exe") and
  /// the name its file description ("Spotify"), both matched ignoring case.
  final String prop;
  final String value;

  /// Shown in the picker.
  final String label;

  // Vommet issue 91: app mode can carry several immutable app identities.
  final List<ScreenShareAudio>? _selected;
  List<ScreenShareAudio> get apps =>
      kind == ScreenShareAudioKind.app ? _selected ?? [this] : const [];
  bool get isValid =>
      kind != ScreenShareAudioKind.app ||
      (apps.isNotEmpty &&
          apps.every((app) =>
              app.value.isNotEmpty &&
              (app.prop == 'application.process.binary' ||
                  app.prop == 'application.name')));

  factory ScreenShareAudio.selected(Iterable<ScreenShareAudio> apps) {
    final selected = <String, ScreenShareAudio>{};
    for (final app in apps) {
      if (app.kind == ScreenShareAudioKind.app && app.value.isNotEmpty) {
        selected.putIfAbsent(app.identity, () => app);
      }
    }
    final list = selected.values.toList()
      ..sort((a, b) => a.identity.compareTo(b.identity));
    if (list.length == 1) return list.single;
    return ScreenShareAudio._(ScreenShareAudioKind.app,
        selected: List.unmodifiable(list));
  }

  /// Match the native backend: exact on Linux, ASCII case-folded on Windows.
  String get identity => identityFor();
  String identityFor({bool? windows}) =>
      '$prop=${(windows ?? PlatformUtils.isWindows) ? _asciiLower(value) : value}';
  static String _asciiLower(String value) => String.fromCharCodes(
      value.codeUnits.map((c) => c >= 65 && c <= 90 ? c + 32 : c));

  bool get isVoiceChat =>
      voiceChatApps.contains(label) ||
      (PlatformUtils.isWindows &&
          windowsVoiceChatBinaries
              .any((exe) => _asciiLower(exe) == _asciiLower(value)));

  const ScreenShareAudio._(this.kind,
      {this.prop = "",
      this.value = "",
      this.label = "",
      List<ScreenShareAudio>? selected})
      : _selected = selected;

  static const none = ScreenShareAudio._(ScreenShareAudioKind.none);

  /// Every app except Vommet and other voice chat apps (see
  /// [voiceChatApps]), so call audio is never sent back into a call.
  static const system = ScreenShareAudio._(ScreenShareAudioKind.system);

  const ScreenShareAudio.app(String prop, String value, String label)
      : this._(ScreenShareAudioKind.app,
            prop: prop, value: value, label: label);

  /// Whether the user can pick which audio to share.
  static bool get canChoose => PlatformUtils.isLinux || PlatformUtils.isWindows;

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
    "Zoom Meetings",
    "Microsoft Teams",
    "teams-for-linux",
  ];

  /// Windows: voice chat apps' exe names, also left out of "All apps" (an
  /// app's file description doesn't always match [voiceChatApps]).
  static const windowsVoiceChatBinaries = [
    "Discord.exe",
    "DiscordPTB.exe",
    "DiscordCanary.exe",
    "Element.exe",
    "Vesktop.exe",
    "Legcord.exe",
    "WebCord.exe",
    "Zoom.exe",
    "ms-teams.exe",
    "Teams.exe",
    "mumble.exe",
    "ts3client_win64.exe",
    "TeamSpeak.exe",
  ];

  /// Options for the fork's `Helper.screenCaptureAudioOptions`. [windows]
  /// defaults to the current platform.
  Map<String, dynamic>? toCaptureOptions({bool? windows}) {
    // An empty native include list means ALL apps, never silence.
    if (!isValid) throw StateError('No screen-share audio apps selected');
    return switch (kind) {
      ScreenShareAudioKind.app => {
          'include': [
            for (final app in {
              for (final app in apps) app.identityFor(windows: windows): app
            }.values)
              {app.prop: app.value}
          ],
        },
      ScreenShareAudioKind.system => {
          'exclude': [
            for (final name in voiceChatApps) {'application.name': name},
            if (windows ?? PlatformUtils.isWindows)
              for (final exe in windowsVoiceChatBinaries)
                {'application.process.binary': exe}
          ],
        },
      ScreenShareAudioKind.none => null,
    };
  }

  /// Apps currently playing audio, one entry per program, without Vommet.
  static Future<List<ScreenShareAudio>> listApps(
      {bool rethrowErrors = false}) async {
    try {
      return appsFrom(await Helper.getLoopbackAudioSources());
    } catch (e, s) {
      Log.onError(e, s, content: "Could not list apps playing audio");
      if (rethrowErrors) rethrow;
      return [];
    }
  }

  /// The picker's app entries for the fork's `getLoopbackAudioSources`
  /// result: one per program, without Vommet, sorted by label.
  static List<ScreenShareAudio> appsFrom(List<Map<String, dynamic>> sources) {
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
      if (app != null) apps.putIfAbsent(app.identity, () => app);
    }
    return apps.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenShareAudio &&
      other.kind == kind &&
      other.prop == prop &&
      other.value == value &&
      (_selected == null
          ? other._selected == null
          : other._selected != null &&
              _selected.length == other._selected.length &&
              List.generate(
                      _selected.length,
                      (i) =>
                          _selected[i].identity == other._selected[i].identity)
                  .every((v) => v));

  @override
  int get hashCode => Object.hash(
      kind,
      prop,
      value,
      _selected == null
          ? null
          : Object.hashAll(_selected.map((app) => app.identity)));
}
