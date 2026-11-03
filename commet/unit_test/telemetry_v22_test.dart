// Vommet telemetry schema v22: reply previews whose quoted message can't be
// found (reply_lookup), and more detail on failed history loads. Counts,
// yes/no values and fixed lists only; no IDs or server names.

import 'dart:io';

import 'package:commet/telemetry/reply_lookup_stats.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v22", () {
    expect(schema.version, greaterThanOrEqualTo(22));
  });

  test("reply_lookup holds counts only", () {
    final ev = <String, Object>{
      "e": "reply_lookup",
      "t": 900000,
      "lookups": 12,
      "found_cached": 3,
      "found_server": 2,
      "missing": 5,
      "errors_not_found": 0,
      "errors_forbidden": 1,
      "errors_timeout": 1,
      "errors_other": 0,
      "federated_lookups": 10,
      "federated_missing": 5,
      "worst_ms": 4200,
    };
    expect(schema.validateEvent(ev), isTrue);
    expect(schema.validateEvent({"e": "reply_lookup", "t": 1}), isFalse,
        reason: "lookups is required");
    expect(schema.validateEvent({...ev, "event_id": "\$abc"}), isFalse);
    expect(schema.validateEvent({...ev, "server": "example.org"}), isFalse);
    expect(schema.validateEvent({...ev, "missing": "5"}), isFalse);
  });

  test("history_load carries the error type and federated_room", () {
    final ev = <String, Object>{
      "e": "history_load",
      "t": 1,
      "ms": 420000,
      "events": 0,
      "encrypted": false,
      "federated_room": true,
      "outcome": "error",
      "error_kind": "http_5xx",
      "error_type": "_Exception",
      "http_status": 504,
    };
    expect(schema.validateEvent(ev), isTrue);
    expect(schema.validateEvent({...ev, "error_kind": "http_error"}), isTrue);
    expect(schema.validateEvent({...ev, "error_type": "Exception: secret"}),
        isFalse);
    expect(schema.validateEvent({...ev, "federated_room": "4d2.org"}), isFalse);
  });

  test("federated_room compares server parts, never keeps them", () {
    expect(ReplyLookupStats.federatedRoom("!a:nether.im", "@z:4d2.org"), true);
    expect(
        ReplyLookupStats.federatedRoom("!a:nether.im", "@d:nether.im"), false);
    expect(ReplyLookupStats.federatedRoom("!opaqueid", "@d:nether.im"), isNull);
    expect(ReplyLookupStats.federatedRoom("!a:nether.im", null), isNull);
  });

  test("Matrix errors without a response are classified by errcode", () {
    matrix.MatrixException err(String code) =>
        matrix.MatrixException.fromJson({"errcode": code, "error": "x"});
    expect(TelemetryErrors.kind(err("M_FORBIDDEN")), "http_403");
    expect(TelemetryErrors.kind(err("M_NOT_FOUND")), "http_404");
    expect(TelemetryErrors.kind(err("M_LIMIT_EXCEEDED")), "http_429");
    expect(TelemetryErrors.kind(err("M_UNKNOWN")), "unknown");
    for (final code in ["M_FORBIDDEN", "M_NOT_FOUND", "M_UNKNOWN_TOKEN"]) {
      expect(schema.enumAllows("error_kind", TelemetryErrors.kind(err(code))),
          isTrue);
    }
  });

  test("the SDK's bare HTTP error is its own kind", () {
    final bare = Exception("http error response");
    expect(TelemetryErrors.isBareHttpError(bare), isTrue);
    expect(TelemetryErrors.isBareHttpError(Exception("other")), isFalse);
    expect(TelemetryErrors.kind(bare), "http_error");
    expect(schema.enumAllows("error_kind", "http_error"), isTrue);
    expect(TelemetryErrors.bareHttpFields(504),
        {"error_kind": "http_5xx", "http_status": 504});
    expect(TelemetryErrors.bareHttpFields(null)["error_kind"], "http_error");
  });

  test("the last error status is matched per family and after a point", () {
    final before = HttpStats.errorSeq;
    expect(HttpStats.errorStatusSince("messages", before), isNull);
    HttpStats.noteErrorStatus("messages", 502);
    expect(HttpStats.errorStatusSince("messages", before), 502);
    expect(HttpStats.errorStatusSince("sync", before), isNull);
    expect(HttpStats.errorStatusSince("messages", HttpStats.errorSeq), isNull);
    HttpStats.clearErrors();
  });

  test("reply lookup errors fall into four buckets", () {
    expect(
        ReplyLookupStats.errorBucket(matrix.MatrixException.fromJson(
            {"errcode": "M_FORBIDDEN", "error": "x"})),
        "forbidden");
    expect(
        ReplyLookupStats.errorBucket(matrix.MatrixException.fromJson(
            {"errcode": "M_NOT_FOUND", "error": "x"})),
        "not_found");
    expect(ReplyLookupStats.errorBucket(const SocketException("x")), "other");
  });
}
