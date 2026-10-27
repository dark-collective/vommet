// Vommet (Deep Search, stage 2): the always-visible coverage line
// (Decision 10, Mockup 5). Several states can show at once, most limiting
// first, each with at most one action. Pure: built from the index's state
// and totals, the network and (scoped to one room) the room's coverage, so
// the UI only lays the lines out. Coverage is per account: the UI builds
// the lines for each account in the account filter.
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';

enum DeepSearchCoverageKind {
  /// Web: no index.
  web,
  off,
  wifiPaused,
  batteryPaused,

  /// Server results missing (offline, or /search failed).
  offline,

  /// Running, nothing complete yet.
  firstRun,
  building,

  /// Every encrypted chat is fully indexed.
  complete,
  keysMissing,

  /// Scoped to one room.
  roomNotIndexed,
  roomPartial,
  roomComplete,

  /// Scoped to an unencrypted group room: the server searches it.
  roomServerOnly,
}

/// What a line's action does.
enum DeepSearchCoverageAction {
  /// MatrixEncryptedSearchIndexComponent.allowMobileDataThisSession().
  indexOnMobileData,

  /// Open the index setting.
  openSettings,

  /// The undecryptable-messages details.
  keyDetails,

  /// indexOlder(room); confirm first when [DeepSearchCoverageLine.confirm].
  lookFurtherBack,
}

class DeepSearchCoverageLine {
  const DeepSearchCoverageLine(this.kind, this.title,
      {this.detail, this.action, this.actionLabel, this.confirm = false});

  final DeepSearchCoverageKind kind;
  final String title;
  final String? detail;
  final DeepSearchCoverageAction? action;
  final String? actionLabel;

  /// The action needs the confirm sheet first ([deepSearchConfirmSheet]).
  final bool confirm;
}

/// One account's inputs.
class DeepSearchCoverageInput {
  const DeepSearchCoverageInput({
    required this.state,
    required this.totals,
    this.indexAvailable = true,
    this.online = true,
    this.serverWanted = true,
    this.serverFailed = false,
    this.mobileDataNeedsConfirmation = false,
    this.room,
  });

  final EncryptedIndexState state;

  /// coverageTotals() over the encrypted chats in scope.
  final IndexCoverageTotals totals;

  /// MatrixEncryptedSearchIndexComponent.available (false on web).
  final bool indexAvailable;
  final bool online;

  /// The query searches the server (it has words, unencrypted rooms are
  /// in scope).
  final bool serverWanted;
  final bool serverFailed;

  /// indexOlderNeedsConfirmation (Wi-Fi only, on mobile data).
  final bool mobileDataNeedsConfirmation;

  /// Scoped to one room.
  final DeepSearchRoomCoverageInput? room;
}

/// Share of [done] in [total] as a whole percent, rounded, but never 100
/// until everything is done ("86%" for 412 of 480).
int deepSearchPercent(int done, int total) {
  if (total <= 0) return 0;
  final pct = (done * 100 / total).round();
  return done < total && pct >= 100 ? 99 : pct;
}

class DeepSearchRoomCoverageInput {
  const DeepSearchRoomCoverageInput({
    required this.name,
    required this.indexed,
    this.coverage = RoomCoverage.unknown,
    this.createdTs,
  });

  /// "#tea-garden".
  final String name;

  /// isIndexed(room): encrypted or a DM. Otherwise the server searches it.
  final bool indexed;
  final RoomCoverage coverage;

  /// When the room was created (ms), for "(room since 2021)".
  final int? createdTs;
}

const _months = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", //
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// "1,700".
String deepSearchCount(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? "-" : "");
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(",");
    out.write(s[i]);
  }
  return out.toString();
}

/// "Mar 2024".
String deepSearchMonth(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return "${_months[d.month - 1]} ${d.year}";
}

String _messages(int n) =>
    n == 1 ? "1 message" : "${deepSearchCount(n)} messages";

