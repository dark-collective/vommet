import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 611: search inside a chat. The magnifier turns the room
/// header into a search field; while there is text the chat shows a live
/// list of matches. Tapping one jumps to it in the normal chat, with the
/// words highlighted, the match outlined and a "3 of 17" bar to step
/// through them; the List button brings the matches back. Unencrypted rooms
/// use the server's search, encrypted ones the on-device index.
///
/// One per room, kept while the app runs: closing search keeps the text, and
/// opening it again shows its matches again.
class InChatSearch extends ChangeNotifier {
  InChatSearch(this.room,
      {Future<EventSearchSession> Function(Room room)? createSession,
      this.debounce = const Duration(milliseconds: 350)})
      : _createSession = createSession ?? _defaultSession;

  final Room room;
  final Duration debounce;
  final Future<EventSearchSession> Function(Room room) _createSession;

  static final Map<String, InChatSearch> _rooms = {};

  static String _keyOf(Room room) =>
      "${room.client.identifier}/${room.identifier}";

  /// The room's search, made on first use.
  static InChatSearch of(Room room) =>
      _rooms.putIfAbsent(_keyOf(room), () => InChatSearch(room));

  /// The room's search if it was ever opened.
  static InChatSearch? existing(Room room) => _rooms[_keyOf(room)];

  static bool availableIn(Room room) =>
      room.client.getComponent<EventSearchComponent>() != null;

  static Future<EventSearchSession> _defaultSession(Room room) => room.client
      .getComponent<EventSearchComponent>()!
      .createSearchSession(room);

  /// How many matches the list wants before it stops asking for more by
  /// itself; scrolling to its end asks for more.
  static const fillCount = 30;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  bool isOpen = false;

  /// The chat is replaced by the list of matches.
  bool showingList = false;

  /// Newest first.
  List<TimelineEvent> results = const [];

  /// Index in [results] of the match the chat is on.
  int? current;

  bool searching = false;
  bool canContinue = false;

  /// Encrypted rooms: how far back the search has looked.
  DateTime? searchedBackTo;
  bool searchedEverything = false;

  /// The query [results] belong to (trimmed); empty when there is none.
  String query = "";

  EventSearchSession? _session;
  StreamSubscription? _subscription;
  ValueNotifier<EncryptedSearchProgress>? _progress;
  Timer? _debounceTimer;
  int _generation = 0;
  bool _stepOlderWhenLoaded = false;

  /// Words to highlight in the chat: only while search is open.
  List<String> get highlightWords =>
      isOpen ? SearchHighlightScope.wordsOfQuery(query) : const [];

  String? get currentEventId {
    final i = current;
    if (!isOpen || i == null || i >= results.length) return null;
    return results[i].eventId;
  }

  /// The "3 of 17" bar stands in for the composer.
  bool get showingBar => isOpen && !showingList && query.isNotEmpty;

