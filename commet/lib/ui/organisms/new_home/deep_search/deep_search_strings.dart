// Vommet (Deep Search, stage 2): the UI's strings (Mockups 1–6). The
// coverage line's own texts live with the core in deep_search_coverage.dart.
import 'package:intl/intl.dart';

class DeepSearchStrings {
  static String get title => Intl.message("Deep Search",
      name: "deepSearchTitle", desc: "Deep Search: the card's title");

  static String get subtitle => Intl.message("messages in every DM and room",
      name: "deepSearchSubtitle",
      desc: "Deep Search: the card's subtitle, under its title");

  static String get placeholder =>
      Intl.message("Search messages in all chats and DMs",
          name: "deepSearchPlaceholder",
          desc: "Deep Search: the search field's placeholder");

  static String get phonePlaceholder => Intl.message("Search all chats",
      name: "deepSearchPhonePlaceholder",
      desc: "Deep Search: the phone's one-line search bar on Home");

  static String get shortcut => Intl.message("Ctrl+Shift+F",
      name: "deepSearchShortcut",
      desc: "Deep Search: the keyboard shortcut shown on the card");

  static String lastSearch(String query) => Intl.message("Last search: $query",
      args: [query],
      name: "deepSearchLastSearch",
      desc: "Deep Search: the card's row that reopens the last search");

  static String get searchMessagesHere => Intl.message("Search messages here",
      name: "deepSearchSearchMessagesHere",
      desc: "Deep Search: a chat's hold menu item that searches its messages");

  static String get searchAllChats => Intl.message("Search all chats",
      name: "deepSearchSearchAllChats",
      desc: "In-chat search: the button that searches every chat instead");

  static String get back => Intl.message("Back",
      name: "deepSearchBack", desc: "Deep Search: tooltip of the back button");

  static String get clear => Intl.message("Clear",
      name: "deepSearchClear",
      desc: "Deep Search: clears the field, or the recent searches");

  static String removeChip(String label) => Intl.message("Remove $label",
      args: [label],
      name: "deepSearchRemoveChip",
      desc: "Deep Search: screen reader hint of a filter chip's remove action");

  // Chips (Mockup 3).
  static String get chipFrom => Intl.message("From",
      name: "deepSearchChipFrom", desc: "Deep Search chip: pick a sender");
  static String get chipIn => Intl.message("In",
      name: "deepSearchChipIn", desc: "Deep Search chip: pick a chat or space");
  static String get chipDms => Intl.message("DMs",
      name: "deepSearchChipDms",
      desc: "Deep Search chip: only direct messages");
  static String get chipRooms => Intl.message("Rooms",
      name: "deepSearchChipRooms", desc: "Deep Search chip: only rooms");
  static String get chipDate => Intl.message("Date",
      name: "deepSearchChipDate", desc: "Deep Search chip: pick a date range");
  static String get chipHas => Intl.message("Has",
      name: "deepSearchChipHas",
      desc: "Deep Search chip: links, images, videos, files, voice messages");
  static String get chipMentionsMe => Intl.message("Mentions me",
      name: "deepSearchChipMentionsMe",
      desc: "Deep Search chip: only messages that mention me");
  static String get sortBest => Intl.message("Best match",
      name: "deepSearchSortBest", desc: "Deep Search sort: best match first");
  static String get sortNewest => Intl.message("Newest",
      name: "deepSearchSortNewest", desc: "Deep Search sort: newest first");

  // The From ▾ / In ▾ popover.
  static String get pickerFromHint => Intl.message("Search people",
      name: "deepSearchPickerFromHint",
      desc: "Deep Search: the From popover's field placeholder");
  static String get pickerInHint => Intl.message("Search chats and spaces",
      name: "deepSearchPickerInHint",
      desc: "Deep Search: the In popover's field placeholder");
  static String get pickerNoMatches => Intl.message("No matches",
      name: "deepSearchPickerNoMatches",
      desc: "Deep Search: the From / In popover found nothing for its text");

  // Tokens: a filter's chip once picked or typed.
  static String tokenIn(String chat) => Intl.message("In: $chat",
      args: [chat],
      name: "deepSearchTokenIn",
      desc: "Deep Search chip: the chat or space searched in");
  static String tokenFrom(String sender) => Intl.message("From: $sender",
      args: [sender],
      name: "deepSearchTokenFrom",
      desc: "Deep Search chip: the sender searched for");
  static String tokenHas(String kind) => Intl.message("Has: $kind",
      args: [kind],
      name: "deepSearchTokenHas",
      desc: "Deep Search chip: what messages must have, e.g. link");
  static String tokenBefore(String date) => Intl.message("Before: $date",
      args: [date],
      name: "deepSearchTokenBefore",
      desc: "Deep Search chip: messages before a day");
  static String tokenAfter(String date) => Intl.message("After: $date",
      args: [date],
      name: "deepSearchTokenAfter",
      desc: "Deep Search chip: messages after a day");

