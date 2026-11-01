import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/event_search/event_search_component.dart';
import 'package:commet/client/matrix/components/event_search/matrix_event_search_component.dart';
import 'package:commet/client/member.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/ui/pages/room_info/room_info_shared_pages.dart'
    show closeRoomInfoToChat;
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

  /// Vommet (search one person's messages): the person in the From chip;
  /// the session gets `from:<their id>`, the field never shows it.
  Member? from;

  /// The `has:*` filter chips that are on, e.g. `has:image`.
  final Set<String> hasFilters = {};

  /// The `has:*` chips, in the order of the row.
  static const hasKinds = [
    MatrixSearchParameters.hasLinkString,
    MatrixSearchParameters.hasImageString,
    MatrixSearchParameters.hasVideoString,
    MatrixSearchParameters.hasFileString,
  ];

  /// The `has:*` chips this room's search supports (encrypted rooms).
  List<String> get supportedHasKinds {
    final features = room.client
            .getComponent<EventSearchComponent>()
            ?.getSupportedSearchFeatures(room) ??
        const <String>[];
    return [
      for (final k in hasKinds)
        if (features.contains(k)) k
    ];
  }

  /// The picker is shut by Esc until the text changes again.
  bool _pickerDismissed = false;

  /// Highlighted row of the picker.
  int pickerIndex = 0;
  bool _membersFetched = false;

  static final _pickerPattern =
      RegExp(r'(?:^|\s)from:(\S+)$', caseSensitive: false);
  static final _fullIdPattern =
      RegExp(r'(?:^|\s)from:(@[^\s:]+:\S+)\s', caseSensitive: false);
  static final _fromToken = RegExp(r'^from:', caseSensitive: false);

  /// What the person picker is looking for: the text after a trailing
  /// `from:`, or null when it is not showing.
  String? get pickerTerm {
    if (!isOpen || _pickerDismissed) return null;
    return _pickerPattern.firstMatch(text.text)?.group(1);
  }

  bool get pickerVisible => pickerTerm != null;

  /// Up to 8 room members whose name or Matrix ID contains [pickerTerm].
  List<Member> get pickerCandidates {
    final term = pickerTerm?.toLowerCase();
    if (term == null) return const [];
    final list = <Member>[];
    for (final m in room.membersList()) {
      if (m.displayName.toLowerCase().contains(term) ||
          m.identifier.toLowerCase().contains(term)) {
        list.add(m);
        if (list.length == 8) break;
      }
    }
    return list;
  }

  void _fetchMembersOnce() {
    if (_membersFetched || room.isMembersListComplete) return;
    _membersFetched = true;
    room.fetchMembersList().then((_) => notifyListeners(), onError: (e) {
      Log.i("In-chat search: couldn't load the members: $e");
    });
  }

  /// The query the session gets: the chips' filters, then the typed words
  /// (any typed `from:` is left to the picker).
  String composedQuery(String typed) => [
        if (from != null) "from:${from!.identifier}",
        ...hasFilters,
        for (final w in typed.split(RegExp(r'\s+')))
          if (w.isNotEmpty && !_fromToken.hasMatch(w)) w,
      ].join(" ");

  /// Text without its trailing `from:…` (what picking a person leaves).
  static String _withoutFromToken(String value) => value
      .replaceFirstMapped(
          RegExp(r'(^|\s)from:\S*\s?$', caseSensitive: false), (m) => m[1]!)
      .trimLeft();

  void _setText(String value) {
    text.value = TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length));
  }

  /// Puts [member] in the From chip (or empties it) and searches again.
  void setFrom(Member? member) {
    from = member;
    _search(now: true);
  }

  /// Picks a person from the picker: the `from:…` text goes, the chip comes.
  void pick(Member member) {
    _setText(_withoutFromToken(text.text));
    pickerIndex = 0;
    setFrom(member);
    focus.requestFocus();
  }

  void pickerMove(int delta) {
    final n = pickerCandidates.length;
    if (n == 0) return;
    pickerIndex = (pickerIndex + delta) % n;
    notifyListeners();
  }

  /// Enter in the picker; false when there was nothing to pick.
  bool pickHighlighted() {
    final list = pickerCandidates;
    if (list.isEmpty) return false;
    pick(list[pickerIndex.clamp(0, list.length - 1)]);
    return true;
  }

  void dismissPicker() {
    _pickerDismissed = true;
    notifyListeners();
  }

  void toggleHas(String kind) {
    if (!hasFilters.remove(kind)) hasFilters.add(kind);
    _search(now: true);
  }

  /// The From… chip: types `from:` for the picker.
  void startFrom() {
    final current = text.text.trimRight();
    _setText(current.isEmpty ? "from:" : "$current from:");
    _pickerDismissed = false;
    focus.requestFocus();
    notifyListeners();
  }

  /// The member menu's "Search their messages": search open on [member]'s
  /// messages, newest first, straight away.
  void searchFrom(Member member) {
    hasFilters.clear();
    _setText("");
    open();
    setFrom(member);
  }

  /// The member menu's item: on phones the member list covers the chat, so
  /// it goes first.
  static void searchMemberMessages(
      BuildContext context, Room room, Member member) {
    if (MediaQuery.of(context).mobile) {
      closeRoomInfoToChat(context);
      EventBus.focusTimeline.add(null);
    }
    InChatSearch.of(room).searchFrom(member);
  }

  /// Backspace in the empty field drops the chip.
  bool backspaceOnEmpty() {
    if (text.text.isNotEmpty || from == null) return false;
    setFrom(null);
    return true;
  }

  void _search({bool now = false}) {
    _lastTyped = null;
    onTextChanged(text.text);
    final term = composedQuery(text.text.trim());
    if (now && term.isNotEmpty) {
      _debounceTimer?.cancel();
      _start(term);
    }
  }

  String? _lastTyped;

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
    if (!isOpen) _membersFetched = false;
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
    if (value != _lastTyped) {
      _pickerDismissed = false;
      pickerIndex = 0;
    }
    _lastTyped = value;
    // A typed full `from:@a:b ` becomes the chip.
    final full = _fullIdPattern.firstMatch(value);
    if (full != null) {
      from = room.getMemberOrFallback(full.group(1)!);
      value = "${value.substring(0, full.start)} ${value.substring(full.end)}"
          .trimLeft();
      _setText(value);
      _lastTyped = value;
    }
    if (pickerTerm != null) _fetchMembersOnce();
    final term = composedQuery(value.trim());
    if (term == query && results.isNotEmpty) {
      notifyListeners();
      return;
    }
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
    from = null;
    hasFilters.clear();
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

  static String inChatSearchFromChip(String name) => Intl.message("From: $name",
      args: [name],
      name: "inChatSearchFromChip",
      desc:
          "In-chat search: the chip in the search field that limits the search to one person's messages");

  static String get inChatSearchRemoveFrom => Intl.message("Remove person",
      name: "inChatSearchRemoveFrom",
      desc:
          "In-chat search: tooltip of the x on the From chip, which searches everyone's messages again");

  static String get inChatSearchPeopleInRoom => Intl.message(
      "People in this room",
      name: "inChatSearchPeopleInRoom",
      desc:
          "In-chat search: heading of the list of members shown after typing from:");

  static String get inChatSearchFromFilter => Intl.message("From…",
      name: "inChatSearchFromFilter",
      desc:
          "In-chat search: filter chip under the search field; picks one person whose messages to search");

  static String get inChatSearchHasLink => Intl.message("Link",
      name: "inChatSearchHasLink",
      desc: "In-chat search: filter chip, only messages with a link");

  static String get inChatSearchHasImage => Intl.message("Image",
      name: "inChatSearchHasImage",
      desc: "In-chat search: filter chip, only messages with an image");

  static String get inChatSearchHasVideo => Intl.message("Video",
      name: "inChatSearchHasVideo",
      desc: "In-chat search: filter chip, only messages with a video");

  static String get inChatSearchHasFile => Intl.message("File",
      name: "inChatSearchHasFile",
      desc: "In-chat search: filter chip, only messages with a file");

  static String get inChatSearchFromTip =>
      Intl.message("Tip: pick From… to see what one person said.",
          name: "inChatSearchFromTip",
          desc: "In-chat search: one-line tip under the empty search");

  static String get inChatSearchTheirMessages => Intl.message(
      "Search their messages",
      name: "inChatSearchTheirMessages",
      desc:
          "Member menu (right-click or long-press a member): opens the chat's search limited to that person's messages");

  static String get inChatSearchYou => Intl.message("You",
      name: "inChatSearchYou",
      desc: "In-chat search: sender name of your own messages in the list");
}
