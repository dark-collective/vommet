// Vommet telemetry schema v32: first_sync says what the first sync response
// contained (bytes and counts, never ids, types or content) and where its
// apply time went (time to cleaningUp, summed database call time).

import 'dart:convert';
import 'dart:io';

import 'package:commet/telemetry/sync_stats.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  final source = File("assets/telemetry/schema.json").readAsStringSync();
  final schema = TelemetrySchema.parse(source);

  test("schema is v32 and still accepts v31", () {
    expect(schema.version, greaterThanOrEqualTo(32));
    expect((jsonDecode(source) as Map)["accepts"], contains(31));
  });

  Map<String, Object?> ev(String type, [String sender = "@a:example.org"]) => {
        "type": type,
        "event_id": "\$${type.hashCode}",
        "sender": sender,
        "origin_server_ts": 1,
        "content": {"body": "secret text"},
        if (type.startsWith("m.room.member")) "state_key": sender,
      };

  // Through JSON, so every map is typed the way a real response is.
  final update = matrix.SyncUpdate.fromJson(jsonDecode(jsonEncode({
    "next_batch": "s1",
    "rooms": {
      "join": {
        "!one:example.org": {
          "timeline": {
            "events": [ev("m.room.message"), ev("m.room.message")]
          },
          "state": {
            "events": [ev("m.room.member"), ev("m.room.member", "@b:x.org")]
          },
          "ephemeral": {
            "events": [
              {"type": "m.typing", "content": {}}
            ]
          },
          "account_data": {
            "events": [
              {"type": "m.fully_read", "content": {}}
            ]
          },
        },
        "!two:example.org": {
          "timeline": {"events": []},
          "state": {
            "events": [ev("m.room.member")]
          },
        },
      },
      "leave": {
        "!three:example.org": {
          "timeline": {
            "events": [ev("m.room.message")]
          },
        },
      },
      "invite": {
        "!four:example.org": {
          "invite_state": {
            "events": [
              {
                "type": "m.room.name",
                "state_key": "",
                "sender": "@c:x.org",
                "content": {"name": "Secret"}
              }
            ]
          },
        },
      },
    },
    "account_data": {
      "events": [
        {"type": "m.direct", "content": {}},
        {"type": "m.push_rules", "content": {}},
      ]
    },
    "presence": {
      "events": [
        {"type": "m.presence", "sender": "@a:example.org", "content": {}}
      ]
    },
    "to_device": {
      "events": [
        {"type": "m.room.encrypted", "sender": "@a:example.org", "content": {}},
        {"type": "m.room.encrypted", "sender": "@b:x.org", "content": {}},
        {"type": "m.room_key_request", "sender": "@b:x.org", "content": {}},
      ]
    },
    "device_lists": {
      "changed": ["@a:example.org", "@b:x.org"],
      "left": ["@c:x.org"],
    },
  })) as Map<String, Object?>);

  test("first sync counts each kind of thing, no ids or content", () {
    final counts = SyncStats.firstSyncCounts(update);
    expect(counts, {
      "rooms": 4,
      "timeline_rooms": 2,
      "timeline_events": 3,
      "state_events": 4,
      "ephemeral_events": 1,
      "room_account_data": 1,
      "account_data": 2,
      "presence": 1,
      "to_device": 3,
      "device_lists_changed": 2,
      "device_lists_left": 1,
    });
    expect(counts.values.every((v) => v >= 0), isTrue);
  });

  test("an empty response counts zero", () {
    final counts =
        SyncStats.firstSyncCounts(matrix.SyncUpdate(nextBatch: "s2"));
    expect(counts.values.every((v) => v == 0), isTrue);
  });

  test("first_sync with the v32 fields validates; ids do not", () {
    final event = {
      "e": "first_sync",
      "t": 38600,
      "request_at_ms": 900,
      "response_at_ms": 8200,
      "done_at_ms": 38600,
      "bytes": 4200000,
      ...SyncStats.firstSyncCounts(update),
      "save_ms": 27000,
      "db_ms": 24000,
      "db_calls": 15000,
    };
    expect(schema.validateEvent(event), isTrue);
    expect(schema.validateEvent({...event, "room_id": "!one:example.org"}),
        isFalse);
    expect(schema.validateEvent({...event, "rooms": -1}), isFalse);
    expect(schema.validateEvent({...event, "bytes": "4 MB"}), isFalse);
  });

  test("database totals only grow", () {
    final (calls, ms) = SyncStats.dbTotals();
    expect(calls, greaterThanOrEqualTo(0));
    expect(ms, greaterThanOrEqualTo(0));
  });
}
