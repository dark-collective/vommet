import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

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
}
