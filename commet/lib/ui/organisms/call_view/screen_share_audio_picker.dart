import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

/// Vommet: chooses the audio a screen share carries: none, every app except
/// Vommet, or one app, independent of the shared window or screen.
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

  List<ScreenShareAudio> apps = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final list = await ScreenShareAudio.listApps();
    if (mounted) setState(() => apps = list);
  }

  List<ScreenShareAudio> get items => [
        ScreenShareAudio.none,
        ScreenShareAudio.system,
        ...apps,
        // A remembered app that is quiet right now stays selectable: it is
        // picked up as soon as it starts playing.
        if (widget.value.kind == ScreenShareAudioKind.app &&
            !apps.contains(widget.value))
          widget.value,
      ];

  String labelOf(ScreenShareAudio audio) => switch (audio.kind) {
        ScreenShareAudioKind.none => screenShareAudioNone,
        ScreenShareAudioKind.system => screenShareAudioSystem,
        ScreenShareAudioKind.app => audio.label,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        tiamat.Text.labelEmphasised(screenShareAudioLabel),
        const SizedBox(width: 12),
        Expanded(
          child: tiamat.DropdownSelector<ScreenShareAudio>(
            items: items,
            value: widget.value,
            itemHeight: 44,
            onItemSelected: (item) {
              if (item != null) widget.onChanged(item);
            },
            itemBuilder: (item) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: tiamat.Text.label(labelOf(item)),
            ),
          ),
        ),
        IconButton(
          tooltip: screenShareAudioRefresh,
          icon: const Icon(Icons.refresh),
          onPressed: refresh,
        ),
      ],
    );
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
    return SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenShareAudioPicker(
            value: audio,
            onChanged: (a) => setState(() => audio = a),
          ),
          const SizedBox(height: 16),
          tiamat.Button(
            text: CommonStrings.promptContinue,
            onTap: () => Navigator.of(context).pop(audio),
          ),
        ],
      ),
    );
  }
}
