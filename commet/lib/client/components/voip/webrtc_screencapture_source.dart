import 'package:commet/client/components/voip/android_screencapture_source.dart';
import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/organisms/call_view/screen_capture_source_dialog.dart';
import 'package:commet/ui/organisms/call_view/screen_share_audio_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:tiamat/atoms/popup_dialog.dart';

class WebrtcScreencaptureSource implements ScreenCaptureSource {
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
          content: const ScreenShareAudioDialog(), title: "Screen Share");
      if (picked == null) return null;
      audio = ScreenShareAudio.lastChoice = picked;
    }

    var sources = await desktopCapturer.getSources(
      types: [if (!isWayland) SourceType.Window, SourceType.Screen],
    );

    if (isWayland && sources.isNotEmpty) {
      return WebrtcScreencaptureSource(sources.first, audio: audio);
    }

    if (context.mounted) {
      var result = await PopupDialog.show<ScreenCaptureChoice>(context,
          content: ScreenCaptureSourceDialog(
              sources, desktopCapturer.onThumbnailChanged.stream),
          title: "Screen Share");

      if (result != null) {
        final (source, audio) = result;
        if (ScreenShareAudio.canChoose) ScreenShareAudio.lastChoice = audio;
        return WebrtcScreencaptureSource(source, audio: audio);
      }
    }

    return null;
  }
}
