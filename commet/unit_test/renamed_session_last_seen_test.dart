import 'package:commet/ui/pages/settings/categories/account/security/matrix/session/renamed_session_last_seen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vommet: a homeserver that stamps a renamed session as used "now" doesn't
// make an offline session show "Active now".

const user = "@me:example.org";

Device device(String id, int? ts, [String? ip]) =>
    Device(deviceId: id, lastSeenTs: ts, lastSeenIp: ip);

void main() {
  group("restoreRenamedLastSeen", () {
    test("puts back the last-seen the rename stamped over", () {
      final records = {
        renamedSessionKey(user, "OLD"):
            RenamedSessionRecord(lastSeenTs: 1000, lastSeenIp: "10.0.0.1"),
      };
      final stamped = device("OLD", 9000, "10.0.0.9");
      expect(restoreRenamedLastSeen(user, [stamped], records), isTrue);
      expect(stamped.lastSeenTs, 1000);
      expect(stamped.lastSeenIp, "10.0.0.1");
      expect(records[renamedSessionKey(user, "OLD")]!.stampedTs, 9000);

      // Reloaded later (or after a restart): still the stamp, still undone.
      final again = device("OLD", 9000, "10.0.0.9");
      expect(restoreRenamedLastSeen(user, [again], records), isFalse);
      expect(again.lastSeenTs, 1000);
    });

    test("drops the record once the session is used again", () {
      final records = {
        renamedSessionKey(user, "OLD"): RenamedSessionRecord(
            lastSeenTs: 1000, lastSeenIp: "10.0.0.1", stampedTs: 9000),
      };
      final used = device("OLD", 12000, "10.0.0.2");
      expect(restoreRenamedLastSeen(user, [used], records), isTrue);
      expect(used.lastSeenTs, 12000);
      expect(used.lastSeenIp, "10.0.0.2");
      expect(records, isEmpty);
    });

    test("a server that leaves last-seen alone needs nothing", () {
      final records = {
        renamedSessionKey(user, "OLD"):
            RenamedSessionRecord(lastSeenTs: 1000, lastSeenIp: "10.0.0.1"),
      };
      final same = device("OLD", 1000, "10.0.0.1");
      expect(restoreRenamedLastSeen(user, [same], records), isTrue);
      expect(same.lastSeenTs, 1000);
      expect(records, isEmpty);
    });

    test("forgets signed-out sessions of this account only", () {
      final records = {
        renamedSessionKey(user, "GONE"): RenamedSessionRecord(lastSeenTs: 1),
        renamedSessionKey("@other:example.org", "X"):
            RenamedSessionRecord(lastSeenTs: 1),
      };
      expect(restoreRenamedLastSeen(user, [device("NEW", 5)], records), isTrue);
      expect(records.keys, [renamedSessionKey("@other:example.org", "X")]);
    });
  });

  group("RenamedSessionLastSeen", () {
    test("survives a restart and undoes a failed rename", () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final first = await RenamedSessionLastSeen(prefs)
          .remember(user, device("OLD", 1000, "10.0.0.1"));
      expect(first, isNull);

      final list = [device("OLD", 9000, "10.0.0.9")];
      await RenamedSessionLastSeen(prefs).restore(user, list);
      expect(list.single.lastSeenTs, 1000);

      // Renamed again (the list already shows the restored value) and the
      // rename fails: the first record, with its stamp, comes back.
      final store = RenamedSessionLastSeen(prefs);
      final earlier = await store.remember(user, list.single);
      expect(earlier!.stampedTs, 9000);
      await store.undo(user, "OLD", earlier);

      final reloaded = [device("OLD", 9000, "10.0.0.9")];
      await RenamedSessionLastSeen(prefs).restore(user, reloaded);
      expect(reloaded.single.lastSeenTs, 1000);
      expect(reloaded.single.lastSeenIp, "10.0.0.1");
    });

    test("a second rename keeps the first real values", () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = RenamedSessionLastSeen(prefs);
      await store.remember(user, device("OLD", 1000, "10.0.0.1"));
      await store.restore(user, [device("OLD", 9000, "10.0.0.9")]);
      await store.remember(user, device("OLD", 1000, "10.0.0.1"));

      final list = [device("OLD", 9500, "10.0.0.9")];
      await store.restore(user, list);
      expect(list.single.lastSeenTs, 1000);
    });
  });
}
