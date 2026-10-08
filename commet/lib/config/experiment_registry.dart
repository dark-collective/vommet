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

/// Vommet: one opt-in experiment, shown as a toggle on the Experiments page.
/// Entries live in experiment_entries.dart (one per topic).
class Experiment {
  const Experiment({
    required this.preference,
    required this.title,
    required this.description,
    required this.category,
    this.needsRestart = false,
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

  /// Runs after the toggle stored its new value.
  final void Function(bool value)? onChanged;

  /// Hides the experiment where it can't work (a platform, a missing feature).
  final bool Function()? available;
}

class ExperimentRegistry {
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
