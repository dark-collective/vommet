// Vommet issue 853: marks bridged "ghost" users and warns before messaging
// the ones a direct message may not reach. The rules are in
// bridged_user_rules.dart; this holds the settings, the profile lookups and
// the strings.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/preferences.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/bridges/room_bridges_settings_page.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

export 'package:commet/utils/bridged_user_rules.dart';

String get bridgedSettingsTitle => Intl.message("Bridged users",
    name: "bridgedSettingsTitle",
    desc: "Bridged users: title of the settings tab and page");

String get bridgedSettingsMark => Intl.message("Show network icons",
    name: "bridgedSettingsMark",
    desc: "Bridged users settings: toggle that shows the network icons");

String get bridgedSettingsMarkDescription =>
    Intl.message("After names on messages, in member lists and user cards",
        name: "bridgedSettingsMarkDescription",
        desc: "Bridged users settings: description of the Mark toggle");

String get bridgedSettingsWarn => Intl.message("Warn before messaging them",
    name: "bridgedSettingsWarn",
    desc: "Bridged users settings: toggle for the direct message warnings");

String get bridgedSettingsWarnDescription =>
    Intl.message("Only for bridges where direct messages may not arrive",
        name: "bridgedSettingsWarnDescription",
        desc: "Bridged users settings: description of the Warn toggle");

String get bridgedSettingsDmsReach => Intl.message("Direct messages reach them",
    name: "bridgedSettingsDmsReach",
    desc:
        "Bridged users settings: checkbox for a pattern whose bridge delivers direct messages, which hides the warning");

String get bridgedSettingsPeopleChanged => Intl.message("People you changed",
    name: "bridgedSettingsPeopleChanged",
    desc:
        "Bridged users settings: header of the people whose bridge the user set by hand");

String get bridgedSettingsReset => Intl.message("Reset",
    name: "bridgedSettingsReset",
    desc: "Bridged users settings: button that removes a person's override");

String get bridgedSettingsNotBridged => Intl.message("Not a bridged user",
    name: "bridgedSettingsNotBridged",
    desc:
        "Bridged users: menu entry and settings label for a person marked as not bridged");

String get bridgedChooseNetwork => Intl.message("Choose network",
    name: "bridgedChooseNetwork",
    desc: "Bridged users: menu entry that opens the list of networks");

String bridgedUseGuess(String bridge) => Intl.message("Guess: $bridge",
    args: [bridge],
    name: "bridgedUseGuess",
    desc:
        "Bridged users: menu entry going back to Vommet's guess; bridge is e.g. 'Telegram (mautrix)'");

String get bridgedChangeIt => Intl.message("Not right? Change it",
    name: "bridgedChangeIt",
    desc:
        "Bridged users: link on the user card that opens the correction menu");

String bridgedTooltip(String network) => Intl.message("Bridged from $network",
    args: [network],
    name: "bridgedTooltip",
    desc:
        "Bridged users: tooltip of the network icon; network is e.g. Telegram");

String bridgedYoursExplained(String network) => Intl.message(
    "Bridged from $network (you set this)",
    args: [network],
    name: "bridgedYoursExplained",
    desc:
        "Bridged users: line under the chip when the user picked the network");

String get bridgedSettingsMatrixIcon => Intl.message("Matrix icon",
    name: "bridgedSettingsMatrixIcon",
    desc:
        "Bridged users settings: choice of where the Matrix icon shows after the names of people who aren't bridged");

String get bridgedSettingsMatrixIconDescription =>
    Intl.message("For people who aren't bridged",
        name: "bridgedSettingsMatrixIconDescription",
        desc: "Bridged users settings: description of the Matrix icon choice");

String get bridgedMatrixIconBridgedRooms => Intl.message(
    "In rooms with bridges",
    name: "bridgedMatrixIconBridgedRooms",
    desc:
        "Bridged users settings: Matrix icon choice, shown only in rooms that have a bridge or bridged people");

String get bridgedMatrixIconEverywhere => Intl.message("Everywhere",
    name: "bridgedMatrixIconEverywhere",
    desc: "Bridged users settings: Matrix icon choice, shown in every room");

