// Capture telemetry (#78): device labels and error messages are read on the
// device only, to pick a fixed device type / error kind; the schema must refuse
// the label or message itself.

import 'dart:io';

import 'package:commet/telemetry/capture_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  final micStart = <String, Object>{
    "e": "capture",
    "t": 3000,
    "source": "mic",
    "action": "start",
    "api": "livekit",
    "device_choice": "preferred",
    "device_type": "bluetooth",
    "devices": 3,
    "ms": 140,
    "outcome": "error",
    "error_kind": "device_busy",
    "error_type": "PlatformException",
  };

  Map<String, Object> withField(String k, Object v) => {...micStart, k: v};

  test("valid capture event passes", () {
    expect(schema.validateEvent(micStart), isTrue);
    expect(
        schema.validateEvent({
          "e": "capture",
          "t": 1,
          "source": "screen",
          "action": "start",
          "outcome": "ok"
        }),
        isTrue);
  });

  test("device names and messages can't ride along", () {
    expect(schema.validateEvent(withField("device_type", "Alice's AirPods")),
        isFalse);
    expect(
        schema.validateEvent(withField("device", "Alice's AirPods")), isFalse);
    expect(schema.validateEvent(withField("device_id", "{0.0.1.00000000}")),
        isFalse);
    expect(
        schema.validateEvent(withField("api", "wasapi: Alice's mic")), isFalse);
    expect(
        schema.validateEvent(
            withField("error_type", "PlatformException(Alice's AirPods)")),
        isFalse);
    expect(
        schema.validateEvent(withField("source", "Alice's AirPods")), isFalse);
  });

  test("source and action are required", () {
    expect(
        schema.validateEvent(
            {"e": "capture", "t": 1, "action": "start", "outcome": "ok"}),
        isFalse);
    expect(
        schema.validateEvent(
            {"e": "capture", "t": 1, "source": "mic", "outcome": "ok"}),
        isFalse);
  });

  // Capture events arrived in schema v2; later versions keep them.
  test("schema is version 2 or later", () {
    expect(schema.version, greaterThanOrEqualTo(2));
  });

  test("device labels map to a fixed type", () {
    const types = {"builtin", "usb", "bluetooth", "virtual", "hdmi", "unknown"};
    final cases = {
      "Headset (Alice's AirPods Hands-Free AG Audio)": "bluetooth",
      "Microphone (Realtek(R) Audio)": "builtin",
      "Microphone Array (Intel® Smart Sound Technology)": "builtin",
      "Microphone (2- USB Audio Device)": "usb",
      "CABLE Output (VB-Audio Virtual Cable)": "virtual",
      "Monitor of Built-in Audio Analog Stereo": "virtual",
      "Steam Streaming Microphone": "virtual",
      "Digital Audio (HDMI)": "hdmi",
      "Bob's Thing": "unknown",
      "": "unknown",
    };
    cases.forEach((label, type) {
      final got = CaptureTelemetry.deviceType(label);
      expect(got, type, reason: label);
      expect(types, contains(got));
    });
    expect(CaptureTelemetry.deviceType(null), "unknown");
  });

  test("capture errors map to a schema error kind, never the message", () {
    final kinds = {
      PlatformException(
          code: "getUserMediaFailed",
          message: "NotAllowedError: Permission denied"): "permission",
      PlatformException(
          code: "getUserMediaFailed",
          message: "Requested device not found"): "not_found",
      PlatformException(
              code: "getUserMediaFailed",
              message: "NotReadableError: Could not start audio source"):
          "device_busy",
      Exception("Alice's AirPods exploded"): "unknown",
    };
    kinds.forEach((error, kind) {
      final got = CaptureTelemetry.errorKind(error);
      expect(got, kind, reason: error.toString());
      expect(
          schema.validateEvent({
            ...micStart,
            "error_kind": got,
            "error_type": "PlatformException"
          }),
          isTrue);
    });
  });
}
