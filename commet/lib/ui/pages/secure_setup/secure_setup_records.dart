import 'dart:convert';

import 'package:commet/config/preferences/preference.dart';
import 'package:flutter/foundation.dart';

/// How the account's recovery key was set up in Vommet: decides the check-in
/// dialog's wording. Unknown (set up in another app, or before Vommet
/// recorded it): neutral wording.
enum RecoveryMethod { key, phrase, password }

/// The recovery key check-in schedule of one account, kept as events with
/// their times, so two devices' copies can be merged ([merge]) without
/// either losing what the other saw. Shared across the user's Vommet devices
/// (encrypted, in account data: see RecoveryCheckInsSync) and cached in the
/// local preferences ([SecureSetupRecords]).
///
/// Merge rules (each tested in unit_test/recovery_checkins_test.dart):
/// - The most recent pass wins; its streak and next check come with it.
/// - A reset newer than the last pass puts the streak back to 0 everywhere:
///   a failure (a wrong entry, "I've lost it") or a setup (a new or
///   replaced key; the next check is then 2 weeks after it).
/// - A snooze newer than the last pass (and setup) pushes the next check to
///   at least snooze + 3 days; the snoozes in a row carry across devices.
/// - On/off, and the setup method: the most recent change wins.
/// Approving a new device from another one changes nothing here: the new
/// device just adopts the shared schedule.
@immutable
class CheckInState {
  const CheckInState(
      {this.lastPass,
      this.streak = 0,
      this.passDue,
      this.setupAt,
      this.failedAt,
      this.snoozedAt,
      this.snoozes = 0,
      this.enabled = true,
      this.enabledAt,
      this.method,
      this.methodAt});

  static const version = 1;

  /// Last time the key was entered right (a check-in, or unlocking a device
  /// with it).
  final DateTime? lastPass;

  /// Passes in a row, as of [lastPass].
  final int streak;

  /// The check after [lastPass] (null: none, e.g. an account that never had
  /// check-ins passed one brought forward for the old-key cleanup).
  final DateTime? passDue;

  /// A key was made (setup, a new or replaced key).
  final DateTime? setupAt;

  /// A wrong key at a check-in, or "I've lost it".
  final DateTime? failedAt;

  /// Last "Remind me later", and how many in a row as of then.
  final DateTime? snoozedAt;
  final int snoozes;

  final bool enabled;
  final DateTime? enabledAt;

  final RecoveryMethod? method;
  final DateTime? methodAt;

  static bool _after(DateTime? a, DateTime? b) =>
      a != null && (b == null || a.isAfter(b));

  static DateTime? _latest(DateTime? a, DateTime? b) => _after(b, a) ? b : a;

  bool get isEmpty =>
      lastPass == null &&
      setupAt == null &&
      failedAt == null &&
      snoozedAt == null &&
      enabledAt == null &&
      methodAt == null;

  /// Since when snoozes count: the last pass or setup.
  DateTime? get _anchor => _latest(lastPass, setupAt);

  /// Passes in a row now: a failure or setup after the last pass ends it.
  int get currentStreak =>
      _after(setupAt, lastPass) || _after(failedAt, lastPass) ? 0 : streak;

  /// "Remind me later"s since the last pass or setup.
  int get snoozesInRow => _after(snoozedAt, _anchor) ? snoozes : 0;

  /// When the next check-in is due (null: none scheduled).
  DateTime? get due {
    DateTime? d = _after(setupAt, lastPass)
        ? setupAt!.add(SecureSetupRecords.firstCheckIn)
        : passDue;
    if (_after(snoozedAt, _anchor)) {
      final s = snoozedAt!.add(SecureSetupRecords.snooze);
      if (d == null || s.isAfter(d)) d = s;
    }
    return d;
  }

