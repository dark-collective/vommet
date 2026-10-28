// Vommet telemetry schema v42: local data encryption (opt-in) — the
// setting and key state at start-up, the user's choice, the start-up
// encryption/decryption runs and the key screens. Every field the client
// builds is accepted by the schema, and none carries a path or a name.

import 'dart:io';

import 'package:commet/security/migration/database_migration.dart';
import 'package:commet/telemetry/local_data_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  bool valid(String event, Map<String, Object?> fields) =>
      schema.validateEvent({"e": event, "t": 1000, ...fields});

  test("schema is v42", () {
    expect(schema.version, greaterThanOrEqualTo(42));
    for (final e in const [
      "local_data_state",
      "local_data_choice",
      "local_data_migration",
      "local_data_unlock"
    ]) {
      expect(schema.hasEvent(e), isTrue, reason: e);
    }
  });

  test("local_data_state", () {
    for (final store in const ["keyring", "portal", "dpapi", "file", "none"]) {
      expect(
          valid(
              "local_data_state",
              LocalDataTelemetry.stateFields(
                  encryptOn: false,
                  chosen: false,
                  pending: "none",
                  keyStore: store,
                  vault: "ready",
                  keyringAvailable: true,
                  filesEncrypted: 0,
                  filesPlain: 3)),
          isTrue,
          reason: store);
    }
    expect(
        valid(
            "local_data_state",
            LocalDataTelemetry.stateFields(
                encryptOn: true,
                chosen: true,
                pending: "decrypt",
                keyStore: "keyring",
                vault: "locked")),
        isTrue);
    for (final file in const ["ok", "missing", "unreadable"]) {
      expect(
          valid(
              "local_data_state",
              LocalDataTelemetry.stateFields(
                  encryptOn: true,
                  chosen: false,
                  pending: "none",
                  keyStore: "keyring",
                  vault: "ready",
                  settingFile: file)),
          isTrue,
          reason: file);
    }
    expect(
        valid("local_data_state", {
          "encrypt_on": true,
          "chosen": true,
          "key_store": "/home/someone/.local"
        }),
        isFalse);
  });

  test("local_data_choice", () {
    for (final source in const ["first_run", "settings", "notice"]) {
      expect(
          valid("local_data_choice",
              LocalDataTelemetry.choiceFields(encrypt: true, source: source)),
          isTrue);
    }
  });

  test("local_data_migration: every step and bucket", () {
    for (final step in MigrationStep.values) {
      expect(
          valid(
              "local_data_migration",
              LocalDataTelemetry.migrationFields(
                  decrypt: step.index.isEven,
                  result: "failed",
                  failedStep: step.name,
                  duration: const Duration(seconds: 3),
                  files: 2)),
          isTrue,
          reason: step.name);
    }
    for (final (seconds, bucket) in const [
      (1, "lt_10s"),
      (30, "10s_1m"),
      (200, "1m_5m"),
      (600, "5m_15m"),
      (5000, "gt_15m"),
    ]) {
      expect(LocalDataTelemetry.bucket(Duration(seconds: seconds)), bucket);
    }
    for (final result in const [
      "done",
      "partial",
      "no_space",
      "failed",
      "interrupted"
    ]) {
      expect(
          valid(
              "local_data_migration",
              LocalDataTelemetry.migrationFields(
                  decrypt: true,
                  result: result,
                  duration: Duration.zero,
                  keysForgotten: result == "done")),
          isTrue,
          reason: result);
    }
  });

  test("local_data_unlock", () {
    for (final screen in const [
      "locked",
      "missing",
      "unreachable",
      "damaged"
    ]) {
      for (final result in const [
        "unlocked",
        "recovered",
        "still_locked",
        "quit",
        "start_over",
        "continued_without",
        "reset_account"
      ]) {
        expect(
            valid(
                "local_data_unlock",
                LocalDataTelemetry.unlockFields(
                    screen: screen,
                    result: result,
                    wait: const Duration(minutes: 2),
                    keptCopy: true)),
            isTrue);
      }
    }
  });
}
