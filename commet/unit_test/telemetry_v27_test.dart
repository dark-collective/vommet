// Vommet telemetry schema v27: every experiment on the Experiments page is
// in the experiment_key list, so diagnostics name it instead of "other".

import 'dart:io';

import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v27", () {
    expect(schema.version, greaterThanOrEqualTo(27));
  });

  test("the experiments added in v27 are reported by name", () {
    for (final key in [
      "experiment_call_cards",
      "experiment_dm_trust_warnings",
      "experiment_encryption_markers",
      "experiment_manage_space_rooms",
      "experiment_secure_setup",
      "experiment_sidebar_subspace_guides",
      "experiment_unified_chat_list",
      "experiment_voice_room_chat",
      "vommet_experiment_block_users",
      "vommet_experiment_deleted_message_placeholders",
      "vommet_experiment_docked_widgets",
      "vommet_experiment_last_room_per_space",
      "vommet_experiment_lightbox_gallery",
      "vommet_experiment_redacted_mode",
      "vommet_experiment_select_messages",
      "vommet_experiment_stream_watching",
      "vommet_experiment_thread_read_state",
    ]) {
      expect(schema.enumAllows("experiment_key", key), isTrue, reason: key);
    }
    expect(
        schema.enumAllows("experiment_key", "experiment_not_listed"), isFalse);
  });
}
