// Vommet telemetry schema v23: why a remote voice can be missing in a call.
// call_stats counts remote audio tracks by subscription and, in encrypted
// calls, by decryption state. Counts only; no identities.

import 'dart:io';

import 'package:commet/telemetry/call_stats.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v23", () {
    expect(schema.version, greaterThanOrEqualTo(23));
  });

  CallSample sampleOf(bool encrypted) {
    final s = CallSample()
      ..elapsedMs = 60000
      ..encrypted = encrypted;
    s.addRemoteAudio(subscribed: true, muted: false, e2ee: lk.E2EEState.kOk);
    s.addRemoteAudio(
        subscribed: true, muted: false, e2ee: lk.E2EEState.kKeyRatcheted);
    s.addRemoteAudio(
        subscribed: true,
        muted: false,
        e2ee: lk.E2EEState.kMissingKey,
        beforeKey: true);
    s.addRemoteAudio(
        subscribed: true, muted: false, e2ee: lk.E2EEState.kDecryptionFailed);
    s.addRemoteAudio(subscribed: true, muted: false);
    s.addRemoteAudio(subscribed: false, muted: true);
    s.keyedParticipants = 4;
    return s;
  }

  test("remote audio is counted by subscription and decryption state", () {
    final f = sampleOf(true).fields();
    expect(f["audio_published"], 6);
    expect(f["audio_muted"], 1);
    expect(f["audio_unsubscribed"], 1);
    expect(f["e2ee_ok"], 2);
    expect(f["e2ee_missing_key"], 1);
    expect(f["e2ee_failed"], 1);
    expect(f["e2ee_pending"], 1);
    expect(f["subscribed_before_key"], 1);
    expect(f["keyed_participants"], 4);
  });

  test("unencrypted calls carry no decryption fields", () {
    final f = sampleOf(false).fields();
    expect(f["audio_published"], 6);
    expect(f.containsKey("e2ee_ok"), isFalse);
    expect(f.containsKey("keyed_participants"), isFalse);
  });

  test("call_stats with the new counts validates; text can't ride along", () {
    final ev = <String, Object?>{
      "e": "call_stats",
      "t": 60000,
      "quality": "excellent",
      "minute": 1,
      "participants": 8,
      "encrypted": true,
      ...sampleOf(true).fields(),
    };
    expect(schema.validateEvent(ev), isTrue);
    expect(schema.validateEvent({...ev, "identity": "@a:b:DEV"}), isFalse);
    expect(schema.validateEvent({...ev, "e2ee_ok": "2"}), isFalse);
  });
}