  /// The sidebar's hand-off row (Mockup 2A).
  static String handoff(String text) =>
      Intl.message("Search messages for “$text” ›",
          args: [text],
          name: "deepSearchHandoff",
          desc: "Name search: the last row, which searches messages for the "
              "typed text with Deep Search");

  // Has / Date (Mockup 6C).
  static String get hasLink => Intl.message("Link",
      name: "deepSearchHasLink", desc: "Deep Search Has filter: a link");
  static String get hasImage => Intl.message("Image or GIF",
      name: "deepSearchHasImage", desc: "Deep Search Has filter: an image");
  static String get hasVideo => Intl.message("Video",
      name: "deepSearchHasVideo", desc: "Deep Search Has filter: a video");
  static String get hasFile => Intl.message("File",
      name: "deepSearchHasFile", desc: "Deep Search Has filter: a file");
  static String get hasVoice => Intl.message("Voice message",
      name: "deepSearchHasVoice",
      desc: "Deep Search Has filter: a voice message");
  static String get dateAny => Intl.message("Any time",
      name: "deepSearchDateAny", desc: "Deep Search Date filter: no limit");
  static String get date7 => Intl.message("Last 7 days",
      name: "deepSearchDate7", desc: "Deep Search Date filter");
  static String get date30 => Intl.message("Last 30 days",
      name: "deepSearchDate30", desc: "Deep Search Date filter");
  static String get dateYear => Intl.message("Last 12 months",
      name: "deepSearchDateYear", desc: "Deep Search Date filter");
  static String get dateRange => Intl.message("Range…",
      name: "deepSearchDateRange",
      desc: "Deep Search Date filter: pick a start and end day");
  static String showResults(int n) => Intl.message("Show $n results",
      args: [n],
      name: "deepSearchShowResults",
      desc: "Deep Search phone filter sheet: the button that applies it");

  // Empty state (Mockup 2B).
  static String get shortcutsHeader => Intl.message("SHORTCUTS",
      name: "deepSearchShortcutsHeader",
      desc: "Deep Search empty state: header of the quick filters");
  static String get shortcutLinks => Intl.message("Links",
      name: "deepSearchShortcutLinks", desc: "Deep Search shortcut: links");
  static String get shortcutFilesWeek => Intl.message("Files this week",
      name: "deepSearchShortcutFilesWeek",
      desc: "Deep Search shortcut: files from the last 7 days");
  static String get shortcutImages => Intl.message("Images",
      name: "deepSearchShortcutImages", desc: "Deep Search shortcut: images");
  static String get recentHeader => Intl.message("RECENT SEARCHES",
      name: "deepSearchRecentHeader",
      desc: "Deep Search empty state: header of the recent searches");
  static String get narrowHeader => Intl.message("TYPE TO NARROW",
      name: "deepSearchNarrowHeader",
      desc: "Deep Search empty state: header of the typed filter examples");
  static String get removeRecent => Intl.message("Remove",
      name: "deepSearchRemoveRecent",
      desc: "Deep Search: tooltip that removes one recent search");