String get bridgedMatrixIconNever => Intl.message("Never",
    name: "bridgedMatrixIconNever",
    desc: "Bridged users settings: Matrix icon choice, never shown");

String get bridgedSettingsShowIconsFor => Intl.message("Show icons for",
    name: "bridgedSettingsShowIconsFor",
    desc:
        "Bridged users settings: header of the list of networks, one switch each");

String get bridgedSettingsVoiceBridge => Intl.message("Voice bridge",
    name: "bridgedSettingsVoiceBridge",
    desc:
        "Bridged users settings: the switch for the Discord voice bridge's icon");

String get bridgedSettingsTrusted => Intl.message("Trusted bridge servers",
    name: "bridgedSettingsTrusted",
    desc:
        "Bridged users settings: header of the servers whose bridged users get a solid icon");

String get bridgedSettingsTrustedHint => Intl.message(
    "People bridged through these servers get a solid icon. Anyone else whose ID only looks bridged gets a dashed icon and keeps their Matrix ID next to their name.",
    name: "bridgedSettingsTrustedHint",
    desc: "Bridged users settings: explanation under Trusted bridge servers");

String bridgedTrustedHomeserver(String networks) => Intl.message(
    "Your homeserver · $networks",
    args: [networks],
    name: "bridgedTrustedHomeserver",
    desc:
        "Bridged users settings: line under the user's homeserver; networks is e.g. 'Telegram, Discord' or 'No bridges seen yet'");

String get bridgedTrustedNoneSeen => Intl.message("No bridges seen yet",
    name: "bridgedTrustedNoneSeen",
    desc:
        "Bridged users settings: the user's homeserver runs no bridge Vommet has seen in a room");

String get bridgedTrustedAutomatic => Intl.message("Automatic",
    name: "bridgedTrustedAutomatic",
    desc:
        "Bridged users settings: chip on the user's homeserver, trusted for the bridges seen there");

String get bridgedTrustedBuiltIn => Intl.message("Built in",
    name: "bridgedTrustedBuiltIn",
    desc: "Bridged users settings: chip on a trusted server Vommet knows");

String get bridgedTrustedYours => Intl.message("Yours",
    name: "bridgedTrustedYours",
    desc: "Bridged users settings: chip on a trusted server the user added");

String get bridgedTrustedRemove => Intl.message("Remove",
    name: "bridgedTrustedRemove",
    desc: "Bridged users settings: tooltip of the button removing a server");

String get bridgedTrustedAdd => Intl.message("Add a trusted bridge server",
    name: "bridgedTrustedAdd",
    desc: "Bridged users settings: button and dialog title");

String get bridgedTrustedServer => Intl.message("Server",
    name: "bridgedTrustedServer",
    desc: "Add a trusted bridge server dialog: label of the server field");

String get bridgedTrustedNetwork => Intl.message("Network",
    name: "bridgedTrustedNetwork",
    desc: "Add a trusted bridge server dialog: label of the network choice");

String get bridgedTrustedIds => Intl.message("User IDs (optional)",
    name: "bridgedTrustedIds",
    desc:
        "Add a trusted bridge server dialog: label of the user ID pattern field");

String get bridgedTrustedIdsHint => Intl.message(
    "Leave empty to use the usual IDs for this network",
    name: "bridgedTrustedIdsHint",
    desc: "Add a trusted bridge server dialog: hint under the pattern field");

String get bridgedTrustedWarning => Intl.message(
    "Only add a server whose admins you trust. Anyone with an account there could look bridged.",
    name: "bridgedTrustedWarning",
    desc: "Add a trusted bridge server dialog: warning at the top");

String get bridgedTrustedInvalid => Intl.message(
    "Enter a server name, like example.org",
    name: "bridgedTrustedInvalid",
    desc: "Add a trusted bridge server dialog: error for a bad server name");

String get bridgedTrustedAddButton => Intl.message("Add",
    name: "bridgedTrustedAddButton",
    desc: "Add a trusted bridge server dialog: confirm button");

