// Vommet issue 362: the search field above the direct messages list.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_aggregator.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/organisms/home_screen/dm_search.dart';
import 'package:commet/ui/organisms/home_screen/important_rooms_list.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Member extends Fake implements Member {
  _Member(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
}

class _Dms extends Fake implements DirectMessagesComponent {
  final partners = <String, String>{};
  @override
  String? getDirectMessagePartnerId(Room room) => partners[room.identifier];
}

class _Client extends Fake implements Client {
  final dms = _Dms();
  @override
  T? getComponent<T extends Component>() => dms is T ? dms as T : null;
}

class _Room extends Fake implements Room {
  _Room(this.client, this.identifier, this.displayName,
      {this.isFavorite = false, Member? partner}) {
    if (partner != null) {
      client.dms.partners[identifier] = partner.identifier;
      members[partner.identifier] = partner;
    }
  }

  @override
  final _Client client;
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  final bool isFavorite;
  final members = <String, Member>{};

  @override
  Member getMemberOrFallback(String id) => members[id] ?? _Member(id, id);
}

class _Aggregator extends Fake implements DirectMessagesAggregator {
  @override
  final StreamController<void> onEventReceived = StreamController.broadcast();
}

class _ClientManager extends Fake implements ClientManager {
  @override
  final DirectMessagesAggregator directMessages = _Aggregator();
}

class _MainPageState extends Fake implements MainPageState {
  _MainPageState(List<Room> favorites, List<Room> dms)
      : favoriteRooms = NotifyingList.from(favorites, growable: true),
        directMessages = NotifyingList.from(dms, growable: true);

  @override
  INotifyingList<Room> favoriteRooms;
  @override
  INotifyingList<Room> directMessages;
  @override
  final ClientManager clientManager = _ClientManager();

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      "_MainPageState";
}

void main() {
  group("dmSearchMatches", () {
    test("an empty or blank query matches everything", () {
      expect(dmSearchMatches("", ["Alice"]), isTrue);
      expect(dmSearchMatches("   ", ["Alice"]), isTrue);
    });

    test("ignores case", () {
      expect(dmSearchMatches("aLi", ["Alice"]), isTrue);
    });

    test("matches any of the names", () {
      final names = ["Mum", "@alice:example.org", "Alice Liddell"];
      expect(dmSearchMatches("mum", names), isTrue);
      expect(dmSearchMatches("@alice:exa", names), isTrue);
      expect(dmSearchMatches("liddell", names), isTrue);
      expect(dmSearchMatches("bob", names), isFalse);
    });

    test("every word must match, each in any name", () {
      final names = ["Alice", "@alice:example.org"];
      expect(dmSearchMatches("alice example", names), isTrue);
      expect(dmSearchMatches("alice bob", names), isFalse);
    });

    test("skips missing names", () {
      expect(dmSearchMatches("a", [null, "Alice"]), isTrue);
      expect(dmSearchMatches("a", [null]), isFalse);
    });
  });

  group("dmSearchNames", () {
    test("a direct message is found by the partner's ID and names", () {
      final client = _Client();
      final room = _Room(client, "!dm", "Mum",
          partner: _Member("@alice:example.org", "Alice"));
      expect(dmSearchNames(room),
          containsAll(["Mum", "@alice:example.org", "Alice"]));
    });

    test("a room that isn't a direct message is found by its name only", () {
      final room = _Room(_Client(), "!group", "Book club");
      expect(dmSearchNames(room), ["Book club"]);
    });
  });

  group("DmListSearch", () {
    late _Client client;
    late NotifyingList<Room> favorites;
    late NotifyingList<Room> dms;
    late DmListSearch search;

    List<String> names(INotifyingList<Room> list) =>
        [for (final room in list) room.displayName];

    setUp(() {
      client = _Client();
      favorites = NotifyingList.from([
        _Room(client, "!fav", "Book club", isFavorite: true),
      ], growable: true);
      dms = NotifyingList.from([
        _Room(client, "!a", "Alice",
            partner: _Member("@alice:example.org", "Alice")),
        _Room(client, "!b", "Mum",
            partner: _Member("@carol:nether.im", "Carol")),
        _Room(client, "!c", "Bob", partner: _Member("@bob:example.org", "Bob")),
      ], growable: true);
      search = DmListSearch(favorites, dms);
    });

    tearDown(() => search.dispose());

    test("a blank query shows the lists themselves", () {
      search.setQuery("  ");
      expect(search.favorites, same(favorites));
      expect(search.directMessages, same(dms));
    });

    test("filters by person, and clearing restores the order", () {
      // The nickname "Mum" is found by the person's own name.
      search.setQuery("carol");
      expect(names(search.directMessages), ["Mum"]);
      expect(names(search.favorites), isEmpty);

      search.setQuery("example.org");
      expect(names(search.directMessages), ["Alice", "Bob"]);

      search.setQuery("book");
      expect(names(search.favorites), ["Book club"]);
      expect(names(search.directMessages), isEmpty);

      search.setQuery("");
      expect(names(search.directMessages), ["Alice", "Mum", "Bob"]);
      expect(names(search.favorites), ["Book club"]);
    });

    test("a DM arriving while searching shows only if it matches", () {
      search.setQuery("dave");
      dms.add(_Room(client, "!d", "Dave",
          partner: _Member("@dave:example.org", "Dave")));
      dms.add(_Room(client, "!e", "Eve",
          partner: _Member("@eve:example.org", "Eve")));
      expect(names(search.directMessages), ["Dave"]);
    });

    test("the hint under Direct Messages", () {
      expect(search.showDirectMessagesHint, isFalse);

      search.setQuery("zed");
      expect(search.showDirectMessagesHint, isTrue);

      // Only a favourite matches: the DM section stays quiet.
      search.setQuery("book");
      expect(search.showDirectMessagesHint, isFalse);

      search.setQuery("");
      dms.clear();
      expect(search.showDirectMessagesHint, isTrue);
    });
  });

  group("ImportantRoomsList search field", () {
    // Empty lists, so no room rows are built: the rows are covered above.
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ImportantRoomsList(
                state: _MainPageState([], []),
                directMessagesListHeaderDesktop: "Direct Messages"))));

    Finder field() => find.byKey(const ValueKey("DirectMessagesSearch"));

    testWidgets("says when nothing matches, and clears", (tester) async {
      await pump(tester);
      expect(find.text("Find a conversation"), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text("No direct messages yet. Press + to start one."),
          findsOneWidget);

      await tester.enterText(field(), "zed");
      await tester.pumpAndSettle();
      expect(find.text('No direct messages match "zed".'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text("No direct messages yet. Press + to start one."),
          findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.text("Find a conversation"), findsOneWidget);
    });
  });
}