  CheckInState copyWith(
          {DateTime? lastPass,
          int? streak,
          DateTime? Function()? passDue,
          DateTime? setupAt,
          DateTime? failedAt,
          DateTime? snoozedAt,
          int? snoozes,
          bool? enabled,
          DateTime? enabledAt,
          RecoveryMethod? method,
          DateTime? methodAt}) =>
      CheckInState(
          lastPass: lastPass ?? this.lastPass,
          streak: streak ?? this.streak,
          passDue: passDue != null ? passDue() : this.passDue,
          setupAt: setupAt ?? this.setupAt,
          failedAt: failedAt ?? this.failedAt,
          snoozedAt: snoozedAt ?? this.snoozedAt,
          snoozes: snoozes ?? this.snoozes,
          enabled: enabled ?? this.enabled,
          enabledAt: enabledAt ?? this.enabledAt,
          method: method ?? this.method,
          methodAt: methodAt ?? this.methodAt);

  /// Joins two copies of the schedule: the same either way round, and
  /// merging a copy with itself changes nothing. Rules: see the class.
  static CheckInState merge(CheckInState a, CheckInState b) {
    // The newest pass, with its streak and next check. The same pass on
    // both (both devices saw it): the lower streak, i.e. a reset one saw.
    final CheckInState pass;
    if (_after(a.lastPass, b.lastPass)) {
      pass = a;
    } else if (_after(b.lastPass, a.lastPass)) {
      pass = b;
    } else if (a.streak != b.streak) {
      pass = a.streak < b.streak ? a : b;
    } else {
      // Same pass and streak: the later next check, deterministically.
      pass = _after(b.passDue, a.passDue) ? b : a;
    }
    final setupAt = _latest(a.setupAt, b.setupAt);
    final anchor = _latest(pass.lastPass, setupAt);
    // Snoozes since the anchor, as counted by whichever device saw more.
    var snoozes = 0;
    for (final s in [a, b]) {
      if (_after(s.snoozedAt, anchor) && s.snoozes > snoozes) {
        snoozes = s.snoozes;
      }
    }
    // Ties (same time) go to "on" and to the method that sorts first, so
    // the result doesn't depend on the order.
    final CheckInState onOff;
    if (_after(a.enabledAt, b.enabledAt)) {
      onOff = a;
    } else if (_after(b.enabledAt, a.enabledAt)) {
      onOff = b;
    } else {
      onOff = a.enabled ? a : b;
    }
    final CheckInState how;
    if (_after(a.methodAt, b.methodAt)) {
      how = a;
    } else if (_after(b.methodAt, a.methodAt)) {
      how = b;
    } else {
      how = (a.method?.index ?? 99) <= (b.method?.index ?? 99) ? a : b;
    }
    return CheckInState(
        lastPass: pass.lastPass,
        streak: pass.streak,
        passDue: pass.passDue,
        setupAt: setupAt,
        failedAt: _latest(a.failedAt, b.failedAt),
        snoozedAt: _latest(a.snoozedAt, b.snoozedAt),
        snoozes: snoozes,
        enabled: onOff.enabled,
        enabledAt: onOff.enabledAt,
        method: how.method,
        methodAt: how.methodAt);
  }

  static int? _ms(DateTime? t) => t?.millisecondsSinceEpoch;

