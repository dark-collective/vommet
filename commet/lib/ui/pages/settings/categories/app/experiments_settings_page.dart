import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/new_user_defaults.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/material.dart';

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

  static String _names(List<Experiment> pending) {
    final names = pending.map((e) => e.title).toList();
    if (names.length == 1) return names.single;
    return "${names.sublist(0, names.length - 1).join(", ")} and ${names.last}";
  }

  static String get _restartLabel =>
      ExperimentRegistry.canRelaunch ? "Restart now" : "Close Vommet";

  static String _restartPrompt(List<Experiment> pending) {
    final verb = pending.length == 1 ? "takes" : "take";
    final then = ExperimentRegistry.canRelaunch
        ? ""
        : " Vommet will close; open it again to finish.";
    return "${_names(pending)} $verb effect after Vommet restarts.$then";
  }

  static Future<void> askToRestart(
      BuildContext context, List<Experiment> pending) async {
    final restart = await AdaptiveDialog.confirmation(context,
        title: "Restart to apply",
        prompt: _restartPrompt(pending),
        confirmationText: _restartLabel,
        cancelText: "Later");
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
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Row(
            children: [
              Icon(Icons.science_outlined, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: tiamat.Text.labelLow(
                    "Unfinished features. They may have bugs or security "
                    "issues; turn one off again if something breaks."),
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
              header: category.label,
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
          title: experiment.title,
          description: experiment.description,
          onChanged: (v) => _changed(experiment, v),
        ),
        if (experiment.needsRestart)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.restart_alt, size: 14),
                SizedBox(width: 4),
                tiamat.Text.labelLow("Needs a restart"),
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
                      ? "You're on new-user defaults"
                      : "Back to new-user defaults",
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
              ? "This is what someone who just installed Vommet sees. Your "
                  "previous setup is saved."
              : "See the app the way a brand-new user does. We'll save your "
                  "current setup so you can switch back."),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              icon: Icon(onDefaults ? Icons.history : Icons.restart_alt),
              label: Text(onDefaults
                  ? "Restore my setup (${_count(NewUserDefaults.savedExperimentCount)})"
                  : "Reset… (${_count(changed.length, changed)})"),
              onPressed: onDefaults ? _restore : () => _confirmReset(context),
            ),
          ),
        ],
      ),
    );
  }

  /// "5 on"; "5 changed" when some of them are experiments that start on
  /// and were turned off.
  static String _count(int n, [List<Experiment>? changed]) {
    final allOn = changed?.every((e) => e.preference.value) ?? true;
    return allOn ? "$n on" : "$n changed";
  }

  Future<void> _confirmReset(BuildContext context) async {
    final changed = NewUserDefaults.changedExperiments;
    final choice = await AdaptiveDialog.show<(bool, bool)>(
      context,
      title: "Back to new-user defaults?",
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
            title: const Text("Turn off experiments"),
            subtitle: Text(n == 0
                ? "All are at their defaults already"
                : allOn
                    ? "$n ${n == 1 ? "is" : "are"} on right now"
                    : "$n ${n == 1 ? "differs" : "differ"} from a new install"),
          ),
          CheckboxListTile(
            value: appSettings,
            onChanged: (v) => setState(() => appSettings = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text("Reset app settings too"),
            subtitle:
                const Text("Appearance, notifications, link previews, sounds"),
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
                      Text("Never touched",
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                          "Your account, rooms, messages and secure messaging "
                          "setup stay exactly as they are.",
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
            child: const Text("Reset and save my setup"),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }
}
