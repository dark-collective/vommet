// Vommet: local data encryption is opt-in (LOCAL-DATA-ENCRYPTION.md,
// decisions 9-13): whether the databases on this device are encrypted is
// the user's choice, kept in keys/data_encryption.json next to keystore.json.
//
// { "v": 1, "encrypt": true|false, "chosen": true|false,
//   "source": "first_run"|"notice"|"settings", "offer": 2 }
//
// Why a file of its own and not a preference or a keystore.json field:
// - it must be read before any database opens, by every engine of the app
//   (Android runs push in headless engines whose SharedPreferences cache
//   doesn't see the UI engine's writes), and on every start even when
//   keystore.json is missing or damaged (the start-up screens depend on it);
// - it is device-local by construction: preferences can be exported, reset
//   or carried to another device, and a reset that turned the switch off
//   would make the app decrypt the data at the next start;
// - only the UI engine writes it, atomically (temporary file + rename).
//
// No file means the default (off, not chosen), unless the disk already has
// encrypted data: then encryption stays on. A file that is there but can't
// be read is treated the same way (fail closed, [LocalDataSetting.resolve]):
// it never turns encryption off, decrypts anything or forgets a key.
// "chosen" tells a user who picked "Not now" from one who never answered,
// so the question can be asked again when the default changes (decision 13).
//
// Encryption is on by default since 10-30 (the "offer" generation 2): a
// new install starts encrypted, and "Not now" given to the opt-in question
// (generation 1: a file without "offer") on the first-run page or the
// notice is asked once more. "source" says where the answer came from;
// files from before it have none and count as the first-run page or the
// notice. A "Not now" from the settings switch is never asked again.
// Older builds read the file as before (they ignore the new fields).
import 'dart:convert';
import 'dart:io';

import 'package:commet/utils/disk_space.dart';
import 'package:commet/utils/private_files/owner_only.dart';
import 'package:path/path.dart' as p;

class LocalDataSetting {
  const LocalDataSetting(
      {required this.encrypt,
      required this.chosen,
      this.source,
      this.offer = currentOffer});

  /// The default for an install that already has data and never answered:
  /// off, not chosen (the notice asks).
  static const LocalDataSetting byDefault =
      LocalDataSetting(encrypt: false, chosen: false);

  /// A new install (nothing stored yet): encrypted from the start, not
  /// chosen yet (the first-run page asks, Encrypt picked).
  static const LocalDataSetting newInstall =
      LocalDataSetting(encrypt: true, chosen: false);

  /// The generation of the question: 1 = opt-in ("Not now" picked by
  /// default), 2 = on by default (Encrypt recommended). An answer to an
  /// older one may be asked again once ([offerDue]).
  static const int currentOffer = 2;

  /// The sources [LocalDataKeys.choose] records.
  static const String sourceFirstRun = "first_run";
  static const String sourceNotice = "notice";
  static const String sourceSettings = "settings";

  static const String fileName = "data_encryption.json";

  /// For tests: used instead of the file when set.
  static LocalDataSetting? debugOverride;

  /// Whether the databases on this device are to be encrypted.
  final bool encrypt;

  /// Whether the user picked [encrypt] (first-run page or settings).
  final bool chosen;

  /// Where [chosen] came from ([sourceFirstRun], [sourceNotice],
  /// [sourceSettings]); null when not chosen, or written by a build that
  /// didn't record it.
  final String? source;

  /// The question's generation the answer was given to (1 for files that
  /// don't say).
  final int offer;

  /// Whether the home notice asks: encryption is off and the user never
  /// answered, or answered "Not now" to an older question on the first-run
  /// page or the notice (or somewhere unknown). Never after the settings
  /// switch turned it off, and never twice for the same generation.
  bool get offerDue =>
      !encrypt &&
      (!chosen || (offer < currentOffer && source != sourceSettings));

  static String pathIn(String keysDirectory) => p.join(keysDirectory, fileName);

  /// The setting kept in [keysDirectory], or the default when there is
  /// none or it can't be read. Only for what doesn't decide encryption
  /// (the start-up decides with [load] and [resolve]).
  static LocalDataSetting read(String keysDirectory) =>
      load(keysDirectory).setting ?? byDefault;

