// Vommet: local data encryption, keystore.json: where the master key is kept
// and the (non-secret) salts and per-file states. Never holds a key.
//
// {
//   "v": 1,
//   "store": "keyring" | "portal" | "dpapi" | "file",
//   "check": "<16 hex>",
//   "app_salt": "<base64>",
//   "media_salt": "<base64>",
//   "accounts": { "<client>": { "salt": "<base64>",
//                               "data": "plain|migrating|encrypted",
//                               "search": "plain|migrating|encrypted",
//                               "data_failures": <n> } },   (optional)
//   "app_data": "plain|migrating|encrypted",
//   "app_data_failures": <n>,       (optional: failed migrations in a row)
//   "pin": "file",                  (optional: the user chose the key file)
//   "file_notice": "due" | "shown", (optional: the no-keyring notice)
//   "fallback_reason": "<text>"     (optional: why the key file is used)
// }
//
// Fields this version doesn't know are kept when the file is rewritten.
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/security/key_vault/key_hierarchy.dart';

/// Where the master key is kept.
enum KeyStoreKind {
  /// The OS keyring: Secret Service on Linux, the Keychain on iOS and
  /// macOS, the Keystore-wrapped store on Android.
  keyring("keyring"),

  /// Flatpak's Secret portal (the key is wrapped with the app's portal
  /// secret in keys/master.wrapped).
  portal("portal"),

  /// Windows DPAPI (keys/master.dpapi, readable only by this Windows user).
  dpapi("dpapi"),

  /// A 0600 file next to the data (keys/master.key): the fallback when
  /// there is no keyring.
  file("file");

  const KeyStoreKind(this.id);
  final String id;

  static KeyStoreKind? fromId(Object? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// A database file's encryption, as last recorded. The file's header is
/// what decides how it is opened; this is for the UI, telemetry and the
/// migration (phase 4).
enum DatabaseEncryptionState {
  plain("plain"),
  migrating("migrating"),
  encrypted("encrypted");

  const DatabaseEncryptionState(this.id);
  final String id;

  static DatabaseEncryptionState? fromId(Object? id) {
    for (final state in values) {
      if (state.id == id) return state;
    }
    return null;
  }
}

class KeystoreFormatException implements Exception {
  KeystoreFormatException(this.message);
  final String message;
  @override
  String toString() => "KeystoreFormatException: $message";
}

class KeystoreDocument {
  KeystoreDocument._(this._json);

  static const int version = 1;

  final Map<String, dynamic> _json;

  /// A new document for a master key with [check], kept in [store].
  factory KeystoreDocument.create(
      {required KeyStoreKind store, required String check}) {
    return KeystoreDocument._({
      "v": version,
      "store": store.id,
      "check": check,
      "app_salt": base64.encode(KeyHierarchy.newSalt()),
      "media_salt": base64.encode(KeyHierarchy.newSalt()),
      "accounts": <String, dynamic>{},
    });
  }

  /// Parses keystore.json. Throws [KeystoreFormatException] for anything
  /// that isn't a usable version 1 document (a newer version included: it
  /// may keep the key somewhere this version doesn't know).
  factory KeystoreDocument.parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw KeystoreFormatException("not JSON: ${e.message}");
    }
    if (json is! Map<String, dynamic>) {
      throw KeystoreFormatException("not an object");
    }
    if (json["v"] != version) {
      throw KeystoreFormatException("unsupported version ${json["v"]}");
    }
    final doc = KeystoreDocument._(json);
    if (doc.store == null) {
      throw KeystoreFormatException("unknown store ${json["store"]}");
    }
    final check = json["check"];
    if (check is! String || !RegExp(r"^[0-9a-f]{16}$").hasMatch(check)) {
      throw KeystoreFormatException("bad check value");
    }
    if (_salt(json["app_salt"]) == null || _salt(json["media_salt"]) == null) {
      throw KeystoreFormatException("bad salts");
    }
    if (json["accounts"] != null && json["accounts"] is! Map) {
      throw KeystoreFormatException("bad accounts");
    }
    return doc;
  }

  String encode() => const JsonEncoder.withIndent("  ").convert(_json);

  KeystoreDocument copy() =>
      KeystoreDocument._(jsonDecode(jsonEncode(_json)) as Map<String, dynamic>);

