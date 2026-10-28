import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/components/voip/android_screencapture_source.dart';
import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/organisms/call_view/screen_capture_source_dialog.dart';
import 'package:commet/ui/organisms/call_view/screen_share_audio_picker.dart';
import 'package:commet/ui/organisms/call_view/share_quality_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tiamat/atoms/popup_dialog.dart';
import 'package:intl/intl.dart';

class WebrtcScreencaptureSource implements ScreenCaptureSource {
  static String get screenShareAudioDialogTitle => Intl.message("Screen share",
      name: "screenShareAudioDialogTitle",
      desc:
          "Title of the dialog that asks which audio to share before choosing what to screen share");

  DesktopCapturerSource source;

  /// Vommet: the audio to share with it (Linux picker; elsewhere all system
  /// audio where supported, as upstream).
  ScreenShareAudio audio;

  WebrtcScreencaptureSource(this.source,
      {this.audio = ScreenShareAudio.system});

  // Vommet: Linux too, via our flutter-webrtc fork (per-app capture that
  // leaves out the call's own playback).
  static bool get supportsSystemAudio =>
      PlatformUtils.isWindows || PlatformUtils.isLinux;

  static Future<ScreenCaptureSource?> showSelectSourcePrompt(
      BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      return WebrtcAndroidScreencaptureSource.getCaptureSource(context);
    }

    bool isWayland = PlatformUtils.displayServer == "wayland";

    // Vommet: on Wayland the system portal picks the video, and depending on
    // the portal it appears while listing sources or only when capture
    // starts. Ask for the audio first, before touching the portal, so the
    // order is always audio, then video.
    var audio = ScreenShareAudio.lastChoice;
    if (isWayland && ScreenShareAudio.canChoose) {
      if (!context.mounted) return null;
      final picked = await PopupDialog.show<ScreenShareAudio>(context,
          content: const ScreenShareAudioDialog(),
          title: screenShareAudioDialogTitle);
      if (picked == null) return null;
      audio = ScreenShareAudio.lastChoice = picked;
    }

    // Vommet: our flutter-webrtc fork runs the portal itself and offers
    // screens AND windows in one system dialog, which opens when capture
    // starts. libwebrtc's own path only asks the portal for screens.
    if (isWayland && await Helper.portalScreenCastAvailable()) {
      final source = PortalCaptureSource();
      if (!await _qualityStep(context, source)) return null;
      return WebrtcScreencaptureSource(source, audio: audio);
    }

    var sources = await desktopCapturer.getSources(
      types: [if (!isWayland) SourceType.Window, SourceType.Screen],
    );

    if (isWayland && sources.isNotEmpty) {
      if (!await _qualityStep(context, sources.first)) return null;
      return WebrtcScreencaptureSource(sources.first, audio: audio);
    }

    // Vommet: the Go live step's Back (or Change source) comes back here.
    while (context.mounted) {
      var result = await PopupDialog.show<ScreenCaptureChoice>(context,
          content: ScreenCaptureSourceDialog(
              sources, desktopCapturer.onThumbnailChanged.stream),
          title: "Screen Share");

      if (result == null) return null;
      final (source, audio) = result;
      if (ScreenShareAudio.canChoose) ScreenShareAudio.lastChoice = audio;
      if (!context.mounted) return null;
      if (!ShareQuality.shouldAsk) {
        return WebrtcScreencaptureSource(source, audio: audio);
      }
      final step = await ShareQualityStep.show(context,
          sourceName: source.name,
          isWindow: source.type == SourceType.Window,
          thumbnail: source.thumbnail);
      if (step == ShareQualityStepResult.goLive) {
        return WebrtcScreencaptureSource(source, audio: audio);
      }
      if (step == null) return null;
    }

    return null;
  }

  /// Vommet: the Go live step (quality), the first time you share or every
  /// time if you asked for it, where the source has no picker to go back
  /// to (Back cancels). Whether to go on.
  static Future<bool> _qualityStep(
      BuildContext context, DesktopCapturerSource source) async {
    if (!ShareQuality.shouldAsk) return true;
    if (!context.mounted) return false;
    final step = await ShareQualityStep.show(context,
        sourceName: source.name,
        isWindow: source.type == SourceType.Window,
        thumbnail: source.thumbnail);
    return step == ShareQualityStepResult.goLive;
  }
}

/// Vommet: stands for "whatever the user picks in the system's screen-capture
/// dialog" (Wayland portal, screens and windows).
class PortalCaptureSource implements DesktopCapturerSource {
  @override
  String get id => Helper.portalScreenCastSourceId;

  @override
  String get name => "Chosen in the system dialog";

  @override
  Uint8List? get thumbnail => null;

  @override
  ThumbnailSize get thumbnailSize => ThumbnailSize(0, 0);

  @override
  SourceType get type => SourceType.Window;

  @override
  StreamController<String> get onNameChanged => StreamController<String>();

  @override
  StreamController<Uint8List> get onThumbnailChanged =>
      StreamController<Uint8List>();
}