/// The coverage lines, most limiting first.
List<DeepSearchCoverageLine> deepSearchCoverage(DeepSearchCoverageInput i) {
  final lines = <DeepSearchCoverageLine>[];
  final t = i.totals;
  final web = !i.indexAvailable || i.state == EncryptedIndexState.unavailable;
  final allComplete = t.rooms > 0 && t.complete >= t.rooms;

  if (web) {
    lines.add(const DeepSearchCoverageLine(
        DeepSearchCoverageKind.web, "Web: no search index",
        detail: "Encrypted chats: only what’s loaded is searched. "
            "The desktop and phone apps search full history."));
  } else if (!allComplete) {
    switch (i.state) {
      case EncryptedIndexState.off:
        lines.add(const DeepSearchCoverageLine(
            DeepSearchCoverageKind.off, "Indexing is off",
            detail: "Encrypted chats: only messages already on this device "
                "are searched.",
            action: DeepSearchCoverageAction.openSettings,
            actionLabel: "Turn on in Settings ›"));
      case EncryptedIndexState.waitingForWifi:
        final pct = deepSearchPercent(t.complete, t.rooms);
        lines.add(DeepSearchCoverageLine(
            DeepSearchCoverageKind.wifiPaused, "Indexing paused: not on Wi-Fi",
            detail: "Searching what’s indexed so far ($pct% of chats).",
            action: DeepSearchCoverageAction.indexOnMobileData,
            actionLabel: "Index on mobile data this session ›"));
      case EncryptedIndexState.pausedForBattery:
        lines.add(const DeepSearchCoverageLine(
            DeepSearchCoverageKind.batteryPaused,
            "Indexing paused: battery saver",
            detail: "Resumes when charging, or when battery saver is turned "
                "off."));
      case EncryptedIndexState.unavailable:
      case EncryptedIndexState.running:
      case EncryptedIndexState.done:
        break;
    }
  }

  if (i.serverWanted && (!i.online || i.serverFailed)) {
    lines.add(
        const DeepSearchCoverageLine(DeepSearchCoverageKind.offline, "Offline",
            detail: "Showing this device only. Unencrypted rooms are searched "
                "again when you reconnect."));
  }

  final room = i.room;
  if (room != null) {
    lines.add(_roomLine(i, room));
  } else if (!web) {
    final indexing = i.state == EncryptedIndexState.running ||
        i.state == EncryptedIndexState.done;
    if (allComplete || t.rooms == 0) {
      lines.add(DeepSearchCoverageLine(DeepSearchCoverageKind.complete,
          "Searched all ${deepSearchCount(t.rooms)} encrypted chats fully"));
    } else if (indexing && t.complete == 0) {
      lines.add(const DeepSearchCoverageLine(
          DeepSearchCoverageKind.firstRun, "Building your search index",
          detail: "Recent messages are searchable now. Older history is "
              "indexed on Wi-Fi, DMs first."));
    } else {
      final left = t.rooms - t.complete;
      lines.add(DeepSearchCoverageLine(
          DeepSearchCoverageKind.building,
          "Searched ${deepSearchCount(t.complete)} of "
          "${deepSearchCount(t.rooms)} encrypted chats fully",
          detail: i.state == EncryptedIndexState.off
              ? "${deepSearchCount(left)} not indexed: their older "
                  "messages aren’t searched."
              : "${deepSearchCount(left)} still indexing: their older "
                  "messages aren’t searched yet."));
    }
  }

  final undecrypted = room != null ? room.coverage.undecrypted : t.undecrypted;
  if (!web && undecrypted > 0) {
    lines.add(DeepSearchCoverageLine(DeepSearchCoverageKind.keysMissing,
        "${_messages(undecrypted)} can’t be decrypted yet",
        detail: "Searchable once their keys arrive from key backup or "
            "another of your devices.",
        action: DeepSearchCoverageAction.keyDetails,
        actionLabel: "Details ›"));
  }
  return lines;
}

