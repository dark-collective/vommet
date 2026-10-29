// Vommet issue 853: marks bridged "ghost" users and warns before messaging
// the ones a direct message may not reach. The rules are in
// bridged_user_rules.dart; this holds the settings, the profile lookups and
// the strings.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/bridged_user_rules.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

export 'package:commet/utils/bridged_user_rules.dart';

String get bridgedSettingsTitle => Intl.message("Bridged users",
    name: "bridgedSettingsTitle",
    desc: "Bridged users: title of the settings tab and page");

String get bridgedSettingsMark => Intl.message("Mark bridged users",
    name: "bridgedSettingsMark",
    desc: "Bridged users settings: toggle that shows the network icons");

String get bridgedSettingsMarkDescription =>
    Intl.message("Icon in member lists, chat lists and user cards",
        name: "bridgedSettingsMarkDescription",
        desc: "Bridged users settings: description of the Mark toggle");

String get bridgedSettingsWarn => Intl.message("Warn before messaging them",
    name: "bridgedSettingsWarn",
    desc: "Bridged users settings: toggle for the direct message warnings");

String get bridgedSettingsWarnDescription =>
    Intl.message("Only for bridges where direct messages may not arrive",
        name: "bridgedSettingsWarnDescription",
        desc: "Bridged users settings: description of the Warn toggle");

String get bridgedSettingsRecognized => Intl.message(
    "Bridges Vommet recognizes",
    name: "bridgedSettingsRecognized",
    desc:
        "Bridged users settings: header of the list of bridges Vommet guesses from user IDs");

String get bridgedSettingsRecognizedHint => Intl.message(
    "Vommet guesses these from the user ID. When a bridge says so on the person's profile, Vommet uses that instead.",
    name: "bridgedSettingsRecognizedHint",
    desc: "Bridged users settings: explanation under the recognized bridges");

String get bridgedSettingsYourPatterns => Intl.message("Your patterns",
    name: "bridgedSettingsYourPatterns",
    desc: "Bridged users settings: header of the user's own ID patterns");

String get bridgedSettingsAddPattern => Intl.message("Add your own pattern",
    name: "bridgedSettingsAddPattern",
    desc: "Bridged users settings: button that adds a user ID pattern");

String get bridgedSettingsPatternHint => Intl.message(
    "A user ID where * stands for anything, like @irc_*:example.org",
    name: "bridgedSettingsPatternHint",
    desc: "Bridged users settings: hint in the pattern field");

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

String bridgedTooltipGuess(String network) => Intl.message(
    "Probably bridged from $network",
    args: [network],
    name: "bridgedTooltipGuess",
    desc:
        "Bridged users: tooltip of the network icon when Vommet guessed it from the user ID");

String bridgedChipGuess(String network) => Intl.message("Probably $network",
    args: [network],
    name: "bridgedChipGuess",
    desc:
        "Bridged users: dashed chip on the user card when Vommet guessed the network; network is e.g. Telegram");

String bridgedGuessExplained(String bridge) => Intl.message(
    "Looks like a $bridge ghost (guessed from the user ID)",
    args: [bridge],
    name: "bridgedGuessExplained",
    desc:
        "Bridged users: line under the guess chip; bridge is e.g. 'mautrix Telegram' or 'Nether voice bridge'");

String bridgedDeclaredExplained(String network) => Intl.message(
    "Bridged from $network (the bridge says so)",
    args: [network],
    name: "bridgedDeclaredExplained",
    desc:
        "Bridged users: line under the chip when the bridge put it on the person's profile");

String bridgedYoursExplained(String network) => Intl.message(
    "Bridged from $network (you set this)",
    args: [network],
    name: "bridgedYoursExplained",
    desc:
        "Bridged users: line under the chip when the user picked the network");

String get bridgedVoiceBridge => Intl.message("Nether voice bridge",
    name: "bridgedVoiceBridge",
    desc:
        "Bridged users: name of the voice bridge between Discord voice channels and Matrix calls");

String get bridgedVoiceNetwork => Intl.message("Discord voice",
    name: "bridgedVoiceNetwork",
    desc:
        "Bridged users: the network of a voice bridge puppet, as in 'Bridged from Discord voice'");

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

  /// Ids of [builtInBridges] the user turned off.
  static final StringListPreference disabledBuiltIns = StringListPreference(
      "vommet_bridged_users_builtins_off",
      defaultValue: []);

  /// [UserBridgePattern.encode]d.
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

  /// What we know about [userId], or null if they don't look bridged (or the
  /// marks are off). Asks the profile in the background the first time;
  /// listen to [onChanged] for the answer.
  static BridgedUser? of(Client client, String userId,
      {bool ignoreSetting = false}) {
    if (!ignoreSetting && !mark.value) return null;
    if (!_declared.containsKey(userId)) _lookUp(client, userId);
    return classify(userId);
  }

  static BridgedUser? classify(String userId) => classifyBridgedUser(userId,
      override: overrideMap[userId],
      declared: _declared[userId],
      patterns: userPatterns,
      disabledBuiltIns: disabledBuiltIns.value.toSet());

  /// What Vommet would say without the user's override.
  static BridgedUser? guessWithoutOverride(String userId) =>
      classifyBridgedUser(userId,
          declared: _declared[userId],
          patterns: userPatterns,
          disabledBuiltIns: disabledBuiltIns.value.toSet());

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
    if (_declared[userId] != null) _changed.add(userId);
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
      network == BridgeNetwork.voiceBridge ? Icons.graphic_eq : iconOf(network);

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
