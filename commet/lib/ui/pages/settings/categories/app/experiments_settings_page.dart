import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/experiment_strings.dart';
import 'package:commet/config/new_user_defaults.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' hide Text, TextButton;

/// Vommet: the experiments come from [ExperimentRegistry], grouped by
/// category. Restart-only experiments are marked, and changing one offers a
/// restart, on the page and again when you leave it.
class ExperimentsSettingsPage extends StatefulWidget {
  const ExperimentsSettingsPage({super.key});

  @override
  State<ExperimentsSettingsPage> createState() =>
      _ExperimentsSettingsPageState();
}

class _ExperimentsSettingsPageState extends State<ExperimentsSettingsPage> {
  /// The pending set we last asked about, so leaving the page twice with the
  /// same unapplied change asks once.
  static String? _askedFor;

  @override
  void initState() {
    super.initState();
    ExperimentRegistry.rememberLaunchValues();
  }

  @override
  void dispose() {
    final pending = ExperimentRegistry.pendingRestart;
    final signature = _signature(pending);
    if (pending.isNotEmpty && signature != _askedFor) {
      _askedFor = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigator.currentContext;
        if (context != null && context.mounted) {
          askToRestart(context, pending);
        }
      });
    }
    super.dispose();
  }

  static String _signature(List<Experiment> pending) =>
      pending.map((e) => "${e.preference.key}=${e.preference.value}").join(",");

  static String get experimentsPageIntro => Intl.message(
      "New features, on unless you switch them off. They may have "
      "bugs; turn one off if something breaks.",
      name: "experimentsPageIntro",
      desc: "Text at the top of the Experiments settings page");

  static String experimentsNameList(String first, String last) => Intl.message(
      "$first and $last",
      args: [first, last],
      name: "experimentsNameList",
      desc:
          "Joins experiment names in a sentence: first is one name or several separated by \", \", last is the final name");

  static String get experimentsRestartNow => Intl.message("Restart now",
      name: "experimentsRestartNow",
      desc: "Button that restarts the app to apply experiment changes");

  static String get experimentsCloseVommet => Intl.message("Close Vommet",
      name: "experimentsCloseVommet",
      desc:
          "Button that closes the app to apply experiment changes, where it can't restart itself");

  static String experimentsRestartPrompt(int count, String names) => Intl.plural(
      count,
      one: "$names takes effect after Vommet restarts.",
      other: "$names take effect after Vommet restarts.",
      args: [count, names],
      name: "experimentsRestartPrompt",
      desc:
          "Says which changed experiments need a restart; names is a list of experiment names, count how many");

  static String experimentsClosePrompt(int count, String names) => Intl.plural(
      count,
      one:
          "$names takes effect after Vommet restarts. Vommet will close; open it again to finish.",
      other:
          "$names take effect after Vommet restarts. Vommet will close; open it again to finish.",
      args: [count, names],
      name: "experimentsClosePrompt",
      desc:
          "Says which changed experiments need a restart, where the app can only close (not restart itself); names is a list of experiment names, count how many");

  static String get experimentsRestartDialogTitle => Intl.message(
      "Restart to apply",
      name: "experimentsRestartDialogTitle",
      desc: "Title of the dialog asking to restart after changing experiments");

  static String get experimentsRestartLater => Intl.message("Later",
      name: "experimentsRestartLater",
      desc: "Button that dismisses the restart dialog without restarting");

  static String get experimentsNeedsRestart => Intl.message("Needs a restart",
      name: "experimentsNeedsRestart",
      desc: "Small note under an experiment that only applies after a restart");

  static String get experimentsOnNewUserDefaults => Intl.message(
      "You're on new-user defaults",
      name: "experimentsOnNewUserDefaults",
      desc:
          "Heading of the Experiments page card after the user reset to what a new install has");

  static String get experimentsBackToNewUserDefaults => Intl.message(
      "Back to new-user defaults",
      name: "experimentsBackToNewUserDefaults",
      desc:
          "Heading of the Experiments page card that resets to what a new install has");

  static String get experimentsOnNewUserDefaultsBody => Intl.message(
      "This is what someone who just installed Vommet sees. Your "
      "previous setup is saved.",
      name: "experimentsOnNewUserDefaultsBody",
      desc: "Text of the new-user defaults card after resetting");

  static String get experimentsBackToNewUserDefaultsBody => Intl.message(
      "See the app the way a brand-new user does. We'll save your "
      "current setup so you can switch back.",
      name: "experimentsBackToNewUserDefaultsBody",
      desc: "Text of the new-user defaults card before resetting");

  static String experimentsRestoreSetup(int count) => Intl.plural(count,
      one: "Restore my setup ($count on)",
      other: "Restore my setup ($count on)",
      args: [count],
      name: "experimentsRestoreSetup",
      desc:
          "Button that brings back the saved setup; count is how many experiments it turns on");

  static String experimentsResetOn(int count) => Intl.plural(count,
      one: "Reset… ($count on)",
      other: "Reset… ($count on)",
      args: [count],
      name: "experimentsResetOn",
      desc:
          "Button that opens the reset dialog; count is how many experiments are on right now");

  static String experimentsResetChanged(int count) => Intl.plural(count,
      one: "Reset… ($count changed)",
      other: "Reset… ($count changed)",
      args: [count],
      name: "experimentsResetChanged",
      desc:
          "Button that opens the reset dialog; count is how many experiments differ from a new install");

  static String get experimentsResetDialogTitle =>
      Intl.message("Back to new-user defaults?",
          name: "experimentsResetDialogTitle",
          desc: "Title of the dialog that resets to what a new install has");

  static String get experimentsResetTurnOff =>
      Intl.message("Turn off experiments",
          name: "experimentsResetTurnOff",
          desc: "Checkbox in the reset dialog");

  static String get experimentsResetAllDefault =>
      Intl.message("All are at their defaults already",
          name: "experimentsResetAllDefault",
          desc: "Under the Turn off experiments checkbox when nothing changed");

  static String experimentsResetCountOn(int count) => Intl.plural(count,
      one: "$count is on right now",
      other: "$count are on right now",
      args: [count],
      name: "experimentsResetCountOn",
      desc:
          "Under the Turn off experiments checkbox: how many experiments are on");

  static String experimentsResetCountDiffer(int count) => Intl.plural(count,
      one: "$count differs from a new install",
      other: "$count differ from a new install",
      args: [count],
      name: "experimentsResetCountDiffer",
      desc:
          "Under the Turn off experiments checkbox: how many experiments differ from a new install");

  static String get experimentsResetAppSettings =>
      Intl.message("Reset app settings too",
          name: "experimentsResetAppSettings",
          desc: "Checkbox in the reset dialog");

  static String get experimentsResetAppSettingsList =>
      Intl.message("Appearance, notifications, link previews, sounds",
          name: "experimentsResetAppSettingsList",
          desc: "Under the Reset app settings too checkbox: what it resets");

  static String get experimentsNeverTouched => Intl.message("Never touched",
      name: "experimentsNeverTouched",
      desc: "Heading of the reset dialog box listing what is never reset");

  static String get experimentsNeverTouchedBody => Intl.message(
      "Your account, rooms, messages and secure messaging "
      "setup stay exactly as they are.",
      name: "experimentsNeverTouchedBody",
      desc: "Text of the reset dialog box listing what is never reset");

  static String get experimentsResetConfirm =>
      Intl.message("Reset and save my setup",
          name: "experimentsResetConfirm",
          desc: "Confirm button of the reset dialog");

  static String _names(List<Experiment> pending) {
    final names = pending.map(experimentTitle).toList();
    if (names.length == 1) return names.single;
    return experimentsNameList(
        names.sublist(0, names.length - 1).join(", "), names.last);
  }

  static String get _restartLabel => ExperimentRegistry.canRelaunch
      ? experimentsRestartNow
      : experimentsCloseVommet;

  static String _restartPrompt(List<Experiment> pending) {
    final names = _names(pending);
    return ExperimentRegistry.canRelaunch
        ? experimentsRestartPrompt(pending.length, names)
        : experimentsClosePrompt(pending.length, names);
  }

  static Future<void> askToRestart(
      BuildContext context, List<Experiment> pending) async {
    final restart = await AdaptiveDialog.confirmation(context,
        title: experimentsRestartDialogTitle,
        prompt: _restartPrompt(pending),
        confirmationText: _restartLabel,
        cancelText: experimentsRestartLater);
    if (restart == true) await ExperimentRegistry.restart();
  }

  void _changed(Experiment experiment, bool value) {
    // After the toggle has stored the new value.
    Future.microtask(() {
      experiment.onChanged?.call(value);
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = ExperimentRegistry.pendingRestart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.science_outlined, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: tiamat.Text.labelLow(experimentsPageIntro),
              ),
            ],
          ),
        ),
        _newUserDefaultsCard(context),
        const SizedBox(height: 12),
        if (pending.isNotEmpty) ...[
          _restartBanner(context, pending),
          const SizedBox(height: 12),
        ],
        for (final category in ExperimentCategory.values)
          if (ExperimentRegistry.inCategory(category).isNotEmpty) ...[
            Panel(
              header: experimentCategoryLabel(category),
              mode: TileType.surfaceContainerLow,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, experiment)
                      in ExperimentRegistry.inCategory(category).indexed) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _toggle(experiment),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _toggle(Experiment experiment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BooleanPreferenceToggle(
          preference: experiment.preference,
          title: experimentTitle(experiment),
          description: experimentDescription(experiment),
          onChanged: (v) => _changed(experiment, v),
        ),
        if (experiment.needsRestart)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.restart_alt, size: 14),
                const SizedBox(width: 4),
                tiamat.Text.labelLow(experimentsNeedsRestart),
              ],
            ),
          ),
      ],
    );
  }

  Widget _restartBanner(BuildContext context, List<Experiment> pending) {
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.restart_alt, size: 20),
            const SizedBox(width: 8),
            Expanded(child: tiamat.Text.label(_restartPrompt(pending))),
            const SizedBox(width: 8),
            tiamat.Button(
              text: _restartLabel,
              onTap: () => ExperimentRegistry.restart(),
            ),
          ],
        ),
      ),
    );
  }

  // Vommet: "Back to new-user defaults". Saves the current setup and resets
  // to what a fresh install has; afterwards the same card offers to restore.
  // Anything that needs a restart shows in the restart banner below.
  Widget _newUserDefaultsCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onDefaults = NewUserDefaults.hasSavedSetup;
    final changed = NewUserDefaults.changedExperiments;

    return Container(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              onDefaults
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : Icon(Icons.restart_alt, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  onDefaults
                      ? experimentsOnNewUserDefaults
                      : experimentsBackToNewUserDefaults,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          tiamat.Text.labelLow(onDefaults
              ? experimentsOnNewUserDefaultsBody
              : experimentsBackToNewUserDefaultsBody),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: Icon(onDefaults ? Icons.history : Icons.restart_alt),
              label: Text(onDefaults
                  ? experimentsRestoreSetup(
                      NewUserDefaults.savedExperimentCount)
                  : _resetLabel(changed)),
              onPressed: onDefaults ? _restore : () => _confirmReset(context),
            ),
          ),
        ],
      ),
    );
  }

  /// "Reset… (5 on)"; "Reset… (5 changed)" when some of them are
  /// experiments that start on and were turned off.
  static String _resetLabel(List<Experiment> changed) {
    final allOn = changed.every((e) => e.preference.value);
    return allOn
        ? experimentsResetOn(changed.length)
        : experimentsResetChanged(changed.length);
  }

  Future<void> _confirmReset(BuildContext context) async {
    final changed = NewUserDefaults.changedExperiments;
    final choice = await AdaptiveDialog.show<(bool, bool)>(
      context,
      title: experimentsResetDialogTitle,
      builder: (context) => _ResetDialog(changed: changed),
    );
    if (choice == null) return;
    final (experiments, appSettings) = choice;
    final changes = await NewUserDefaults.reset(
        experiments: experiments, appSettings: appSettings);
    await _afterChange(changes, appearance: appSettings);
  }

  Future<void> _restore() async {
    final changes = await NewUserDefaults.restore();
    await _afterChange(changes, appearance: true);
  }

  /// Runs the side effects a toggle would have (each experiment's
  /// onChanged), applies the theme and scale again, and redraws.
  Future<void> _afterChange(List<Experiment> changes,
      {required bool appearance}) async {
    for (final e in changes) {
      e.onChanged?.call(e.preference.value);
    }
    if (appearance && mounted) {
      final scale = preferences.appScale.value;
      ScaledWidgetsFlutterBinding.instance.scaleFactor = (_) => scale;
      final theme = await preferences.resolveTheme();
      if (mounted) ThemeChanger.setTheme(context, theme);
    }
    if (mounted) setState(() {});
  }
}