  // Results (Mockup 3).
  static String get mostMatches => Intl.message("MOST MATCHES",
      name: "deepSearchMostMatches",
      desc: "Deep Search: header of the strip of chats with the most matches");
  static String moreRooms(int n) => Intl.message("+$n more",
      args: [n],
      name: "deepSearchMoreRooms",
      desc: "Deep Search: more chats than the strip shows");
  static String localHeader(bool newest) =>
      newest ? localHeaderNewest : localHeaderBest;
  static String get localHeaderBest =>
      Intl.message("ON THIS DEVICE · ENCRYPTED CHATS AND DMS · BEST MATCH",
          name: "deepSearchLocalHeaderBest",
          desc: "Deep Search: header of the results from this device's index");
  static String get localHeaderNewest =>
      Intl.message("ON THIS DEVICE · ENCRYPTED CHATS AND DMS · NEWEST FIRST",
          name: "deepSearchLocalHeaderNewest",
          desc: "Deep Search: header of the results from this device's index");
  static String get localHeaderShort => Intl.message("ON THIS DEVICE",
      name: "deepSearchLocalHeaderShort",
      desc: "Deep Search (phone): header of this device's results");
  static String get webLocalHeader =>
      Intl.message("LOADED MESSAGES · THIS SESSION",
          name: "deepSearchWebLocalHeader",
          desc: "Deep Search on the web: header of results from loaded chats");
  static String get serverHeader => Intl.message(
      "UNENCRYPTED ROOMS · SEARCHED ON YOUR HOMESERVER · NEWEST FIRST",
      name: "deepSearchServerHeader",
      desc: "Deep Search: header of the homeserver's results");
  static String get serverHeaderShort =>
      Intl.message("UNENCRYPTED ROOMS · SERVER",
          name: "deepSearchServerHeaderShort",
          desc: "Deep Search (phone): header of the homeserver's results");
  static String get loadMore => Intl.message("Load more from the server",
      name: "deepSearchLoadMore",
      desc: "Deep Search: loads the next page of homeserver results");
  static String get serverFailed =>
      Intl.message("Couldn’t search your homeserver. Try again",
          name: "deepSearchServerFailed",
          desc: "Deep Search: the homeserver search failed; tap to retry");
  static String get serverOffline => Intl.message(
      "Not searched while you’re offline",
      name: "deepSearchServerOffline",
      desc:
          "Deep Search: the homeserver's results are missing because the app is offline");
  static String get serverNeedsWords => Intl.message(
      "Unencrypted rooms are searched on your homeserver, which needs words to search for.",
      name: "deepSearchServerNeedsWords",
      desc: "Deep Search: filters alone don't search the homeserver");
  static String get noResults => Intl.message("No messages found",
      name: "deepSearchNoResults", desc: "Deep Search: nothing matched");
  static String get noServerResults =>
      Intl.message("Nothing more in unencrypted rooms",
          name: "deepSearchNoServerResults",
          desc: "Deep Search: the homeserver found nothing more");
  static String moreHere(int n) => Intl.message("+$n more here",
      args: [n],
      name: "deepSearchMoreHere",
      desc: "Deep Search: more matches near this one in the same chat");
  static String get directMessage => Intl.message("DM",
      name: "deepSearchDirectMessage",
      desc: "Deep Search result: the message is in a direct message");
  static String inRoom(String room) => Intl.message("in $room",
      args: [room],
      name: "deepSearchInRoom",
      desc: "Deep Search result: the chat a message is in");
  static String get oldVersion => Intl.message("(old version)",
      name: "deepSearchOldVersion",
      desc: "Deep Search result: from an earlier version of an upgraded room");
  static String get tagEdited => Intl.message("edited",
      name: "deepSearchTagEdited", desc: "Deep Search result tag");
  static String get tagLink => Intl.message("link",
      name: "deepSearchTagLink", desc: "Deep Search result tag");
  static String get tagThread => Intl.message("in thread",
      name: "deepSearchTagThread", desc: "Deep Search result tag");
  static String get seen => Intl.message("seen",
      name: "deepSearchSeen",
      desc: "Deep Search result: already opened from this search");
  static String get lastOpened => Intl.message("last opened",
      name: "deepSearchLastOpened",
      desc: "Deep Search result: the one opened last from this search");
  static String stillIndexing(int n) => Intl.message(
      "$n encrypted chats are still indexing; their older messages aren’t searched yet.",
      args: [n],
      name: "deepSearchStillIndexing",
      desc: "Deep Search: footer under the results while indexing");
  static String get pickToSearchBack =>
      Intl.message("Pick one to search further back ›",
          name: "deepSearchPickToSearchBack",
          desc: "Deep Search: footer action that scopes to one chat");
  static String get searchThisChat => Intl.message("Search only this chat",
      name: "deepSearchSearchThisChat",
      desc: "Deep Search result hold menu: scope to the result's chat");
  static String resultsAnnounce(int n) => Intl.plural(n,
      zero: "No results",
      one: "1 result",
      other: "$n results",
      args: [n],
      name: "deepSearchResultsAnnounce",
      desc: "Deep Search: what a screen reader hears when results change");

  // Opening (Mockup 4b).
  static String get youLeft => Intl.message("You left this room",
      name: "deepSearchYouLeft",
      desc: "Deep Search: a result is in a room you're no longer in");
  static String get results => Intl.message("Results",
      name: "deepSearchResults",
      desc: "Deep Search results bar in a chat: back to the list");
  static String position(int index, int count) =>
      Intl.message("$index of $count",
          args: [index, count],
          name: "deepSearchPosition",
          desc: "Deep Search results bar: which result is open, e.g. 3 of 14");
  static String get previous => Intl.message("Previous result (Ctrl+Shift+G)",
      name: "deepSearchPrevious",
      desc: "Deep Search results bar: tooltip of the up button");
  static String get next => Intl.message("Next result (Ctrl+G)",
      name: "deepSearchNext",
      desc: "Deep Search results bar: tooltip of the down button");
  static String get endSearch => Intl.message("End search",
      name: "deepSearchEndSearch",
      desc: "Deep Search results bar: tooltip of the close button");
}
