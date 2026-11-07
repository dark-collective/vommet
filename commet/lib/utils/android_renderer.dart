import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:flutter/widgets.dart';

/// Vommet: the Android renderer choice (Settings › Advanced › Renderer). The
/// app reads it natively at launch (RendererChoice.kt), before any Flutter
/// engine starts, so a change takes effect after restarting Vommet.
class AndroidRenderer {
  /// null = Flutter's default (Impeller, Vulkan where it works), "opengles"
  /// (Impeller on OpenGL ES) or "skia".
  static final NullableStringPreference choice =
      NullableStringPreference("android_renderer", defaultValue: null);

  /// Launches with a chosen renderer that never drew a frame, counted by
  /// RendererChoice.kt, which falls back to the default after two.
  static const String _unconfirmedKey = "android_renderer_unconfirmed";

  /// Clears the launch counter once the UI drew its first frame.
  static void confirmAfterFirstFrame() {
    if (!PlatformUtils.isAndroid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Preference.preferences?.remove(_unconfirmedKey);
    });
  }
}
