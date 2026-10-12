import 'package:commet/config/preferences/preference.dart';

/// Vommet issue 129: what this install remembers per account about secure
/// messaging: whether the user skipped setup (for the reminder banner) and
/// when they last proved they still have their recovery key (for the
/// "Still have your recovery key?" check-ins). Never the key itself.
class SecureSetupRecords {
  SecureSetupRecords(this.userId);

  final String userId;

  /// First check-in a few days after setup, then about monthly.
  static const firstCheckIn = Duration(days: 3);
  static const nextCheckIn = Duration(days: 30);
  static const snooze = Duration(days: 3);

  String _key(String field) => "vommet_secure_${field}_$userId";

  bool get skipped => Preference.preferences?.getBool(_key("skipped")) ?? false;

  Future<void> setSkipped(bool value) async =>
      Preference.preferences?.setBool(_key("skipped"), value);

  DateTime? _time(String field) {
    final ms = Preference.preferences?.getInt(_key(field));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setTime(String field, DateTime when) async =>
      Preference.preferences?.setInt(_key(field), when.millisecondsSinceEpoch);

  /// The user just confirmed they have their key (setup or check-in).
  Future<void> confirmed({DateTime? now, bool firstTime = false}) async {
    final at = now ?? DateTime.now();
    await setSkipped(false);
    await _setTime("confirmed", at);
    await _setTime(
        "checkin_due", at.add(firstTime ? firstCheckIn : nextCheckIn));
  }

  /// "Remind me later".
  Future<void> snoozed({DateTime? now}) =>
      _setTime("checkin_due", (now ?? DateTime.now()).add(snooze));

  /// A check-in is due (only once setup was confirmed on this install).
  bool checkInDue({DateTime? now}) {
    final due = _time("checkin_due");
    return due != null && !(now ?? DateTime.now()).isBefore(due);
  }

  DateTime? get lastConfirmed => _time("confirmed");
}
