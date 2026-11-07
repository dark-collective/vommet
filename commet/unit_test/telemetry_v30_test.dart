// Vommet telemetry schema v30: `secure_unlock` (unlocking an existing
// account's messages on a new device) and `history_keys_import` (the
// background key backup import after it).

import 'dart:convert';
import 'dart:io';

import 'package:commet/telemetry/secure_unlock_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> event(String name, Map<String, Object?> fields) {
  final ev = <String, Object>{"e": name, "t": 1000};
  fields.forEach((k, v) {
    if (v != null) ev[k] = v;
  });
  return ev;
}

void main() {
  final source = File("assets/telemetry/schema.json").readAsStringSync();
  final schema = TelemetrySchema.parse(source);

  test("schema is v30 and still accepts v29", () {
    expect(schema.version, greaterThanOrEqualTo(30));
    expect((jsonDecode(source) as Map)["accepts"], contains(29));
  });

  test("secure_unlock with a recovery key validates", () {
    final steps = UnlockSteps()
      ..openMs = 900
      ..cacheMs = 400
      ..selfSignMs = 700;
    final fields = SecureUnlockTelemetry.unlockFields(
        path: "recovery_key", screenMs: 2100, steps: steps);
    expect(fields["outcome"], "ok");
    expect(fields.containsKey("failure"), isFalse);
    expect(schema.validateEvent(event("secure_unlock", fields)), isTrue);
  });

  test("secure_unlock failures carry only a fixed kind", () {
    for (final (error, kind) in [
      (WrongRecoveryKeyException(), "wrong_key"),
      (MalformedRecoveryKeyException(), "malformed_key"),
      (NothingToUnlockException(), "nothing_to_unlock"),
      (StateError("anything at all"), "other"),
    ]) {
      final fields = SecureUnlockTelemetry.unlockFields(
          path: "passphrase",
          screenMs: 300,
          steps: UnlockSteps()..openMs = 300,
          error: error);
      expect(fields["outcome"], "error");
      expect(fields["failure"], kind);
      expect(schema.validateEvent(event("secure_unlock", fields)), isTrue,
          reason: "$fields");
    }
  });

  test("secure_unlock after approval validates; no key or id fits", () {
    final fields = SecureUnlockTelemetry.unlockFields(
        path: "approval", screenMs: 350, finishMs: 300);
    final ev = event("secure_unlock", fields);
    expect(schema.validateEvent(ev), isTrue);
    expect(schema.validateEvent({...ev, "path": "EsTc 1234 5678"}), isFalse);
    expect(schema.validateEvent({...ev, "recovery_key": "EsTc 1234"}), isFalse);
    expect(
        schema.validateEvent({...ev, "room_id": "!abc:example.org"}), isFalse);
    expect(schema.validateEvent(Map.of(ev)..remove("screen_ms")), isFalse);
  });

  test("history_keys_import validates; the count is clamped", () {
    for (final trigger in ["unlock", "approval", "startup"]) {
      final fields = SecureUnlockTelemetry.importFields(
          trigger: trigger, ms: 185000, sessions: 42000);
      expect(
          schema.validateEvent(event("history_keys_import", fields)), isTrue);
    }
    final huge = SecureUnlockTelemetry.importFields(
        trigger: "unlock", ms: 1, sessions: 5000000);
    expect(huge["sessions"], 1000000);
    expect(schema.validateEvent(event("history_keys_import", huge)), isTrue);
    final failed = SecureUnlockTelemetry.importFields(
        trigger: "startup", ms: 20, error: const SocketException("down"));
    expect(failed["outcome"], "error");
    expect(schema.validateEvent(event("history_keys_import", failed)), isTrue);
    expect(
        schema.validateEvent(event("history_keys_import", {
          ...failed,
          "room_id": "!abc:example.org",
        })),
        isFalse);
  });
}
