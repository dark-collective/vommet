// Vommet: remembers the identity (cross-signing master key) we last saw for
// each person we have a direct message with, so a reset can be flagged.
// The SDK replaces a user's keys silently when they change; a changed identity
// is what a lost-everything reset looks like, and also what impersonation
// looks like, so the user has to be told.
import 'dart:convert';

import 'package:commet/config/preferences/string_preference.dart';
import 'package:matrix/matrix.dart' as matrix;

enum PeerIdentity {
  /// We don't have their keys (yet).
  unknown,

  /// They have never set up secure messaging (no master key).
  notSetUp,

  /// Set up, not verified by us, same identity as before. The normal case.
  unverified,

  /// We verified their identity.
  verified,

  /// Their identity is different from the one we saw before.
  changed,
}

class IdentityPins {
  static final StringPreference _store =
      StringPreference("vommet_identity_pins", defaultValue: "{}");

  static Map<String, String>? _cache;

  static Map<String, String> get _pins {
    if (_cache != null) return _cache!;
    try {
      _cache = Map<String, String>.from(jsonDecode(_store.value) as Map);
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static String _key(matrix.Client client, String userId) =>
      "${client.userID}|$userId";

  static Future<void> _pin(
      matrix.Client client, String userId, String masterKey) async {
    final key = _key(client, userId);
    if (_pins[key] == masterKey) return;
    _pins[key] = masterKey;
    await _store.set(jsonEncode(_pins));
  }

  static PeerIdentity check(matrix.Client client, String userId) {
    final keys = client.userDeviceKeys[userId];
    if (keys == null) return PeerIdentity.unknown;

    final master = keys.masterKey?.publicKey;
    if (master == null) return PeerIdentity.notSetUp;

    if (keys.verified == matrix.UserVerifiedStatus.verified) {
      // Verifying (again) accepts this identity.
      _pin(client, userId, master);
      _mirror(client, userId, master, overwrite: true);
      return PeerIdentity.verified;
    }

    final pinned = _pins[_key(client, userId)];
    if (pinned == null) {
      // First time we see them: trust on first use.
      _pin(client, userId, master);
      _mirror(client, userId, master, overwrite: false);
      return PeerIdentity.unverified;
    }
    _mirror(client, userId, pinned, overwrite: false);

    return pinned == master ? PeerIdentity.unverified : PeerIdentity.changed;
  }

  /// "It was them": accept their new identity.
  static Future<void> acknowledge(matrix.Client client, String userId) async {
    final master = client.userDeviceKeys[userId]?.masterKey?.publicKey;
    if (master == null) return;
    await _pin(client, userId, master);
    await _mirror(client, userId, master, overwrite: true);
  }

  /// The SDK keeps its own record of the identity it last saw for people it
  /// shares room history with when inviting them (MSC4268), and refuses to
  /// share after a change until they are verified. Keeping that record in
  /// step with these pins makes the SDK refuse exactly when we warn, and
  /// lets "It was them" lift it. Same storage key as the SDK's
  /// HistorySharing; an older SDK just never reads it.
  static String _sdkKey(String userId) => "im.nether.msc4268.identity.$userId";

  static final Set<String> _mirrored = {};

  /// Writes [masterKey] as the SDK's record for [userId]. Without
  /// [overwrite] only when the SDK has none yet, so a key it saw earlier
  /// (a change we never pinned) still blocks sharing.
  static Future<void> _mirror(
      matrix.Client client, String userId, String masterKey,
      {required bool overwrite}) async {
    final key = "${_key(client, userId)}|$masterKey";
    if (!overwrite && _mirrored.contains(key)) return;
    _mirrored.add(key);
    try {
      final database = client.database;
      if (!overwrite &&
          await database.getCustomCacheObject(_sdkKey(userId)) != null) {
        return;
      }
      await database
          .cacheCustomObject(_sdkKey(userId), {"master_key": masterKey});
    } catch (_) {
      // The database isn't ready or is closing; a later check retries.
      _mirrored.remove(key);
    }
  }
}
