import 'package:intl/intl.dart';

String get directoryTitle => Intl.message("Explore rooms",
    desc: "Title of the public room directory page, and the tooltip of the "
        "sidebar button that opens it",
    name: "directoryTitle");

String get directorySearchPlaceholder => Intl.message("Search rooms and spaces",
    desc: "Placeholder of the search box in the room directory",
    name: "directorySearchPlaceholder");

String get directoryFilterAll => Intl.message("All",
    desc: "Room directory filter: rooms and spaces",
    name: "directoryFilterAll");

String get directoryFilterRooms => Intl.message("Rooms",
    desc: "Room directory filter: only rooms", name: "directoryFilterRooms");

String get directoryFilterSpaces => Intl.message("Spaces",
    desc: "Room directory filter: only spaces", name: "directoryFilterSpaces");

String get directoryJoinAs => Intl.message("Join as",
    desc: "Label in front of the account picker that chooses who joins",
    name: "directoryJoinAs");

String get directoryJoin =>
    Intl.message("Join", desc: "Join a room or space", name: "directoryJoin");

String get directoryOpen => Intl.message("Open",
    desc: "Open a room or space the account is already in",
    name: "directoryOpen");

String directoryJoinAsAccount(String account) =>
    Intl.message("Join as $account",
        desc: "Button to retry a failed join with another signed-in account",
        args: [account],
        name: "directoryJoinAsAccount");

String directoryMembers(int count) => Intl.plural(count,
    one: "$count member",
    other: "$count members",
    desc: "Member count of a room in the directory",
    args: [count],
    name: "directoryMembers");

String directoryRoomCount(int count) => Intl.plural(count,
    one: "$count room",
    other: "$count rooms",
    desc: "Number of rooms in a space",
    args: [count],
    name: "directoryRoomCount");

String directoryMoreRooms(int count) => Intl.message("and $count more",
    desc: "Shown after a shortened list of a space's rooms",
    args: [count],
    name: "directoryMoreRooms");

String get directoryBadgeSpace => Intl.message("Space",
    desc: "Badge on a space", name: "directoryBadgeSpace");

String get directoryBadgeEncrypted => Intl.message("Encrypted",
    desc: "Badge on an encrypted room", name: "directoryBadgeEncrypted");

String get directoryBadgeGuests => Intl.message("Guests allowed",
    desc: "Badge on a room that guests can join", name: "directoryBadgeGuests");

String get directoryBadgeReadable => Intl.message("Readable without joining",
    desc: "Badge on a room whose history anyone can read",
    name: "directoryBadgeReadable");

String get directoryBadgeKnock => Intl.message("Ask to join",
    desc: "Badge on a room that has to be knocked on",
    name: "directoryBadgeKnock");

String get directoryLoadingDetails => Intl.message("Loading details…",
    desc: "Shown while an expanded directory row loads its details",
    name: "directoryLoadingDetails");

String get directoryNoTopic => Intl.message("No description",
    desc: "Shown in an expanded directory row when a room has no topic",
    name: "directoryNoTopic");

String get directoryEmpty =>
    Intl.message("This server has no public rooms or spaces yet.",
        desc: "Room directory is empty", name: "directoryEmpty");

// Vommet: the empty message follows the Rooms / Spaces filter (it said "no
// public rooms" when only spaces were missing).
String get directoryEmptyRooms =>
    Intl.message("This server has no public rooms yet.",
        desc: "Room directory has no rooms (Rooms filter)",
        name: "directoryEmptyRooms");

String get directoryEmptySpaces =>
    Intl.message("This server has no public spaces yet.",
        desc: "Room directory has no spaces (Spaces filter)",
        name: "directoryEmptySpaces");

String directoryNoMatches(String search) =>
    Intl.message("Nothing matches “$search”.",
        desc: "No directory results for a search",
        args: [search],
        name: "directoryNoMatches");

String directoryRemoteNotShared(String server) =>
    Intl.message("$server doesn't share its room directory with other servers.",
        desc: "A remote server refuses to show its directory to other servers",
        args: [server],
        name: "directoryRemoteNotShared");

String directoryRemoteNotSharedHint(String server) => Intl.message(
    "If you have an account on $server, sign in with it as well and its rooms will show up here.",
    desc: "Hint below directoryRemoteNotShared",
    args: [server],
    name: "directoryRemoteNotSharedHint");

String directoryOwnServerRestricted(String server) => Intl.message(
    "Your server ($server) doesn't let its users browse its room directory.",
    desc: "The user's own homeserver refuses to show its directory",
    args: [server],
    name: "directoryOwnServerRestricted");

String get directoryOwnServerRestrictedHint => Intl.message(
    "This is a server setting. Ask your server's admin, or browse another server.",
    desc: "Hint below directoryOwnServerRestricted",
    name: "directoryOwnServerRestrictedHint");

String directoryUnreachable(String server) =>
    Intl.message("Couldn't reach $server.",
        desc: "A directory server doesn't exist or is down",
        args: [server],
        name: "directoryUnreachable");

String get directoryUnreachableHint =>
    Intl.message("Check the server name and try again.",
        desc: "Hint below directoryUnreachable",
        name: "directoryUnreachableHint");

String get directoryFailed => Intl.message("Couldn't load the room directory.",
    desc: "Generic room directory error", name: "directoryFailed");

String get directoryRetry =>
    Intl.message("Try again", desc: "Retry button", name: "directoryRetry");

String get directoryJoinFailed => Intl.message("Couldn't join.",
    desc: "Joining a room from the directory failed",
    name: "directoryJoinFailed");

String get directoryServerYours => Intl.message("Your servers",
    desc: "Server chooser section: servers the user has accounts on",
    name: "directoryServerYours");

String get directoryServerSaved => Intl.message("Saved",
    desc: "Server chooser section: servers the user saved",
    name: "directoryServerSaved");

String get directoryServerSuggested => Intl.message("Suggested",
    desc: "Server chooser section: suggested servers",
    name: "directoryServerSuggested");

String get directoryServerHideSuggested => Intl.message("Hide",
    desc: "Hide the suggested servers section",
    name: "directoryServerHideSuggested");

String get directoryServerSearch => Intl.message("Find or add a server",
    desc: "Placeholder of the server chooser search box",
    name: "directoryServerSearch");

String directoryServerBrowse(String server) => Intl.message("Browse $server",
    desc: "Browse a server typed into the server chooser",
    args: [server],
    name: "directoryServerBrowse");

String directoryServerMoreSaved(int count) =>
    Intl.message("$count more, type to search",
        desc: "Saved servers hidden by the server chooser's length cap",
        args: [count],
        name: "directoryServerMoreSaved");

String get directoryServerSave => Intl.message("Save server",
    desc: "Tooltip: save the browsed server", name: "directoryServerSave");

String get directoryServerUnsave => Intl.message("Remove from saved",
    desc: "Tooltip: forget a saved server", name: "directoryServerUnsave");

String directoryServerVia(String account) => Intl.message("via $account",
    desc: "Which signed-in account browses a server",
    args: [account],
    name: "directoryServerVia");

String get directoryServerChoose => Intl.message("Choose server",
    desc: "Title of the server chooser", name: "directoryServerChoose");
