// Vommet telemetry schema v38: the chat wallpaper and New room info page
// experiments are in the experiment_key list, so session_start reports them
// by name instead of "other".

import 'dart:io';

import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/config/experiment_entries.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v38", () {
    expect(schema.version, greaterThanOrEqualTo(38));
  });

  test("the new experiments are in the schema's list", () {
    for (final pref in [experimentChatWallpapers, experimentRoomInfoPage]) {
      expect(schema.enumAllows("experiment_key", pref.key), isTrue,
          reason: pref.key);
    }
  });

  test("every experiment on the Experiments page is in the schema's list",
      () async {
    // unit_test/ isn't a directory the analyzer counts as tests.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    for (final e in experimentEntries()) {
      expect(schema.enumAllows("experiment_key", e.preference.key), isTrue,
          reason: e.preference.key);
    }
  });
}
