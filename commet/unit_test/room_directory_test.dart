import 'dart:async';

import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:commet/utils/room_directory/directory_pager.dart';
import 'package:commet/utils/room_directory/directory_servers.dart';
import 'package:test/test.dart';

DirectoryEntry room(String id) => DirectoryEntry(roomId: id);

void main() {
  group("DirectoryServers.normalize", () {
    test("plain names", () {
      expect(DirectoryServers.normalize("matrix.org"), "matrix.org");
      expect(DirectoryServers.normalize("  Matrix.ORG "), "matrix.org");
      expect(
          DirectoryServers.normalize("example.org:8448"), "example.org:8448");
    });

    test("urls, ids and aliases", () {
      expect(DirectoryServers.normalize("https://matrix.org/"), "matrix.org");
      expect(DirectoryServers.normalize("https://matrix.org/_matrix/client"),
          "matrix.org");
      expect(DirectoryServers.normalize("@me:tchncs.de"), "tchncs.de");
      expect(DirectoryServers.normalize("#room:gnome.org"), "gnome.org");
      expect(DirectoryServers.normalize("matrix.org."), "matrix.org");
      expect(DirectoryServers.normalize("[::1]:8448"), "[::1]:8448");
    });

    test("rejects junk", () {
      expect(DirectoryServers.normalize(""), isNull);
      expect(DirectoryServers.normalize("   "), isNull);
      expect(DirectoryServers.normalize("not a server"), isNull);
      expect(DirectoryServers.normalize("@nocolon"), isNull);
      expect(DirectoryServers.normalize("-bad.org"), isNull);
      expect(DirectoryServers.normalize("example.org:99999"), isNull);
      expect(DirectoryServers.normalize("example.org:0"), isNull);
    });
  });

  group("DirectoryServers saved list", () {
    test("touch moves to front without duplicates", () {
      var saved = ["a.org", "b.org", "c.org"];
      expect(
          DirectoryServers.touch(saved, "c.org"), ["c.org", "a.org", "b.org"]);
      expect(DirectoryServers.touch(saved, "d.org"),
          ["d.org", "a.org", "b.org", "c.org"]);
    });

    test("touch caps the list", () {
      var saved = List.generate(DirectoryServers.maxSaved, (i) => "s$i.org");
      var result = DirectoryServers.touch(saved, "new.org");
      expect(result.length, DirectoryServers.maxSaved);
      expect(result.first, "new.org");
      expect(result.contains("s${DirectoryServers.maxSaved - 1}.org"), isFalse);
    });

    test("remove", () {
      expect(DirectoryServers.remove(["a.org", "b.org"], "a.org"), ["b.org"]);
    });
  });

  group("DirectoryServers.sections", () {
    test("each server appears once, own first", () {
      var s = DirectoryServers.sections(
        own: ["nether.im", "matrix.org"],
        saved: ["matrix.org", "envs.net"],
        suggestions: ["matrix.org", "gnome.org"],
      );
      expect(s.own, ["nether.im", "matrix.org"]);
      expect(s.saved, ["envs.net"]);
      expect(s.suggested, ["gnome.org"]);
      expect(s.customServer, isNull);
    });

    test("a long saved list stays capped", () {
      var saved = List.generate(30, (i) => "s$i.org");
      var s = DirectoryServers.sections(
          own: ["home.org"], saved: saved, perSection: 5);
      expect(s.saved.length, 5);
      expect(s.hiddenSaved, 25);
    });

    test("search narrows sections and hides suggestions", () {
      var s = DirectoryServers.sections(
        own: ["home.org"],
        saved: ["s1.org", "s12.org", "other.net"],
        search: "s1",
      );
      expect(s.own, isEmpty);
      expect(s.saved, ["s1.org", "s12.org"]);
      expect(s.suggested, isEmpty);
    });

    test("search can reach saved servers beyond the cap", () {
      var saved = List.generate(30, (i) => "s$i.org");
      var s = DirectoryServers.sections(
          own: ["home.org"], saved: saved, search: "s29");
      expect(s.saved, ["s29.org"]);
    });

    test("typed server name is offered unless already known", () {
      expect(
          DirectoryServers.sections(
                  own: ["home.org"], saved: [], search: "https://New.org")
              .customServer,
          "new.org");
      expect(
          DirectoryServers.sections(
                  own: ["home.org"], saved: ["new.org"], search: "new.org")
              .customServer,
          isNull);
      expect(
          DirectoryServers.sections(
                  own: ["home.org"], saved: [], search: "not valid")
              .customServer,
          isNull);
    });

    test("suggestions can be dismissed", () {
      var s = DirectoryServers.sections(
          own: ["home.org"], saved: [], showSuggestions: false);
      expect(s.suggested, isEmpty);
    });
  });

  group("DirectoryAccounts", () {
    const a = DirectoryAccount("a", "nether.im");
    const b = DirectoryAccount("b", "matrix.org");
    const b2 = DirectoryAccount("b2", "matrix.org");
    final all = [a, b, b2];

    test("own server is a local query", () {
      var plan = DirectoryAccounts.plan("nether.im", a, all);
      expect(plan.account, a);
      expect(plan.isLocal, isTrue);
    });

    test("another account on the server is used locally", () {
      var plan = DirectoryAccounts.plan("matrix.org", a, all);
      expect(plan.account, b);
      expect(plan.isLocal, isTrue);
    });

    test("joining account wins among several on the same server", () {
      var plan = DirectoryAccounts.plan("matrix.org", b2, all);
      expect(plan.account, b2);
      expect(plan.isLocal, isTrue);
    });

    test("no account there: federated query through the joining account", () {
      var plan = DirectoryAccounts.plan("gnome.org", a, all);
      expect(plan.account, a);
      expect(plan.serverParam, "gnome.org");
    });

    test("own servers are listed once, current first", () {
      expect(DirectoryAccounts.ownServers(b, all), ["matrix.org", "nether.im"]);
    });

    test("join failure suggests an account on the room's server", () {
      expect(
          DirectoryAccounts.suggestAfterJoinFailure("matrix.org", a, all), b);
      expect(DirectoryAccounts.suggestAfterJoinFailure("gnome.org", a, all),
          isNull);
      expect(DirectoryAccounts.suggestAfterJoinFailure("matrix.org", b, all),
          isNull);
    });
  });

  group("DirectoryErrors.classify", () {
    DirectoryProblemKind c(int? status, String? code,
            {bool local = false, bool? alive}) =>
        DirectoryErrors.classify(
            statusCode: status,
            errcode: code,
            isLocal: local,
            serverAlive: alive);

    test("own server refusing its members", () {
      expect(c(403, "M_FORBIDDEN", local: true),
          DirectoryProblemKind.ownServerRestricted);
      expect(c(500, "M_UNKNOWN", local: true), DirectoryProblemKind.failed);
      expect(c(null, null, local: true), DirectoryProblemKind.failed);
    });

    test("Tuwunel's 502 is told apart by the probe", () {
      expect(c(502, "M_CONNECTION_FAILED", alive: true),
          DirectoryProblemKind.remoteNotShared);
      expect(c(502, "M_CONNECTION_FAILED", alive: false),
          DirectoryProblemKind.unreachable);
      expect(c(502, "M_CONNECTION_FAILED"), DirectoryProblemKind.failed);
    });

    test("remote 403 means not shared unless the server is dead", () {
      expect(c(403, "M_FORBIDDEN"), DirectoryProblemKind.remoteNotShared);
      expect(c(403, "M_FORBIDDEN", alive: true),
          DirectoryProblemKind.remoteNotShared);
      expect(c(403, "M_FORBIDDEN", alive: false),
          DirectoryProblemKind.unreachable);
    });

    test("our own server failing is not blamed on the remote", () {
      expect(c(null, null, alive: true), DirectoryProblemKind.failed);
      expect(c(500, "M_UNKNOWN", alive: false), DirectoryProblemKind.failed);
    });
  });

  group("DirectoryPager", () {
    test("pages until the server stops, skipping repeats", () async {
      var pages = {
        null: DirectoryPage([room("1"), room("2")], nextBatch: "p2"),
        "p2": DirectoryPage([room("2"), room("3")], nextBatch: "p3"),
        "p3": DirectoryPage([room("4")]),
      };
      var asked = <String?>[];
      var pager = DirectoryPager()
        ..reset((since) async {
          asked.add(since);
          return pages[since]!;
        });

      expect(pager.hasMore, isTrue);
      while (await pager.loadMore()) {}
      expect(asked, [null, "p2", "p3"]);
      expect(pager.entries.map((e) => e.roomId), ["1", "2", "3", "4"]);
      expect(pager.hasMore, isFalse);
      expect(pager.isEmpty, isFalse);
    });

    test("a token that doesn't move stops paging", () async {
      var calls = 0;
      var pager = DirectoryPager()
        ..reset((since) async {
          calls++;
          return DirectoryPage([room("r$calls")], nextBatch: "same");
        });
      while (await pager.loadMore()) {}
      expect(calls, 2);
      expect(pager.hasMore, isFalse);
    });

    test("empty directory", () async {
      var pager = DirectoryPager()..reset((_) async => const DirectoryPage([]));
      expect(pager.isEmpty, isFalse);
      await pager.loadMore();
      expect(pager.isEmpty, isTrue);
    });

    test("errors are kept and the page can be retried", () async {
      var fail = true;
      var pager = DirectoryPager()
        ..reset((_) async {
          if (fail) {
            throw const DirectoryException(
                DirectoryProblemKind.unreachable, "x.org");
          }
          return DirectoryPage([room("1")]);
        });
      expect(await pager.loadMore(), isFalse);
      expect(pager.error, isA<DirectoryException>());
      expect(pager.isEmpty, isFalse);
      fail = false;
      expect(await pager.loadMore(), isTrue);
      expect(pager.error, isNull);
      expect(pager.entries.length, 1);
    });

    test("a slow answer to an old query is dropped after reset", () async {
      var slow = Completer<DirectoryPage>();
      var pager = DirectoryPager()..reset((_) => slow.future);
      var first = pager.loadMore();
      expect(pager.loading, isTrue);
      expect(await pager.loadMore(), isFalse, reason: "no double loading");

      pager.reset((_) async => DirectoryPage([room("new")]));
      expect(pager.loading, isFalse);
      await pager.loadMore();

      slow.complete(DirectoryPage([room("old")]));
      expect(await first, isFalse);
      expect(pager.entries.map((e) => e.roomId), ["new"]);
    });
  });
}