  /// The setting file as it is: parsed, missing, or there but unreadable
  /// (truncated by a power loss, hand-edited, unreadable after a restore).
  static LocalDataSettingFile load(String keysDirectory) {
    final override = debugOverride;
    if (override != null) {
      return LocalDataSettingFile(LocalDataSettingFileState.ok, override);
    }
    try {
      final file = File(pathIn(keysDirectory));
      if (!file.existsSync()) {
        return const LocalDataSettingFile(
            LocalDataSettingFileState.missing, null);
      }
      final setting = parse(file.readAsStringSync());
      if (setting == null) {
        return const LocalDataSettingFile(
            LocalDataSettingFileState.unreadable, null);
      }
      return LocalDataSettingFile(LocalDataSettingFileState.ok, setting);
    } on FileSystemException {
      return const LocalDataSettingFile(
          LocalDataSettingFileState.unreadable, null);
    }
  }

  /// What the app does when the file is [file] and the disk has encrypted
  /// data ([encryptedOnDisk]: an encrypted database, a conversion in
  /// progress, or database keys in keystore.json). Fails closed: only a
  /// setting that was read turns encryption off. Without one (missing, or
  /// unreadable), encryption stays as the disk has it: on when anything is
  /// encrypted, never decrypted and no key forgotten because of it.
  static LocalDataSetting resolve(LocalDataSettingFile file,
      {required bool encryptedOnDisk}) {
    final setting = file.setting;
    if (file.state == LocalDataSettingFileState.ok && setting != null) {
      return setting;
    }
    return encryptedOnDisk
        ? const LocalDataSetting(encrypt: true, chosen: false)
        : byDefault;
  }

  /// Whether [keysDirectory] has a setting file at all.
  static bool existsIn(String keysDirectory) =>
      debugOverride != null || File(pathIn(keysDirectory)).existsSync();

  static LocalDataSetting? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map || json["v"] != 1) return null;
      final encrypt = json["encrypt"];
      final chosen = json["chosen"];
      final source = json["source"];
      final offer = json["offer"];
      if (encrypt is! bool) return null;
      return LocalDataSetting(
          encrypt: encrypt,
          chosen: chosen is bool ? chosen : false,
          source: source is String ? source : null,
          offer: offer is int ? offer : 1);
    } on FormatException {
      return null;
    }
  }

  String encode() => const JsonEncoder.withIndent("  ").convert({
        "v": 1,
        "encrypt": encrypt,
        "chosen": chosen,
        if (source != null) "source": source,
        "offer": offer,
      });

  /// For tests: called before each write attempt; throwing fails it.
  static void Function(int attempt)? debugBeforeWrite;

  /// Writes the setting (UI engine only), owner-only and atomically, and
  /// syncs the folder so the rename survives a power loss. Tried [tries]
  /// times; throws [FileSystemException] when every try failed (the old
  /// file, if any, is still there).
  Future<void> write(String keysDirectory, {int tries = 3}) async {
    if (debugOverride != null && debugBeforeWrite == null) {
      debugOverride = this;
      return;
    }
    for (var attempt = 1;; attempt++) {
      try {
        debugBeforeWrite?.call(attempt);
        if (debugOverride != null) {
          debugOverride = this;
          return;
        }
        await _writeOnce(keysDirectory);
        return;
      } on FileSystemException {
        if (attempt >= tries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
      }
    }
  }

  Future<void> _writeOnce(String keysDirectory) async {
    final dir = Directory(keysDirectory);
    if (!await dir.exists()) await dir.create(recursive: true);
    await OwnerOnly.directory(keysDirectory);
    final target = pathIn(keysDirectory);
    final temp = "$target.tmp";
    final file = File(temp);
    if (await file.exists()) await file.delete();
    await file.create(exclusive: true);
    await OwnerOnly.file(temp);
    await file.writeAsString(encode(), flush: true);
    await file.rename(target);
    DiskSpace.syncDirectory(keysDirectory);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDataSetting &&
      other.encrypt == encrypt &&
      other.chosen == chosen &&
      other.source == source &&
      other.offer == offer;

  @override
  int get hashCode => Object.hash(encrypt, chosen, source, offer);

  @override
  String toString() => "LocalDataSetting(${encrypt ? "on" : "off"}"
      "${chosen ? ", chosen" : ""}${source != null ? ", $source" : ""}"
      ", offer $offer)";
}

enum LocalDataSettingFileState { ok, missing, unreadable }

/// The setting file as [LocalDataSetting.load] found it.
class LocalDataSettingFile {
  const LocalDataSettingFile(this.state, this.setting);
  final LocalDataSettingFileState state;

  /// Set when [state] is ok.
  final LocalDataSetting? setting;
}
