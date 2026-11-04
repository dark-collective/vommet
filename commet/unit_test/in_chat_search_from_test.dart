import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/permissions.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vommet (search one person's messages): the From chip, the person picker
/// and the member menu's "Search their messages".

class _Member implements Member {
  _Member(this.identifier, this.displayName);
  @override
  final String identifier;
  @override
  final String displayName;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Session implements EventSearchSession {
  final List<String> searchedFor = [];
  @override
  bool currentlySearching = false;
  @override
  bool get canContinueSearch => false;
  @override
  Stream<List<TimelineEvent>> startSearch(String searchTerm) {
    searchedFor.add(searchTerm);
    return Stream.value(const []);
  }

  @override
  Stream<List<TimelineEvent>> continueSearch() => const Stream.empty();
}

class _SearchComponent implements EventSearchComponent {
  @override
  Future<EventSearchSession> createSearchSession(Room room) async => _Session();
  @override
  List<String> getSupportedSearchFeatures(Room room) => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements Client {
  @override
  String get identifier => "client";
  @override
  T? getComponent<T extends Component>() {
    final c = _SearchComponent();
    return c is T ? c as T : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Permissions extends Permissions {}

class _Room implements Room {
  _Room(this.members);
  final List<Member> members;
  int fetches = 0;

  @override
  final Client client = _Client();
  @override
  String get identifier => "!room:x";
  @override
  Permissions get permissions => _Permissions();
  @override
  List<Member> membersList() => members;
  @override
  bool get isMembersListComplete => false;
  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async {
    fetches++;
    return members;
  }

  @override
  Member? getMember(String id) =>
      members.where((m) => m.identifier == id).firstOrNull;
  @override
  Member getMemberOrFallback(String id) => getMember(id) ?? _Member(id, id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final jun = _Member("@jun:x", "Jun");
  final members = <Member>[
    jun,
    _Member("@june:x", "June Moss"),
    _Member("@bo:junction.org", "Bo"),
    _Member("@ann:x", "Ann"),
    for (var i = 0; i < 10; i++) _Member("@j$i:x", "Junior $i"),
  ];

  late _Session session;
  late _Room room;
  late InChatSearch search;

  setUp(() {
    session = _Session();
    room = _Room(members);
    search = InChatSearch(
      room,
      createSession: (_) async => session,
      debounce: Duration.zero,
    );
  });

  Future<void> type(String text) async {
    search.text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    search.onTextChanged(text);
    await pumpEventQueue();
  }

  test('the chip limits the search to that person; x drops it', () async {
    search.open();
    await type('moss');
    search.setFrom(jun);
    await pumpEventQueue();
    expect(session.searchedFor.last, 'from:@jun:x moss');
    expect(search.text.text, 'moss');
    expect(search.highlightWords, ['moss']);

    search.setFrom(null);
    await pumpEventQueue();
    expect(session.searchedFor.last, 'moss');
  });

  test('a person-only search lists their messages, words-free', () async {
    search.open();
    search.setFrom(jun);
    await pumpEventQueue();
    expect(session.searchedFor.last, 'from:@jun:x');
    expect(search.query, 'from:@jun:x');
    expect(search.showingList, isTrue);
    // No words: the jump outlines the match but highlights nothing.
    expect(search.highlightWords, isEmpty);
  });

  test('Backspace in the empty field drops the chip', () async {
    search.open();
    search.setFrom(jun);
    await pumpEventQueue();
    expect(search.backspaceOnEmpty(), isTrue);
    expect(search.from, isNull);
    expect(search.query, '');
  });

  test('from:jun lists up to 8 members by name or ID; Enter picks', () async {
    search.open();
    await type('moss from:jun');
    expect(search.pickerVisible, isTrue);
    final names = search.pickerCandidates.map((m) => m.identifier).toList();
    expect(names, hasLength(8));
    expect(names.take(3), ['@jun:x', '@june:x', '@bo:junction.org']);
    expect(room.fetches, 1);
    // The half-typed from: is not searched for.
    expect(session.searchedFor.last, 'moss');

    search.pickerMove(1);
    expect(search.pickHighlighted(), isTrue);
    await pumpEventQueue();
    expect(search.from?.identifier, '@june:x');
    expect(search.text.text, 'moss ');
    expect(search.pickerVisible, isFalse);
    expect(session.searchedFor.last, 'from:@june:x moss');

    // Members are asked for once per open.
    await type('moss from:a');
    expect(room.fetches, 1);
  });

  test('From: is case-insensitive and Esc closes the picker', () async {
    search.open();
    await type('From:ANN');
    expect(search.pickerCandidates.map((m) => m.identifier), ['@ann:x']);
    search.dismissPicker();
    expect(search.pickerVisible, isFalse);
  });

  test('a typed full from:@a:b and a space becomes the chip', () async {
    search.open();
    await type('from:@ann:x ');
    expect(search.from?.identifier, '@ann:x');
    expect(search.text.text, '');
    expect(session.searchedFor.last, 'from:@ann:x');
  });

  test('highlight words never include from:', () {
    expect(SearchHighlightScope.wordsOfQuery('from:@jun:x moss From:@a:b'), [
      'moss',
    ]);
  });

  testWidgets('the member menu searches their messages', (tester) async {
    InChatSearch.reset();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => RoomMemberList.userContextMenu(
            context,
            userId: '@jun:x',
            userDisplayName: 'Jun',
            room: room,
            isSelf: true,
            child: const Text('Jun'),
          ),
        ),
      ),
    );
    final menu = tester.widget<AdaptiveContextMenu>(
      find.byType(AdaptiveContextMenu),
    );
    final item = menu.items.firstWhere(
      (i) => i.text == InChatSearch.inChatSearchTheirMessages,
    );
    expect(item.icon, Icons.manage_search);

    item.onPressed!();
    await tester.pump();
    final opened = InChatSearch.of(room);
    expect(opened.isOpen, isTrue);
    expect(opened.from?.identifier, '@jun:x');
    expect(opened.query, 'from:@jun:x');
    InChatSearch.reset();
  });
}
