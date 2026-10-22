import 'dart:io';

import 'package:commet/client/matrix/nicknames/matrix_nicknames.dart';
import 'package:commet/client/matrix/nicknames/nickname_rules.dart';
import 'package:commet/telemetry/telemetry_schema.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

void main() {
  // Vommet issue 69: your own nickname per space and per room, with inheritance.
  final rules = NicknameRules.fromJson({
    "spaces": {"!outer": "Outer Name", "!inner": "Inner Name", "!blank": " "},
    "rooms": {"!override": "Room Name"},
  });

  test('room override wins', () {
    expect(rules.resolve("!override", ["!inner", "!outer"]),
        ("Room Name", NicknameSource.room, "!override"));
  });

  test('nearest space wins, then outer spaces', () {
    expect(rules.resolve("!r", ["!inner", "!outer"]),
        ("Inner Name", NicknameSource.space, "!inner"));
    expect(rules.resolve("!r", ["!other", "!outer"]),
        ("Outer Name", NicknameSource.space, "!outer"));
  });

  test('no rule: global name', () {
    expect(
        rules.resolve("!r", ["!other"]), (null, NicknameSource.global, null));
  });

  test('blank and malformed entries are ignored; round trip', () {
    expect(rules.spaces.containsKey("!blank"), isFalse);
    expect(
        NicknameRules.fromJson({
          "spaces": "x",
          "rooms": [1]
        }).isEmpty,
        isTrue);
    expect(NicknameRules.fromJson(null).isEmpty, isTrue);
    final again = NicknameRules.fromJson(rules.toJson());
    expect(again.spaces, rules.spaces);
    expect(again.rooms, rules.rooms);
  });

  group('member content', () {
    final current = {
      "membership": "join",
      "displayname": "Global",
      "avatar_url": "mxc://example.org/abc",
      "reason": "old kick reason",
    };

    test('writes the new name, keeps the avatar, drops the reason', () {
      expect(NicknameRules.updatedMemberContent(current, "Space Name"), {
        "membership": "join",
        "displayname": "Space Name",
        "avatar_url": "mxc://example.org/abc",
      });
    });

    test('nothing to write when the name is already shown', () {
      expect(NicknameRules.updatedMemberContent(current, "Global"), isNull);
    });

    test('nothing to write when not joined', () {
      expect(
          NicknameRules.updatedMemberContent(
              {...current, "membership": "leave"}, "Space Name"),
          isNull);
    });

    test('clearing a space only reverts rooms still showing it', () {
      final showing = {...current, "displayname": "Old Space Name"};
      expect(
          NicknameRules.updatedMemberContent(showing, "Global",
              onlyIfShowing: "Old Space Name")?["displayname"],
          "Global");
      expect(
          NicknameRules.updatedMemberContent(current, "Other",
              onlyIfShowing: "Old Space Name"),
          isNull);
    });

    test('no global name removes the displayname', () {
      expect(
          NicknameRules.updatedMemberContent(current, null)!
              .containsKey("displayname"),
          isFalse);
    });
  });

  // Telemetry: counts only, never which rooms or what names (schema v13).
  group('nickname_apply telemetry', () {
    final schema = TelemetrySchema.parse(
        File("assets/telemetry/schema.json").readAsStringSync());

    Map<String, Object> event(NicknameBatchStats stats, String trigger) => {
          "e": "nickname_apply",
          "t": 1000,
          "trigger": trigger,
          for (final f in stats.toFields().entries)
            if (f.value != null) f.key: f.value!,
          "space_rules": 2,
          "room_rules": 1,
          "ms": 5200,
        };

    test('a clean batch is valid', () {
      final stats = NicknameBatchStats()..rooms = 3;
      stats.count(NicknameApplyResult.written);
      stats.count(NicknameApplyResult.unchanged);
      stats.count(NicknameApplyResult.notJoined);
      final ev = event(stats, "space_set");
      expect(ev["outcome"], "ok");
      expect(schema.validateEvent(ev), isTrue);
    });

    test('a rate-limited failure keeps step, status and errcode only', () {
      final stats = NicknameBatchStats()
        ..rooms = 40
        ..failed = 3
        ..rateLimited = 5
        ..failStep = "write"
        ..firstError = matrix.MatrixException.fromJson({
          "errcode": "M_LIMIT_EXCEEDED",
          "error": "Too many requests in !secret:example.org",
        });
      final ev = event(stats, "global_change");
      expect(schema.validateEvent(ev), isTrue);
      expect(ev["outcome"], "error");
      expect(ev["errcode"], "M_LIMIT_EXCEEDED");
      expect(ev.values.whereType<String>().any((v) => v.contains("!secret")),
          isFalse);
    });

    test('room ids, names and unknown triggers are rejected', () {
      final ev = event(NicknameBatchStats(), "join");
      for (final (key, value) in <(String, Object)>[
        ("room_id", "!a:example.org"),
        ("nickname", "Captain Juniper"),
        ("trigger", "rename"),
        ("fail_step", "!a:example.org"),
        ("written", "3"),
      ]) {
        expect(schema.validateEvent({...ev, key: value}), isFalse,
            reason: "$key=$value");
      }
    });
  });
}