/// The reset dialog: what to reset, what is never touched. Pops with
/// (turn off experiments, reset app settings).
class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.changed});
  final List<Experiment> changed;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  bool experiments = true;
  bool appSettings = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = widget.changed.length;
    final allOn = widget.changed.every((e) => e.preference.value);

    // The desktop popup doesn't bound its width; list tiles need it.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: experiments,
            onChanged: (v) => setState(() => experiments = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(_ExperimentsSettingsPageState.experimentsResetTurnOff),
            subtitle: Text(n == 0
                ? _ExperimentsSettingsPageState.experimentsResetAllDefault
                : allOn
                    ? _ExperimentsSettingsPageState.experimentsResetCountOn(n)
                    : _ExperimentsSettingsPageState.experimentsResetCountDiffer(
                        n)),
          ),
          CheckboxListTile(
            value: appSettings,
            onChanged: (v) => setState(() => appSettings = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title:
                Text(_ExperimentsSettingsPageState.experimentsResetAppSettings),
            subtitle: Text(
                _ExperimentsSettingsPageState.experimentsResetAppSettingsList),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, color: Colors.green.shade400),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          _ExperimentsSettingsPageState.experimentsNeverTouched,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          _ExperimentsSettingsPageState
                              .experimentsNeverTouchedBody,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: experiments || appSettings
                ? () => Navigator.of(context).pop((experiments, appSettings))
                : null,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(_ExperimentsSettingsPageState.experimentsResetConfirm),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(CommonStrings.promptCancel),
          ),
        ],
      ),
    );
  }
}
