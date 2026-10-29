import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_power_levels.dart';
import 'package:test/test.dart';

void main() {
  group("resolvePermissionLevel", () {
    final content = <String, Object?>{
      "state_default": 75,
      "events_default": 10,
      "invite": 25,
      "events": {"m.room.name": 60},
      "notifications": {"room": 20},
    };

    test("explicit values win", () {
      expect(resolvePermissionLevel(content, key: "invite"), 25);
      expect(
          resolvePermissionLevel(content, key: "m.room.name", parent: "events"),
          60);
      expect(
          resolvePermissionLevel(content, key: "room", parent: "notifications"),
          20);
    });

    test("unset event types fall back by kind", () {
      expect(
          resolvePermissionLevel(content,
              key: "m.room.tombstone", parent: "events"),
          75);
      expect(
          resolvePermissionLevel(content,
              key: "m.reaction", parent: "events", isStateEvent: false),
          10);
    });

    test("unset top-level keys use the spec defaults", () {
      final empty = <String, Object?>{};
      expect(resolvePermissionLevel(empty, key: "invite"), 0);
      expect(resolvePermissionLevel(empty, key: "kick"), 50);
      expect(resolvePermissionLevel(empty, key: "ban"), 50);
      expect(resolvePermissionLevel(empty, key: "events_default"), 0);
      expect(resolvePermissionLevel(empty, key: "state_default"), 50);
      expect(
          resolvePermissionLevel(empty,
              key: "m.room.encryption", parent: "events"),
          50);
      expect(
          resolvePermissionLevel(empty, key: "room", parent: "notifications"),
          50);
    });
  });

  group("powerLevelsWithUserLevel", () {
    test("sets and resets without touching the original", () {
      final content = <String, Object?>{
        "users": {"@a:example.org": 100},
        "ban": 50,
      };
      final set = powerLevelsWithUserLevel(content, "@b:example.org", 50);
      expect(set["users"], {"@a:example.org": 100, "@b:example.org": 50});
      expect(content["users"], {"@a:example.org": 100});

      final reset = powerLevelsWithUserLevel(set, "@a:example.org", null);
      expect(reset["users"], {"@b:example.org": 50});
      expect(reset["ban"], 50);
    });

    test("creates a missing users map", () {
      final out = powerLevelsWithUserLevel({}, "@a:example.org", 50);
      expect(out["users"], {"@a:example.org": 50});
    });
  });

  test("powerLevelsWithPermissions writes nested and top-level keys", () {
    final content = <String, Object?>{
      "events": {"m.room.name": 50},
    };
    final out = powerLevelsWithPermissions(content, {
      ("events", "m.room.pinned_events"): 0,
      (null, "invite"): 50,
    });
    expect(out["events"], {"m.room.name": 50, "m.room.pinned_events": 0});
    expect(out["invite"], 50);
    expect(content["events"], {"m.room.name": 50});
  });

  test("privilegedUsers skips default levels and lists creators first", () {
    final content = <String, Object?>{
      "users_default": 0,
      "users": {
        "@member:example.org": 0,
        "@mod:example.org": 50,
        "@admin:example.org": 100,
        "@creator:example.org": 100,
        "@muted:example.org": -1,
      },
    };
    final list = privilegedUsers(content, creators: {"@creator:example.org"});
    expect(list.map((u) => u.userId).toList(), [
      "@creator:example.org",
      "@admin:example.org",
      "@mod:example.org",
      "@muted:example.org",
    ]);
    expect(list.first.isCreator, isTrue);
  });

  group("guards", () {
    test("only yourself or people below you", () {
      expect(
          canChangeUserLevel(
              canEditPowerLevels: true,
              ownLevel: 50,
              targetLevel: 50,
              isSelf: false),
          isFalse);
      expect(
          canChangeUserLevel(
              canEditPowerLevels: true,
              ownLevel: 50,
              targetLevel: 50,
              isSelf: true),
          isTrue);
      expect(
          canChangeUserLevel(
              canEditPowerLevels: true,
              ownLevel: 100,
              targetLevel: 50,
              isSelf: false),
          isTrue);
      expect(
          canChangeUserLevel(
              canEditPowerLevels: false,
              ownLevel: 100,
              targetLevel: 50,
              isSelf: false),
          isFalse);
      expect(
          canChangeUserLevel(
              canEditPowerLevels: true,
              ownLevel: creatorPowerLevel,
              targetLevel: creatorPowerLevel,
              isSelf: false,
              isTargetCreator: true),
          isFalse);
    });

    test("no raising above your own level", () {
      expect(canAssignLevel(ownLevel: 50, newLevel: 50), isTrue);
      expect(canAssignLevel(ownLevel: 50, newLevel: 100), isFalse);
    });

    test("self demotion is detected", () {
      expect(isSelfDemotion(isSelf: true, currentLevel: 100, newLevel: 50),
          isTrue);
      expect(isSelfDemotion(isSelf: false, currentLevel: 100, newLevel: 50),
          isFalse);
      expect(isSelfDemotion(isSelf: true, currentLevel: 50, newLevel: 100),
          isFalse);
    });
  });
}
