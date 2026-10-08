// The schema is the privacy boundary for diagnostics: these tests check that
// content cannot get through it, and that error helpers never keep messages.

import 'dart:async';
import 'dart:io';

import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  final photo = <String, Object>{
    "e": "attachment_send",
    "t": 1200,
    "kind": "image",
    "mime": "image/jpeg",
    "bytes": 4100000,
    "width": 4032,
    "height": 3024,
    "encrypted": true,
    "exif_ms": 900,
    "process_ms": 18200,
    "send_ms": 40000,
    "total_ms": 61000,
    "outcome": "ok",
  };

  Map<String, Object> withField(String k, Object v) => {...photo, k: v};

  test("valid attachment event passes", () {
    expect(schema.validateEvent(photo), isTrue);
  });

  test("free text cannot ride along", () {
    expect(schema.validateEvent(withField("file_name", "me.jpg")), isFalse);
    expect(schema.validateEvent(withField("body", "hello")), isFalse);
    expect(schema.validateEvent(withField("room_id", "!a:nether.im")), isFalse);
    expect(schema.validateEvent(withField("mime", 'image/jpeg; name="me.jpg"')),
        isFalse);
    expect(schema.validateEvent(withField("kind", "selfie")), isFalse);
    expect(schema.validateEvent(withField("bytes", "4100000")), isFalse);
    expect(
        schema.validateEvent(withField("error_type", "Exception: my message")),
        isFalse);
  });

  // Vommet: timeline timings (schema v3).
  final roomOpen = <String, Object>{
    "e": "room_open",
    "t": 5000,
    "ms": 840,
    "events": 32,
    "history_requested": false,
    "convert_ms": 120,
    "startup_loads_running": true,
    "encrypted": true,
    "outcome": "ok",
  };
  final historyLoad = <String, Object>{
    "e": "history_load",
    "t": 9000,
    "ms": 2300,
    "events": 50,
    "startup_loads_running": false,
    "encrypted": false,
    "outcome": "error",
    "error_kind": "http_5xx",
    "http_status": 502,
  };

  test("valid timeline events pass", () {
    expect(schema.validateEvent(roomOpen), isTrue);
    expect(schema.validateEvent(historyLoad), isTrue);
  });

  test("timeline events can't carry text or IDs", () {
    for (final base in [roomOpen, historyLoad]) {
      Map<String, Object> w(String k, Object v) => {...base, k: v};
      expect(schema.validateEvent(w("room_id", "!a:nether.im")), isFalse);
      expect(schema.validateEvent(w("room_name", "Light Chat")), isFalse);
      expect(schema.validateEvent(w("body", "hello")), isFalse);
      expect(schema.validateEvent(w("event_id", r"$abc")), isFalse);
      expect(schema.validateEvent(w("ms", "840")), isFalse);
      expect(schema.validateEvent(w("events", "thirty")), isFalse);
      expect(schema.validateEvent(w("encrypted", "yes")), isFalse);
      expect(schema.validateEvent(w("startup_loads_running", 1)), isFalse);
      expect(schema.validateEvent(w("outcome", "it broke in Light Chat")),
          isFalse);
      expect(
          schema.validateEvent(w("error_kind", "Exception: secret")), isFalse);
    }
    expect(schema.validateEvent({...roomOpen, "convert_ms": "fast"}), isFalse);
    expect(
        schema.validateEvent({...historyLoad, "http_status": 9000}), isFalse);
  });

  test("timeline events need their required fields", () {
    expect(schema.validateEvent({"e": "room_open", "t": 1, "outcome": "ok"}),
        isFalse);
    expect(
        schema.validateEvent({"e": "history_load", "t": 1, "ms": 5}), isFalse);
  });

  test("unknown events and missing required fields are refused", () {
    expect(schema.validateEvent({"e": "keystrokes", "t": 1}), isFalse);
    expect(
        schema.validateEvent({"e": "attachment_send", "t": 1, "kind": "image"}),
        isFalse);
  });

  test("timer names must be code identifiers", () {
    Map<String, Object> perf(String name) => {
          "e": "perf_summary",
          "t": 1,
          "timers": [
            {"name": name, "calls": 1, "total_ms": 2}
          ]
        };
    expect(schema.validateEvent(perf("loadFromDB")), isTrue);
    expect(schema.validateEvent(perf("Initializing client abcdef")), isFalse);
  });

  test("error kinds come from the schema's list", () {
    for (final e in <Object>[
      TimeoutException("x"),
      const SocketException("x"),
      const FormatException("x"),
      StateError("x"),
      Exception("my secret message"),
    ]) {
      expect(schema.enumAllows("error_kind", TelemetryErrors.kind(e)), isTrue);
    }
    expect(TelemetryErrors.kind(TimeoutException("x")), "timeout");
    expect(TelemetryErrors.httpKind(413), "http_413");
  });

  test("error type keeps the type, never the message", () {
    final name = TelemetryErrors.typeName(Exception("my secret message"));
    expect(name.contains("secret"), isFalse);
    expect(schema.matchesType("code_type", name), isTrue);
  });

  test("stack frames keep only package locations", () {
    final trace = StackTrace.fromString(
        "#0      MatrixRoom.sendMessage (package:commet/client/matrix/matrix_room.dart:539:7)\n"
        "#1      <anonymous closure> (package:matrix/src/room.dart:1679:12)\n"
        "#2      main (file:///home/alice/secret project/main.dart:3:1)\n"
        "#3      _rootRun (dart:async/zone.dart:1399:13)\n");
    final frames = TelemetryErrors.frames(trace);
    expect(frames, [
      "package:commet/client/matrix/matrix_room.dart:539 MatrixRoom.sendMessage",
      "package:matrix/src/room.dart:1679 <anonymous_closure>",
      "dart:async/zone.dart:1399 _rootRun",
    ]);
    expect(schema.matchesType("code_frames", frames), isTrue);
  });
  test("Matrix error codes come from a fixed list, never the message", () {
    final forbidden = matrix.MatrixException.fromJson({
      "errcode": "M_FORBIDDEN",
      "error": "You are not permitted to create rooms",
    });
    expect(TelemetryErrors.errcode(forbidden), "M_FORBIDDEN");
    expect(
        TelemetryErrors.errcode(matrix.MatrixException.fromJson(
            {"errcode": "IO.EXAMPLE.SECRET_ROOM_NAME", "error": "x"})),
        "other");
    expect(
        TelemetryErrors.errcode(
            matrix.MatrixException.fromJson({"error": "no code"})),
        "other");
    expect(TelemetryErrors.errcode(TimeoutException("x")), isNull);
    expect(TelemetryErrors.errcode(null), isNull);

    // The client's list and the schema's list are the same.
    for (final code in [...TelemetryErrors.knownErrcodes, "other"]) {
      expect(schema.enumAllows("errcode", code), isTrue, reason: code);
    }
    expect(schema.enumAllows("errcode", "M_SOMETHING_NEW"), isFalse);
  });

  test("crash events can carry the HTTP status and Matrix error code", () {
    final crash = <String, Object>{
      "e": "crash",
      "t": 1341546,
      "source": "logged",
      "fatal": false,
      "error_type": "MatrixException",
      "frames": [
        "package:matrix/matrix_api_lite/generated/api.dart:1836 Api.createRoom"
      ],
      "http_status": 403,
      "errcode": "M_FORBIDDEN",
    };
    expect(schema.validateEvent(crash), isTrue);
    expect(
        schema.validateEvent({
          ...crash,
          "errcode": "M_FORBIDDEN: You are not permitted to create rooms"
        }),
        isFalse);
    expect(schema.validateEvent({...crash, "error": "not permitted"}), isFalse);
    expect(
        schema.validateEvent(
            {...withField("outcome", "error"), "errcode": "M_TOO_LARGE"}),
        isTrue);
  });
  test("decryption diagnostics are counts only", () {
    final visit = <String, Object>{
      "e": "timeline_crypto",
      "t": 5000,
      "open_s": 240,
      "utd_at_open": 4,
      "utd_at_close": 0,
      "key_arrivals": 1,
      "decrypted": 1,
      "removed": 3,
      "removed_utd": 3,
      "events_peak": 12,
      "events_at_close": 9,
    };
    expect(schema.validateEvent(visit), isTrue);
    expect(
        schema.validateEvent({...visit, "room_id": "!a:nether.im"}), isFalse);
    expect(schema.validateEvent({...visit, "removed": "three"}), isFalse);
    expect(schema.validateEvent({...visit, "session_id": "abc"}), isFalse);
    expect(schema.validateEvent({"e": "timeline_crypto", "t": 1}), isFalse);

    final request = <String, Object>{
      "e": "key_request",
      "t": 6000,
      "source": "manual",
      "outcome": "error",
      "error_kind": "unknown",
    };
    expect(schema.validateEvent(request), isTrue);
    expect(schema.validateEvent({...request, "source": "Alice's laptop"}),
        isFalse);
    expect(schema.validateEvent({...request, "sender_key": "abc"}), isFalse);

    final open = <String, Object>{
      "e": "room_open",
      "t": 1,
      "ms": 300,
      "encrypted": true,
      "utd": 4,
      "at_start": true,
      "outcome": "ok",
    };
    expect(schema.validateEvent(open), isTrue);
    expect(schema.validateEvent({...open, "at_start": "yes"}), isFalse);
  });
}
