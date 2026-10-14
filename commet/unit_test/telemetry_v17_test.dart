// Vommet telemetry schema v17: request timings, call quality, message
// sends, encryption state, memory pressure and device context. As with the
// other telemetry tests, the point is that nothing but numbers, booleans
// and fixed-list values can get through.

import 'dart:convert';
import 'dart:io';

import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/call_stats.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/telemetry_errors.dart';
import 'package:commet/telemetry/telemetry_http.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/src/stats/stats.dart' as lk;

void main() {
  final schema = TelemetrySchema.parse(
      File("assets/telemetry/schema.json").readAsStringSync());

  test("schema is v18 or later and still accepts every older version", () {
    expect(schema.version, greaterThanOrEqualTo(18));
  });

  group("Android crash locations (v18)", () {
    // What a --split-debug-info release build prints; the addresses are
    // made up but the shape is the Dart VM's.
    const nonSymbolic = """
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 19226, tid: 19255, name 1.ui
os: android arch: arm64 comp: yes sim: no
build_id: '4e0f6c4b0c6f6f0f9a1b2c3d4e5f6a7b'
isolate_dso_base: 7a2c5f2000, vm_dso_base: 7a2c5f2000
isolate_instructions: 7a2c6aa000, vm_instructions: 7a2c69c000
    #00 abs 0000007a2c8b3d0f virt 00000000002c1d0f _kDartIsolateSnapshotInstructions+0x209d0f
    #01 abs 0000007a2c8a1111 virt 00000000002af111 _kDartIsolateSnapshotInstructions+0x1f7111
<asynchronous suspension>
    #02 abs 0000007a2c69c123 _kDartVmSnapshotInstructions+0x123
    #03 abs 0000007a2c6ab000
""";

    test("build id and symbol offsets are taken, nothing else", () {
      final r = TelemetryErrors.dartPcs(StackTrace.fromString(nonSymbolic))!;
      expect(r.buildId, "4e0f6c4b0c6f6f0f9a1b2c3d4e5f6a7b");
      expect(r.pcs, ["i+209d0f", "i+1f7111", "v+123", "i+1000"]);
    });

    test("symbolic traces (debug, Linux) give nothing", () {
      expect(
          TelemetryErrors.dartPcs(StackTrace.fromString(
              "#0      main (package:commet/main.dart:10:3)")),
          isNull);
      expect(TelemetryErrors.dartPcs(null), isNull);
    });

    test("the crash event takes them; text and addresses can't ride along", () {
      final r = TelemetryErrors.dartPcs(StackTrace.fromString(nonSymbolic))!;
      final crash = <String, Object>{
        "e": "crash",
        "t": 1,
        "source": "logged",
        "error_type": "RangeError",
        "frames": <String>[],
        "dart_build_id": r.buildId,
        "dart_pcs": r.pcs,
      };
      expect(schema.validateEvent(crash), isTrue);
      expect(schema.validateEvent({...crash, "dart_build_id": "not hex!"}),
          isFalse);
      expect(
          schema.validateEvent({
            ...crash,
            "dart_pcs": ["i+209d0f", "pid: 19226"]
          }),
          isFalse);
      expect(
          schema.validateEvent({
            ...crash,
            "dart_pcs": ["7a2c8b3d0f"]
          }),
          isFalse,
          reason: "absolute addresses are not offsets");
    });
  });

  test("a \$comment beside an event's fields is not a field", commentTolerance);

  group("http_stats", () {
    test("request families come from the path shape only", () {
      expect(HttpStats.family("/_matrix/client/v3/sync"), "sync");
      expect(
          HttpStats.family(
              "/_matrix/client/unstable/org.matrix.simplified_msc3575/sync"),
          "sync");
      expect(
          HttpStats.family(
              "/_matrix/client/v3/rooms/!abc:nether.im/send/m.room.message/txn1"),
          "send");
      expect(
          HttpStats.family(
              "/_matrix/client/v3/rooms/!abc:nether.im/redact/\$ev/txn2"),
          "redact");
      expect(
          HttpStats.family(
              "/_matrix/client/v1/media/download/nether.im/AbCdEf"),
          "media_download");
      expect(HttpStats.family("/_matrix/media/v3/download/nether.im/AbCdEf"),
          "media_download");
      expect(
          HttpStats.family(
              "/_matrix/client/v1/media/thumbnail/nether.im/AbCdEf"),
          "media_thumbnail");
      expect(HttpStats.family("/_matrix/media/v3/upload"), "media_upload");
      expect(HttpStats.family("/_matrix/media/v1/create"), "media_upload");
      expect(HttpStats.family("/_matrix/client/v3/keys/query"), "keys");
      expect(HttpStats.family("/_matrix/client/v3/profile/@me:nether.im"),
          "profile");
      expect(
          HttpStats.family(
              "/_matrix/client/v3/rooms/!abc:nether.im/state/m.room.name"),
          "state");
      expect(
          HttpStats.family("/_matrix/client/v3/rooms/!abc:nether.im/messages"),
          "messages");
      expect(
          HttpStats.family("/_matrix/client/v3/rooms/!abc:nether.im/members"),
          "members");
      expect(HttpStats.family("/_matrix/client/v3/pushers"), "push");
      expect(HttpStats.family("/_matrix/client/v3/pushrules/"), "push");
      expect(
          HttpStats.family(
              "/_matrix/client/v3/user/@me:nether.im/account_data/m.direct"),
          "account_data");
      expect(
          HttpStats.family(
              "/_matrix/client/v3/rooms/!abc:nether.im/context/\$ev"),
          "context");
      expect(
          HttpStats.family("/_matrix/client/v3/join/!abc:nether.im"), "join");
      expect(HttpStats.family("/_matrix/client/v3/login"), "login");
      expect(HttpStats.family("/.well-known/matrix/client"), "well_known");
      expect(HttpStats.family("/_matrix/client/v3/capabilities"), "other");
      for (final path in [
        "/_matrix/client/v3/rooms/!abc:nether.im/send/m.room.message/txn1",
        "/anything/at/all"
      ]) {
        expect(
            schema.enumAllows("http_family", HttpStats.family(path)), isTrue);
      }
    });

    test("the event holds a family and numbers, never a URL", () {
      final ok = <String, Object>{
        "e": "http_stats",
        "t": 900000,
        "family": "sync",
        "own_server": true,
        "requests": 60,
        "errors": 1,
        "p95_ms": 31000,
        "worst_ms": 40000,
        "bytes_rx": 123456,
      };
      expect(schema.validateEvent(ok), isTrue);
      expect(schema.validateEvent({...ok, "url": "/sync?since=abc"}), isFalse);
      expect(
          schema.validateEvent({...ok, "path": "/rooms/!a:b/send"}), isFalse);
      expect(
          schema.validateEvent({...ok, "family": "sync?since=abc"}), isFalse);
      expect(schema.validateEvent({...ok, "host": "nether.im"}), isFalse);
      expect(schema.validateEvent({"e": "http_stats", "t": 1, "requests": 1}),
          isFalse);
    });

    test("the wrapper passes requests through untouched", () async {
      final inner = MockClient((request) async {
        expect(request.url.path, "/_matrix/client/v3/sync");
        return http.Response('{"next_batch":"s1"}', 200,
            headers: {"date": HttpDate.format(DateTime.now().toUtc())});
      });
      final client = TelemetryHttpClient(inner);
      final response = await client
          .get(Uri.parse("https://nether.im/_matrix/client/v3/sync"));
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body)["next_batch"], "s1");
    });

    test("the server's clock is read as a skew in seconds, bounded", () {
      HttpStats.noteServerDate(HttpDate.format(
          DateTime.now().toUtc().add(const Duration(hours: 1))));
      expect(HttpStats.clockSkewS, inInclusiveRange(3598, 3601));
      HttpStats.noteServerDate("not a date");
      expect(HttpStats.clockSkewS, inInclusiveRange(3598, 3601));
      final event = <String, Object>{
        "e": "perf_summary",
        "t": 1,
        "clock_skew_s": HttpStats.clockSkewS!,
        "timelines_live": 3,
        "db_mb": 120,
        "dropped": 0,
        "overflow": 0,
      };
      expect(schema.validateEvent(event), isTrue);
      expect(
          schema.validateEvent({...event, "clock_skew_s": -40000000}), isFalse);
    });
  });

  group("startup and general timers", () {
    test("known phrases become identifiers; anything else is left out", () {
      final d = CumulativeDiagnostics("test");
      d.addResult("Startup: accounts loaded", const Duration(seconds: 2));
      d.addResult(
          "Startup: file cache + config", const Duration(milliseconds: 30));
      d.addResult(
          "Open room (load timeline)", const Duration(milliseconds: 120));
      d.addResult("loadFromDB", const Duration(milliseconds: 50));
      d.addResult(
          "Initializing client a1b2c3d4e5f6", const Duration(seconds: 1));
      d.addResult("Startup: room list on screen (since launch)",
          const Duration(seconds: 3));
      final names = Telemetry.timers(d).map((t) => t["name"]).toList();
      expect(
          names,
          containsAll([
            "Startup_accounts_loaded",
            "Startup_file_cache_config",
            "Open_room_load_timeline",
            "loadFromDB",
            "Startup_room_list_on_screen_since_launch",
          ]));
      expect(names.any((n) => (n as String).contains("a1b2c3d4e5f6")), isFalse);
      expect(names.length, 5);
      final event = <String, Object>{
        "e": "app_ready",
        "t": 4000,
        "ms": 4000,
        "startup": Telemetry.timers(d),
      };
      expect(schema.validateEvent(event), isTrue);
    });

    test("the splash wait, first frame and deferred room loads ship", () {
      expect(Telemetry.timerName("Startup: splash held for room state"),
          "Startup_splash_held_for_room_state");
      expect(Telemetry.timerName("Startup: first frame (since launch)"),
          "Startup_first_frame_since_launch");
      expect(Telemetry.timerName("Deferred room state loads (209 rooms)"),
          "Deferred_room_state_loads");
      for (final name in [
        "Startup_splash_held_for_room_state",
        "Startup_first_frame_since_launch",
        "Deferred_room_state_loads",
      ]) {
        expect(Telemetry.knownGeneralTimers, contains(name));
      }
    });

    test("every known timer name fits the schema's identifier pattern", () {
      for (final name in Telemetry.knownGeneralTimers) {
        expect(
            schema.validateEvent({
              "e": "perf_summary",
              "t": 1,
              "timers": [
                {"name": name, "calls": 1, "total_ms": 1}
              ]
            }),
            isTrue,
            reason: name);
      }
    });
  });

  group("device context", () {
    test("desktop names reduce to a fixed list", () {
      expect(Telemetry.desktopKind("ubuntu:GNOME"), "gnome");
      expect(Telemetry.desktopKind("KDE"), "kde");
      expect(Telemetry.desktopKind("Hyprland"), "hyprland");
      expect(Telemetry.desktopKind("X-Cinnamon"), "cinnamon");
      expect(Telemetry.desktopKind("my-custom-wm:extra"), "other");
      expect(Telemetry.desktopKind(null), "unknown");
      expect(Telemetry.desktopKind(""), "unknown");
      for (final v in ["ubuntu:GNOME", "weird", null]) {
        expect(schema.enumAllows("desktop", Telemetry.desktopKind(v)), isTrue);
      }
    });

    test("total memory comes from /proc/meminfo's MemTotal line", () {
      expect(
          Telemetry.memTotalMb([
            "MemTotal:       16318740 kB",
            "MemFree:         1234567 kB",
          ]),
          15936);
      expect(Telemetry.memTotalMb(["MemFree: 1 kB"]), isNull);
    });

    test("envelope device fields are numbers and booleans only", () {
      final envelope = <String, Object>{
        "v": 17,
        "install": "3f2b8c1e-9a4d-4e6f-8b2a-1c3d5e7f9a0b",
        "session": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
        "app_version": "testing-2026-10-11+1900",
        "flavor": "testing",
        "platform": "linux",
        "display": "wayland",
        "cpu_cores": 16,
        "ram_mb": 15936,
        "low_ram": false,
        "screen_w": 2560,
        "screen_h": 1440,
        "dpr_x100": 150,
        "text_scale_x100": 100,
        "bold_text": false,
        "reduce_motion": false,
        "high_contrast": false,
        "desktop": "kde",
        "gl_software": false,
      };
      expect(schema.validateEnvelope(envelope), isTrue);
      expect(schema.validateEnvelope({...envelope, "desktop": "KDE Plasma 6"}),
          isFalse);
      expect(
          schema.validateEnvelope({...envelope, "gpu": "Mesa Intel"}), isFalse);
      expect(schema.validateEnvelope({...envelope, "hostname": "laptop"}),
          isFalse);
    });

    test("memory pressure carries figures, not content", () {
      final ok = <String, Object>{
        "e": "memory_pressure",
        "t": 1,
        "uptime_s": 3600,
        "rss_mb": 900,
        "image_cache_mb": 90,
        "timelines_live": 12,
        "foreground": true,
      };
      expect(schema.validateEvent(ok), isTrue);
      expect(schema.validateEvent({...ok, "room": "Light Chat"}), isFalse);
    });
  });

  group("message_send", () {
    final ok = <String, Object>{
      "e": "message_send",
      "t": 5000,
      "kind": "text",
      "encrypted": true,
      "chars": 42,
      "html": false,
      "mentions": 1,
      "markdown_ms": 3,
      "send_ms": 410,
      "outcome": "ok",
    };
    test("kinds and figures only", () {
      expect(schema.validateEvent(ok), isTrue);
      for (final kind in [
        "text",
        "reply",
        "edit",
        "thread",
        "reaction",
        "redaction",
        "sticker"
      ]) {
        expect(schema.validateEvent({...ok, "kind": kind}), isTrue);
      }
      expect(schema.validateEvent({...ok, "kind": "dm"}), isFalse);
      expect(schema.validateEvent({...ok, "body": "hello"}), isFalse);
      expect(schema.validateEvent({...ok, "text": "hello"}), isFalse);
      expect(schema.validateEvent({...ok, "mentioned": "@a:b"}), isFalse);
      expect(schema.validateEvent({...ok, "chars": "42"}), isFalse);
    });

    test("a silently failed send is an error without a type", () {
      final failed = {
        ...ok,
        "outcome": "error",
        "error_kind": "unknown",
      };
      expect(schema.validateEvent(failed), isTrue);
      expect(
          schema.validateEvent({
            ...ok,
            "outcome": "error",
            "error_kind": "http_429",
            "error_type": "MatrixException",
            "http_status": 429,
            "errcode": "M_LIMIT_EXCEEDED",
          }),
          isTrue);
      expect(schema.validateEvent({...failed, "error_type": "Exception: hi"}),
          isFalse);
    });
  });

  test("crypto_state is booleans and counts", () {
    final ok = <String, Object>{
      "e": "crypto_state",
      "t": 70000,
      "account_index": 1,
      "accounts": 2,
      "own_server": true,
      "encryption": true,
      "cross_signing": true,
      "cross_signing_cached": false,
      "key_backup": true,
      "key_backup_cached": true,
      "own_device_verified": false,
      "devices": 4,
      "unverified_devices": 2,
      "blocked_devices": 0,
      "rooms": 180,
      "encrypted_rooms": 25,
    };
    expect(schema.validateEvent(ok), isTrue);
    expect(schema.validateEvent({...ok, "device_id": "ABCDEFGH"}), isFalse);
    expect(schema.validateEvent({...ok, "recovery_key": "EsTx..."}), isFalse);
    expect(schema.validateEvent({...ok, "encryption": "yes"}), isFalse);
    expect(schema.validateEvent({"e": "crypto_state", "t": 1}), isFalse);
  });

  test("timeline_crypto and sync_stats carry the new counts", () {
    expect(
        schema.validateEvent({
          "e": "timeline_crypto",
          "t": 1,
          "utd_at_open": 3,
          "utd_at_close": 2,
          "utd_no_key": 1,
          "utd_corrupted": 1,
          "utd_requestable": 2,
        }),
        isTrue);
    expect(
        schema.validateEvent({
          "e": "timeline_crypto",
          "t": 1,
          "utd_at_open": 3,
          "utd_at_close": 2,
          "utd_reason": "The sender has not sent us the session key.",
        }),
        isFalse);
    expect(
        schema.validateEvent({
          "e": "sync_stats",
          "t": 1,
          "syncs": 30,
          "gap_worst_ms": 125000,
          "gaps_90s": 1,
        }),
        isTrue);
  });

  group("call_stats", () {
    lk.AudioReceiverStats audio(
        {required num packets,
        required num lost,
        required num bytes,
        required num concealed,
        required num concealments,
        required num jitter}) {
      final s = lk.AudioReceiverStats("stream", 0);
      s.packetsReceived = packets;
      s.packetsLost = lost;
      s.bytesReceived = bytes;
      s.concealedSamples = concealed;
      s.concealmentEvents = concealments;
      s.jitter = jitter;
      return s;
    }

    test("samples report the change since the previous one", () {
      final prev = TrackCounters();
      final first = CallSample()..elapsedMs = 60000;
      first.addAudioReceiver(
          audio(
              packets: 3000,
              lost: 10,
              bytes: 240000,
              concealed: 4800,
              concealments: 3,
              jitter: 0.012),
          prev);
      expect(first.rxPackets, 3000);
      expect(first.rxLost, 10);
      expect(first.rxConcealedMs, 100);
      expect(first.rxConcealments, 3);
      expect(first.rxJitterMs, 12);
      expect(first.fields()["rx_kbps"], 32);

      final second = CallSample()..elapsedMs = 60000;
      second.addAudioReceiver(
          audio(
              packets: 6000,
              lost: 12,
              bytes: 480000,
              concealed: 4800,
              concealments: 3,
              jitter: 0.004),
          prev);
      expect(second.rxPackets, 3000);
      expect(second.rxLost, 2);
      expect(second.rxConcealedMs, 0);
      expect(second.rxConcealments, 0);
      expect(second.rxJitterMs, 4);
    });

    test("a counter that went backwards (new stream) never goes negative", () {
      final prev = TrackCounters();
      final a = CallSample()..elapsedMs = 60000;
      a.addAudioReceiver(
          audio(
              packets: 5000,
              lost: 0,
              bytes: 1,
              concealed: 0,
              concealments: 0,
              jitter: 0),
          prev);
      final b = CallSample()..elapsedMs = 60000;
      b.addAudioReceiver(
          audio(
              packets: 100,
              lost: 0,
              bytes: 1,
              concealed: 0,
              concealments: 0,
              jitter: 0),
          prev);
      expect(b.rxPackets, 0);
    });

    test("sender stats: round trip, losses reported back, video size", () {
      final prev = TrackCounters();
      final s = lk.VideoSenderStats("stream", 0);
      s.packetsSent = 1200;
      s.packetsLost = 6;
      s.bytesSent = 600000;
      s.roundTripTime = 0.085;
      s.jitter = 0.002;
      s.frameHeight = 720;
      s.framesPerSecond = 29.7;
      s.qualityLimitationResolutionChanges = 2;
      final sample = CallSample()..elapsedMs = 60000;
      sample.addSender(s, prev);
      final f = sample.fields();
      expect(f["tx_rtt_ms"], 85);
      expect(f["tx_lost"], 6);
      expect(f["tx_jitter_ms"], 2);
      expect(f["tx_kbps"], 80);
      expect(f["video_tx_height"], 720);
      expect(f["video_tx_fps"], 30);
      expect(f["video_tx_limited"], 2);
      expect(f.containsKey("video_rx_fps"), isFalse);
    });

    test("the event is figures and a quality word, never a participant", () {
      final sample = CallSample()..elapsedMs = 60000;
      final ok = <String, Object?>{
        "e": "call_stats",
        "t": 60000,
        "quality": CallStats.quality(null),
        "minute": 1,
        "participants": 3,
        "remote_poor": 0,
        "encrypted": true,
        "screen_share": false,
        "reconnects": 0,
        ...sample.fields(),
      }..removeWhere((k, v) => v == null);
      expect(schema.validateEvent(ok.cast<String, Object>()), isTrue);
      expect(ok["quality"], "unknown");
      expect(
          schema.validateEvent(
              {...ok.cast<String, Object>(), "participant": "@a:nether.im"}),
          isFalse);
      expect(
          schema
              .validateEvent({...ok.cast<String, Object>(), "quality": "meh"}),
          isFalse);
      expect(
          schema.validateEvent({...ok.cast<String, Object>(), "sid": "TR_x"}),
          isFalse);
    });
  });
}

// A "$comment" next to an event's fields is documentation; the validator
// must neither treat it as a field nor crash on it (a crash here would
// surface in the code path that records the event, e.g. sending a message).
void commentTolerance() {
  final schema = TelemetrySchema.parse(jsonEncode({
    "version": 1,
    "limits": {"max_body_bytes": 1, "max_events": 1},
    "types": {
      "ms": {"type": "int", "min": 0, "max": 86400000}
    },
    "envelope": {},
    "events": {
      "x": {
        r"$comment": "a note",
        "n": {"type": "int", "min": 0, "max": 9, "required": true}
      }
    }
  }));
  expect(schema.validateEvent({"e": "x", "t": 1, "n": 3}), isTrue);
  expect(schema.validateEvent({"e": "x", "t": 1}), isFalse);
  expect(schema.validateEvent({"e": "x", "t": 1, "n": 3, r"$comment": "hi"}),
      isFalse);
}
