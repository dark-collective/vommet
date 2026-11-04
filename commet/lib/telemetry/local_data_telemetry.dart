// Vommet (schema v42): local data encryption, which is opt-in. The setting
// and the key's state once per start (`local_data_state`), the user's
// choice (`local_data_choice`), each start-up run encrypting or decrypting
// the databases (`local_data_migration`) and the start-up screens about
// the key (`local_data_unlock`). Fixed words, booleans, counts and
// duration buckets only: never paths, account names, key stores' own names
// or key material.

import 'package:commet/telemetry/telemetry.dart';

class LocalDataTelemetry {
  /// A duration as one of the schema's buckets.
  static String bucket(Duration d) {
    final s = d.inMilliseconds / 1000;
    if (s < 10) return "lt_10s";
    if (s < 60) return "10s_1m";
    if (s < 300) return "1m_5m";
    if (s < 900) return "5m_15m";
    return "gt_15m";
  }

  /// `failed_step` from a migration step's name (MigrationStep.name).
  static String step(String? name) => switch (name) {
        "resume" => "resume",
        "spaceCheck" => "space_check",
        "export" => "export",
        "verify" => "verify",
        "sync" => "sync",
        "deletePlainWal" => "delete_wal",
        "renamePlain" => "rename_old",
        "renameTemp" => "rename_temp",
        "wipe" => "wipe",
        "key" => "key",
        _ => "other",
      };

  static Map<String, Object?> stateFields({
    required bool encryptOn,
    required bool chosen,
    required String pending,
    required String keyStore,
    required String vault,
    bool? keyringAvailable,
    int? filesEncrypted,
    int? filesPlain,
    String? settingFile,
  }) =>
      {
        "encrypt_on": encryptOn,
        "chosen": chosen,
        "pending": pending,
        "key_store": keyStore,
        "vault": vault,
        if (keyringAvailable != null) "keyring_available": keyringAvailable,
        if (filesEncrypted != null)
          "files_encrypted": filesEncrypted.clamp(0, 1000000),
        if (filesPlain != null) "files_plain": filesPlain.clamp(0, 1000000),
        if (settingFile != null) "setting_file": settingFile,
      };

  static void state({
    required bool encryptOn,
    required bool chosen,
    required String pending,
    required String keyStore,
    required String vault,
    bool? keyringAvailable,
    int? filesEncrypted,
    int? filesPlain,
    String? settingFile,
  }) =>
      Telemetry.record(
          "local_data_state",
          stateFields(
              encryptOn: encryptOn,
              chosen: chosen,
              pending: pending,
              keyStore: keyStore,
              vault: vault,
              keyringAvailable: keyringAvailable,
              filesEncrypted: filesEncrypted,
              filesPlain: filesPlain,
              settingFile: settingFile));

  static Map<String, Object?> choiceFields(
          {required bool encrypt, required String source}) =>
      {"encrypt": encrypt, "source": source};

  static void choice({required bool encrypt, required String source}) =>
      Telemetry.record(
          "local_data_choice", choiceFields(encrypt: encrypt, source: source));

  /// [result]: done, partial, no_space, failed or interrupted.
  static Map<String, Object?> migrationFields({
    required bool decrypt,
    required String result,
    required Duration duration,
    String? failedStep,
    int? files,
    bool? keysForgotten,
  }) =>
      {
        "direction": decrypt ? "decrypt" : "encrypt",
        "outcome": result == "done" ? "ok" : "error",
        "result": result,
        if (failedStep != null) "failed_step": step(failedStep),
        "duration": bucket(duration),
        if (files != null) "files": files.clamp(0, 1000000),
        if (keysForgotten != null) "keys_forgotten": keysForgotten,
      };

  static void migration({
    required bool decrypt,
    required String result,
    required Duration duration,
    String? failedStep,
    int? files,
    bool? keysForgotten,
  }) =>
      Telemetry.record(
          "local_data_migration",
          migrationFields(
              decrypt: decrypt,
              result: result,
              duration: duration,
              failedStep: failedStep,
              files: files,
              keysForgotten: keysForgotten));

  /// [screen]: locked, missing, unreachable or damaged.
  static Map<String, Object?> unlockFields({
    required String screen,
    required String result,
    required Duration wait,
    bool? keptCopy,
  }) =>
      {
        "screen": screen,
        "result": result,
        "wait": bucket(wait),
        if (keptCopy != null) "kept_copy": keptCopy,
      };

  static void unlock({
    required String screen,
    required String result,
    required Duration wait,
    bool? keptCopy,
  }) =>
      Telemetry.record(
          "local_data_unlock",
          unlockFields(
              screen: screen, result: result, wait: wait, keptCopy: keptCopy));
}
