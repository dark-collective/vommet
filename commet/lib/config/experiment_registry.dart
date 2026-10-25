import 'dart:io';

import 'package:commet/config/experiment_entries.dart';
import 'package:commet/config/preferences/bool_preference.dart';

/// Vommet: where an experiment is listed on the Experiments page, in this
/// order.
enum ExperimentCategory {
  messages("Chat and messages"),
  calls("Calls and voice"),
  layout("Layout and sidebar"),
  sync("Sync and performance");

  const ExperimentCategory(this.label);
  final String label;
}

/// Vommet: one experiment, shown as a toggle on the Experiments page. On
/// unless the user switches it off (or [optIn] is set). Entries live in
/// experiment_entries.dart (one per topic).
class Experiment {
  const Experiment({
    required this.preference,
    required this.title,
    required this.description,
    required this.category,
    this.needsRestart = false,
    this.optIn = false,
    this.onChanged,
    this.available,
  });

  final BoolPreference preference;
  final String title;
  final String description;
  final ExperimentCategory category;

  /// Only takes effect after the app restarts (read once at startup). The
  /// page marks it, and asks to restart when you leave after changing it.
  final bool needsRestart;

  /// Off until the user turns it on. Experiments are on by default so new
  /// users get new features; set this only when one is too risky for that.
  final bool optIn;

  /// Runs after the toggle stored its new value.
  final void Function(bool value)? onChanged;

  /// Hides the experiment where it can't work (a platform, a missing feature).
  final bool Function()? available;
}

class ExperimentRegistry {
  /// Experiments that stayed opt-in when experiments became opt-out
  /// (operator, 10-10): read state per thread changes when a room counts as
  /// read, and nicknames per space are unfinished. Newer entries set
  /// [Experiment.optIn] instead. Sliding sync left this list on 10-13
  /// (operator): on by default, falling back to regular sync where the
  /// server lacks it; anyone who switched it off keeps it off.
  static const Set<String> optInKeys = {
    "vommet_experiment_thread_read_state",
    "vommet_experiment_space_nicknames",
  };

  /// Experiments that graduated (operator, 10-25): no longer on the
  /// Experiments page, and always on, even where someone had switched them
  /// off. Their preferences and call sites stay as they were.
  static const Set<String> graduatedKeys = {
    "experiment_enabled_e2ee_element_call",
    "experiment_encryption_markers",
    "vommet_experiment_block_users",
    "experiment_message_timestamps",
    "vommet_experiment_message_drafts",
    "experiment_sidebar_pinned_rooms",
    "vommet_experiment_last_room_per_space",
    "experiment_voice_room_chat",
    "experiment_dm_trust_warnings",
    "experiment_call_cards",
    "vommet_experiment_stream_watching",
    "experiment_sidebar_subspace_guides",
  };

  /// The preference keys of [entries] that default to on.
  static Set<String> defaultOnKeysOf(Iterable<Experiment> entries) => {
        for (final e in entries)
          if (!e.optIn && !optInKeys.contains(e.preference.key))
            e.preference.key,
      };

  /// Makes experiments opt-out, and graduated ones always on. Runs when the
  /// preferences load, before anything reads an experiment.
  static void applyDefaults() {
    BoolPreference.defaultOnKeys
      ..clear()
      ..addAll(defaultOnKeysOf(experimentEntries()));
    BoolPreference.alwaysOnKeys
      ..clear()
      ..addAll(graduatedKeys);
  }

  static List<Experiment> get all => experimentEntries()
      .where((e) => e.available?.call() ?? true)
      .toList(growable: false);

  static List<Experiment> inCategory(ExperimentCategory category) =>
      all.where((e) => e.category == category).toList(growable: false);

  /// Values of the restart-only experiments as this process started using
  /// them, taken the first time the page opens (they only change there).
  static Map<String, bool>? _atLaunch;

  static void rememberLaunchValues() {
    _atLaunch ??= {
      for (final e in all)
        if (e.needsRestart) e.preference.key: e.preference.value,
    };
  }

  /// Restart-only experiments changed since launch: changes not applied yet.
  static List<Experiment> get pendingRestart {
    final launch = _atLaunch;
    if (launch == null) return const [];
    return all
        .where((e) =>
            e.needsRestart &&
            launch.containsKey(e.preference.key) &&
            launch[e.preference.key] != e.preference.value)
        .toList(growable: false);
  }

  /// Whether this build can start itself again. A Flatpak app's sandbox ends
  /// with its main process, and mobile apps can't relaunch themselves, so
  /// those only close.
  static bool get canRelaunch =>
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS) &&
      !Platform.environment.containsKey("FLATPAK_ID");

  /// Restarts the app where possible; otherwise closes it so the next launch
  /// applies the change.
  static Future<void> restart() async {
    if (canRelaunch) {
      final exe =
          Platform.environment["APPIMAGE"] ?? Platform.resolvedExecutable;
      await Process.start(exe, const [], mode: ProcessStartMode.detached);
    }
    exit(0);
  }
}
