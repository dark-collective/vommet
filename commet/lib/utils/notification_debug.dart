import 'dart:math';

import 'package:commet/client/room.dart';
import 'package:commet/client/matrix/components/threads/thread_read_scope.dart';

// Vommet issue 949: "Copy notification debug". What every badge shows and
// why, per room, as numbers only, so a tester can share it when badges look
// wrong. Privacy is the point: nothing here holds a name, a message, a user
// or server name or an event id. Rooms are #1, #2… and spaces S1, S2…,
// numbered in a new random order every time. This file is the plain model
// (no app state), so the checks and the text can be unit tested; the
// collector is notification_debug_collect.dart.

enum DebugRoomKind { dm, inSpace, outside }

/// Which of the account's own read receipts is the newest.
enum DebugReceipt { none, public, private }

/// The thread of that receipt.
enum DebugReceiptThread { unthreaded, main, thread }

/// How the SDK gets the room counts.
enum DebugCountSource { classicSync, slidingTrusted, slidingLocal }

class DebugRoom {
  DebugRoom({
    required this.kind,
    required this.rule,
    this.favourite = false,
    this.lowPriority = false,
    this.groupSize = 1,
    this.olderGroupCount = 0,
    this.spaces = const [],
    this.count = 0,
    this.serverHighlights = 0,
    this.localHighlights = 0,
    this.markedUnread = false,
    this.receipt = DebugReceipt.none,
    this.receiptThread = DebugReceiptThread.unthreaded,
    this.receiptOnNewest = false,
    this.newestIsOwn = false,
    this.fullyReadOnNewest = false,
    this.threadScope,
    this.badge = 0,
    this.badgeNoisy = false,
    this.dot = false,
    this.rowDot = false,
    this.railIcon = 0,
    this.homeAdds = 0,
    this.inDmSection = false,
    this.trayChat = false,
    this.olderTrayChats = 0,
    this.unreadCard = false,
    this.cardUnread = 0,
  });

  // What the room is.
  final DebugRoomKind kind;
  final PushRule rule;
  final bool favourite;
  final bool lowPriority;

  /// A direct message: how many rooms you have with that person (this one
  /// is the newest, shown one; older ones aren't listed on their own).
  final int groupSize;

  /// A direct message: the raw counts of the person's older rooms.
  final int olderGroupCount;

  /// Keys of the spaces holding the room (see [DebugSnapshot.spaces]).
  final List<String> spaces;

  // The counts.
  /// The SDK's notification count (the server's, or counted here).
  final int count;
  final int serverHighlights;

  /// Mentions found on this device in encrypted messages.
  final int localHighlights;
  final bool markedUnread;

  // The read state.
  final DebugReceipt receipt;
  final DebugReceiptThread receiptThread;
  final bool receiptOnNewest;
  final bool newestIsOwn;
  final bool fullyReadOnNewest;
  final ThreadReadScope? threadScope;

  // What the app shows for it.
  /// The number on its row (badgeCount) and whether it's red.
  final int badge;
  final bool badgeNoisy;

  /// The row's unread dot (roomHasUnread).
  final bool dot;

  /// A direct message's row dot: any of the person's rooms is unread.
  final bool rowDot;

  /// A direct message's rail icon: all the person's rooms added up.
  final int railIcon;

  /// What it adds to Home and People (raw counts of direct messages).
  final int homeAdds;

  /// Shown in New Home's Direct messages section (adds [badge] to it).
  final bool inDmSection;

  /// Counted as a chat by the tray, the taskbar and the mobile header.
  final bool trayChat;

  /// A direct message: the person's older rooms the tray counts too.
  final int olderTrayChats;

  /// Listed on Home's Unread card.
  final bool unreadCard;

  /// Unread rows on Home's Notifications card.
  final int cardUnread;

  bool get isDm => kind == DebugRoomKind.dm;

  int get highlights => serverHighlights + localHighlights;

  /// Whether the room has anything to say: a count, a mark or a badge.
  bool get worthListing =>
      count > 0 ||
      highlights > 0 ||
      markedUnread ||
      badge > 0 ||
      dot ||
      rowDot ||
      railIcon > 0 ||
      homeAdds > 0 ||
      trayChat ||
      olderTrayChats > 0 ||
      cardUnread > 0;
}

/// A space's badge on the rail.
class DebugSpace {
  DebugSpace(this.key, {required this.badge, this.dot = false});

  /// Internal key, only to tie rooms to it; never printed.
  final String key;
  final int badge;
  final bool dot;
}

