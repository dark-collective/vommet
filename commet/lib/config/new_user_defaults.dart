import 'dart:convert';

import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/preference.dart';
import 'package:commet/config/preferences/string_list_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';

/// Vommet: "Back to new-user defaults" on the Experiments page. Saves the
/// current setup, then puts the chosen preferences back to what a fresh
/// install has, so testers can see the app as a new user does (and narrow a
/// crash down); "Restore my setup" switches back.
///
/// Only preferences are touched: never the account, rooms, messages or the
/// secure-messaging setup. "New-user defaults" means each preference's own
/// default, so experiments that start on (Encrypted Element Call) stay on.
class NewUserDefaults {
  /// The saved setup: `{"prefs": {key: {"stored": bool, "value": ...}},
  /// "experiments": <how many experiments differed from their defaults>}`.
  static final _saved =
      NullableStringPreference("vommet_saved_setup", defaultValue: null);

  /// What "Reset app settings too" covers: appearance, notifications, link
  /// previews and sounds. Left alone: developer options, the proxy, call and
  /// streaming settings, devices, push registration and app bookkeeping.
  static List<Preference> get appSettings => [
        // Appearance
        preferences.theme,
        preferences.shouldFollowSystemTheme,
        preferences.shouldFollowSystemColors,
        preferences.appScale,
        preferences.textScale,
        preferences.layoutOverride,
        preferences.showRoomAvatars,
        preferences.usePlaceholderRoomAvatars,
        preferences.messageEffectsEnabled,
        preferences.showStateEvents,
        preferences.collapseStateEvents,
        preferences.hideRoomSidePanel,
        preferences.showRoomPreviewsInSpaceSidebar,
        preferences.pauseAnimationsWhenNotFocused,
        // Notifications
        preferences.enableNotifications,
        preferences.silenceNotifications,
        preferences.suppressNotificationWhenRoomFocused,
        preferences.showMediaInNotifications,
        preferences.formatNotificationBody,
        preferences.previewUrlInNotifications,
        preferences.showNotificationBadgesInTaskbar,
        // Link previews
        preferences.urlPreviewInE2EEChat,
        preferences.previewMediaInPublicRooms,
        preferences.previewMediaInPrivateRooms,
        preferences.allowedRemoteVideoHosts,
        // Sounds
        preferences.notificationsVolume,
      ];

  /// Appearance preferences that only show after the theme or scale is
  /// applied again.
  static Set<String> get appearanceKeys => {
        preferences.theme.key,
        preferences.shouldFollowSystemTheme.key,
        preferences.shouldFollowSystemColors.key,
        preferences.appScale.key,
      };

  /// Experiments not at their new-user value.
  static List<Experiment> get changedExperiments => ExperimentRegistry.all
      .where((e) => e.preference.value != e.preference.defaultForNewUser)
      .toList(growable: false);

  static bool get hasSavedSetup => _saved.value != null;

  static Map<String, dynamic>? get _savedSetup {
    final raw = _saved.value;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// How many experiments the saved setup had changed, for "Restore my setup
  /// (N on)".
  static int get savedExperimentCount =>
      (_savedSetup?["experiments"] as num?)?.toInt() ?? 0;

  /// Saves the chosen preferences, then resets them. Returns the experiments
  /// whose value changed, so the caller can run their side effects.
  static Future<List<Experiment>> reset(
      {required bool experiments, required bool appSettings}) async {
    final experimentList = ExperimentRegistry.all;
    final prefs = <Preference>[
      if (experiments) ...experimentList.map((e) => e.preference),
      if (appSettings) ...NewUserDefaults.appSettings,
    ];
    final before = {for (final e in experimentList) e: e.preference.value};

    await _saved.set(jsonEncode({
      "experiments": experiments ? changedExperiments.length : 0,
      "prefs": {
        for (final p in prefs)
          p.key: {"stored": p.hasStoredValue, "value": p.value},
      },
    }));

    for (final p in prefs) {
      await p.reset();
    }
    return [
      for (final e in experimentList)
        if (before[e] != e.preference.value) e
    ];
  }

  /// Puts the saved setup back and forgets it. Returns the experiments whose
  /// value changed.
  static Future<List<Experiment>> restore() async {
    final saved = _savedSetup;
    final experimentList = ExperimentRegistry.all;
    final before = {for (final e in experimentList) e: e.preference.value};

    if (saved != null) {
      final byKey = {
        for (final p in [
          ...experimentList.map((e) => e.preference),
          ...appSettings,
        ])
          p.key: p,
      };
      final entries = (saved["prefs"] as Map?) ?? const {};
      for (final MapEntry(:key, :value) in entries.entries) {
        final p = byKey[key];
        if (p == null || value is! Map) continue;
        if (value["stored"] == true) {
          await _set(p, value["value"]);
        } else {
          await p.reset();
        }
      }
    }

    await _saved.set(null);
    return [
      for (final e in experimentList)
        if (before[e] != e.preference.value) e
    ];
  }

  static Future<void> _set(Preference p, Object? value) async {
    try {
      if (p is DoublePreference) {
        await p.set((value as num).toDouble());
      } else if (p is StringListPreference) {
        await p.set(List<String>.from(value as List));
      } else {
        await (p as dynamic).set(value);
      }
    } catch (_) {
      // A value of the wrong type (the preference changed shape); keep the
      // default instead.
      await p.reset();
    }
  }
}
