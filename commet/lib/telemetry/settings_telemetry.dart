// Vommet: which of the settings that used to be experiments are switched
// off, for opt-in diagnostics, so we can see how many people turn each one
// off now that it is an ordinary setting (they leave the experiments list
// when they graduate). Only the settings' fixed preference keys from the
// schema's list, never anything personal.

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';

class SettingsTelemetry {
  /// The settings reported, by preference.
  static List<BoolPreference> get tracked => [
        preferences.experimentNoiseSuppression,
        preferences.experimentAutoGainControl,
        preferences.experimentSidebarNewestUnreadDms,
        preferences.experimentSlidingSync,
        preferences.experimentSecureSetup,
        preferences.experimentBannerLayout,
        experimentDeletedMessagePlaceholders,
      ];

  /// Sorted preference keys of the switched-off settings in [settings]
  /// (default: [tracked]). Keys the schema doesn't list ([known] false) are
  /// left out, so only fixed values ever leave the device.
  static List<String> off(
      {List<BoolPreference>? settings, bool Function(String key)? known}) {
    final isKnown = known ?? (key) => Telemetry.enumAllows("setting_key", key);
    return (settings ?? tracked)
        .where((p) => p.value == false && isKnown(p.key))
        .map((p) => p.key)
        .toSet()
        .toList()
      ..sort();
  }
}
