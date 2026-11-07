// Vommet (Deep Search, stage 2): the always-visible coverage line
// (Decision 10, Mockup 5). Several states can show at once, most limiting
// first, each with at most one action. Pure: built from the index's state
// and totals, the network and (scoped to one room) the room's coverage, so
// the UI only lays the lines out. Coverage is per account: the UI builds
// the lines for each account in the account filter.
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:intl/intl.dart';

enum DeepSearchCoverageKind {
  /// Web: no index.
  web,
  off,
  wifiPaused,
  batteryPaused,

  /// Server results missing: no sync connection, or /search failed for
  /// the network.
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
    this.mobileDataNeedsConfirmation = false,
    this.room,
  });

  final EncryptedIndexState state;

  /// coverageTotals() over the encrypted chats in scope.
  final IndexCoverageTotals totals;

  /// MatrixEncryptedSearchIndexComponent.available (false on web).
  final bool indexAvailable;

  /// False when the homeserver part can't run: an account's sync
  /// connection is down or its /search failed for the network
  /// (deepSearchServerOffline). A server error that isn't the network's
  /// shows in the server section ("Couldn’t search your homeserver"), not
  /// as Offline.
  final bool online;

  /// The query searches the server (it has words, unencrypted rooms are
  /// in scope).
  final bool serverWanted;

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

String _messages(int n) => n == 1
    ? _CoverageStrings.oneMessage
    : _CoverageStrings.messages(deepSearchCount(n));

/// The coverage lines, most limiting first.
List<DeepSearchCoverageLine> deepSearchCoverage(DeepSearchCoverageInput i) {
  final lines = <DeepSearchCoverageLine>[];
  final t = i.totals;
  final web = !i.indexAvailable || i.state == EncryptedIndexState.unavailable;
  final allComplete = t.rooms > 0 && t.complete >= t.rooms;

  if (web) {
    lines.add(DeepSearchCoverageLine(
        DeepSearchCoverageKind.web, _CoverageStrings.webTitle,
        detail: _CoverageStrings.webDetail));
  } else if (!allComplete) {
    switch (i.state) {
      case EncryptedIndexState.off:
        lines.add(DeepSearchCoverageLine(
            DeepSearchCoverageKind.off, _CoverageStrings.offTitle,
            detail: _CoverageStrings.offDetail,
            action: DeepSearchCoverageAction.openSettings,
            actionLabel: _CoverageStrings.offAction));
      case EncryptedIndexState.waitingForWifi:
        final pct = deepSearchPercent(t.complete, t.rooms);
        lines.add(DeepSearchCoverageLine(
            DeepSearchCoverageKind.wifiPaused, _CoverageStrings.wifiTitle,
            detail: _CoverageStrings.wifiDetail("$pct"),
            action: DeepSearchCoverageAction.indexOnMobileData,
            actionLabel: _CoverageStrings.wifiAction));
      case EncryptedIndexState.pausedForBattery:
        lines.add(DeepSearchCoverageLine(
            DeepSearchCoverageKind.batteryPaused, _CoverageStrings.batteryTitle,
            detail: _CoverageStrings.batteryDetail));
      case EncryptedIndexState.unavailable:
      case EncryptedIndexState.running:
      case EncryptedIndexState.done:
        break;
    }
  }

  if (i.serverWanted && !i.online) {
    lines.add(DeepSearchCoverageLine(
        DeepSearchCoverageKind.offline, _CoverageStrings.offlineTitle,
        detail: _CoverageStrings.offlineDetail));
  }

  final room = i.room;
  if (room != null) {
    lines.add(_roomLine(i, room));
  } else if (!web) {
    final indexing = i.state == EncryptedIndexState.running ||
        i.state == EncryptedIndexState.done;
    if (allComplete || t.rooms == 0) {
      lines.add(DeepSearchCoverageLine(DeepSearchCoverageKind.complete,
          _CoverageStrings.allComplete(deepSearchCount(t.rooms))));
    } else if (indexing && t.complete == 0) {
      lines.add(DeepSearchCoverageLine(
          DeepSearchCoverageKind.firstRun, _CoverageStrings.firstRunTitle,
          detail: _CoverageStrings.firstRunDetail));
    } else {
      final left = t.rooms - t.complete;
      lines.add(DeepSearchCoverageLine(
          DeepSearchCoverageKind.building,
          _CoverageStrings.building(
              deepSearchCount(t.complete), deepSearchCount(t.rooms)),
          detail: i.state == EncryptedIndexState.off
              ? _CoverageStrings.notIndexed(deepSearchCount(left))
              : _CoverageStrings.stillIndexing(deepSearchCount(left))));
    }
  }

  final undecrypted = room != null ? room.coverage.undecrypted : t.undecrypted;
  if (!web && undecrypted > 0) {
    lines.add(DeepSearchCoverageLine(DeepSearchCoverageKind.keysMissing,
        _CoverageStrings.keysTitle(_messages(undecrypted)),
        detail: _CoverageStrings.keysDetail,
        action: DeepSearchCoverageAction.keyDetails,
        actionLabel: _CoverageStrings.keysAction));
  }
  return lines;
}