  static Uint8List? _salt(Object? value) {
    if (value is! String) return null;
    try {
      final bytes = base64.decode(value);
      return bytes.length == KeyHierarchy.saltLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  KeyStoreKind? get store => KeyStoreKind.fromId(_json["store"]);
  set store(KeyStoreKind? value) => _json["store"] = value!.id;

  String get check => _json["check"] as String;

  Uint8List get appSalt => _salt(_json["app_salt"])!;
  Uint8List get mediaSalt => _salt(_json["media_salt"])!;

  /// A new media salt: the media cache's key changes, which wipes the
  /// sealed entries (sign-out, phase 5).
  void rotateMediaSalt() =>
      _json["media_salt"] = base64.encode(KeyHierarchy.newSalt());

  /// Whether the user chose to keep the key in the file (no automatic move
  /// to a keyring that appears later).
  bool get pinnedToFile => _json["pin"] == KeyStoreKind.file.id;
  set pinnedToFile(bool value) {
    if (value) {
      _json["pin"] = KeyStoreKind.file.id;
    } else {
      _json.remove("pin");
    }
  }

  /// Whether the one-time "no keyring was found" notice is still to be
  /// shown.
  bool get fileNoticeDue => _json["file_notice"] == "due";

  /// Why the key file is used, when it is a fallback (for the notice and
  /// the settings page).
  String? get fallbackReason => _json["fallback_reason"] as String?;

  void setFileFallback({required bool noticeDue, String? reason}) {
    if (noticeDue) _json["file_notice"] = "due";
    if (reason != null) _json["fallback_reason"] = reason;
  }

  void markFileNoticeShown() {
    if (_json["file_notice"] == "due") _json["file_notice"] = "shown";
  }

  void clearFileFallback() {
    _json.remove("file_notice");
    _json.remove("fallback_reason");
  }

  Map<String, dynamic> get _accounts {
    final accounts = _json["accounts"];
    if (accounts is Map<String, dynamic>) return accounts;
    final created = <String, dynamic>{};
    _json["accounts"] = created;
    return created;
  }

  Iterable<String> get accounts => _accounts.keys;

  Map<String, dynamic>? _account(String account) {
    final entry = _accounts[account];
    return entry is Map<String, dynamic> ? entry : null;
  }

  /// The account's salt, or null when it has none (no database of it was
  /// ever encrypted here, or it was signed out).
  Uint8List? accountSalt(String account) => _salt(_account(account)?["salt"]);

  /// Gives [account] a salt if it has none. True when one was added.
  bool ensureAccountSalt(String account) {
    if (accountSalt(account) != null) return false;
    final entry = _account(account) ?? <String, dynamic>{};
    entry["salt"] = base64.encode(KeyHierarchy.newSalt());
    _accounts[account] = entry;
    return true;
  }

  /// Forgets [account]'s salt and states: what its databases were
  /// encrypted with can no longer be derived (cryptographic sign-out).
  void removeAccount(String account) => _accounts.remove(account);

  /// Whether a database key is still recorded (an account's salt, or an
  /// encrypted app_data.db).
  bool get hasDatabaseKeys =>
      accounts.any((a) => accountSalt(a) != null) ||
      state(DatabaseRole.appData, null) == DatabaseEncryptionState.encrypted;

  /// Forgets the database keys (local data encryption turned off and the
  /// files decrypted): the accounts' salts and states go, except those of
  /// the accounts in [keep] (files of theirs are still encrypted), and the
  /// app salt is replaced. The media salt stays (the media cache is always
  /// encrypted). Always changes the document (a new app salt).
  bool forgetDatabaseKeys({Set<String> keep = const {}}) {
    _json["accounts"] = <String, dynamic>{
      for (final account in keep)
        if (_accounts[account] != null) account: _accounts[account],
    };
    _json.remove("app_data");
    _json.remove("app_data_failures");
    _json["app_salt"] = base64.encode(KeyHierarchy.newSalt());
    return true;
  }

  /// The salt a database of [role] uses ([account] for per-account roles).
  Uint8List? saltFor(DatabaseRole role, String? account) {
    if (!role.perAccount) return appSalt;
    if (account == null) return null;
    return accountSalt(account);
  }

  static String _stateField(DatabaseRole role) => switch (role) {
        DatabaseRole.data => "data",
        DatabaseRole.searchIndex => "search",
        DatabaseRole.appData => "app_data",
      };

  DatabaseEncryptionState? state(DatabaseRole role, String? account) {
    final field = _stateField(role);
    if (!role.perAccount) return DatabaseEncryptionState.fromId(_json[field]);
    if (account == null) return null;
    return DatabaseEncryptionState.fromId(_account(account)?[field]);
  }

  /// Records [state]; true when it changed.
  bool setState(
      DatabaseRole role, String? account, DatabaseEncryptionState state) {
    final field = _stateField(role);
    if (!role.perAccount) {
      if (_json[field] == state.id) return false;
      _json[field] = state.id;
      return true;
    }
    if (account == null) return false;
    final entry = _account(account) ?? <String, dynamic>{};
    if (entry[field] == state.id) return false;
    entry[field] = state.id;
    _accounts[account] = entry;
    return true;
  }

  static String _failuresField(DatabaseRole role) =>
      "${_stateField(role)}_failures";

  /// How many migrations of the file failed in a row (they stop being
  /// retried after a few).
  int migrationFailures(DatabaseRole role, String? account) {
    final field = _failuresField(role);
    final value = role.perAccount
        ? (account == null ? null : _account(account)?[field])
        : _json[field];
    return value is int ? value : 0;
  }

  /// Records the failure count; 0 removes it. True when it changed.
  bool setMigrationFailures(DatabaseRole role, String? account, int count) {
    if (migrationFailures(role, account) == count) return false;
    final field = _failuresField(role);
    final Map<String, dynamic> target;
    if (!role.perAccount) {
      target = _json;
    } else {
      if (account == null) return false;
      target = _account(account) ?? <String, dynamic>{};
      _accounts[account] = target;
    }
    if (count == 0) {
      target.remove(field);
    } else {
      target[field] = count;
    }
    return true;
  }
}