/// The totals each aggregate shows.
class DebugTotals {
  const DebugTotals({
    this.home = 0,
    this.homeInvites = 0,
    this.homeCountsDms = true,
    this.people = 0,
    this.peopleInvites = 0,
    this.dmHeader = 0,
    this.dmRows = 0,
    this.roomsRail = 0,
    this.roomsRailDots = 0,
    this.trayChats = 0,
    this.unreadCard = 0,
    this.cardUnread = 0,
    this.cardEarlier = 0,
    this.cardLoaded = false,
  });

  final int home;
  final int homeInvites;
  final bool homeCountsDms;
  final int people;
  final int peopleInvites;
  final int dmHeader;
  final int dmRows;
  final int roomsRail;
  final int roomsRailDots;
  final int trayChats;
  final int unreadCard;
  final int cardUnread;
  final int cardEarlier;

  /// Whether the Notifications card's list was loaded this session.
  final bool cardLoaded;
}

class DebugCheck {
  const DebugCheck(this.ok, this.lines);
  final bool ok;
  final List<String> lines;
}

class DebugSnapshot {
  DebugSnapshot({
    required this.rooms,
    this.spaces = const [],
    this.totals = const DebugTotals(),
    this.build = "",
    this.platform = "",
    this.layout = "",
    this.accounts = 1,
    this.countSource = DebugCountSource.classicSync,
    Random? random,
  }) {
    // Fresh numbers in a random order, so nothing can be matched between
    // two dumps.
    final rnd = random ?? Random.secure();
    final listed = rooms.where((r) => r.worthListing).toList()..shuffle(rnd);
    for (var i = 0; i < listed.length; i++) {
      _roomNo[listed[i]] = i + 1;
    }
    final order = spaces.toList()..shuffle(rnd);
    for (var i = 0; i < order.length; i++) {
      _spaceNo[order[i].key] = i + 1;
    }
    this.listed = listed;
  }

  final List<DebugRoom> rooms;
  final List<DebugSpace> spaces;
  final DebugTotals totals;
  final String build;
  final String platform;
  final String layout;
  final int accounts;
  final DebugCountSource countSource;

  late final List<DebugRoom> listed;
  final Map<DebugRoom, int> _roomNo = {};
  final Map<String, int> _spaceNo = {};

  String no(DebugRoom room) => "#${_roomNo[room] ?? "?"}";
  String spaceNo(String key) => "S${_spaceNo[key] ?? "?"}";

  /// Plain-word checks: aggregates against the rooms they add up.
  List<DebugCheck> checks() {
    final result = <DebugCheck>[];
    final rows = rooms.where((r) => r.inDmSection);
    final rowSum = rows.fold(0, (s, r) => s + r.badge);
    if (totals.dmHeader != rowSum) {
      result.add(DebugCheck(false, [
        "Direct messages ${totals.dmHeader} ≠ its rows $rowSum",
      ]));
    }

    final homeDms = totals.home - totals.homeInvites;
    if (totals.homeCountsDms && homeDms != totals.dmHeader) {
      final lines = [
        "Direct messages ${totals.dmHeader} ≠ Home's DMs $homeDms"
      ];
      for (final r in rooms.where((r) => r.isDm)) {
        final header = r.inDmSection ? r.badge : 0;
        if (header == r.homeAdds) continue;
        lines.add("${no(r)} adds $header to the header, ${r.homeAdds} to Home");
        final why = _why(r);
        if (why.isNotEmpty) lines.add("($why)");
      }
      result.add(DebugCheck(false, lines));
    } else {
      result.add(DebugCheck(true, ["Direct messages = Home's DMs"]));
    }

    final peopleDms = totals.people - totals.peopleInvites;
    if (totals.homeCountsDms && peopleDms != homeDms) {
      result.add(
          DebugCheck(false, ["People's DMs $peopleDms ≠ Home's DMs $homeDms"]));
    }
    if (totals.peopleInvites != totals.homeInvites) {
      result.add(DebugCheck(false, [
        "People's invites ${totals.peopleInvites} ≠ "
            "Home's invites ${totals.homeInvites}",
      ]));
    }

    for (final r in rooms.where((r) => r.isDm && r.inDmSection)) {
      if (r.railIcon == r.badge) continue;
      result.add(DebugCheck(false, [
        "${no(r)}: rail icon shows ${r.railIcon}, row shows "
            "${r.badge > 0 ? r.badge : (r.rowDot ? "a dot" : "nothing")}",
        if (r.olderGroupCount > 0)
          "(${r.groupSize - 1} older room${r.groupSize > 2 ? "s" : ""}, "
              "same person: ${r.olderGroupCount} unread)",
      ]));
    }

    final hidden = rooms.where(
        (r) => r.isDm && !r.inDmSection && (r.homeAdds > 0 || r.badge > 0));
    for (final r in hidden) {
      result.add(DebugCheck(false, [
        "${no(r)} counts on Home, not in Direct",
        "messages${r.favourite ? " (in Favorites)" : r.lowPriority ? " (in Low priority)" : ""}",
      ]));
    }

    var spacesOk = true;
    for (final space in spaces) {
      final sum = rooms
          .where((r) => r.spaces.contains(space.key))
          .fold(0, (s, r) => s + (r.rule == PushRule.dontNotify ? 0 : r.badge));
      if (sum == space.badge || space.badge == 0) continue;
      spacesOk = false;
      result.add(DebugCheck(
          false, ["${spaceNo(space.key)} ${space.badge} ≠ its rooms $sum"]));
    }
    if (spacesOk && spaces.isNotEmpty) {
      result.add(const DebugCheck(true, ["Each space = its rooms added up"]));
    }

    final numbered =
        rooms.fold(0, (s, r) => s + (r.trayChat ? 1 : 0) + r.olderTrayChats);
    result.add(totals.trayChats == numbered
        ? DebugCheck(
            true, ["Tray ${totals.trayChats} chats = $numbered rooms counted"])
        : DebugCheck(false,
            ["Tray ${totals.trayChats} chats ≠ $numbered rooms counted"]));

    if (totals.cardLoaded) {
      final cardRooms = rooms.where((r) => r.cardUnread > 0).length;
      final counted = rooms.where((r) => r.count > 0 || r.highlights > 0);
      final missing = counted.where((r) => r.cardUnread == 0).length;
      if (missing > 0) {
        result.add(DebugCheck(false, [
          "Notifications card has unread rows in $cardRooms rooms;",
          "$missing room${missing == 1 ? "" : "s"} with a count "
              "${missing == 1 ? "has" : "have"} none there",
        ]));
      }
    }

    final dotOnly = rooms.where((r) => r.dot && r.badge == 0 && r.count == 0);
    if (dotOnly.isNotEmpty) {
      result.add(DebugCheck(true, [
        "${dotOnly.length} room${dotOnly.length == 1 ? "" : "s"} "
            "show only a dot (no count)",
      ]));
    }
    return result;
  }