  static DateTime? _time(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  Map<String, Object?> toJson() => {
        "version": version,
        if (lastPass != null) "last_pass": _ms(lastPass),
        "streak": streak,
        if (passDue != null) "pass_due": _ms(passDue),
        if (setupAt != null) "setup_at": _ms(setupAt),
        if (failedAt != null) "failed_at": _ms(failedAt),
        if (snoozedAt != null) "snoozed_at": _ms(snoozedAt),
        "snoozes": snoozes,
        // For reading only: always worked out from the fields above.
        if (due != null) "next_due": _ms(due),
        "enabled": enabled,
        if (enabledAt != null) "enabled_at": _ms(enabledAt),
        if (method != null) "method": method!.name,
        if (methodAt != null) "method_at": _ms(methodAt)
      };

  /// Null for anything that isn't a record this version understands.
  static CheckInState? fromJson(Object? json) {
    if (json is! Map) return null;
    final v = json["version"];
    if (v is! int || v < 1) return null;
    final streak = json["streak"];
    final snoozes = json["snoozes"];
    final enabled = json["enabled"];
    final method = json["method"];
    return CheckInState(
        lastPass: _time(json["last_pass"]),
        streak: streak is int && streak >= 0 ? streak : 0,
        passDue: _time(json["pass_due"]),
        setupAt: _time(json["setup_at"]),
        failedAt: _time(json["failed_at"]),
        snoozedAt: _time(json["snoozed_at"]),
        snoozes: snoozes is int && snoozes >= 0 ? snoozes : 0,
        enabled: enabled is bool ? enabled : true,
        enabledAt: _time(json["enabled_at"]),
        method:
            method is String ? RecoveryMethod.values.asNameMap()[method] : null,
        methodAt: _time(json["method_at"]));
  }

  @override
  bool operator ==(Object other) =>
      other is CheckInState &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => "CheckInState(${toJson()})";
}

/// Vommet issue 129: what this install remembers per account about secure
/// messaging: whether the user skipped setup (for the reminder banner) and
/// the "Still have your recovery key?" check-in schedule ([CheckInState]:
/// the local copy of the one shared with the user's other Vommet devices,
/// so an offline device still works). Never the key itself.
class SecureSetupRecords {
  /// [deviceScope] keeps a second device of the same account apart in one
  /// process (integration tests).
  SecureSetupRecords(this.userId, {this.deviceScope = ""});

  final String userId;
  final String deviceScope;

  /// First check-in 2 weeks after setup, then further apart with each
  /// check-in passed in a row: 30, 90, then every 180 days.
  static const firstCheckIn = Duration(days: 14);
  static const nextCheckIn = Duration(days: 30);
  static const checkInGaps = [
    nextCheckIn,
    Duration(days: 90),
    Duration(days: 180)
  ];
  static const snooze = Duration(days: 3);

  /// "Remind me later"s in a row after which the check-in waits for an
  /// answer.
  static const snoozesBeforeUltimatum = 3;

  /// No check-in for this long after this device was signed in and
  /// confirmed (approved from another device, or unlocked with the key):
  /// the user just did that, asking again right away is a nag. Covers the
  /// shared schedule and the old-key cleanup's early check-in alike.
  static const newDeviceQuiet = firstCheckIn;

  /// The gap after a check-in passed with [streak] passes in a row before it.
  static Duration gapAfterPass(int streak) =>
      checkInGaps[streak.clamp(0, checkInGaps.length - 1)];

  String _key(String field) => "vommet_secure_${field}_$deviceScope$userId";

  bool get skipped => Preference.preferences?.getBool(_key("skipped")) ?? false;

  Future<void> setSkipped(bool value) async =>
      Preference.preferences?.setBool(_key("skipped"), value);

