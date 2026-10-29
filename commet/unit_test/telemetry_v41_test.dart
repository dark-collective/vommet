// Vommet telemetry schema v41: the camera background blur experiment is in
// the experiment_key list, so session_start reports it by name instead of
// "other".

import 'dart:io';

import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v41", () {
    expect(schema.version, greaterThanOrEqualTo(41));
  });

  test("the camera background blur experiment is in the schema's list", () {
    expect(
        schema.enumAllows(
            "experiment_key", preferences.experimentCameraBackgroundBlur.key),
        isTrue);
  });
}
