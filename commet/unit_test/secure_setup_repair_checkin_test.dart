// Vommet issue 526 follow-up: while old-key copies of the secrets wait for
// the user's current recovery key, the existing "Still have your recovery
// key?" check-in is brought forward to now, once per pending cleanup, and
// the dialog's own answers (snooze, confirm) still decide what comes next.

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final t0 = DateTime(2026, 10, 21, 9);
  const day = Duration(days: 1);
  var n = 0;
  late SecureSetupRecords r;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    r = SecureSetupRecords("@u${n++}:x");
  });

  test("decision table", () {
    RepairCheckIn d(bool pending, bool canCheck, bool marked) =>
        SecureSetupRecords.decideRepairCheckIn(
            pending: pending, canCheck: canCheck, marked: marked);
    expect(d(true, true, false), RepairCheckIn.bringForward);
    expect(d(true, true, true), RepairCheckIn.none, reason: "once only");
    expect(d(true, false, false), RepairCheckIn.none,
        reason: "unconfirmed device / no secret storage");
    expect(d(false, true, false), RepairCheckIn.none);
    expect(d(false, true, true), RepairCheckIn.restore);
    expect(d(false, false, true), RepairCheckIn.restore);
  });

  test("pending copies: due now, also without any check-in before", () async {
    expect(r.checkInDue(now: t0), isFalse, reason: "never scheduled");
    expect(await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0),
        RepairCheckIn.bringForward);
    expect(r.checkInDue(now: t0), isTrue);
    expect(r.repairCheckInMarked, isTrue);
  });

  test("pending copies: a check-in 30 days away comes now", () async {
    await r.confirmed(now: t0.subtract(day));
    expect(r.checkInDue(now: t0), isFalse);
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    expect(r.checkInDue(now: t0), isTrue);
  });

  test("an overdue check-in stays due (not moved later)", () async {
    await r.confirmed(now: t0.subtract(const Duration(days: 40)));
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    expect(r.checkInDue(now: t0.subtract(const Duration(days: 5))), isTrue);
  });

  test("nothing pending: schedule unchanged", () async {
    await r.confirmed(now: t0);
    expect(await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0),
        RepairCheckIn.none);
    expect(r.repairCheckInMarked, isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 29))), isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 30))), isTrue);

    final fresh = SecureSetupRecords("@never:x");
    await fresh.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
    expect(fresh.checkInDue(now: t0.add(const Duration(days: 400))), isFalse);
  });

  test("unconfirmed device (or no secret storage): not shown", () async {
    expect(await r.updateRepairCheckIn(pending: true, canCheck: false, now: t0),
        RepairCheckIn.none);
    expect(r.checkInDue(now: t0), isFalse);
    expect(r.repairCheckInMarked, isFalse,
        reason: "brought forward later, once this device is confirmed");
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    expect(r.checkInDue(now: t0), isTrue);
  });

  test("dismissed (Remind me later): the usual 3-day snooze, not every launch",
      () async {
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.snoozed(now: t0); // what "Remind me later" or closing it does
    // Next launches, copies still pending: no new bring-forward.
    for (final later in [t0.add(const Duration(hours: 1)), t0.add(day * 2)]) {
      expect(
          await r.updateRepairCheckIn(
              pending: true, canCheck: true, now: later),
          RepairCheckIn.none);
      expect(r.checkInDue(now: later), isFalse);
    }
    expect(r.checkInDue(now: t0.add(SecureSetupRecords.snooze)), isTrue);
  });

  test("passed on an account that had no check-ins: none start", () async {
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.confirmed(now: t0);
    await r.confirmedRepairCheckIn();
    expect(r.checkInDue(now: t0.add(const Duration(days: 400))), isFalse);
    // Cleanup done: the mark goes, nothing else changes.
    expect(await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0),
        RepairCheckIn.restore);
    expect(r.repairCheckInMarked, isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 400))), isFalse);
  });

  test("passed on an account with check-ins: the usual 30 days", () async {
    await r.confirmed(now: t0.subtract(day * 10));
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.confirmed(now: t0);
    await r.confirmedRepairCheckIn();
    await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
    expect(r.checkInDue(now: t0.add(const Duration(days: 29))), isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 30))), isTrue);
  });

  test("cleaned up elsewhere: the old schedule comes back", () async {
    await r.confirmed(now: t0.subtract(day * 10)); // due at t0 + 20 d
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.snoozed(now: t0);
    await r.updateRepairCheckIn(
        pending: false, canCheck: true, now: t0.add(day));
    expect(r.checkInDue(now: t0.add(const Duration(days: 19))), isFalse);
    expect(r.checkInDue(now: t0.add(const Duration(days: 20))), isTrue);

    final never = SecureSetupRecords("@n2:x");
    await never.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await never.snoozed(now: t0);
    await never.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
    expect(never.checkInDue(now: t0.add(const Duration(days: 400))), isFalse);
  });

  test("a setup run meanwhile keeps its own check-ins", () async {
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.confirmed(now: t0, firstTime: true); // e.g. replaced the key
    await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
    expect(r.checkInDue(now: t0.add(SecureSetupRecords.firstCheckIn)), isTrue);
  });

  test("once per pending state: a later new one is brought forward again",
      () async {
    await r.updateRepairCheckIn(pending: true, canCheck: true, now: t0);
    await r.snoozed(now: t0);
    await r.updateRepairCheckIn(pending: false, canCheck: true, now: t0);
    final later = t0.add(const Duration(days: 50));
    expect(
        await r.updateRepairCheckIn(pending: true, canCheck: true, now: later),
        RepairCheckIn.bringForward);
    expect(r.checkInDue(now: later), isTrue);
  });
}
