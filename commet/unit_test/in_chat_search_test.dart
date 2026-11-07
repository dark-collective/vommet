import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search_views.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class _Event implements TimelineEvent {
  _Event(this.eventId, int day) : originServerTs = DateTime(2026, 1, day);

  @override
  final String eventId;
  @override
  final DateTime originServerTs;
  @override
  String get plainTextBody => "";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out [pages] one per call: startSearch the first, continueSearch the
/// rest, each as only that page (like the server search).
class _PagedSession implements EventSearchSession {
  @override
  bool holdsTimeline = true;

  int closed = 0;

  @override
  void close() => closed++;

  _PagedSession(this.pages);
  final List<List<TimelineEvent>> pages;
  int next = 0;
  final List<String> searchedFor = [];

  @override
  bool currentlySearching = false;

  @override
  bool get canContinueSearch => next < pages.length;

  Stream<List<TimelineEvent>> _page() async* {
    currentlySearching = true;
    await Future<void>.delayed(Duration.zero);
    final page = pages[next++];
    currentlySearching = false;
    yield page;
  }

  @override
  Stream<List<TimelineEvent>> startSearch(String searchTerm) {
    searchedFor.add(searchTerm);
    next = 0;
    return _page();
  }

  @override
  Stream<List<TimelineEvent>> continueSearch() => _page();

  @override
  String? get resumePoint => canContinueSearch ? "page$next" : null;

  final List<String> resumedFrom = [];

  @override
  Stream<List<TimelineEvent>> resumeSearch(String searchTerm, String from) {
    resumedFrom.add(from);
    next = int.parse(from.substring(4));
    return _page();
  }
}

class _Room implements Room {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchHighlightScope', () {
    test('words of a query leave out filters and case', () {
      expect(
          SearchHighlightScope.wordsOfQuery(' Moss  from:@a:b has:image Wet'),
          ['moss', 'wet']);
    });

    test('matches are case-insensitive, sorted and merged', () {
      expect(SearchHighlightScope.matches('Moss or mossy MOSS', ['moss']),
          [(0, 4), (8, 12), (14, 18)]);
      expect(
          SearchHighlightScope.matches('lichens', ['lich', 'chen']), [(0, 6)]);
      expect(SearchHighlightScope.matches('nothing here', ['moss']), isEmpty);
    });

    test('text spans mark only the matched words', () {
      final spans = SearchHighlightScope.textSpans(
          'Found moss today', ['moss'], const TextStyle(color: Colors.yellow));
      expect(
          spans.map((s) => (s as TextSpan).text), ['Found ', 'moss', ' today']);
      expect((spans[1] as TextSpan).style?.color, Colors.yellow);
      expect((spans[0] as TextSpan).style, isNull);
    });

    test('links are kept as they are', () {
      final link =
          TextSpan(text: 'moss.example', recognizer: TapGestureRecognizer());
      final spans = SearchHighlightScope.highlightSpans(
          [const TextSpan(text: 'see moss: '), link],
          ['moss'],
          const TextStyle(fontWeight: FontWeight.bold));
      expect(spans, hasLength(4));
      expect(spans.last, same(link));
    });
  });

  group('InChatSearch', () {
    late _PagedSession session;
    late InChatSearch search;

    setUp(() {
      session = _PagedSession([
        [_Event('c', 3), _Event('b', 2)],
        [_Event('a', 1)],
      ]);
      search = InChatSearch(_Room(),
          createSession: (_) async => session, debounce: Duration.zero);
    });

    Future<void> type(String text) async {
      search.text.text = text;
      search.onTextChanged(text);
      await pumpEventQueue();
    }

    test('typing shows the list of matches, newest first', () async {
      search.open();
      await type('moss ');
      expect(session.searchedFor, ['moss']);
      expect(search.showingList, isTrue);
      expect(search.results.map((e) => e.eventId), ['c', 'b']);
      expect(search.canContinue, isTrue);
      expect(search.highlightWords, ['moss']);
    });

    test('pages are merged and the list asks for more while short', () async {
      search.open();
      await type('moss');
      search.wantMore(nearEnd: false);
      await pumpEventQueue();
      expect(search.results.map((e) => e.eventId), ['c', 'b', 'a']);
      expect(search.canContinue, isFalse);
    });

    test('a jump leaves the list; arrows step through the matches', () async {
      search.open();
      await type('moss');
      search.select(0);
      expect(search.showingList, isFalse);
      expect(search.showingBar, isTrue);
      expect(search.currentEventId, 'c');
      expect(search.hasNewer, isFalse);

      search.older();
      expect(search.currentEventId, 'b');
      expect(search.hasNewer, isTrue);

      // At the last loaded match, "older" loads the next page and goes on.
      search.older();
      await pumpEventQueue();
      expect(search.currentEventId, 'a');
      expect(search.hasOlder, isFalse);

      search.newer();
      expect(search.currentEventId, 'b');

      search.showList();
      expect(search.showingList, isTrue);
      expect(search.showingBar, isFalse);
    });

    test('clearing the text removes the highlights', () async {
      search.open();
      await type('moss');
      search.select(1);
      await type('');
      expect(search.highlightWords, isEmpty);
      expect(search.currentEventId, isNull);
      expect(search.results, isEmpty);
      expect(search.showingList, isFalse);
    });

    test('closing keeps the text; reopening shows the list again', () async {
      search.open();
      await type('moss');
      search.select(0);
      search.close();
      expect(session.closed, 1, reason: "its timeline can close");
      expect(search.highlightWords, isEmpty);
      expect(search.currentEventId, isNull);
      expect(search.showingBar, isFalse);

      search.open();
      expect(search.text.text, 'moss');
      expect(search.showingList, isTrue);
      expect(search.results, hasLength(2));
    });

    test('a newer query drops the older one\'s late results', () async {
      final slow = Completer<EventSearchSession>();
      var calls = 0;
      search = InChatSearch(_Room(), createSession: (_) {
        calls++;
        return calls == 1 ? slow.future : Future.value(session);
      }, debounce: Duration.zero);
      search.open();
      await type('mo');
      await type('moss');
      slow.complete(_PagedSession([
        [_Event('old', 9)]
      ]));
      await pumpEventQueue();
      expect(search.query, 'moss');
      expect(search.results.map((e) => e.eventId), ['c', 'b']);
    });
  });

  group('result rows', () {
    test('a long message starts shortly before the match', () {
      final body = '${'word ' * 20}moss at the end';
      final snippet = InChatSearchResultRow.snippetOf(body, ['moss']);
      expect(snippet, startsWith('…'));
      expect(snippet, contains('moss at the end'));
      expect(snippet.length, lessThan(body.length));
      expect(InChatSearchResultRow.snippetOf('short moss', ['moss']),
          'short moss');
    });

    test('dates: time today, day this year, full date before', () {
      final now = DateTime(2026, 10, 22, 18);
      expect(InChatSearchResultRow.dateOf(DateTime(2026, 10, 19), now: now),
          'Oct 19');
      expect(InChatSearchResultRow.dateOf(DateTime(2025, 3, 30), now: now),
          'Mar 30, 2025');
    });
  });

  testWidgets('the bar says which match the chat is on', (tester) async {
    final search = InChatSearch(_Room(),
        createSession: (_) async => _PagedSession([
              [for (var i = 17; i > 0; i--) _Event('e$i', i)]
            ]),
        debounce: Duration.zero);
    // Real timers: the search's debounce and pages run outside fake time.
    await tester.runAsync(() async {
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      await pumpEventQueue();
    });
    search.select(2);

    await tester.pumpWidget(MaterialApp(
        theme: ThemeDark.theme, home: Scaffold(body: InChatSearchBar(search))));
    expect(find.text('3 of 17'), findsOneWidget);
    expect(find.text('List'), findsOneWidget);

    await tester.tap(find.text('List'));
    expect(search.showingList, isTrue);
  });

  // Vommet: leaving the chat drops the session; looking further back goes
  // on from where it was, not from the newest messages.
  testWidgets('after leaving the chat, more matches go on from the last page',
      (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e3', 3)],
        [_Event('e2', 2)],
        [_Event('e1', 1)],
      ]);
      sessions.add(s);
      return s;
    }, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      await pumpEventQueue();
      search.loadMore();
      await pumpEventQueue();
      search.detachChat();
    });
    await tester.pump();
    expect(sessions.single.closed, 1, reason: "the chat went");
    expect(search.results.map((e) => e.eventId), ['e3', 'e2']);

    await tester.runAsync(() async {
      search.attachChat();
      search.loadMore();
      await pumpEventQueue();
    });
    expect(sessions, hasLength(2));
    expect(sessions.last.searchedFor, isEmpty, reason: "no restart");
    expect(sessions.last.resumedFrom, ['page2']);
    expect(search.results.map((e) => e.eventId), ['e3', 'e2', 'e1']);
  });

  // Vommet: the on-device index holds no timeline, so leaving keeps it and
  // looking further back goes on in the same session.
  testWidgets('after leaving the chat, a session without a timeline is kept',
      (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e3', 3)],
        [_Event('e2', 2)],
        [_Event('e1', 1)],
      ])
        ..holdsTimeline = false;
      sessions.add(s);
      return s;
    }, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      await pumpEventQueue();
      search.loadMore();
      await pumpEventQueue();
      search.detachChat();
    });
    await tester.pump();
    expect(sessions.single.closed, 0, reason: "it holds no timeline");

    await tester.runAsync(() async {
      search.attachChat();
      search.loadMore();
      await pumpEventQueue();
    });
    expect(sessions, hasLength(1), reason: "no new session");
    expect(sessions.single.searchedFor, ['moss'], reason: "no restart");
    expect(search.results.map((e) => e.eventId), ['e3', 'e2', 'e1']);
    search.detachChat();
  });

  testWidgets('leaving inside the debounce searches the typed text on return',
      (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e1', 1)]
      ]);
      sessions.add(s);
      return s;
    }, debounce: const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      search.detachChat();
      await Future.delayed(const Duration(milliseconds: 400));
    });
    expect(sessions, isEmpty, reason: "the timer was cancelled");

    await tester.runAsync(() async {
      search.attachChat();
      await pumpEventQueue();
    });
    expect(sessions.single.searchedFor, ['moss']);
    expect(search.query, 'moss');
    search.detachChat();
  });

  // Vommet: closing search ends its session too; a search not done yet
  // searches on when search is opened again.
  testWidgets('closing inside the debounce searches the typed text on reopen',
      (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e1', 1)]
      ]);
      sessions.add(s);
      return s;
    }, debounce: const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      search.close();
      await Future.delayed(const Duration(milliseconds: 400));
    });
    expect(sessions, isEmpty, reason: "the timer was cancelled");

    // Leaving and coming back while closed doesn't search.
    await tester.runAsync(() async {
      search.detachChat();
      search.attachChat();
      await pumpEventQueue();
    });
    expect(sessions, isEmpty, reason: "search is closed");

    await tester.runAsync(() async {
      search.open();
      await pumpEventQueue();
    });
    expect(sessions.single.searchedFor, ['moss']);
    expect(search.results.map((e) => e.eventId), ['e1']);
    search.close();
    search.detachChat();
  });

  // Vommet: closing keeps a session that holds no timeline, like leaving.
  testWidgets('closing keeps a session without a timeline', (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e2', 2)],
        [_Event('e1', 1)],
      ])
        ..holdsTimeline = false;
      sessions.add(s);
      return s;
    }, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      await pumpEventQueue();
      search.close();
      search.open();
      search.loadMore();
      await pumpEventQueue();
    });
    expect(sessions.single.closed, 0, reason: "it holds no timeline");
    expect(sessions.single.searchedFor, ['moss'], reason: "no restart");
    expect(search.results.map((e) => e.eventId), ['e2', 'e1']);
    search.close();
    search.detachChat();
  });

  // Vommet: closing again (or leaving after closing) with no session kept
  // where the search had got to.
  testWidgets('closing twice still goes on from the last page', (tester) async {
    final sessions = <_PagedSession>[];
    final search = InChatSearch(_Room(), createSession: (_) async {
      final s = _PagedSession([
        [_Event('e3', 3)],
        [_Event('e2', 2)],
        [_Event('e1', 1)],
      ]);
      sessions.add(s);
      return s;
    }, debounce: Duration.zero);
    await tester.runAsync(() async {
      search.attachChat();
      search.open();
      search.text.text = 'moss';
      search.onTextChanged('moss');
      await pumpEventQueue();
      search.close();
      search.open();
      search.close();
      search.detachChat();
      search.attachChat();
      search.open();
      search.loadMore();
      await pumpEventQueue();
    });
    expect(sessions, hasLength(2));
    expect(sessions.last.searchedFor, isEmpty, reason: "no restart");
    expect(sessions.last.resumedFrom, ['page1']);
    expect(search.results.map((e) => e.eventId), ['e3', 'e2']);
    search.close();
    search.detachChat();
  });
}