String get bridgedTrustedRoomFooter => Intl.message(
    "A room's own bridge setting also counts: if the room's admins added a bridge, people from that bridge's server are trusted in that room.",
    name: "bridgedTrustedRoomFooter",
    desc: "Bridged users settings: note under the trusted bridge servers");

String bridgedTooltipUnverified(String network) => Intl.message(
    "Looks like $network, not verified",
    args: [network],
    name: "bridgedTooltipUnverified",
    desc:
        "Bridged users: tooltip of the dashed network icon when the person's server isn't a trusted bridge server; network is e.g. Telegram");

String get bridgedTooltipMatrix => Intl.message("On Matrix, not bridged",
    name: "bridgedTooltipMatrix",
    desc: "Bridged users: tooltip of the Matrix icon after a name");

String bridgedChipUnverified(String network) => Intl.message(
    "Looks like $network · not verified",
    args: [network],
    name: "bridgedChipUnverified",
    desc:
        "Bridged users: dashed chip on the user card when the person's server isn't trusted; network is e.g. Telegram");

String bridgedVerifiedExplained(String network, String server) => Intl.message(
    "Bridged from $network by $server.",
    args: [network, server],
    name: "bridgedVerifiedExplained",
    desc:
        "Bridged users: line under the chip of a verified bridged user; network is e.g. Telegram, server e.g. t2bot.io");

String bridgedUnverifiedExplained(String network, String server) => Intl.message(
    "Their ID looks like a $network bridge user, but $server isn't one of your trusted bridge servers. Anyone there could pick an ID like this.",
    args: [network, server],
    name: "bridgedUnverifiedExplained",
    desc:
        "Bridged users: line under the dashed chip on the user card; network is e.g. Telegram, server e.g. example.org");

String get bridgedTrustServer => Intl.message("Trust this server…",
    name: "bridgedTrustServer",
    desc:
        "Bridged users: link on the user card that opens Add a trusted bridge server, filled in");

String get bridgedVoiceBridge => Intl.message("Nether voice bridge",
    name: "bridgedVoiceBridge",
    desc:
        "Bridged users: name of the voice bridge between Discord voice channels and Matrix calls");

String get bridgedVoiceNetwork => Intl.message("Discord voice",
    name: "bridgedVoiceNetwork",
    desc:
        "Bridged users: the network of a voice bridge puppet, as in 'Bridged from Discord voice'");

String get bridgedVoiceOnlyChip => Intl.message("Discord · voice only",
    name: "bridgedVoiceOnlyChip",
    desc:
        "Bridged users: chip on the user card of someone in a call from Discord through the voice bridge");

String bridgedVoiceOnlyExplained(String name) => Intl.message(
    "$name is in the call from Discord. They hear you and you hear them, but messages here don't reach them.",
    args: [name],
    name: "bridgedVoiceOnlyExplained",
    desc:
        "Bridged users: line under the chip of someone in a call from Discord through the voice bridge; name is their display name");

String get bridgedCantMessage => Intl.message("Can't message them",
    name: "bridgedCantMessage",
    desc:
        "Bridged users: disabled button on the user card, instead of Message, for someone in a call from Discord through the voice bridge");

String get bridgedOtherNetwork => Intl.message("another network",
    name: "bridgedOtherNetwork",
    desc:
        "Bridged users: an unknown network, as in 'Bridged from another network'");

String bridgedConfirmTitle(String name) => Intl.message("Message $name?",
    args: [name],
    name: "bridgedConfirmTitle",
    desc:
        "Bridged users: title of the dialog before messaging a voice bridge puppet");

String bridgedConfirmBody(String name) => Intl.message(
    "$name is a voice bridge puppet, not a person. Nobody reads its direct messages.",
    args: [name],
    name: "bridgedConfirmBody",
    desc:
        "Bridged users: body of the dialog before messaging a voice bridge puppet");

String get bridgedMessageAnyway => Intl.message("Message anyway",
    name: "bridgedMessageAnyway",
    desc: "Bridged users: button that starts the direct message anyway");

