// Vommet telemetry schema v37: the Layout panel's seven "Rooms and spaces"
// options are in the setting_key list, so session_start can say which ones
// are switched off.

import 'dart:io';

import 'package:commet/config/room_layout_options.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v37", () {
    expect(schema.version, greaterThanOrEqualTo(37));
  });

  test("every Rooms and spaces option is in the schema's list", () {
    for (final pref in [
      shrinkBannersOnScroll,
      memberListOnlineSections,
      memberListCallActivity,
      memberPanelTabs,
      resizablePanels,
      spaceHomeLikeRoomList,
      homeBadgeCountsDms,
    ]) {
      expect(schema.enumAllows("setting_key", pref.key), isTrue,
          reason: pref.key);
    }
  });

  test("settings_off takes the new keys, still nothing else", () {
    final start = {
      "e": "session_start",
      "t": 1000,
      "settings_off": ["vommet_rooms_member_list_online"],
    };
    expect(schema.validateEvent(start), isTrue);
    expect(
        schema.validateEvent({
          ...start,
          "settings_off": ["vommet_rooms_unknown"]
        }),
        isFalse);
  });
}
