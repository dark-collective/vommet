import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/organisms/room_event_search/room_event_search_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _FakeSession implements EventSearchSession {
  final List<String> searchedFor = [];

  @override
  Stream<List<TimelineEvent>> startSearch(String searchTerm) {
    searchedFor.add(searchTerm);
    return Stream.value(<TimelineEvent>[]);
  }

  @override
  Stream<List<TimelineEvent>> continueSearch() => const Stream.empty();

  @override
  bool get currentlySearching => false;

  @override
  bool get canContinueSearch => false;
}

class _FakeSearch implements EventSearchComponent<Client> {
  final List<Completer<EventSearchSession>> pending = [];

  @override
  Future<EventSearchSession> createSearchSession(Room room) {
    var completer = Completer<EventSearchSession>();
    pending.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient(this.search);
  final _FakeSearch search;

  @override
  T? getComponent<T extends Component>() => search as T;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom(this.client);

  @override
  final Client client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'a search whose session arrives after the text changed is dropped',
      (tester) async {
    var search = _FakeSearch();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeDark.theme,
      home: Scaffold(
          body: RoomEventSearchWidget(room: _FakeRoom(_FakeClient(search)))),
    ));

    await tester.enterText(find.byType(TextField), 'hel');
    await tester.pump(const Duration(seconds: 1));
    expect(search.pending, hasLength(1));

    // The text changes while the first session is still being created.
    await tester.enterText(find.byType(TextField), 'hello');
    var stale = _FakeSession();
    search.pending[0].complete(stale);
    await tester.pump();
    expect(stale.searchedFor, isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(search.pending, hasLength(2));
    var current = _FakeSession();
    search.pending[1].complete(current);
    await tester.pump();
    await tester.pump();

    expect(current.searchedFor, ['hello']);
    expect(find.text('No results found'), findsOneWidget);
  });
}