DeepSearchCoverageLine _roomLine(
    DeepSearchCoverageInput i, DeepSearchRoomCoverageInput room) {
  if (!room.indexed) {
    return DeepSearchCoverageLine(
        DeepSearchCoverageKind.roomServerOnly, _CoverageStrings.serverOnlyTitle,
        detail: _CoverageStrings.serverOnlyDetail);
  }
  final web = !i.indexAvailable || i.state == EncryptedIndexState.unavailable;
  final confirm = i.state == EncryptedIndexState.off ||
      (i.state == EncryptedIndexState.waitingForWifi &&
          i.mobileDataNeedsConfirmation);
  final c = room.coverage;
  if (!c.known) {
    return DeepSearchCoverageLine(
        DeepSearchCoverageKind.roomNotIndexed, _CoverageStrings.roomNotIndexed,
        detail: _CoverageStrings.roomNotIndexedDetail,
        action: web ? null : DeepSearchCoverageAction.lookFurtherBack,
        actionLabel: web ? null : _CoverageStrings.lookFurtherBack,
        confirm: confirm);
  }
  if (c.complete) {
    return DeepSearchCoverageLine(
        DeepSearchCoverageKind.roomComplete,
        c.historyLimited
            ? _CoverageStrings.indexedSinceJoined
            : _CoverageStrings.fullyIndexed);
  }
  final oldest = c.oldestTs;
  final created = room.createdTs;
  final since = created == null
      ? ""
      : _CoverageStrings.roomSince(
          "${DateTime.fromMillisecondsSinceEpoch(created).year}");
  return DeepSearchCoverageLine(
      DeepSearchCoverageKind.roomPartial,
      oldest == null
          ? _CoverageStrings.justStarted
          : _CoverageStrings.indexedBackTo(deepSearchMonth(oldest), since),
      action: web ? null : DeepSearchCoverageAction.lookFurtherBack,
      actionLabel: web ? null : _CoverageStrings.lookFurtherBack,
      confirm: confirm);
}

/// The confirm sheet before Look further back when indexing is off (or
/// Wi-Fi only on mobile data).
({String title, String body, String cancel, String confirm})
    deepSearchConfirmSheet(String roomName, EncryptedIndexState state) => (
          title: _CoverageStrings.confirmTitle(roomName),
          body: state == EncryptedIndexState.off
              ? _CoverageStrings.confirmBodyOff
              : _CoverageStrings.confirmBodyMobileData,
          cancel: _CoverageStrings.confirmCancel,
          confirm: _CoverageStrings.confirmSearchBack,
        );