  DateTime? _time(String field) {
    final ms = Preference.preferences?.getInt(_key(field));
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  // ---- the schedule ----

  /// The local copy of the schedule. Installs from before it was kept as
  /// one record start from the separate values they had (last confirmed,
  /// due, streak; a missing streak is 0, so nobody jumps to 180 days).
  CheckInState get state {
    final raw = Preference.preferences?.getString(_key("checkins"));
    if (raw != null) {
      try {
        final s = CheckInState.fromJson(jsonDecode(raw));
        if (s != null) return s;
      } catch (_) {}
    }
    final confirmed = _time("confirmed");
    final due = _time("checkin_due");
    if (confirmed == null && due == null) return const CheckInState();
    return CheckInState(
        lastPass: confirmed,
        streak: Preference.preferences?.getInt(_key("checkin_streak")) ?? 0,
        passDue: due);
  }

  /// Saves [s] as the local copy. The separate values are kept up to date
  /// too, for an older Vommet on this install.
  Future<void> save(CheckInState s) async {
    final p = Preference.preferences;
    if (p == null) return;
    await p.setString(_key("checkins"), jsonEncode(s.toJson()));
    final due = s.due;
    if (due == null) {
      await p.remove(_key("checkin_due"));
    } else {
      await p.setInt(_key("checkin_due"), due.millisecondsSinceEpoch);
    }
    if (s.lastPass != null) {
      await p.setInt(_key("confirmed"), s.lastPass!.millisecondsSinceEpoch);
    }
    await p.setInt(_key("checkin_streak"), s.currentStreak);
  }

  /// Merges a copy from another device into the local one. True when that
  /// changed anything here.
  Future<bool> adopt(CheckInState other) async {
    final before = state;
    final merged = CheckInState.merge(before, other);
    if (merged == before) return false;
    await save(merged);
    return true;
  }

  bool get checkInsEnabled => state.enabled;

  /// Settings › Security › "Recovery key check-ins".
  Future<void> setCheckInsEnabled(bool on, {DateTime? now}) async =>
      save(state.copyWith(enabled: on, enabledAt: now ?? DateTime.now()));

  RecoveryMethod? get method => state.method;

  /// Check-ins passed in a row.
  int get checkInStreak => state.currentStreak;

  /// "Remind me later"s in a row (on any of the user's devices).
  int get snoozesInRow => state.snoozesInRow;

  /// The check-in can't be put off any more.
  bool get ultimatum => snoozesInRow >= snoozesBeforeUltimatum;

  /// Back to 30 days after the next pass: a wrong key at the check-in, or
  /// "I've lost it".
  Future<void> resetCheckInStreak({DateTime? now}) async =>
      save(state.copyWith(failedAt: now ?? DateTime.now(), streak: 0));

  /// A key was made here (setup, a new or replaced key), with [method]: the
  /// first check-in comes 2 weeks later, the streak starts over.
  Future<void> setUp({RecoveryMethod? method, DateTime? now}) async {
    final at = now ?? DateTime.now();
    await setSkipped(false);
    var s = state.copyWith(setupAt: at);
    if (method != null) s = s.copyWith(method: method, methodAt: at);
    await save(s);
    // A setup run here starts its own check-ins: whatever the old-key
    // cleanup brought forward gives way.
    await Preference.preferences?.remove(_key("repair_due"));
  }

  /// The user just entered their key right: a passed check-in, or this
  /// device unlocked with it ([firstTime]: they made a new key, see
  /// [setUp]). The next comes 30, 90, then 180 days later as passes add up.
  /// A check-in brought forward only for the old-key cleanup (Vommet issue
  /// 526) doesn't add to the streak: it came early, so it says nothing about
  /// keeping the key over a longer gap.
  Future<void> confirmed({DateTime? now, bool firstTime = false}) async {
    if (firstTime) return setUp(now: now);
    final at = now ?? DateTime.now();
    await setSkipped(false);
    final s = state;
    final streak = s.currentStreak;
    final early = _earlyForRepair(at);
    // An account without check-ins before the cleanup gets none after it.
    final due = early && _repairMark == _noSchedule
        ? null
        : at.add(gapAfterPass(early ? streak - 1 : streak));
    await save(s.copyWith(
        lastPass: at, streak: early ? streak : streak + 1, passDue: () => due));
    // Answered: the cleanup's early date is used up (the mark stays, so it
    // isn't brought forward again for the same cleanup).
    await Preference.preferences?.remove(_key("repair_due"));
  }

  /// "Remind me later" (or closing the check-in).
  Future<void> snoozed({DateTime? now}) async {
    final at = now ?? DateTime.now();
    if (repairCheckInMarked) {
      await Preference.preferences
          ?.setInt(_key("repair_due"), at.add(snooze).millisecondsSinceEpoch);
      // Only here because of the cleanup: the shared schedule isn't
      // involved, so it doesn't count toward "put off 3 times" either.
      if (_earlyForRepair(at)) return;
    }
    final s = state;
    await save(s.copyWith(snoozedAt: at, snoozes: s.snoozesInRow + 1));
  }

  /// When the next check-in is due on this device: the shared schedule, or
  /// sooner while the old-key cleanup brought it forward.
  DateTime? get nextCheckInAt {
    final due = state.due;
    final repair = _time("repair_due");
    if (repair == null || !repairCheckInMarked) return due;
    return due == null || repair.isBefore(due) ? repair : due;
  }

  /// A check-in is due (check-ins on, and a schedule: set up or passed),
  /// and this device isn't newly signed in ([inNewDeviceQuiet]).
  bool checkInDue({DateTime? now}) {
    if (!checkInsEnabled) return false;
    final at = now ?? DateTime.now();
    if (inNewDeviceQuiet(now: at)) return false;
    final due = nextCheckInAt;
    return due != null && !at.isBefore(due);
  }

  // ---- a newly signed-in device ----
  //
  // The sign-in gate saw this device unconfirmed (a new sign-in), so the
  // user is about to approve it or enter their key. Once it's confirmed,
  // no check-in for [newDeviceQuiet]: not the shared schedule's (it may be
  // overdue from another device) and not the old-key cleanup's.

  /// The sign-in gate found this device not confirmed yet.
  Future<void> sawUnconfirmed() async =>
      Preference.preferences?.setBool(_key("unconfirmed"), true);

  /// This device is confirmed now: after [sawUnconfirmed], the quiet
  /// [newDeviceQuiet] starts.
  Future<void> sawConfirmed({DateTime? now}) async {
    final p = Preference.preferences;
    if (p == null || !(p.getBool(_key("unconfirmed")) ?? false)) return;
    await p.setInt(_key("confirmed_device"),
        (now ?? DateTime.now()).millisecondsSinceEpoch);
    await p.remove(_key("unconfirmed"));
  }

  /// Newly signed in: still waiting to be confirmed, or confirmed less than
  /// [newDeviceQuiet] ago.
  bool inNewDeviceQuiet({DateTime? now}) {
    if (Preference.preferences?.getBool(_key("unconfirmed")) ?? false) {
      return true;
    }
    final at = _time("confirmed_device");
    return at != null &&
        (now ?? DateTime.now()).isBefore(at.add(newDeviceQuiet));
  }

  DateTime? get lastConfirmed => state.lastPass;

  // ---- Vommet issue 526: bring the check-in forward for the cleanup ----
  //
  // Old-key copies of the secrets can only be removed while the user types
  // their current key, and the check-in is where they do that. So while
  // copies wait, the check-in is due now instead of in up to 180 days, once
  // per pending state: after that the dialog's own answers decide ("Remind
  // me later" snoozes 3 days as always). This stays on this device: only
  // the answers change the shared schedule. The mark keeps the due date the
  // account had before (or none), to tell an early check-in.

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
  Future<RepairCheckIn> updateRepairCheckIn(
      {required bool pending, required bool canCheck, DateTime? now}) async {
    final action = decideRepairCheckIn(
        pending: pending, canCheck: canCheck, marked: repairCheckInMarked);
    switch (action) {
      case RepairCheckIn.bringForward:
        final at = now ?? DateTime.now();
        final due = state.due;
        await Preference.preferences?.setInt(
            _key("repair_checkin"), due?.millisecondsSinceEpoch ?? _noSchedule);
        if (due == null || due.isAfter(at)) {
          await Preference.preferences
              ?.setInt(_key("repair_due"), at.millisecondsSinceEpoch);
        }
      case RepairCheckIn.restore:
        await Preference.preferences?.remove(_key("repair_due"));
        await Preference.preferences?.remove(_key("repair_checkin"));
      case RepairCheckIn.none:
        break;
    }
    return action;
  }

  /// The user passed the check-in brought forward for the cleanup. Nothing
  /// left to do: [confirmed] already keeps an account that had no
  /// check-ins before without any.
  Future<void> confirmedRepairCheckIn() async {}

  /// The decision on its own, for tests. [pending]: old-key copies wait for
  /// the user's current key (and the cleanup isn't recorded as done).
  static RepairCheckIn decideRepairCheckIn(
      {required bool pending, required bool canCheck, required bool marked}) {
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
  restore
}
