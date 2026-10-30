// Vommet: "Camera effects" in Settings, Voice and video. Where Vommet can
// blur (web, Android, iOS, macOS) it holds the background blur switch, behind
// its experiment; otherwise the native apps point people at their system's
// own camera effects, which every app's camera gets.

import 'dart:async';

import 'package:commet/client/components/voip/camera_background_blur.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/links/link_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CameraEffectsSettings extends StatefulWidget {
  const CameraEffectsSettings({super.key});

  @override
  State<CameraEffectsSettings> createState() => _CameraEffectsSettingsState();
}

class _CameraEffectsSettingsState extends State<CameraEffectsSettings> {
  StreamSubscription<void>? _sub;

  static final Uri _macHelp =
      Uri.parse("https://support.apple.com/en-us/105117");
  static final Uri _windowsHelp = Uri.parse(
      "https://support.microsoft.com/en-us/windows/ai/ai-features/windows-studio-effects");

  @override
  void initState() {
    super.initState();
    _sub = CameraBackgroundBlur.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = CameraBackgroundBlur.available
        ? _blur()
        : PlatformUtils.isWeb
            ? _web()
            : _native(context);
    if (child == null) return const SizedBox.shrink();

    return tiamat.Panel(
      header: "Camera effects",
      mode: tiamat.TileType.surfaceContainerLow,
      child: child,
    );
  }

  Widget? _web() {
    if (!preferences.experimentCameraBackgroundBlur.value) return null;

    return const tiamat.Text.labelLow(
        "This browser can't blur the camera. A recent Chrome, Edge or "
        "Firefox can.");
  }

  Widget _blur() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BooleanPreferenceToggle(
          preference: preferences.cameraBackgroundBlur,
          title: "Blur background",
          description: "Blurs what's behind you when your camera is on. Off "
              "by default and saved on this device. Turns itself off if this "
              "device is too slow for it.",
          onChanged: (_) {
            CameraBackgroundBlur.turnedOffForSpeed = false;
            CameraBackgroundBlur.notifyChanged();
          },
        ),
        if (CameraBackgroundBlur.turnedOffForSpeed)
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 8, 0, 0),
            child: tiamat.Text.labelLow(
                "Turned off because it was too slow on this device."),
          ),
      ],
    );
  }

  Widget? _native(BuildContext context) {
    final (String text, Uri? help) = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => (
          "To blur your background, use Video Effects in Control Center "
              "while your camera is on. It works in every app.",
          _macHelp
        ),
      TargetPlatform.windows => (
          "To blur your background, use Windows Studio Effects (Quick "
              "Settings) if your PC supports it. It works in every app.",
          _windowsHelp
        ),
      TargetPlatform.linux => (
          "To blur your background, use a virtual camera (for example OBS "
              "with a background removal filter, or Backscrub, through "
              "v4l2loopback) and pick it under Devices.",
          null
        ),
      TargetPlatform.iOS => (
          "To blur your background, use your phone's camera effects in "
              "Control Center while your camera is on, where your phone "
              "offers them.",
          null
        ),
      _ => (
          "To blur your background, use your phone's camera effects if it "
              "offers them for video calls.",
          null
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(text),
        if (help != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
            child: SizedBox(
              height: 40,
              child: tiamat.TextButton(
                "How to turn it on",
                icon: Icons.open_in_browser,
                onTap: () => LinkUtils.open(help, context: context),
              ),
            ),
          ),
      ],
    );
  }
}
