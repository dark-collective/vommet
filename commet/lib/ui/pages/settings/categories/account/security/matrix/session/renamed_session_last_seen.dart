import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: some homeservers (Tuwunel, conduwuit) treat renaming a session as
// using it: PUT /devices/{id} sets that session's last_seen_ts to now and its
// last_seen_ip to the address of the device doing the renaming. An offline
// session then shows "Active now" as soon as you rename it. Before renaming,
// we remember what the session showed; while the server still reports the
// rename's own timestamp we show the remembered values instead, and drop
// them once the session is really used again (or the server never stamped
// it, as Synapse does).

const _key = "vommet_renamed_session_last_seen";

/// What a session showed before we renamed it, and the timestamp the server
/// gave it for the rename (null until the device list is reloaded).
class RenamedSessionRecord {
  RenamedSessionRecord({this.lastSeenTs, this.lastSeenIp, this.stampedTs});

  final int? lastSeenTs;
  final String? lastSeenIp;
  final int? stampedTs;

  factory RenamedSessionRecord.fromJson(Map<String, dynamic> json) =>
      RenamedSessionRecord(
          lastSeenTs: json["ts"] as int?,
          lastSeenIp: json["ip"] as String?,
          stampedTs: json["stamped"] as int?);

  Map<String, dynamic> toJson() =>
      {"ts": lastSeenTs, "ip": lastSeenIp, "stamped": stampedTs};
}

String renamedSessionKey(String userId, String deviceId) => "$userId|$deviceId";

/// Puts back what [devices] showed before a rename, for each session the
/// server stamped as used by the rename. Updates [records] (keyed by
/// [renamedSessionKey]) and returns whether they changed.
bool restoreRenamedLastSeen(String userId, List<Device> devices,
    Map<String, RenamedSessionRecord> records) {
  var changed = false;
  final present = <String>{};
  for (final device in devices) {
    final key = renamedSessionKey(userId, device.deviceId);
    present.add(key);
    final record = records[key];
    if (record == null) continue;

    var stamped = record.stampedTs;
    if (stamped == null) {
      if (device.lastSeenTs == record.lastSeenTs) {
        // The server left last-seen alone: nothing to undo.
        records.remove(key);
        changed = true;
        continue;
      }
      stamped = device.lastSeenTs;
      records[key] = RenamedSessionRecord(
          lastSeenTs: record.lastSeenTs,
          lastSeenIp: record.lastSeenIp,
          stampedTs: stamped);
      changed = true;
    }

    if (device.lastSeenTs != stamped) {
      // Used since the rename: the server's values are real again.
      records.remove(key);
      changed = true;
      continue;
    }

    device.lastSeenTs = record.lastSeenTs;
    device.lastSeenIp = record.lastSeenIp;
  }

  // Forget signed-out sessions of this account.
  final gone = records.keys
      .where((k) => k.startsWith("$userId|") && !present.contains(k))
      .toList();
  for (final key in gone) {
    records.remove(key);
    changed = true;
  }
  return changed;
}

/// The remembered sessions, kept in shared preferences so the fix survives
/// a restart.
class RenamedSessionLastSeen {
  RenamedSessionLastSeen(this._prefs);

  final SharedPreferences? _prefs;

  Map<String, RenamedSessionRecord> _load() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(
          k, RenamedSessionRecord.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, RenamedSessionRecord> records) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (records.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
          _key, jsonEncode(records.map((k, v) => MapEntry(k, v.toJson()))));
    }
  }

  /// Call just before renaming [device]. A session renamed again before it
  /// was used keeps its first, real values, and waits for the new stamp.
  /// Returns the earlier record, for [undo].
  Future<RenamedSessionRecord?> remember(String userId, Device device) async {
    final records = _load();
    final key = renamedSessionKey(userId, device.deviceId);
    final earlier = records[key];
    records[key] = RenamedSessionRecord(
        lastSeenTs: earlier != null ? earlier.lastSeenTs : device.lastSeenTs,
        lastSeenIp: earlier != null ? earlier.lastSeenIp : device.lastSeenIp);
    await _save(records);
    return earlier;
  }

  /// Call when a rename failed: the server didn't touch the session, so
  /// put back what [remember] replaced.
  Future<void> undo(
      String userId, String deviceId, RenamedSessionRecord? earlier) async {
    final records = _load();
    final key = renamedSessionKey(userId, deviceId);
    if (earlier == null) {
      records.remove(key);
    } else {
      records[key] = earlier;
    }
    await _save(records);
  }

  /// See [restoreRenamedLastSeen].
  Future<void> restore(String userId, List<Device> devices) async {
    final records = _load();
    if (records.isEmpty) return;
    if (restoreRenamedLastSeen(userId, devices, records)) {
      await _save(records);
    }
  }
}
