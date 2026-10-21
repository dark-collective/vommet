import 'package:commet/config/preferences/preference.dart';

/// Vommet issue 129: what this install remembers per account about secure
/// messaging: whether the user skipped setup (for the reminder banner) and
/// when they last proved they still have their recovery key (for the
/// "Still have your recovery key?" check-ins). Never the key itself.
class SecureSetupRecords {
  SecureSetupRecords(this.userId);

  final String userId;

  /// First check-in a few days after setup, then further apart with each
  /// check-in passed in a row: 30, 90, then every 180 days.
  static const firstCheckIn = Duration(days: 3);
  static const nextCheckIn = Duration(days: 30);
  static const checkInGaps = [
    nextCheckIn,
    Duration(days: 90),
    Duration(days: 180)
  ];
  static const snooze = Duration(days: 3);

  /// The gap after a check-in passed with [streak] passes in a row before it.
  static Duration gapAfterPass(int streak) =>
      checkInGaps[streak.clamp(0, checkInGaps.length - 1)];

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

  /// Check-ins passed in a row on this install. Installs from before the
  /// streak have none stored: 0, so nobody jumps straight to 180 days.
  int get checkInStreak =>
      Preference.preferences?.getInt(_key("checkin_streak")) ?? 0;

  Future<void> _setStreak(int value) async =>
      Preference.preferences?.setInt(_key("checkin_streak"), value);

  /// Back to 30 days after the next pass: a wrong key at the check-in, "I've
  /// lost it", or a setup (new key, replaced key, this device set up again).
  Future<void> resetCheckInStreak() async =>
      Preference.preferences?.remove(_key("checkin_streak"));

  /// The user just confirmed they have their key: a setup ([firstTime],
  /// first check-in in 3 days) or a passed check-in (30, 90, then 180 days
  /// as passes add up). A check-in brought forward only for the old-key
  /// cleanup (Vommet issue 526) doesn't add to the streak: it came early,
  /// so it says nothing about keeping the key over a longer gap.
  Future<void> confirmed({DateTime? now, bool firstTime = false}) async {
    final at = now ?? DateTime.now();
    await setSkipped(false);
    await _setTime("confirmed", at);
    final Duration gap;
    if (firstTime) {
      await resetCheckInStreak();
      gap = firstCheckIn;
    } else if (_earlyForRepair(at)) {
      gap = gapAfterPass(checkInStreak - 1);
    } else {
      final streak = checkInStreak;
      gap = gapAfterPass(streak);
      await _setStreak(streak + 1);
    }
    final due = at.add(gap);
    await _setTime("checkin_due", due);
    // A setup run here (e.g. replacing the key) starts its own check-ins:
    // ending a cleanup check-in must not take those away again.
    if (firstTime && repairCheckInMarked) {
      await Preference.preferences
          ?.setInt(_key("repair_checkin"), due.millisecondsSinceEpoch);
    }
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

  // ---- Vommet issue 526: bring the check-in forward for the cleanup ----
  //
  // Old-key copies of the secrets can only be removed while the user types
  // their current key, and the check-in is where they do that. So while
  // copies wait, the check-in is due now instead of in up to 180 days, once
  // per pending state: after that the dialog's own answers decide ("Remind
  // me later" snoozes 3 days as always). The mark keeps the due date the
  // account had before (or none), so it can be put back afterwards.

  static const _noSchedule = -1;

  int? get _repairMark =>
      Preference.preferences?.getInt(_key("repair_checkin"));

  /// The check-in was brought forward for the current pending cleanup.
  bool get repairCheckInMarked => _repairMark != null;

  /// The check-in at [at] only came because of the cleanup: the account had
  /// none scheduled, or its own was still ahead.
  bool _earlyForRepair(DateTime at) {
    final prev = _repairMark;
    if (prev == null) return false;
    return prev == _noSchedule ||
        DateTime.fromMillisecondsSinceEpoch(prev).isAfter(at);
  }

  /// Pending old-key copies: make the check-in due [now], once.
  /// [canCheck]: this device is confirmed and the account has secret
  /// storage, i.e. the check-in can run and the key it takes can clean up.
  Future<RepairCheckIn> updateRepairCheckIn({
    required bool pending,
    required bool canCheck,
    DateTime? now,
  }) async {
    final action = decideRepairCheckIn(
        pending: pending, canCheck: canCheck, marked: repairCheckInMarked);
    switch (action) {
      case RepairCheckIn.bringForward:
        final at = now ?? DateTime.now();
        final due = _time("checkin_due");
        await Preference.preferences?.setInt(
            _key("repair_checkin"), due?.millisecondsSinceEpoch ?? _noSchedule);
        if (due == null || due.isAfter(at)) await _setTime("checkin_due", at);
      case RepairCheckIn.restore:
        await _restoreSchedule(clearMark: true);
      case RepairCheckIn.none:
        break;
    }
    return action;
  }

  /// The user passed the check-in. An account that had no check-ins before
  /// the cleanup brought one in doesn't start getting them now.
  Future<void> confirmedRepairCheckIn() async {
    if (_repairMark == _noSchedule) await _restoreSchedule(clearMark: false);
  }

  /// Back to the schedule from before the cleanup: none, or the later of
  /// the old due date and the current one (never sooner than either).
  Future<void> _restoreSchedule({required bool clearMark}) async {
    final prev = _repairMark;
    if (prev == null) return;
    if (prev == _noSchedule) {
      await Preference.preferences?.remove(_key("checkin_due"));
    } else {
      final old = DateTime.fromMillisecondsSinceEpoch(prev);
      final due = _time("checkin_due");
      if (due == null || due.isBefore(old)) await _setTime("checkin_due", old);
    }
    if (clearMark) await Preference.preferences?.remove(_key("repair_checkin"));
  }

  /// The decision on its own, for tests. [pending]: old-key copies wait for
  /// the user's current key (and the cleanup isn't recorded as done).
  static RepairCheckIn decideRepairCheckIn({
    required bool pending,
    required bool canCheck,
    required bool marked,
  }) {
    if (!pending) return marked ? RepairCheckIn.restore : RepairCheckIn.none;
    if (marked || !canCheck) return RepairCheckIn.none;
    return RepairCheckIn.bringForward;
  }
}

enum RepairCheckIn {
  /// Nothing to change.
  none,

  /// Make the check-in due now (first sight of this pending cleanup).
  bringForward,

  /// The cleanup is no longer pending: put the old schedule back.
  restore,
}