  static String _why(DebugRoom r) {
    if (r.rule == PushRule.dontNotify && r.homeAdds > 0) return "muted";
    if (r.localHighlights > 0 && r.count == 0) {
      return "${r.localHighlights} found here, server count 0";
    }
    if (r.rule == PushRule.mentionsOnly) return "Mentions only";
    if (r.olderGroupCount > 0) return "older room with the same person";
    if (!r.inDmSection) {
      return r.favourite
          ? "in Favorites"
          : r.lowPriority
              ? "in Low priority"
              : "not in the section";
    }
    return "";
  }

  String text() {
    final b = StringBuffer();
    final dms = rooms.where((r) => r.isDm).length;
    final inSpaces = rooms.where((r) => r.kind == DebugRoomKind.inSpace).length;
    final outside = rooms.where((r) => r.kind == DebugRoomKind.outside).length;
    b.writeln("Vommet notification debug");
    b.writeln([build, platform, if (layout.isNotEmpty) "$layout layout"]
        .where((s) => s.isNotEmpty)
        .join(" · "));
    b.writeln("$accounts account${accounts == 1 ? "" : "s"} · "
        "${rooms.length} rooms: $dms DMs, $inSpaces in spaces,");
    b.writeln("$outside outside spaces · counts ${switch (countSource) {
      DebugCountSource.classicSync => "from the server",
      DebugCountSource.slidingTrusted => "from the server",
      DebugCountSource.slidingLocal => "counted here",
    }}");
    b.writeln();
    b.writeln("WHAT THE BADGES SHOW");
    void line(String name, Object value, [String note = ""]) => b.writeln(
        "${name.padRight(20)}${"$value".padLeft(3)}${note.isEmpty ? "" : "  $note"}"
            .trimRight());
    line("Home (rail)", totals.home,
        "invites ${totals.homeInvites}${totals.homeCountsDms ? " + DMs ${totals.home - totals.homeInvites}" : ""}");
    line("People", totals.people,
        "invites ${totals.peopleInvites} + DMs ${totals.people - totals.peopleInvites}");
    line("Direct messages", totals.dmHeader, "over ${totals.dmRows} rows");
    line("Rooms (#)", totals.roomsRail,
        "${totals.roomsRailDots} dot${totals.roomsRailDots == 1 ? "" : "s"}");
    final sortedSpaces = spaces.toList()
      ..sort((a, c) => _spaceNo[a.key]!.compareTo(_spaceNo[c.key]!));
    for (final s in sortedSpaces) {
      line("Space ${spaceNo(s.key)}", s.badge, s.dot ? "dot" : "");
    }
    line("Tray / taskbar", totals.trayChats, "chats");
    line("Unread card", totals.unreadCard, "rooms");
    if (totals.cardLoaded) {
      line("Notifications card", totals.cardUnread,
          "unread, ${totals.cardEarlier} earlier");
    } else {
      b.writeln("Notifications card    -  not opened yet");
    }
    b.writeln();

