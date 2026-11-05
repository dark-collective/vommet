// Vommet telemetry schema v34: verification step timings, numbers and fixed
// words only.

import 'dart:io';

import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/telemetry/verification_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/utils/key_verification.dart';

void main() {
  final schema = TelemetrySchema.parse(
    File("assets/telemetry/schema.json").readAsStringSync(),
  );

  Map<String, Object?> event(Map<String, Object?> fields) => {
        "e": "verification",
        "t": 700000,
        for (final MapEntry(:key, :value) in fields.entries)
          if (value != null) key: value,
      };

  const ready = "m.key.verification.ready";
  const start = "m.key.verification.start";
  const accept = "m.key.verification.accept";
  const key = "m.key.verification.key";
  const mac = "m.key.verification.mac";

  /// The desktop asking the phone, SAS over to-device (the 10-22 flow).
  VerificationRecord requesterFlow() {
    final r = VerificationRecord(
      requester: true,
      self: true,
      originMs: 640000,
      firstSyncPending: true,
    );
    r.observe(640000, KeyVerificationState.waitingAccept, null);
    // The other side's ready, 3.4 s into a slow sync round.
    r.received(651000, ready, applyWaitMs: 3400, loopBusyMs: 9000);
    r.observe(651050, KeyVerificationState.waitingAccept, ready);
    r.observe(651300, KeyVerificationState.waitingAccept, ready,
        fromUpdate: true);
    r.syncRound(647600, 652000);
    r.received(655000, accept, applyWaitMs: 200, loopBusyMs: 100);
    r.observe(655400, KeyVerificationState.waitingAccept, accept);
    r.received(657000, key, applyWaitMs: 50);
    r.observe(657100, KeyVerificationState.askSas, key, fromUpdate: true);
    r.observe(665000, KeyVerificationState.waitingSas, key, fromUpdate: true);
    r.received(666000, mac, applyWaitMs: 10, loopBusyMs: 20);
    r.observe(666300, KeyVerificationState.done, mac, fromUpdate: true);
    return r;
  }

  /// The phone answering, cold-started into the request.
  VerificationRecord responderFlow() {
    final r = VerificationRecord(
      requester: false,
      self: true,
      originMs: 3000,
      firstSyncPending: true,
    )
      ..coldStart = true
      ..requestAgeMs = 31000;
    r.shown(4200);
    r.observe(
        4200, KeyVerificationState.askAccept, "m.key.verification.request");
    r.observe(
        9000, KeyVerificationState.waitingAccept, "m.key.verification.request",
        fromUpdate: true);
    r.observe(
        9400, KeyVerificationState.askChoice, "m.key.verification.request",
        fromUpdate: true);
    r.received(14000, start, applyWaitMs: 4000, loopBusyMs: 2500);
    r.observe(14300, KeyVerificationState.askChoice, start);
    r.received(16000, key, applyWaitMs: 100);
    r.observe(16400, KeyVerificationState.askSas, start, fromUpdate: true);
    r.observe(22000, KeyVerificationState.waitingSas, key, fromUpdate: true);
    r.received(22500, mac);
    r.observe(22600, KeyVerificationState.done, mac, fromUpdate: true);
    return r;
  }

  test("schema is v34", () {
    expect(schema.version, greaterThanOrEqualTo(34));
  });

  test("requester steps, from the request it sent", () {
    final f = requesterFlow().fields(666300, outcome: "done");
    expect(f["role"], "requester");
    expect(f["kind"], "self");
    expect(f["method"], "sas");
    expect(f["ready_ms"], 11000);
    // The start goes out after the ready, seen on the SDK's update.
    expect(f["start_ms"], 11300);
    expect(f["accept_ms"], 15000);
    expect(f["key_sent_ms"], 15400);
    expect(f["key_received_ms"], 17000);
    expect(f["sas_shown_ms"], 17100);
    expect(f["sas_confirmed_ms"], 25000);
    expect(f["mac_received_ms"], 26000);
    expect(f["done_ms"], 26300);
    expect(f["end_ms"], 26300);
    expect(f["first_sync_pending"], true);
    expect(f, isNot(contains("cold_start")));
    expect(f, isNot(contains("user_accept_ms")));
    expect(f["recv_events"], 4);
    expect(f["recv_apply_wait_max_ms"], 3400);
    expect(f["recv_apply_wait_total_ms"], 3660);
    expect(f["recv_loop_busy_max_ms"], 9000);
    expect(f["recv_loop_busy_total_ms"], 9120);
    expect(f["sync_rounds"], 1);
    expect(f["sync_apply_total_ms"], 4400);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("responder steps and the person's time to accept", () {
    final f = responderFlow().fields(22600, outcome: "done");
    expect(f["role"], "responder");
    expect(f["shown_ms"], 1200);
    expect(f["user_accept_ms"], 4800);
    expect(f["ready_ms"], 6400);
    expect(f["start_ms"], 11000);
    // Its accept went out once the start had been handled.
    expect(f["accept_ms"], 11300);
    expect(f["key_received_ms"], 13000);
    expect(f["key_sent_ms"], 13400);
    expect(f["sas_shown_ms"], 13400);
    expect(f["sas_confirmed_ms"], 19000);
    expect(f["mac_received_ms"], 19500);
    expect(f["cold_start"], true);
    expect(f["request_age_ms"], 31000);
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("a start seen before the person accepted isn't an accept", () {
    final r = VerificationRecord(requester: false, self: true, originMs: 0)
      ..shown(10);
    r.observe(20, KeyVerificationState.askAccept, start);
    expect(r.steps, isNot(contains("accept")));
    expect(r.steps, isNot(contains("accepted")));
  });

  test("a sync round before the request doesn't count", () {
    final r = VerificationRecord(requester: true, self: true, originMs: 5000);
    r.syncRound(1000, 4000);
    r.syncRound(4000, 6000);
    r.syncRound(7000, 7000, error: true);
    final f = r.fields(8000, outcome: "abandoned");
    expect(f["sync_rounds"], 1);
    expect(f["sync_apply_total_ms"], 1000);
    expect(f["sync_errors"], 1);
    expect(f["method"], "none");
    expect(schema.validateEvent(event(f)), isTrue);
  });

  test("cancel codes are a fixed list", () {
    final r = VerificationRecord(requester: false, self: false, originMs: 0);
    for (final code in [...verificationCancelCodes, "x.custom", null]) {
      final f = r.fields(10,
          outcome: "cancelled",
          cancelCode: code,
          byOther: code == "m.accepted");
      expect(schema.validateEvent(event(f)), isTrue, reason: "$code");
      if (code == "x.custom" || code == null) {
        expect(f["cancel_code"], "other");
      }
    }
    expect(
      r.fields(10, outcome: "cancelled", cancelCode: "m.user")["cancelled_by"],
      isNull,
    );
    expect(
      r.fields(10, outcome: "done", cancelCode: "m.user"),
      isNot(contains("cancel_code")),
    );
  });

  test("only numbers, booleans and fixed words; no ids accepted", () {
    final f = responderFlow().fields(22600, outcome: "done");
    const words = {"role", "kind", "method", "outcome"};
    for (final MapEntry(:key, :value) in f.entries) {
      if (value == null) continue;
      expect(value is int || value is bool || words.contains(key), isTrue,
          reason: key);
    }
    for (final extra in {
      "transaction_id": "abc",
      "device_id": "ABCDEF",
      "user_id": "@a:b",
      "room_id": "!a:b",
    }.entries) {
      expect(
          schema.validateEvent({...event(f), extra.key: extra.value}), isFalse,
          reason: extra.key);
    }
  });
}