String get bridgedCancel => Intl.message("Cancel",
    name: "bridgedCancel", desc: "Bridged users: cancels starting the message");

String bridgedPuppetBanner(String name) => Intl.message(
    "Nobody reads this chat. $name is a voice bridge puppet, not a person.",
    args: [name],
    name: "bridgedPuppetBanner",
    desc:
        "Bridged users: banner above the message box in a direct message with a voice bridge puppet");

String bridgedMayNotReachBanner(String name, String network) => Intl.message(
    "$name is bridged from $network. They only see this if they linked their $network account.",
    args: [name, network],
    name: "bridgedMayNotReachBanner",
    desc:
        "Bridged users: banner above the message box in a direct message with a bridged user; network is e.g. Telegram");

class BridgedUsers {
  static final BoolPreference mark =
      BoolPreference("vommet_bridged_users_mark", defaultValue: true);

  static final BoolPreference warn =
      BoolPreference("vommet_bridged_users_warn", defaultValue: true);

  /// Ids of [builtInBridges] whose network shows no icon (Settings › Show
  /// icons for). One built-in per network; before network marks this
  /// turned off the guess from the user ID.
  static final StringListPreference disabledBuiltIns = StringListPreference(
      "vommet_bridged_users_builtins_off",
      defaultValue: []);

  /// Ids of [builtInTrustedServers] the user turned off.
  static final StringListPreference disabledTrusted = StringListPreference(
      "vommet_bridged_users_trusted_off",
      defaultValue: []);

  /// [MatrixMarkMode] name: where the `[m]` mark shows.
  static final StringPreference matrixMark = StringPreference(
      "vommet_bridged_users_matrix_mark",
      defaultValue: MatrixMarkMode.bridgedRooms.name);

  /// The user's trusted bridge servers, [UserBridgePattern.encode]d (older
  /// values are full-ID patterns).
  static final StringListPreference patterns =
      StringListPreference("vommet_bridged_users_patterns", defaultValue: []);

  /// "<user id>\t<network name or none>".
  static final StringListPreference overrides =
      StringListPreference("vommet_bridged_users_overrides", defaultValue: []);

  /// Rooms whose "they only see this if…" banner was closed.
  static final StringListPreference dismissedBanners = StringListPreference(
      "vommet_bridged_users_banner_dismissed",
      defaultValue: []);

  static final Map<String, DeclaredBridge?> _declared = {};
  static final Set<String> _looking = {};
  static final List<Completer<void>> _queue = [];
  static int _running = 0;
  static const _maxLookups = 3;

  static final StreamController<String> _changed = StreamController.broadcast();

  /// A user ID whose profile answer arrived.
  static Stream<String> get onChanged => _changed.stream;

  static final StreamController<void> _anyChange = StreamController.broadcast();
  static StreamSubscription? _prefsSub;

  /// The settings changed, a profile answer arrived or a bridge appeared in
  /// room state: marks and name safety may change.
  static Stream<void> get onAnyChange {
    _prefsSub ??= Preferences.onSettingChangedController.stream
        .listen((_) => _invalidate());
    return _anyChange.stream;
  }

  /// Bumped on every change; the per-account caches start over when it moves.
  static int _generation = 0;
  static _Settings? _settings;

  static void _invalidate() {
    _generation++;
    _settings = null;
    _anyChange.add(null);
  }

  /// Profile answers drop only that person's cached answers, and are told
  /// to listeners in batches: opening a big bridged room answers many at once.
  static int _userGeneration = 0;
  static final Map<String, int> _dirtyAt = {};
  static Timer? _profileFlush;

  static void _invalidateUser(String userId) {
    _dirtyAt[userId] = ++_userGeneration;
    _profileFlush ??= Timer(const Duration(milliseconds: 300), () {
      _profileFlush = null;
      _anyChange.add(null);
    });
  }

  static _Settings get _now => _settings ??= _Settings(
        overrides: overrideMap,
        patterns: userPatterns,
        disabledTrusted: disabledTrusted.value.toSet(),
        hidden: hiddenNetworks,
      );