    final checks = this.checks();
    final broken = checks.where((c) => !c.ok).length;
    b.writeln("CHECKS: $broken broken");
    for (final c in checks) {
      for (var i = 0; i < c.lines.length; i++) {
        b.writeln("${i == 0 ? (c.ok ? "✓ " : "✗ ") : "  "}${c.lines[i]}");
      }
    }
    b.writeln();

    b.writeln("ROOMS (new numbers, new order every time)");
    final sorted = listed.toList()
      ..sort((a, c) => _roomNo[a]!.compareTo(_roomNo[c]!));
    for (final r in sorted) {
      _room(b, r);
    }
    final quiet = rooms.length - listed.length;
    if (quiet > 0) {
      b.writeln("$quiet more room${quiet == 1 ? "" : "s"}: nothing unread, "
          "no badge");
    }
    return b.toString();
  }

  void _room(StringBuffer b, DebugRoom r) {
    final kind = switch (r.kind) {
      DebugRoomKind.dm =>
        "DM · ${r.groupSize} room${r.groupSize == 1 ? "" : "s"}",
      DebugRoomKind.inSpace => "Room in ${r.spaces.map(spaceNo).join(", ")}",
      DebugRoomKind.outside => "Room outside spaces",
    };
    final rule = switch (r.rule) {
      PushRule.notify => "All messages",
      PushRule.mentionsOnly => "Mentions only",
      PushRule.dontNotify => "Off",
    };
    final tags = [
      if (r.favourite) "favorite",
      if (r.lowPriority) "low priority",
    ];
    b.writeln("${no(r)} $kind · $rule");
    if (tags.isNotEmpty) b.writeln("   ${tags.join(", ")}");
    b.writeln("   server ${r.count} · mentions ${r.serverHighlights} · "
        "found here ${r.localHighlights}");
    if (r.olderGroupCount > 0) {
      b.writeln("   older rooms with the person: ${r.olderGroupCount}");
    }
    final receipt = switch (r.receipt) {
      DebugReceipt.none => "no receipt",
      DebugReceipt.public => "receipt public",
      DebugReceipt.private => "receipt private",
    };
    final thread =
        r.receipt == DebugReceipt.none ? "" : ", ${r.receiptThread.name}";
    final where = r.newestIsOwn
        ? "newest is yours"
        : r.receiptOnNewest
            ? "on newest"
            : "not on newest";
    b.writeln("   $receipt$thread, $where");
    b.writeln("   fully read: ${r.fullyReadOnNewest ? "yes" : "no"} · "
        "marked unread: ${r.markedUnread ? "yes" : "no"}");
    if (r.threadScope != null) {
      b.writeln("   threads: ${switch (r.threadScope!) {
        ThreadReadScope.off => "Off",
        ThreadReadScope.mine => "Threads I'm in",
        ThreadReadScope.all => "All threads",
      }}");
    }
    final shows = <String>[
      r.badge > 0
          ? "row ${r.badgeNoisy ? "red" : "gray"} ${r.badge}"
          : (r.isDm ? r.rowDot : r.dot)
              ? "row dot"
              : "row -",
      if (r.isDm && r.inDmSection) "header +${r.badge}",
      if (r.isDm) "Home +${r.homeAdds}",
      if (r.isDm && r.railIcon > 0) "rail icon ${r.railIcon}",
      for (final s in r.spaces)
        if (r.badge > 0) "${spaceNo(s)} +${r.badge}",
      if (r.trayChat) "tray chat",
      if (r.olderTrayChats > 0) "tray +${r.olderTrayChats} older",
      if (r.unreadCard) "Unread card",
      if (r.cardUnread > 0) "card ${r.cardUnread}",
    ];
    // Wrapped so no line passes 46 characters (phones).
    var current = "   shows:";
    for (final part in shows) {
      final next = "$current ${current.endsWith(":") ? "" : "· "}$part";
      if (next.length > 46 && !current.endsWith(":")) {
        b.writeln(current);
        current = "          $part";
      } else {
        current = next;
      }
    }
    b.writeln(current);
  }
}
