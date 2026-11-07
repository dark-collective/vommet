import 'dart:math';

import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: chooses the audio a screen share carries: none, every app except
/// Vommet, or one app, independent of the shared window or screen.
// Vommet issue 91: selected apps now share one inclusion checkbox list.
class ScreenShareAudioPicker extends StatefulWidget {
  const ScreenShareAudioPicker(
      {required this.value, required this.onChanged, super.key});

  final ScreenShareAudio value;
  final void Function(ScreenShareAudio audio) onChanged;

  @override
  State<ScreenShareAudioPicker> createState() => _ScreenShareAudioPickerState();
}

class _ScreenShareAudioPickerState extends State<ScreenShareAudioPicker> {
  String get screenShareAudioNone => Intl.message("No audio",
      name: "screenShareAudioNone",
      desc: "Screen share audio picker: option to share no audio");

  String get screenShareAudioSystem => Intl.message(
      "All apps (except voice chat apps)",
      name: "screenShareAudioSystem",
      desc:
          "Screen share audio picker: option to share the audio of every app");

  String get screenShareAudioLabel => Intl.message("Audio:",
      name: "screenShareAudioLabel",
      desc: "Screen share audio picker: label in front of the dropdown");

  String get screenShareAudioRefresh =>
      Intl.message("Refresh the list of apps playing audio",
          name: "screenShareAudioRefresh",
          desc: "Screen share audio picker: tooltip on the refresh button");

  String get selectedLabel => Intl.message("Selected apps",
      name: "screenShareAudioSelected",
      desc: "Share audio only from the checked apps");
  String get emptyLabel => Intl.message("Select an app or choose No audio.",
      name: "screenShareAudioEmpty",
      desc: "No apps have been checked for screen share audio");
  String get missingLabel => Intl.message("Not currently listed",
      name: "screenShareAudioMissing",
      desc: "A selected audio app is quiet or no longer running");
  String get errorLabel =>
      Intl.message("Could not list audio apps. Refresh to retry.",
          name: "screenShareAudioListError",
          desc: "The screen share audio source list could not be loaded");
  String get voiceLabel => Intl.message("May send another call's audio",
      name: "screenShareAudioVoiceWarning",
      desc: "Warning when explicitly selecting a voice chat app to share");
  String get scopeLabel => Intl.message(
      "Shares all matching instances of each checked app.",
      name: "screenShareAudioAppScope",
      desc:
          "Screen share audio selects whole apps, not individual windows or tabs");

  List<ScreenShareAudio> apps = [];
  late List<ScreenShareAudio> remembered = widget.value.apps;
  int refreshId = 0;
  bool loading = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(covariant ScreenShareAudioPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.kind == ScreenShareAudioKind.app) {
      remembered = widget.value.apps;
    }
  }

  Future<void> refresh() async {
    final id = ++refreshId;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final list = await ScreenShareAudio.listApps(rethrowErrors: true);
      if (mounted && id == refreshId) setState(() => apps = list);
    } catch (_) {
      if (mounted && id == refreshId) setState(() => failed = true);
    } finally {
      if (mounted && id == refreshId) setState(() => loading = false);
    }
  }

  String labelOf(ScreenShareAudioKind kind) => switch (kind) {
        ScreenShareAudioKind.none => screenShareAudioNone,
        ScreenShareAudioKind.system => screenShareAudioSystem,
        ScreenShareAudioKind.app => selectedLabel,
      };

  Widget appList() {
    final entries = {for (final app in apps) app.identity: app};
    for (final app in widget.value.apps) {
      entries.putIfAbsent(app.identity, () => app);
    }
    final list = entries.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final checked = widget.value.apps.map((a) => a.identity).toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Text(scopeLabel, style: Theme.of(context).textTheme.bodySmall),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(shrinkWrap: true, primary: false, children: [
          for (final app in list)
            CheckboxListTile(
              value: checked.contains(app.identity),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(app.label),
              subtitle: Text([
                app.value,
                if (!apps.any((a) => a.identity == app.identity)) missingLabel,
                if (app.isVoiceChat) voiceLabel,
              ].join(' · ')),
              onChanged: (on) => widget.onChanged(ScreenShareAudio.selected([
                for (final selected in widget.value.apps)
                  if (selected.identity != app.identity) selected,
                if (on == true) app,
              ])),
            ),
        ]),
      ),
      if (!widget.value.isValid) Text(emptyLabel),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        tiamat.Text.labelEmphasised(screenShareAudioLabel),
        const SizedBox(width: 12),
        Expanded(
          child: tiamat.DropdownSelector<ScreenShareAudioKind>(
            items: ScreenShareAudioKind.values,
            value: widget.value.kind,
            itemHeight: 56,
            onItemSelected: (kind) {
              if (kind == null) return;
              widget.onChanged(switch (kind) {
                ScreenShareAudioKind.none => ScreenShareAudio.none,
                ScreenShareAudioKind.system => ScreenShareAudio.system,
                ScreenShareAudioKind.app =>
                  ScreenShareAudio.selected(remembered),
              });
            },
            itemBuilder: (kind) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(labelOf(kind),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
        IconButton(
          tooltip: screenShareAudioRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: refresh,
        ),
      ]),
      if (loading) const LinearProgressIndicator(),
      if (failed) Text(errorLabel),
      if (widget.value.kind == ScreenShareAudioKind.app) appList(),
    ]);
  }
}

/// Audio-only step for when the system picks the video source (Wayland
/// portal), so the in-app source dialog is skipped. Pops the choice, or null.
class ScreenShareAudioDialog extends StatefulWidget {
  const ScreenShareAudioDialog({super.key});

  @override
  State<ScreenShareAudioDialog> createState() => _ScreenShareAudioDialogState();
}

class _ScreenShareAudioDialogState extends State<ScreenShareAudioDialog> {
  ScreenShareAudio audio = ScreenShareAudio.lastChoice;

  @override
  Widget build(BuildContext context) {
    // Vommet issue 91: keep actions reachable in short/narrow windows.
    return SizedBox(
      width: 500,
      height: min(430, MediaQuery.sizeOf(context).height * .65),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child: SingleChildScrollView(
                  child: ScreenShareAudioPicker(
            value: audio,
            onChanged: (a) => setState(() => audio = a),
          ))),
          const SizedBox(height: 16),
          Row(children: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(CommonStrings.promptCancel)),
            const SizedBox(width: 8),
            Expanded(
                child: tiamat.Button(
              text: CommonStrings.promptContinue,
              onTap:
                  audio.isValid ? () => Navigator.of(context).pop(audio) : null,
            )),
          ]),
        ],
      ),
    );
  }
}