  static Map<String, String> get overrideMap {
    final result = <String, String>{};
    for (final line in overrides.value) {
      final tab = line.indexOf("\t");
      if (tab > 0) result[line.substring(0, tab)] = line.substring(tab + 1);
    }
    return result;
  }

  static List<UserBridgePattern> get userPatterns => patterns.value
      .map(UserBridgePattern.decode)
      .whereType<UserBridgePattern>()
      .toList();

  /// Networks whose icon is switched off.
  static Set<BridgeNetwork> get hiddenNetworks {
    final off = disabledBuiltIns.value.toSet();
    return {
      for (final b in builtInBridges)
        if (off.contains(b.id)) b.network
    };
  }

  static MatrixMarkMode get matrixMarkMode =>
      matrixMarkModeFromName(matrixMark.value);

  /// What we know about [userId], or null if they don't look bridged (or the
  /// marks are off, or their network's icon is). [room] is where they're
  /// shown: its bridges can make the mark verified there. Asks the profile
  /// in the background the first time; listen to [onChanged] for the answer.
  static BridgedUser? of(Client client, String userId,
      {Room? room, bool ignoreSetting = false}) {
    if (!ignoreSetting && !mark.value) return null;
    if (!_declared.containsKey(userId)) _lookUp(client, userId);
    final user = classifyIn(client, userId, room: room);
    if (!ignoreSetting && user != null && isHidden(user)) return null;
    return user;
  }

  static bool isHidden(BridgedUser user) => _now.hidden.contains(user.network);

  /// Like [of] without the settings or a profile lookup; cached per
  /// account, room and person.
  static BridgedUser? classifyIn(Client client, String userId, {Room? room}) {
    if (client is! MatrixClient) return classify(userId);
    final cache = _BridgeCache.of(client.getMatrixClient());
    return cache.user(userId, room is MatrixRoom ? room.matrixRoom : null);
  }

  /// Without the account's or a room's bridges.
  static BridgedUser? classify(String userId) => _classify(userId);

  static BridgedUser? _classify(String userId,
      {BridgeTrust? trust, Iterable<SeenBridge> room = const []}) {
    final now = _now;
    return classifyBridgedUser(userId,
        override: now.overrides[userId],
        declared: _declared[userId],
        patterns: now.patterns,
        trust: trust ?? BridgeTrust(disabledBuiltIns: now.disabledTrusted),
        room: room);
  }

  /// Whether the `[m]` mark goes after a non-bridged person in [room].
  static bool showMatrixMark(Client client, Room? room) {
    if (!mark.value) return false;
    switch (matrixMarkMode) {
      case MatrixMarkMode.never:
        return false;
      case MatrixMarkMode.everywhere:
        return true;
      case MatrixMarkMode.bridgedRooms:
        if (client is! MatrixClient || room is! MatrixRoom) return false;
        return _BridgeCache.of(client.getMatrixClient())
            .hasBridges(room.matrixRoom);
    }
  }

  /// The networks a bridge on the user's homeserver was seen for.
  static Set<BridgeNetwork> ownServerNetworks(Client client) {
    if (client is! MatrixClient) return const {};
    return _BridgeCache.of(client.getMatrixClient()).ownNetworks;
  }

  /// Name safety's group for [userId] in [room] (see [markGroup]).
  static String markGroupOf(Client client, String userId, {Room? room}) {
    if (!mark.value) return plainMarkGroup;
    return markGroup(classifyIn(client, userId, room: room),
        marksOn: true, hidden: _now.hidden);
  }

  /// What Vommet would say without the user's override.
  static BridgedUser? guessWithoutOverride(String userId) =>
      classifyBridgedUser(userId,
          declared: _declared[userId],
          patterns: userPatterns,
          trust: BridgeTrust(disabledBuiltIns: _now.disabledTrusted));

  /// [value] is a [BridgeNetwork] name, [notBridgedOverride], or null to go
  /// back to the guess.
  static Future<void> setOverride(String userId, String? value) async {
    final kept =
        overrides.value.where((l) => !l.startsWith("$userId\t")).toList();
    if (value != null) kept.add("$userId\t$value");
    await overrides.set(kept);
  }