/// The empty state's one-line summary (Mockup 2B): "Encrypted chats: 412
/// of 480 fully indexed · building on Wi-Fi".
String deepSearchCoverageSummary(
    EncryptedIndexState state, IndexCoverageTotals t,
    {bool wifiOnly = false}) {
  if (state == EncryptedIndexState.unavailable) {
    return _CoverageStrings.webTitle;
  }
  final head = _CoverageStrings.summary(
      deepSearchCount(t.complete), deepSearchCount(t.rooms));
  switch (state) {
    case EncryptedIndexState.off:
      return _CoverageStrings.summaryOff(head);
    case EncryptedIndexState.waitingForWifi:
      return _CoverageStrings.summaryWifi(head);
    case EncryptedIndexState.pausedForBattery:
      return _CoverageStrings.summaryBattery(head);
    case EncryptedIndexState.running:
      return wifiOnly
          ? _CoverageStrings.summaryBuildingWifi(head)
          : _CoverageStrings.summaryBuilding(head);
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

/// How much an index state limits what's searched, for All accounts (the
/// worst one shows): off (nothing more gets indexed) > paused for Wi-Fi
/// (one tap resumes it) > paused for battery > running > done. No index
/// (the web) ranks below all: it shows only when no account has one.
int deepSearchStateSeverity(EncryptedIndexState state) => switch (state) {
      EncryptedIndexState.off => 5,
      EncryptedIndexState.waitingForWifi => 4,
      EncryptedIndexState.pausedForBattery => 3,
      EncryptedIndexState.running => 2,
      EncryptedIndexState.done => 1,
      EncryptedIndexState.unavailable => 0,
    };

/// One account's index state and totals (null: not loaded yet).
typedef DeepSearchAccountCoverage = ({
  EncryptedIndexState state,
  IndexCoverageTotals? totals,
});

/// All accounts: the totals summed and the worst relevant state. An
/// account whose chats are all fully indexed limits nothing, so its state
/// (e.g. indexing turned off afterwards) only counts when every account's
/// is complete. Accounts without an index are left out unless none has
/// one.
({EncryptedIndexState state, IndexCoverageTotals totals})
    deepSearchMergeCoverage(Iterable<DeepSearchAccountCoverage> accounts) {
  final all = accounts.toList();
  final totals = deepSearchSumTotals([
    for (final a in all)
      if (a.totals case final t?) t
  ]);
  final indexed = [
    for (final a in all)
      if (a.state != EncryptedIndexState.unavailable) a
  ];
  if (indexed.isEmpty) {
    return (state: EncryptedIndexState.unavailable, totals: totals);
  }
  bool limiting(DeepSearchAccountCoverage a) {
    final t = a.totals;
    return t == null || t.complete < t.rooms;
  }

  final relevant = indexed.where(limiting).toList();
  var state = EncryptedIndexState.unavailable;
  for (final a in relevant.isEmpty ? indexed : relevant) {
    if (deepSearchStateSeverity(a.state) > deepSearchStateSeverity(state)) {
      state = a.state;
    }
  }
  return (state: state, totals: totals);
}

/// The coverage line's texts (Mockup 5), in intl_en.arb.
class _CoverageStrings {
  static String get oneMessage => Intl.message("1 message",
      name: "deepSearchCoverageOneMessage",
      desc: "Deep Search coverage: one message (in the keys line)");
  static String messages(String count) => Intl.message("$count messages",
      args: [count],
      name: "deepSearchCoverageMessages",
      desc: "Deep Search coverage: several messages (in the keys line); "
          "count is already formatted, e.g. 1,700");

  static String get webTitle => Intl.message("Web: no search index",
      name: "deepSearchCoverageWebTitle",
      desc: "Deep Search coverage: the web app has no search index");
  static String get webDetail => Intl.message(
      "Encrypted chats: only what’s loaded is searched. The desktop and phone apps search full history.",
      name: "deepSearchCoverageWebDetail",
      desc: "Deep Search coverage: detail of the web line");

  static String get offTitle => Intl.message("Indexing is off",
      name: "deepSearchCoverageOffTitle",
      desc: "Deep Search coverage: the search index is turned off");
  static String get offDetail => Intl.message(
      "Encrypted chats: only messages already on this device are searched.",
      name: "deepSearchCoverageOffDetail",
      desc: "Deep Search coverage: detail of the indexing-off line");
  static String get offAction => Intl.message("Turn on in Settings ›",
      name: "deepSearchCoverageOffAction",
      desc: "Deep Search coverage: opens the search index setting");

  static String get wifiTitle => Intl.message("Indexing paused: not on Wi-Fi",
      name: "deepSearchCoverageWifiTitle",
      desc: "Deep Search coverage: indexing waits for Wi-Fi");
  static String wifiDetail(String percent) =>
      Intl.message("Searching what’s indexed so far ($percent% of chats).",
          args: [percent],
          name: "deepSearchCoverageWifiDetail",
          desc: "Deep Search coverage: detail of the Wi-Fi line");
  static String get wifiAction =>
      Intl.message("Index on mobile data this session ›",
          name: "deepSearchCoverageWifiAction",
          desc: "Deep Search coverage: indexes on mobile data until restart");

  static String get batteryTitle =>
      Intl.message("Indexing paused: battery saver",
          name: "deepSearchCoverageBatteryTitle",
          desc: "Deep Search coverage: indexing waits for battery saver");
  static String get batteryDetail => Intl.message(
      "Resumes when charging, or when battery saver is turned off.",
      name: "deepSearchCoverageBatteryDetail",
      desc: "Deep Search coverage: detail of the battery saver line");

  static String get offlineTitle => Intl.message("Offline",
      name: "deepSearchCoverageOfflineTitle",
      desc: "Deep Search coverage: no connection to the homeserver");
  static String get offlineDetail => Intl.message(
      "Showing this device only. Unencrypted rooms are searched again when you reconnect.",
      name: "deepSearchCoverageOfflineDetail",
      desc: "Deep Search coverage: detail of the offline line");

  static String allComplete(String count) =>
      Intl.message("Searched all $count encrypted chats fully",
          args: [count],
          name: "deepSearchCoverageAllComplete",
          desc: "Deep Search coverage: every encrypted chat is indexed");
  static String get firstRunTitle => Intl.message("Building your search index",
      name: "deepSearchCoverageFirstRunTitle",
      desc: "Deep Search coverage: the index has just started");
  static String get firstRunDetail => Intl.message(
      "Recent messages are searchable now. Older history is indexed on Wi-Fi, DMs first.",
      name: "deepSearchCoverageFirstRunDetail",
      desc: "Deep Search coverage: detail of the first-run line");
  static String building(String complete, String total) =>
      Intl.message("Searched $complete of $total encrypted chats fully",
          args: [complete, total],
          name: "deepSearchCoverageBuilding",
          desc: "Deep Search coverage: how many encrypted chats are indexed");
  static String notIndexed(String count) =>
      Intl.message("$count not indexed: their older messages aren’t searched.",
          args: [count],
          name: "deepSearchCoverageNotIndexed",
          desc: "Deep Search coverage: chats left unindexed (indexing is off)");
  static String stillIndexing(String count) => Intl.message(
      "$count still indexing: their older messages aren’t searched yet.",
      args: [count],
      name: "deepSearchCoverageStillIndexing",
      desc: "Deep Search coverage: chats still indexing");

  static String keysTitle(String messages) =>
      Intl.message("$messages can’t be decrypted yet",
          args: [messages],
          name: "deepSearchCoverageKeysTitle",
          desc: "Deep Search coverage: messages without their keys; "
              "messages is e.g. \"12 messages\"");
  static String get keysDetail => Intl.message(
      "Searchable once their keys arrive from key backup or another of your devices.",
      name: "deepSearchCoverageKeysDetail",
      desc: "Deep Search coverage: detail of the keys line");
  static String get keysAction => Intl.message("Details ›",
      name: "deepSearchCoverageKeysAction",
      desc: "Deep Search coverage: opens the key backup settings");

  static String get serverOnlyTitle =>
      Intl.message("Searched on your homeserver",
          name: "deepSearchCoverageServerOnlyTitle",
          desc: "Deep Search coverage (one room): an unencrypted room");
  static String get serverOnlyDetail => Intl.message(
      "This room isn’t encrypted, so your homeserver searches its history.",
      name: "deepSearchCoverageServerOnlyDetail",
      desc: "Deep Search coverage (one room): detail of the unencrypted line");
  static String get roomNotIndexed => Intl.message("Not indexed yet",
      name: "deepSearchCoverageRoomNotIndexed",
      desc: "Deep Search coverage (one room): nothing indexed yet");
  static String get roomNotIndexedDetail =>
      Intl.message("Only messages already on this device are searched.",
          name: "deepSearchCoverageRoomNotIndexedDetail",
          desc: "Deep Search coverage (one room): detail of not indexed yet");
  static String get lookFurtherBack => Intl.message("Look further back ›",
      name: "deepSearchCoverageLookFurtherBack",
      desc: "Deep Search coverage (one room): indexes its older history");
  static String get indexedSinceJoined =>
      Intl.message("Indexed back to when you joined",
          name: "deepSearchCoverageIndexedSinceJoined",
          desc: "Deep Search coverage (one room): indexed as far as visible");
  static String get fullyIndexed => Intl.message("Fully indexed",
      name: "deepSearchCoverageFullyIndexed",
      desc: "Deep Search coverage (one room): all history indexed");
  static String get justStarted => Intl.message("Indexing has just started",
      name: "deepSearchCoverageJustStarted",
      desc: "Deep Search coverage (one room): indexing began");
  static String indexedBackTo(String month, String since) =>
      Intl.message("Indexed back to $month$since",
          args: [month, since],
          name: "deepSearchCoverageIndexedBackTo",
          desc: "Deep Search coverage (one room): month is e.g. Mar 2024; "
              "since is empty or e.g. \" (room since 2019)\"");
  static String roomSince(String year) => Intl.message(" (room since $year)",
      args: [year],
      name: "deepSearchCoverageRoomSince",
      desc: "Deep Search coverage (one room): the year the room was made, "
          "after Indexed back to …");

  static String confirmTitle(String roomName) =>
      Intl.message("Search further back in $roomName?",
          args: [roomName],
          name: "deepSearchConfirmTitle",
          desc: "Deep Search: title of the Look further back confirm sheet");
  static String get confirmBodyOff => Intl.message(
      "Indexing is off. This saves this chat’s older messages on this device so they can be searched. Nothing else starts indexing.",
      name: "deepSearchConfirmBodyOff",
      desc: "Deep Search confirm sheet: body when indexing is off");
  static String get confirmBodyMobileData => Intl.message(
      "You’re not on Wi-Fi. This uses mobile data to save this chat’s older messages on this device so they can be searched.",
      name: "deepSearchConfirmBodyMobileData",
      desc: "Deep Search confirm sheet: body on mobile data");
  static String get confirmCancel => Intl.message("Cancel",
      name: "deepSearchConfirmCancel",
      desc: "Deep Search confirm sheet: the cancel button");
  static String get confirmSearchBack => Intl.message("Search back",
      name: "deepSearchConfirmSearchBack",
      desc: "Deep Search confirm sheet: the confirm button");

  static String summary(String complete, String total) =>
      Intl.message("Encrypted chats: $complete of $total fully indexed",
          args: [complete, total],
          name: "deepSearchCoverageSummary",
          desc: "Deep Search empty state: the coverage summary");
  static String summaryOff(String summary) =>
      Intl.message("$summary · indexing is off",
          args: [summary],
          name: "deepSearchCoverageSummaryOff",
          desc: "Deep Search empty state: the summary, indexing off");
  static String summaryWifi(String summary) =>
      Intl.message("$summary · paused until Wi-Fi",
          args: [summary],
          name: "deepSearchCoverageSummaryWifi",
          desc: "Deep Search empty state: the summary, waiting for Wi-Fi");
  static String summaryBattery(String summary) =>
      Intl.message("$summary · paused for battery saver",
          args: [summary],
          name: "deepSearchCoverageSummaryBattery",
          desc: "Deep Search empty state: the summary, battery saver");
  static String summaryBuildingWifi(String summary) =>
      Intl.message("$summary · building on Wi-Fi",
          args: [summary],
          name: "deepSearchCoverageSummaryBuildingWifi",
          desc: "Deep Search empty state: the summary, indexing on Wi-Fi only");
  static String summaryBuilding(String summary) =>
      Intl.message("$summary · building",
          args: [summary],
          name: "deepSearchCoverageSummaryBuilding",
          desc: "Deep Search empty state: the summary, indexing");
}
