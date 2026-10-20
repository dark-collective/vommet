// Vommet telemetry schema v24 + shared history wording: why messages from
// before you joined can't be read. history_share reports what happened to
// each history bundle (MSC4268) with fixed words and counts only; the
// banner says when some earlier messages weren't shared.

import 'dart:io';

import 'package:commet/telemetry/history_sharing_telemetry.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:commet/ui/molecules/shared_history_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption/history_sharing.dart';

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v24", () {
    expect(schema.version, greaterThanOrEqualTo(24));
  });

  Map<String, Object?> event(HistorySharingReport r) => {
        "e": "history_share",
        "t": 1000,
        ...HistorySharingTelemetry.fields(r),
      };

  test("every report the SDK can make validates", () {
    const outcomes = {
      "send": [
        "sent",
        "nothing_shareable",
        "no_cross_signed_devices",
        "identity_changed",
        "disabled",
        "error",
      ],
      "receive": [
        "imported",
        "too_late",
        "sender_unknown",
        "sender_not_cross_signed",
        "download_failed",
        "invalid",
        "error",
      ],
      "outbound_session": ["shared", "not_shared", "visibility_unknown"],
    };
    for (final MapEntry(key: direction, value: list) in outcomes.entries) {
      for (final outcome in list) {
        final r = HistorySharingReport(
            direction: direction,
            outcome: outcome,
            keys: 3,
            withheld: 15,
            skipped: 1,
            devices: 2,
            ms: 420);
        expect(schema.validateEvent(event(r)), isTrue,
            reason: "$direction $outcome");
      }
    }
  });

  test("only the fields that mean something per direction are sent", () {
    final send = HistorySharingTelemetry.fields(const HistorySharingReport(
        direction: "send", outcome: "sent", keys: 4, withheld: 2, devices: 1));
    expect(
        send.keys,
        unorderedEquals(
            ["direction", "outcome", "keys", "withheld", "ms", "devices"]));
    final receive = HistorySharingTelemetry.fields(const HistorySharingReport(
        direction: "receive", outcome: "imported", keys: 4, skipped: 1));
    expect(
        receive.keys,
        unorderedEquals(
            ["direction", "outcome", "keys", "withheld", "ms", "skipped"]));
    final session = HistorySharingTelemetry.fields(const HistorySharingReport(
        direction: "outbound_session", outcome: "visibility_unknown"));
    expect(session.keys, unorderedEquals(["direction", "outcome"]));
  });

  test("names, ids and free text can't ride along", () {
    final ev = event(const HistorySharingReport(
        direction: "receive", outcome: "imported", keys: 4));
    expect(
        schema.validateEvent({...ev, "room_id": "!abc:example.org"}), isFalse);
    expect(schema.validateEvent({...ev, "outcome": "shared by Dana"}), isFalse);
    expect(schema.validateEvent({...ev, "keys": "4"}), isFalse);
  });

  test("timeline_crypto counts messages whose history wasn't shared", () {
    expect(
        schema.validateEvent({
          "e": "timeline_crypto",
          "t": 1000,
          "utd_at_open": 15,
          "utd_at_close": 15,
          "utd_history_not_shared": 15,
        }),
        isTrue);
  });

  test("the banner says when some earlier messages weren't shared", () {
    expect(SharedHistoryBanner.message("Dana Reyes"),
        "Earlier messages were shared by Dana Reyes when you joined. You have Dana Reyes's word for who sent them.");
    expect(SharedHistoryBanner.message("Dana Reyes", withheld: 3),
        "Earlier messages were shared by Dana Reyes when you joined. You have Dana Reyes's word for who sent them. Some weren't shared: their senders' apps didn't allow it, so those can't be read here.");
  });
}