  static Future<void> _lookUp(Client client, String userId) async {
    if (client is! MatrixClient || _looking.contains(userId)) return;
    _looking.add(userId);
    try {
      if (_running >= _maxLookups) {
        final turn = Completer<void>();
        _queue.add(turn);
        await turn.future;
      }
      _running++;
      final mx = client.getMatrixClient();
      final profile = await mx
          .request(matrix.RequestType.GET,
              "/client/v3/profile/${Uri.encodeComponent(userId)}")
          .timeout(const Duration(seconds: 10));
      _declared[userId] = DeclaredBridge.fromProfile(profile);
    } catch (_) {
      // No profile (or offline): fall back to the ID patterns for now.
      _declared[userId] = null;
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0).complete();
      _looking.remove(userId);
    }
    if (_declared[userId] != null) {
      _changed.add(userId);
      _invalidateUser(userId);
    }
  }

  static String networkLabel(BridgeNetwork network, {String? name}) {
    switch (network) {
      case BridgeNetwork.telegram:
        return "Telegram";
      case BridgeNetwork.discord:
        return "Discord";
      case BridgeNetwork.whatsapp:
        return "WhatsApp";
      case BridgeNetwork.signal:
        return "Signal";
      case BridgeNetwork.irc:
        return "IRC";
      case BridgeNetwork.voiceBridge:
        return bridgedVoiceNetwork;
      case BridgeNetwork.other:
        return name ?? bridgedOtherNetwork;
    }
  }

  static String labelOf(BridgedUser user) =>
      networkLabel(user.network, name: user.networkName);

  /// "mautrix Telegram", "Nether voice bridge": the bridge software a guess
  /// points at.
  static String bridgeName(BridgeNetwork network) {
    switch (network) {
      case BridgeNetwork.voiceBridge:
        return bridgedVoiceBridge;
      case BridgeNetwork.irc:
      case BridgeNetwork.other:
        return networkLabel(network);
      default:
        return "mautrix ${networkLabel(network)}";
    }
  }

  /// "Telegram (mautrix)" for the settings list and the menu.
  static String builtInLabel(BridgeNetwork network) {
    switch (network) {
      case BridgeNetwork.voiceBridge:
        return bridgedVoiceBridge;
      case BridgeNetwork.irc:
      case BridgeNetwork.other:
        return networkLabel(network);
      default:
        return "${networkLabel(network)} (mautrix)";
    }
  }

  static IconData iconOf(BridgeNetwork network) {
    switch (network) {
      case BridgeNetwork.telegram:
        return Icons.telegram;
      case BridgeNetwork.discord:
      case BridgeNetwork.voiceBridge:
        return Icons.discord;
      case BridgeNetwork.whatsapp:
        return Icons.chat_bubble;
      case BridgeNetwork.signal:
        return Icons.forum;
      case BridgeNetwork.irc:
        return Icons.tag;
      case BridgeNetwork.other:
        return Icons.link;
    }
  }

  /// One glyph for an avatar's corner: a voice bridge puppet gets the sound
  /// wave (the full mark is the Discord logo plus a wave, too small there).
  static IconData cornerIconOf(BridgeNetwork network) =>
      network == BridgeNetwork.voiceBridge ? Icons.discord : iconOf(network);

  /// Before starting a direct message: a voice bridge puppet gets a "nobody
  /// reads this" dialog. Returns false to cancel.
  static Future<bool> confirmMessage(
      BuildContext context, Client client, String userId, String name) async {
    if (!warn.value) return true;
    final user = of(client, userId, ignoreSetting: true);
    if (user?.dms != BridgeDmReach.nobody) return true;
    final go = await AdaptiveDialog.show<bool>(context,
        title: bridgedConfirmTitle(name),
        builder: (context) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(bridgedConfirmBody(name)),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(bridgedCancel),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(bridgedMessageAnyway),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ));
    return go == true;
  }
}