  void open() {
    isOpen = true;
    showingList = query.isNotEmpty;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  void close() {
    if (!isOpen) return;
    isOpen = false;
    showingList = false;
    focus.unfocus();
    notifyListeners();
  }

  void toggle() => isOpen ? close() : open();

  void onTextChanged(String value) {
    final term = value.trim();
    if (term == query && results.isNotEmpty) return;
    _debounceTimer?.cancel();
    if (term.isEmpty) {
      _stop();
      query = "";
      results = const [];
      current = null;
      showingList = false;
      notifyListeners();
      return;
    }
    // The old query's matches stay on screen until the new ones come.
    _stop();
    showingList = true;
    current = null;
    searching = true;
    notifyListeners();
    _debounceTimer = Timer(debounce, () => _start(term));
  }

  void clearText() {
    text.clear();
    onTextChanged("");
    focus.requestFocus();
  }

  void showList() {
    showingList = true;
    notifyListeners();
  }

  /// Jumps to the match at [index] in the normal chat.
  void select(int index) {
    if (index < 0 || index >= results.length) return;
    current = index;
    showingList = false;
    focus.unfocus();
    notifyListeners();
    final eventId = results[index].eventId;
    // After the frame that puts the chat back on screen.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => EventBus.jumpToEvent.add(eventId));
  }

  bool get hasOlder =>
      current != null && (current! + 1 < results.length || canContinue);
  bool get hasNewer => current != null && current! > 0;

  /// The next match up the chat (older).
  void older() {
    final i = current;
    if (i == null) return;
    if (i + 1 < results.length) {
      select(i + 1);
    } else if (canContinue) {
      _stepOlderWhenLoaded = true;
      loadMore();
    }
  }

  /// The next match down the chat (newer).
  void newer() {
    final i = current;
    if (i != null && i > 0) select(i - 1);
  }

  /// Looks further back, when the session can.
  void loadMore() {
    final session = _session;
    if (session == null || searching || !canContinue) return;
    final Stream<List<TimelineEvent>> more;
    try {
      more = session.continueSearch();
    } catch (e) {
      // The live scan of an encrypted room (web) throws once it has reached
      // the room's start.
      Log.i("In-chat search: can't search further back: $e");
      canContinue = false;
      _stepOlderWhenLoaded = false;
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    _listen(session, more, _generation);
  }

  /// Called by the list after it is laid out: asks for more while it is
  /// short or scrolled to its end.
  void wantMore({required bool nearEnd}) {
    if (!isOpen || !showingList) return;
    if (results.length < fillCount || nearEnd) loadMore();
  }

  Future<void> _start(String term) async {
    _stop();
    final generation = ++_generation;
    query = term;
    results = const [];
    current = null;
    searching = true;
    canContinue = false;
    searchedBackTo = null;
    searchedEverything = false;
    notifyListeners();

    final EventSearchSession session;
    try {
      session = await _createSession(room);
    } catch (e, s) {
      Log.onError(e, s, content: "In-chat search: no search session");
      if (generation == _generation) {
        searching = false;
        notifyListeners();
      }
      return;
    }
    // The text changed while the session was being made: a newer search
    // owns the results.
    if (generation != _generation) return;
    _session = session;
    if (session is MatrixIndexedRoomEventSearchSession) {
      _progress = session.progress..addListener(_onProgress);
    }
    _listen(session, session.startSearch(term), generation);
  }

  void _listen(EventSearchSession session, Stream<List<TimelineEvent>> stream,
      int generation) {
    _subscription?.cancel();
    _subscription = stream.listen((list) {
      if (generation != _generation) return;
      _merge(list);
      searching = session.currentlySearching;
      canContinue = session.canContinueSearch;
      _afterUpdate();
    }, onError: (Object e, StackTrace s) {
      Log.onError(e, s, content: "In-chat search failed");
      if (generation != _generation) return;
      searching = false;
      notifyListeners();
    }, onDone: () {
      if (generation != _generation) return;
      searching = false;
      canContinue = session.canContinueSearch;
      _afterUpdate();
    });
  }

  void _afterUpdate() {
    if (_stepOlderWhenLoaded && !searching) {
      _stepOlderWhenLoaded = false;
      final i = current;
      if (i != null && i + 1 < results.length) {
        select(i + 1);
        return;
      }
    }
    notifyListeners();
  }

  /// Sessions hand back either everything so far or just the latest page;
  /// keep the union, newest first.
  void _merge(List<TimelineEvent> list) {
    final byId = <String, TimelineEvent>{
      for (final e in results) e.eventId: e,
      for (final e in list) e.eventId: e,
    };
    if (byId.length == results.length && list.length <= results.length) {
      return;
    }
    final currentId =
        current != null && current! < results.length ? results[current!] : null;
    results = byId.values.toList()
      ..sort((a, b) => b.originServerTs.compareTo(a.originServerTs));
    if (currentId != null) {
      final i = results.indexWhere((e) => e.eventId == currentId.eventId);
      current = i < 0 ? null : i;
    }
  }

  void _onProgress() {
    final p = _progress?.value;
    if (p == null) return;
    searchedBackTo = p.searchedBackTo;
    searchedEverything = p.complete;
    notifyListeners();
  }

  void _stop() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _progress?.removeListener(_onProgress);
    _progress = null;
    _session = null;
    searching = false;
    canContinue = false;
    _stepOlderWhenLoaded = false;
  }

  /// Forgets every room's search (logout, tests).
  static void reset() {
    for (final s in _rooms.values) {
      s._debounceTimer?.cancel();
      s._stop();
    }
    _rooms.clear();
  }

  // Strings

  static String inChatSearchSearchingOlder(String month) => Intl.message(
      "Searching older messages: $month",
      args: [month],
      name: "inChatSearchSearchingOlder",
      desc:
          "In-chat search, encrypted rooms: shown while older messages are being searched; the month and year it has reached so far");

  static String inChatSearchSearchedBackTo(String month) => Intl.message(
      "Searched back to $month",
      args: [month],
      name: "inChatSearchSearchedBackTo",
      desc:
          "In-chat search, encrypted rooms: how far back it has searched so far, while it is paused (scroll down for more)");

  static String get inChatSearchSearching => Intl.message("Searching…",
      name: "inChatSearchSearching",
      desc: "In-chat search: shown while matches are being looked up");

  static String inChatSearchFound(int count) => Intl.plural(count,
      zero: "None found",
      one: "1 found",
      other: "$count found",
      args: [count],
      name: "inChatSearchFound",
      desc: "In-chat search: how many matching messages were found so far");

  static String get inChatSearchNoResults => Intl.message("No messages found",
      name: "inChatSearchNoResults",
      desc: "In-chat search: nothing matches the search");

  static String get inChatSearchTapToJump =>
      Intl.message("Tap a result to jump to it in the chat",
          name: "inChatSearchTapToJump",
          desc: "In-chat search: hint under the list of matches");

  static String inChatSearchPosition(int index, int count) => Intl.message(
      "$index of $count",
      args: [index, count],
      name: "inChatSearchPosition",
      desc:
          "In-chat search: which match the chat is on, e.g. \"3 of 17\" (counted from the newest)");

  static String get inChatSearchList => Intl.message("List",
      name: "inChatSearchList",
      desc: "In-chat search: button that shows the list of matches again");

  static String get inChatSearchOlder => Intl.message("Older match",
      name: "inChatSearchOlder",
      desc:
          "In-chat search: tooltip of the button that goes to an older match");

  static String get inChatSearchNewer => Intl.message("Newer match",
      name: "inChatSearchNewer",
      desc: "In-chat search: tooltip of the button that goes to a newer match");

  static String get inChatSearchClose => Intl.message("Close search",
      name: "inChatSearchClose",
      desc: "In-chat search: tooltip of the back button that closes search");

  static String get inChatSearchClear => Intl.message("Clear",
      name: "inChatSearchClear",
      desc:
          "In-chat search: tooltip of the button that clears the search text");

  static String get inChatSearchYou => Intl.message("You",
      name: "inChatSearchYou",
      desc: "In-chat search: sender name of your own messages in the list");
}
