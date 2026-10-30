// Vommet: startup work for an account the size of a heavy real one (~300
// rooms, ~30 spaces, some nested). A CPU profile of a Pinebook Pro launch put
// the spaces' top-level checks at ~9%, building a push rule evaluator per
// room at ~8% and the spaces' colour schemes at ~5% of the UI isolate before
// the first screen. Prints timings; asserts only that the results are right,
// so a slow CI machine can't fail it.
import 'package:commet/client/matrix/components/space_color_scheme/matrix_space_color_scheme_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_space.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

import 'roomlist_fixture.dart';

const roomCount = 300;
const spaceCount = 30;
const roomsPerSpace = 8;

/// Spaces 1..5 sit inside space 0, so they are not top level.
const nestedSpaces = 5;

String roomId(int i) => "!room$i:example.com";
String spaceId(int i) => "!space$i:example.com";

const mutedRoom = 5;
const mentionsRoom = 6;
const notifyRoom = 7;

matrix.BasicEvent pushRules({required bool groupChatsNotify}) =>
    matrix.BasicEvent(type: "m.push_rules", content: {
      "global": {
        "override": [
          {
            "rule_id": ".m.rule.master",
            "default": true,
            "enabled": false,
            "conditions": [],
            "actions": [],
          },
          {
            "rule_id": ".m.rule.suppress_notices",
            "default": true,
            "enabled": true,
            "conditions": [
              {
                "kind": "event_match",
                "key": "content.msgtype",
                "pattern": "m.notice"
              }
            ],
            "actions": [],
          },
          {
            "rule_id": roomId(mutedRoom),
            "default": false,
            "enabled": true,
            "conditions": [
              {
                "kind": "event_match",
                "key": "room_id",
                "pattern": roomId(mutedRoom)
              }
            ],
            "actions": [],
          },
        ],
        "content": [
          {
            "rule_id": ".m.rule.contains_user_name",
            "default": true,
            "enabled": true,
            "pattern": "me",
            "actions": [
              "notify",
              {"set_tweak": "highlight"}
            ],
          }
        ],
        "room": [
          {
            "rule_id": roomId(mentionsRoom),
            "default": false,
            "enabled": true,
            "actions": ["dont_notify"],
          },
          {
            "rule_id": roomId(notifyRoom),
            "default": false,
            "enabled": true,
            "actions": ["notify"],
          },
        ],
        "sender": [],
        "underride": [
          {
            "rule_id": ".m.rule.room_one_to_one",
            "default": true,
            "enabled": true,
            "conditions": [
              {"kind": "room_member_count", "is": "2"},
              {
                "kind": "event_match",
                "key": "type",
                "pattern": "m.room.message"
              }
            ],
            "actions": ["notify"],
          },
          for (final type in ["m.room.message", "m.room.encrypted"])
            {
              "rule_id": type == "m.room.message"
                  ? ".m.rule.message"
                  : ".m.rule.encrypted",
              "default": true,
              "enabled": true,
              "conditions": [
                {"kind": "event_match", "key": "type", "pattern": type}
              ],
              "actions": groupChatsNotify ? ["notify"] : [],
            },
        ],
      },
    });

double _ms(Duration d) => d.inMicroseconds / 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MatrixClient client;
  late List<MatrixSpace> spaces;

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
    client = await signedInClient("startup-benchmark");

    await sync(
      client,
      join: {
        for (var s = 0; s < spaceCount; s++)
          spaceId(s): joined(spaceId(s), children: [
            for (var r = 0; r < roomsPerSpace; r++)
              roomId(s * roomsPerSpace + r),
            if (s == 0)
              for (var n = 1; n <= nestedSpaces; n++) spaceId(n),
          ]),
        for (var r = 0; r < roomCount; r++) roomId(r): joined(roomId(r)),
      },
      accountData: [pushRules(groupChatsNotify: false)],
    );
    spaces = client.spaces.whereType<MatrixSpace>().toList();
  });

  tearDownAll(() => client.getMatrixClient().dispose(closeDatabase: true));

  test("spaces: top-level checks and refresh", () {
    expect(spaces.length, spaceCount);

    for (final space in spaces) {
      space.updateTopLevelStatus();
    }
    const runs = 20;
    final topLevel = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      for (final space in spaces) {
        space.updateTopLevelStatus();
      }
    }
    topLevel.stop();

    final refresh = Stopwatch()..start();
    for (var i = 0; i < runs; i++) {
      for (final space in spaces) {
        space.refresh();
      }
    }
    refresh.stop();
    debugPrint("BENCH top-level check, all $spaceCount spaces "
        "($roomCount rooms): ${(_ms(topLevel.elapsed) / runs).toStringAsFixed(3)} ms; "
        "refresh, all spaces: ${(_ms(refresh.elapsed) / runs).toStringAsFixed(3)} ms");

    for (var s = 0; s < spaceCount; s++) {
      final space = client.getSpace(spaceId(s))! as MatrixSpace;
      expect(space.isTopLevel, !(s >= 1 && s <= nestedSpaces),
          reason: spaceId(s));
    }
    expect(
      (client.getSpace(spaceId(0))! as MatrixSpace)
          .subspaces
          .map((s) => s.identifier)
          .toSet(),
      {for (var n = 1; n <= nestedSpaces; n++) spaceId(n)},
    );
    expect(
        client.getSpace(spaceId(2))!.rooms.map((r) => r.identifier).toSet(), {
      for (var r = 0; r < roomsPerSpace; r++) roomId(2 * roomsPerSpace + r)
    });
  });

  test("space colour schemes when spaces are created", () {
    final created = Stopwatch()..start();
    final components = [
      for (final space in spaces) MatrixSpaceColorSchemeComponent(client, space)
    ];
    created.stop();
    debugPrint("BENCH colour scheme components for $spaceCount spaces: "
        "${_ms(created.elapsed).toStringAsFixed(3)} ms");
    for (final c in components) {
      expect(c.scheme.primary, isNotNull);
    }
  });

  Future<Duration> pushRulesPass({required bool groupChatsNotify}) async {
    await sync(client,
        accountData: [pushRules(groupChatsNotify: groupChatsNotify)]);
    // One pass = every room working out its setting after the rules changed
    // (or at startup).
    final clock = Stopwatch()..start();
    for (final room in client.rooms) {
      room.pushRule;
    }
    clock.stop();
    return clock.elapsed;
  }

  void expectRules({required bool groupChatsNotify}) {
    for (var r = 0; r < roomCount; r++) {
      final expected = switch (r) {
        mutedRoom => PushRule.dontNotify,
        mentionsRoom => PushRule.mentionsOnly,
        notifyRoom => PushRule.notify,
        _ => groupChatsNotify ? PushRule.notify : PushRule.mentionsOnly,
      };
      expect(client.getRoom(roomId(r))!.pushRule, expected, reason: roomId(r));
    }
  }

  test("room notification settings (push rules)", () async {
    // First pass sets up each room's push rule listener.
    await pushRulesPass(groupChatsNotify: false);
    expectRules(groupChatsNotify: false);

    final times = <Duration>[];
    for (var i = 0; i < 6; i++) {
      times.add(await pushRulesPass(groupChatsNotify: i.isOdd));
      expectRules(groupChatsNotify: i.isOdd);
    }
    final avg = times.map(_ms).reduce((a, b) => a + b) / times.length;
    debugPrint("BENCH push rule setting for $roomCount rooms after a rules "
        "change: ${avg.toStringAsFixed(3)} ms per pass");
  });
}