DeepSearchCoverageLine _roomLine(
    DeepSearchCoverageInput i, DeepSearchRoomCoverageInput room) {
  if (!room.indexed) {
    return const DeepSearchCoverageLine(
        DeepSearchCoverageKind.roomServerOnly, "Searched on your homeserver",
        detail: "This room isn’t encrypted, so your homeserver searches its "
            "history.");
  }
  final web = !i.indexAvailable || i.state == EncryptedIndexState.unavailable;
  final confirm = i.state == EncryptedIndexState.off ||
      (i.state == EncryptedIndexState.waitingForWifi &&
          i.mobileDataNeedsConfirmation);
  final c = room.coverage;
  if (!c.known) {
    return DeepSearchCoverageLine(
        DeepSearchCoverageKind.roomNotIndexed, "Not indexed yet",
        detail: "Only messages already on this device are searched.",
        action: web ? null : DeepSearchCoverageAction.lookFurtherBack,
        actionLabel: web ? null : "Look further back ›",
        confirm: confirm);
  }
  if (c.complete) {
    return DeepSearchCoverageLine(DeepSearchCoverageKind.roomComplete,
        c.historyLimited ? "Indexed back to when you joined" : "Fully indexed");
  }
  final oldest = c.oldestTs;
  final created = room.createdTs;
  final since = created == null
      ? ""
      : " (room since ${DateTime.fromMillisecondsSinceEpoch(created).year})";
  return DeepSearchCoverageLine(
      DeepSearchCoverageKind.roomPartial,
      oldest == null
          ? "Indexing has just started"
          : "Indexed back to ${deepSearchMonth(oldest)}$since",
      action: web ? null : DeepSearchCoverageAction.lookFurtherBack,
      actionLabel: web ? null : "Look further back ›",
      confirm: confirm);
}

/// The confirm sheet before Look further back when indexing is off (or
/// Wi-Fi only on mobile data).
({String title, String body, String cancel, String confirm})
    deepSearchConfirmSheet(String roomName, EncryptedIndexState state) => (
          title: "Search further back in $roomName?",
          body: state == EncryptedIndexState.off
              ? "Indexing is off. This saves this chat’s older messages on "
                  "this device so they can be searched. Nothing else starts "
                  "indexing."
              : "You’re not on Wi-Fi. This uses mobile data to save this "
                  "chat’s older messages on this device so they can be "
                  "searched.",
          cancel: "Cancel",
          confirm: "Search back",
        );

/// The empty state's one-line summary (Mockup 2B): "Encrypted chats: 412
/// of 480 fully indexed · building on Wi-Fi".
String deepSearchCoverageSummary(
    EncryptedIndexState state, IndexCoverageTotals t,
    {bool wifiOnly = false}) {
  if (state == EncryptedIndexState.unavailable) return "Web: no search index";
  final head = "Encrypted chats: ${deepSearchCount(t.complete)} of "
      "${deepSearchCount(t.rooms)} fully indexed";
  switch (state) {
    case EncryptedIndexState.off:
      return "$head · indexing is off";
    case EncryptedIndexState.waitingForWifi:
      return "$head · paused until Wi-Fi";
    case EncryptedIndexState.pausedForBattery:
      return "$head · paused for battery saver";
    case EncryptedIndexState.running:
      return wifiOnly ? "$head · building on Wi-Fi" : "$head · building";
    case EncryptedIndexState.done:
    case EncryptedIndexState.unavailable:
      return head;
  }
}

/// All accounts: one account's totals summed with another's.
IndexCoverageTotals deepSearchSumTotals(Iterable<IndexCoverageTotals> all) {
  var rooms = 0, complete = 0, started = 0, undecrypted = 0, limited = 0;
  var migrating = false;
  for (final t in all) {
    rooms += t.rooms;
    complete += t.complete;
    started += t.started;
    undecrypted += t.undecrypted;
    limited += t.historyLimited;
    migrating = migrating || t.migrating;
  }
  return IndexCoverageTotals(
      rooms: rooms,
      complete: complete,
      started: started,
      undecrypted: undecrypted,
      historyLimited: limited,
      migrating: migrating);
}