class _Settings {
  _Settings(
      {required this.overrides,
      required this.patterns,
      required this.disabledTrusted,
      required this.hidden});

  final Map<String, String> overrides;
  final List<UserBridgePattern> patterns;
  final Set<String> disabledTrusted;
  final Set<BridgeNetwork> hidden;
}

/// Per account: the bridges seen in room state, and the answer per room and
/// person, until the settings, a profile answer or a room's bridges change.
class _BridgeCache {
  static final Expando<_BridgeCache> _instances = Expando();

  static _BridgeCache of(matrix.Client mx) =>
      _instances[mx] ??= _BridgeCache._(mx);

  _BridgeCache._(this.mx) {
    _sync = mx.onSync.stream.listen(_onSync);
    // Starts listening to the settings.
    BridgedUsers.onAnyChange;
  }

  final matrix.Client mx;
  // ignore: unused_field
  StreamSubscription? _sync;
  int _generation = -1;
  int _userGeneration = 0;
  Set<BridgeNetwork>? _own;
  final Map<String, List<SeenBridge>> _rooms = {};
  final Map<String, bool> _hasBridges = {};

  /// Room id ("" for none) → user id → answer.
  final Map<String, Map<String, BridgedUser?>> _users = {};

  void _check() {
    if (_generation != BridgedUsers._generation) {
      _generation = BridgedUsers._generation;
      _userGeneration = BridgedUsers._userGeneration;
      _users.clear();
      _hasBridges.clear();
      return;
    }
    if (_userGeneration == BridgedUsers._userGeneration) return;
    for (final MapEntry(key: id, value: at) in BridgedUsers._dirtyAt.entries) {
      if (at <= _userGeneration) continue;
      for (final answers in _users.values) {
        answers.remove(id);
      }
    }
    _userGeneration = BridgedUsers._userGeneration;
    // A declared bridge can make a room count as bridged.
    _hasBridges.clear();
  }

  void _onSync(matrix.SyncUpdate update) {
    final joined = update.rooms?.join;
    if (joined == null) return;
    var bridgesChanged = false;
    for (final entry in joined.entries) {
      // New members may be bridged.
      _hasBridges.remove(entry.key);
      final events = [
        ...?entry.value.state,
        ...?entry.value.timeline?.events,
      ];
      if (events.any((e) => bridgeStateTypes.contains(e.type))) {
        _rooms.remove(entry.key);
        bridgesChanged = true;
      }
    }
    if (bridgesChanged) {
      _own = null;
      BridgedUsers._invalidate();
    }
  }

  List<SeenBridge> bridgesIn(matrix.Room room) => _rooms[room.id] ??= [
        for (final b in matrixRoomBridges(room))
          if (SeenBridge.from(
                  protocol: b.protocol.id ?? b.protocol.displayName,
                  bridgeBot: b.bridgeBot)
              case final seen?)
            seen
      ];

  String? get ownServer {
    final id = mx.userID;
    return id == null ? null : serverOfUserId(id);
  }

  Set<BridgeNetwork> get ownNetworks {
    final server = ownServer;
    if (server == null) return const {};
    return _own ??= {
      for (final room in mx.rooms)
        if (room.membership == matrix.Membership.join)
          ...networksOnServer(server, bridgesIn(room)),
    };
  }

  BridgedUser? user(String userId, matrix.Room? room) {
    _check();
    final users = _users[room?.id ?? ""] ??= {};
    if (users.containsKey(userId)) return users[userId];
    return users[userId] = BridgedUsers._classify(userId,
        trust: BridgeTrust(
            disabledBuiltIns: BridgedUsers._now.disabledTrusted,
            ownServer: ownServer,
            ownNetworks: ownNetworks),
        room: room == null ? const [] : bridgesIn(room));
  }

  /// The room lists a bridge or has a bridged member.
  bool hasBridges(matrix.Room room) {
    _check();
    return _hasBridges[room.id] ??= bridgesIn(room).isNotEmpty ||
        room
            .getParticipants()
            .any((u) => u.id != mx.userID && user(u.id, room) != null);
  }
}
