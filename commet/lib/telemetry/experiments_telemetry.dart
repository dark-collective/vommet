// Vommet: which experiments are switched on, for opt-in diagnostics, so a
// feature can leave its experiment flag on evidence: how many testers use
// it, on which platforms, and whether problems follow it. Only the
// experiments' fixed preference keys from the schema's list (others are sent
// as "other"), never anything personal.

import 'package:commet/config/experiment_registry.dart';
import 'package:commet/telemetry/telemetry.dart';

class ExperimentsTelemetry {
  /// Sorted preference keys of the enabled experiments in [experiments]
  /// (default: every experiment available on this device). Keys the schema
  /// doesn't list ([known] false) are sent as "other", so only fixed values
  /// ever leave the device.
  static List<String> enabled(
      {List<Experiment>? experiments, bool Function(String key)? known}) {
    final isKnown =
        known ?? (key) => Telemetry.enumAllows("experiment_key", key);
    final keys = (experiments ?? ExperimentRegistry.all)
        .where((e) => e.preference.value == true)
        .map((e) => isKnown(e.preference.key) ? e.preference.key : "other")
        .toSet()
        .toList()
      ..sort();
    return keys.take(64).toList();
  }
}
