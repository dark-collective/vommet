import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/ui/pages/room_directory/directory_account_handle.dart';
import 'package:commet/ui/pages/room_directory/room_directory_page.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class Query {
  final String? server;
  final String? search;
  final DirectoryTypeFilter type;
  final String? since;
  Query(this.server, this.search, this.type, this.since);

  @override
  String toString() => "Query($server, $search, $type, $since)";
}

/// A directory backed by a list of rooms per server name ("" = own).
class FakeDirectory implements RoomDirectoryComponent<Client> {
  FakeDirectory(this.homeserverName, this.rooms, {this.pageSize = 2});

  @override
  final String homeserverName;
  final Map<String, List<DirectoryEntry>> rooms;
  final int pageSize;
  final Map<String, DirectoryProblemKind> problems = {};
  final Map<String, DirectoryDetails> detailsById = {};
  final List<Query> queries = [];
  final List<String> detailRequests = [];

  @override
  Client get client => throw UnimplementedError();

  @override
  Future<DirectoryPage> query(
      {String? server,
      String? search,
      DirectoryTypeFilter type = DirectoryTypeFilter.all,
      String? since,
      int limit = 30}) async {
    queries.add(Query(server, search, type, since));
    var name = server ?? homeserverName;
    var problem = problems[name];
    if (problem != null) throw DirectoryException(problem, name);

    var list = (rooms[name] ?? []).where((r) {
      if (type == DirectoryTypeFilter.rooms && r.isSpace) return false;
      if (type == DirectoryTypeFilter.spaces && !r.isSpace) return false;
      if (search != null &&
          search.isNotEmpty &&
          !r.displayName.toLowerCase().contains(search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    var start = since == null ? 0 : int.parse(since);
    var end = (start + pageSize).clamp(0, list.length);
    return DirectoryPage(list.sublist(start, end),
        nextBatch: end < list.length ? "$end" : null);
  }

  @override
  Future<DirectoryDetails> details(DirectoryEntry entry, {String? via}) async {
    detailRequests.add(entry.roomId);
    return detailsById[entry.roomId] ?? const DirectoryDetails();
  }

  @override
  ImageProvider? image(Uri? url, {bool banner = false}) => null;
}

class FakeAccount {
  FakeAccount(String id, String homeserver, this.directory,
      {this.failJoins = false})
      : account = DirectoryAccount(id, homeserver);

  final DirectoryAccount account;
  final FakeDirectory directory;
  final bool failJoins;
  final Set<String> joinedRooms = {};
  final List<(String, String)> joins = [];
  final List<String> opened = [];

  DirectoryAccountHandle get handle => DirectoryAccountHandle(
        account: account,
        userId: "@${account.id}:${account.homeserver}",
        displayName: account.id,
        directory: directory,
        isJoined: joinedRooms.contains,
        join: (entry, server) async {
          joins.add((entry.roomId, server));
          if (failJoins) throw Exception("M_FORBIDDEN");
          joinedRooms.add(entry.roomId);
        },
        open: (entry) => opened.add(entry.roomId),
      );
}

DirectoryEntry room(String id, String name,
        {bool space = false, int members = 1, String? topic}) =>
    DirectoryEntry(
        roomId: "!$id",
        name: name,
        isSpace: space,
        memberCount: members,
        topic: topic);

final ownRooms = [
  room("cats", "Cats", members: 50, topic: "All about cats"),
  room("space", "Pet Space", space: true, members: 40),
  room("dogs", "Dogs", members: 30),
];

Widget app(List<FakeAccount> accounts, {DirectoryServerStore? store}) {
  return MaterialApp(
    theme: ThemeDark.theme,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1000, 800)),
      child: RoomDirectoryPage(
        accounts: accounts.map((a) => a.handle).toList(),
        store: store ?? MemoryDirectoryServerStore(),
        searchDebounce: Duration.zero,
        pageSize: 2,
      ),
    ),
  );
}

Finder rowFor(String id) => find.byKey(ValueKey("directory_row_!$id"));

Future<void> chooseServer(WidgetTester tester, String server) async {
  await tester.tap(find.byKey(const ValueKey("directory_server_button")));
  await tester.pumpAndSettle();
  var tile = find.byKey(ValueKey("directory_server_$server"));
  if (tile.evaluate().isEmpty) {
    await tester.enterText(
        find.byKey(const ValueKey("directory_server_search")), server);
    await tester.pumpAndSettle();
    tile = find.byKey(const ValueKey("directory_server_custom"));
  }
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  late FakeDirectory nether;
  late FakeAccount a;

  setUp(() {
    nether = FakeDirectory("nether.im", {"nether.im": ownRooms});
    a = FakeAccount("a", "nether.im", nether);
  });

  testWidgets("loads the own server's directory, all pages", (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();

    expect(rowFor("cats"), findsOneWidget);
    expect(rowFor("space"), findsOneWidget);
    expect(rowFor("dogs"), findsOneWidget);
    expect(nether.queries.first.server, isNull, reason: "local query");
    expect(nether.queries.map((q) => q.since), [null, "2"]);
    // no account picker with one account
    expect(
        find.byKey(const ValueKey("directory_account_picker")), findsNothing);
  });

  testWidgets("type filter and search re-query the server", (tester) async {
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Spaces"));
    await tester.pumpAndSettle();
    expect(nether.queries.last.type, DirectoryTypeFilter.spaces);
    expect(rowFor("space"), findsOneWidget);
    expect(rowFor("cats"), findsNothing);

    await tester.tap(find.text("All"));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey("directory_search")), "dog");
    await tester.pumpAndSettle();
    expect(nether.queries.last.search, "dog");
    expect(rowFor("dogs"), findsOneWidget);
    expect(rowFor("cats"), findsNothing);

    await tester.enterText(
        find.byKey(const ValueKey("directory_search")), "zebra");
    await tester.pumpAndSettle();
    expect(find.text("Nothing matches “zebra”."), findsOneWidget);
  });

  testWidgets("empty directory", (tester) async {
    var empty = FakeAccount("e", "empty.org", FakeDirectory("empty.org", {}));
    await tester.pumpWidget(app([empty]));
    await tester.pumpAndSettle();
    expect(find.text("This server has no public rooms or spaces yet."),
        findsOneWidget);
  });

  // Vommet: the empty message follows the Rooms / Spaces filter.
  testWidgets("empty directory message follows the filter", (tester) async {
    var empty = FakeAccount("e", "empty.org", FakeDirectory("empty.org", {}));
    await tester.pumpWidget(app([empty]));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Spaces"));
    await tester.pumpAndSettle();
    expect(find.text("This server has no public spaces yet."), findsOneWidget);

    await tester.tap(find.text("Rooms"));
    await tester.pumpAndSettle();
    expect(find.text("This server has no public rooms yet."), findsOneWidget);
  });

  testWidgets("a row expands with details and collapses again", (tester) async {
    nether.detailsById["!space"] = const DirectoryDetails(
      topic: "Everything pets",
      encrypted: true,
      children: [
        DirectoryChild(roomId: "!c1", name: "Hamsters", memberCount: 3),
        DirectoryChild(roomId: "!c2", name: "Parrots", memberCount: 4),
      ],
    );
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();

    expect(find.text("Everything pets"), findsNothing);
    await tester.tap(find.byKey(const ValueKey("directory_row_header_!space")));
    await tester.pumpAndSettle();

    expect(nether.detailRequests, ["!space"]);
    expect(find.text("Everything pets"), findsOneWidget);
    expect(find.text("Hamsters"), findsOneWidget);
    expect(find.text("Parrots"), findsOneWidget);
    expect(find.text("2 rooms"), findsOneWidget);
    expect(find.text("Encrypted"), findsOneWidget);

    // only one row open at a time
    await tester.tap(find.byKey(const ValueKey("directory_row_header_!cats")));
    await tester.pumpAndSettle();
    expect(find.text("Hamsters"), findsNothing);
    expect(find.text("No description"), findsNothing);
    expect(find.text("All about cats"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("directory_row_header_!cats")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("directory_join_failed_!cats")),
        findsNothing);
    // collapsed rows show a one-line topic and the compact join button
    expect(find.byKey(const ValueKey("directory_join_!cats")), findsOneWidget);
  });

  testWidgets("join goes through the joining account, joined shows Open",
      (tester) async {
    a.joinedRooms.add("!dogs");
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey("directory_open_!dogs")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("directory_open_!dogs")));
    expect(a.opened, ["!dogs"]);

    await tester.tap(find.byKey(const ValueKey("directory_join_!cats")));
    await tester.pumpAndSettle();
    expect(a.joins, [("!cats", "nether.im")]);
  });

  testWidgets("remote server that doesn't share its directory", (tester) async {
    nether.problems["kde.org"] = DirectoryProblemKind.remoteNotShared;
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();

    await chooseServer(tester, "kde.org");
    expect(nether.queries.last.server, "kde.org");
    expect(find.byKey(const ValueKey("directory_problem_remoteNotShared")),
        findsOneWidget);
    expect(
        find.text("kde.org doesn't share its room directory with other "
            "servers."),
        findsOneWidget);
  });

  testWidgets("own server restricting its directory has its own warning",
      (tester) async {
    nether.problems["nether.im"] = DirectoryProblemKind.ownServerRestricted;
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("directory_problem_ownServerRestricted")),
        findsOneWidget);
  });

  testWidgets("unreachable server, then retry", (tester) async {
    nether.problems["nowhere.invalid"] = DirectoryProblemKind.unreachable;
    await tester.pumpWidget(app([a]));
    await tester.pumpAndSettle();
    await chooseServer(tester, "nowhere.invalid");
    expect(find.byKey(const ValueKey("directory_problem_unreachable")),
        findsOneWidget);

    nether.problems.remove("nowhere.invalid");
    nether.rooms["nowhere.invalid"] = [room("back", "Back online")];
    await tester.tap(find.text("Try again"));
    await tester.pumpAndSettle();
    expect(rowFor("back"), findsOneWidget);
  });

  testWidgets("another account on the server browses it locally",
      (tester) async {
    var matrixOrg = FakeDirectory("matrix.org", {
      "matrix.org": [room("hq", "Matrix HQ", members: 9000)]
    });
    var b = FakeAccount("b", "matrix.org", matrixOrg);
    await tester.pumpWidget(app([a, b]));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey("directory_account_picker")), findsOneWidget);
    await chooseServer(tester, "matrix.org");

    expect(matrixOrg.queries.last.server, isNull, reason: "local to b");
    expect(nether.queries.where((q) => q.server == "matrix.org"), isEmpty);
    expect(find.text("via @b:matrix.org"), findsOneWidget);
    expect(rowFor("hq"), findsOneWidget);

    // joining still uses the selected joining account (a)
    await tester.tap(find.byKey(const ValueKey("directory_join_!hq")));
    await tester.pumpAndSettle();
    expect(a.joins, [("!hq", "matrix.org")]);
    expect(b.joins, isEmpty);
  });

  testWidgets("a failed join suggests the account on the room's server",
      (tester) async {
    var matrixOrg = FakeDirectory("matrix.org", {
      "matrix.org": [room("hq", "Matrix HQ")]
    });
    a = FakeAccount("a", "nether.im", nether, failJoins: true);
    var b = FakeAccount("b", "matrix.org", matrixOrg);
    await tester.pumpWidget(app([a, b]));
    await tester.pumpAndSettle();
    await chooseServer(tester, "matrix.org");

    await tester.tap(find.byKey(const ValueKey("directory_row_header_!hq")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("directory_join_!hq")));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey("directory_join_failed_!hq")),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("directory_join_as_!hq")));
    await tester.pumpAndSettle();
    expect(b.joins, [("!hq", "matrix.org")]);
  });

  group("server chooser", () {
    testWidgets("long saved list stays capped and searchable", (tester) async {
      var store = MemoryDirectoryServerStore(
          saved: List.generate(20, (i) => "s$i.org"));
      await tester.pumpWidget(app([a], store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("directory_server_button")));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey("directory_server_s0.org")),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey("directory_server_s19.org")), findsNothing);
      expect(find.text("15 more, type to search"), findsOneWidget);
      expect(find.byKey(const ValueKey("directory_server_matrix.org")),
          findsOneWidget,
          reason: "suggested");

      await tester.enterText(
          find.byKey(const ValueKey("directory_server_search")), "s19");
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("directory_server_s19.org")),
          findsOneWidget);
      expect(find.byKey(const ValueKey("directory_server_matrix.org")),
          findsNothing,
          reason: "suggestions hide while searching");
    });

    testWidgets("remove a saved server, hide suggestions", (tester) async {
      var store = MemoryDirectoryServerStore(saved: ["old.org"]);
      await tester.pumpWidget(app([a], store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("directory_server_button")));
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const ValueKey("directory_server_remove_old.org")));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      expect(
          find.byKey(const ValueKey("directory_server_old.org")), findsNothing);

      await tester
          .tap(find.byKey(const ValueKey("directory_server_hide_suggested")));
      await tester.pumpAndSettle();
      expect(store.showSuggestions, isFalse);
      expect(find.byKey(const ValueKey("directory_server_matrix.org")),
          findsNothing);
    });

    testWidgets("browse and save a typed server", (tester) async {
      var store = MemoryDirectoryServerStore();
      nether.rooms["new.org"] = [room("n", "New room")];
      await tester.pumpWidget(app([a], store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("directory_server_button")));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("directory_server_search")),
          "https://New.org/");
      await tester.pumpAndSettle();
      expect(find.text("Browse new.org"), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey("directory_server_custom_save")));
      await tester.pumpAndSettle();
      expect(store.saved, ["new.org"]);
      expect(rowFor("n"), findsOneWidget);

      // the bookmark in the header un-saves it
      await tester.tap(find.byKey(const ValueKey("directory_save_server")));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
    });
  });
}
