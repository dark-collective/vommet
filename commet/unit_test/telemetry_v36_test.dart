// Vommet telemetry schema v36: the Friends tab, New Home and Help on
// right-click experiments are in the experiment_key list, so diagnostics
// name them instead of "other"; session_start lists which settings that
// used to be experiments are switched off.

import 'dart:io';

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/telemetry/settings_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v36", () {
    expect(schema.version, greaterThanOrEqualTo(36));
  });

  test("the experiments added in v36 are reported by name", () {
    for (final key in [
      "vommet_experiment_friends_tab",
      "vommet_experiment_new_home",
      "vommet_experiment_guides",
    ]) {
      expect(schema.enumAllows("experiment_key", key), isTrue, reason: key);
    }
  });

  test("settings_off: fixed keys only, nothing else gets through", () {
    final start = {
      "e": "session_start",
      "t": 1000,
      "settings_off": ["experiment_noise_suppression"],
    };
    expect(schema.validateEvent(start), isTrue);
    expect(
        schema.validateEvent({...start, "settings_off": <String>[]}), isTrue);
    for (final bad in [
      ["Noise suppression"],
      ["other"],
      ["experiment_call_cards"],
      "experiment_noise_suppression",
    ]) {
      expect(schema.validateEvent({...start, "settings_off": bad}), isFalse,
          reason: "$bad");
    }
  });

  test("every tracked setting is in the schema's list", () {
    for (final key in [
      "experiment_noise_suppression",
      "experiment_auto_gain_control",
      "experiment_sidebar_newest_unread_dms",
      "experiment_sliding_sync",
      "experiment_secure_setup",
      "vommet_experiment_banner_layout",
      "vommet_experiment_deleted_message_placeholders",
    ]) {
      expect(schema.enumAllows("setting_key", key), isTrue, reason: key);
    }
  });

  test("settings_off: off only, sorted, unknown keys left out", () {
    expect(
        SettingsTelemetry.off(settings: [
          BoolPreference("zeta_off", defaultValue: false),
          BoolPreference("alpha_off", defaultValue: false),
          BoolPreference("beta_on", defaultValue: true),
          BoolPreference("unknown", defaultValue: false),
        ], known: (k) => k != "unknown"),
        ["alpha_off", "zeta_off"]);
  });
}
