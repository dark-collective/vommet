// "Still have your recovery key?" check-ins get further apart as they pass
// in a row: 3 days after setup, then 30, 90, and every 180 days after that.
// A wrong key, "I've lost it", or a setup starts over at 30; "Remind me
// later" leaves the streak alone.

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 10, 21, 9);
  const day = Duration(days: 1);
  var n = 0;
  late SecureSetupRecords r;

  Future<void> prefs([Map<String, Object> values = const {}]) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(values);
    Preference.preferences = await SharedPreferences.getInstance();
  }

  setUp(() async {
    await prefs();
    r = SecureSetupRecords("@u${n++}:x");
  });

  /// Days from [at] until the check-in is due (exactly: due at that day,
  /// not the day before).
  int dueInDays(DateTime at) {
    for (var d = 0; d <= 400; d++) {
      if (r.checkInDue(now: at.add(day * d))) {
        expect(r.checkInDue(now: at.add(day * d - const Duration(minutes: 1))),
            isFalse);
        return d;
      }
    }
    return -1;
  }

  /// Passes every check-in on its due day; returns the gaps it got.
  Future<List<int>> passes(int count, DateTime from) async {
    final gaps = <int>[];
    var at = from;
    for (var i = 0; i < count; i++) {
      await r.confirmed(now: at);
      final gap = dueInDays(at);
      gaps.add(gap);
      at = at.add(day * gap);
    }
    return gaps;
  }

  test("passes in a row: 30, 90, then 180 days for good", () async {
    await r.confirmed(now: t0, firstTime: true);
    expect(dueInDays(t0), 3, reason: "first check-in after setup");
    expect(r.checkInStreak, 0);
    expect(await passes(5, t0.add(day * 3)), [30, 90, 180, 180, 180]);
    expect(r.checkInStreak, 5);
  });

  test("the gap table", () {
    expect(SecureSetupRecords.gapAfterPass(-1), const Duration(days: 30));
    expect(SecureSetupRecords.gapAfterPass(0), const Duration(days: 30));
    expect(SecureSetupRecords.gapAfterPass(1), const Duration(days: 90));
    expect(SecureSetupRecords.gapAfterPass(2), const Duration(days: 180));
    expect(SecureSetupRecords.gapAfterPass(50), const Duration(days: 180));
  });

  test("a wrong key or \"I've lost it\": back to 30", () async {
    await r.confirmed(now: t0, firstTime: true);
    expect(await passes(3, t0), [30, 90, 180]);
    await r.resetCheckInStreak(); // what both of them do
    expect(r.checkInStreak, 0);
    expect(await passes(3, t0.add(day * 400)), [30, 90, 180]);
  });

  test("a setup (new key, replaced key, set up again): back to 30", () async {
    await r.confirmed(now: t0, firstTime: true);
    expect(await passes(2, t0), [30, 90]);
    await r.confirmed(now: t0.add(day * 200), firstTime: true);
    expect(r.checkInStreak, 0);
    expect(dueInDays(t0.add(day * 200)), 3);
    expect(await passes(2, t0.add(day * 203)), [30, 90]);
  });

  test("Remind me later: 3 days, streak unchanged", () async {
    await r.confirmed(now: t0, firstTime: true);
    expect(await passes(2, t0), [30, 90]);
    final at = t0.add(day * 120);
    await r.snoozed(now: at);
    expect(r.checkInStreak, 2);
    expect(dueInDays(at), 3);
    expect(await passes(1, at.add(day * 3)), [180]);
  });

  test("installs from before the streak start at 30, not 180", () async {
    const user = "@old:x";
    await prefs({
      "vommet_secure_confirmed_$user": t0.millisecondsSinceEpoch,
      "vommet_secure_checkin_due_$user":
          t0.add(day * 30).millisecondsSinceEpoch,
    });
    r = SecureSetupRecords(user);
    expect(r.checkInStreak, 0);
    expect(r.checkInDue(now: t0.add(day * 30)), isTrue, reason: "kept");
    expect(await passes(3, t0.add(day * 30)), [30, 90, 180]);
  });

  group("Vommet issue 526 early check-in", () {
    test("passed early: no step up, the schedule it had comes back", () async {
      await r.confirmed(now: t0.subtract(day * 10)); // 1 pass, due t0 + 20 d
      expect(r.checkInStreak, 1);
      await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
      await r.confirmed(now: t0);
      await r.confirmedRepairCheckIn();
      expect(r.checkInStreak, 1, reason: "came early: doesn't count");
      await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
      expect(dueInDays(t0), 30);
      expect(await passes(2, t0.add(day * 30)), [90, 180]);
    });

    test("an account without check-ins keeps none", () async {
      await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
      await r.confirmed(now: t0);
      await r.confirmedRepairCheckIn();
      await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
      expect(r.checkInDue(now: t0.add(day * 400)), isFalse);
      expect(r.checkInStreak, 0);
    });

    test("its own check-in was due anyway: counts", () async {
      await r.confirmed(now: t0.subtract(day * 40)); // due t0 - 10 d
      await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
      await r.confirmed(now: t0);
      await r.confirmedRepairCheckIn();
      expect(r.checkInStreak, 2);
      await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
      expect(dueInDays(t0), 90);
    });
  });
}
