// Vommet: Settings › Redacted mode (Vommet issue 400), shown while its
// experiment is on.

import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:commet/utils/redaction/redaction_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

String get labelSettingsRedactedMode => Intl.message("Redacted mode",
    name: "labelSettingsRedactedMode",
    desc: "Label of the Redacted mode settings tab and its main switch");

String get redactedModeDescription => Intl.message(
    "Hide names, pictures and messages on screen, e.g. for screenshots or "
    "while sharing your screen. Only what this device shows changes.",
    name: "redactedModeDescription",
    desc: "Explains the Redacted mode switch in settings");

String get redactedModeNotCovered => Intl.message(
    "Not everything is hidden yet: calls, profiles, system notifications and "
    "some lists still show names, and Copy text copies the original.",
    name: "redactedModeNotCovered",
    desc:
        "Warns under the Redacted mode switch which parts of the app it doesn't hide yet");

String get redactedModeLevel => Intl.message("Level",
    name: "redactedModeLevel",
    desc: "Header above the list of redaction levels in settings");

String get redactedModeCustom => Intl.message("Custom",
    name: "redactedModeCustom",
    desc: "Redaction level shown when the switches below were changed by hand");

String get redactedModeDetails => Intl.message("What to redact",
    name: "redactedModeDetails",
    desc: "Header above the individual redaction switches in settings");

String get redactedModePreview => Intl.message("Preview",
    name: "redactedModePreview",
    desc: "Header above the sample messages showing the redaction settings");

String get redactedModeNames => Intl.message("Display names",
    name: "redactedModeNames", desc: "Redaction switch for people's names");

String get redactedModeText => Intl.message("Message text",
    name: "redactedModeText", desc: "Redaction switch for message text");

String get redactedModeKeep => Intl.message("Show",
    name: "redactedModeKeep",
    desc: "Redaction choice: show names or text unchanged");

String get redactedModeHide => Intl.message("Hide",
    name: "redactedModeHide", desc: "Redaction choice: hide names or text");

String get redactedModeScramble => Intl.message("Lorem ipsum",
    name: "redactedModeScramble",
    desc: "Redaction choice: replace names or text with nonsense words");

String get redactedModeAvatars =>
    Intl.message("Hide pictures of people and rooms",
        name: "redactedModeAvatars",
        desc: "Redaction switch for profile pictures and room icons");

String get redactedModeDistinguishable => Intl.message("Keep people apart",
    name: "redactedModeDistinguishable",
    desc: "Redaction switch: give each person their own colour and tag");

String get redactedModeDistinguishableDescription => Intl.message(
    "Each person gets a color and a short tag. They change every time the "
    "app starts and can't be traced back to the person.",
    name: "redactedModeDistinguishableDescription",
    desc: "Explains the Keep people apart redaction switch");

String get redactedModeRoomNames => Intl.message("Room and space names",
    name: "redactedModeRoomNames",
    desc: "Redaction switch for room and space names and topics");

String get redactedModeRoomNamesDescription => Intl.message(
    "Direct messages are named after the person, so they follow Display names.",
    name: "redactedModeRoomNamesDescription",
    desc: "Explains the room names redaction switch");

String get redactedModeImages => Intl.message("Blur pictures and videos",
    name: "redactedModeImages",
    desc: "Redaction switch for pictures and videos in chats");

String get redactedModePreset1 => Intl.message("Hide everything",
    name: "redactedModePreset1",
    desc: "Redaction level 1: hide text, pictures and names");

String get redactedModePreset2 =>
    Intl.message("Hide everything, keep people apart",
        name: "redactedModePreset2",
        desc: "Redaction level 2: like level 1, people stay distinguishable");

String get redactedModePreset3 => Intl.message("Hide who's who",
    name: "redactedModePreset3",
    desc: "Redaction level 3: keep text, hide names and pictures");

String get redactedModePreset4 =>
    Intl.message("Hide who's who, keep people apart",
        name: "redactedModePreset4",
        desc: "Redaction level 4: like level 3, people stay distinguishable");

String get redactedModePreset5 => Intl.message("Lorem ipsum names",
    name: "redactedModePreset5",
    desc: "Redaction level 5: nonsense names, hidden pictures, real text");

String get redactedModePreset6 => Intl.message("Lorem ipsum everything",
    name: "redactedModePreset6",
    desc: "Redaction level 6: all names and text become nonsense words");

String get redactedModePreset1Description => Intl.message(
    "Messages, names and pictures are hidden. Everyone looks the same.",
    name: "redactedModePreset1Description",
    desc: "Describes redaction level 1");

String get redactedModePreset2Description => Intl.message(
    "Messages, names and pictures are hidden. Each person keeps a color and tag.",
    name: "redactedModePreset2Description",
    desc: "Describes redaction level 2");

String get redactedModePreset3Description => Intl.message(
    "Messages stay readable. Names and pictures are hidden; everyone looks the same.",
    name: "redactedModePreset3Description",
    desc: "Describes redaction level 3");

String get redactedModePreset4Description => Intl.message(
    "Messages stay readable. Names and pictures are hidden; each person keeps a color and tag.",
    name: "redactedModePreset4Description",
    desc: "Describes redaction level 4");

String get redactedModePreset5Description => Intl.message(
    "Messages stay readable. Names become nonsense words, pictures are hidden.",
    name: "redactedModePreset5Description",
    desc: "Describes redaction level 5");

String get redactedModePreset6Description => Intl.message(
    "Names and messages become nonsense words; pictures are hidden and blurred.",
    name: "redactedModePreset6Description",
    desc: "Describes redaction level 6");

String redactedModePresetTitle(int level) => [
      redactedModePreset1,
      redactedModePreset2,
      redactedModePreset3,
      redactedModePreset4,
      redactedModePreset5,
      redactedModePreset6,
    ][level - 1];

String redactedModePresetDescription(int level) => [
      redactedModePreset1Description,
      redactedModePreset2Description,
      redactedModePreset3Description,
      redactedModePreset4Description,
      redactedModePreset5Description,
      redactedModePreset6Description,
    ][level - 1];

class RedactionSettingsPage extends StatefulWidget {
  const RedactionSettingsPage({super.key});

  @override
  State<RedactionSettingsPage> createState() => _RedactionSettingsPageState();
}

class _RedactionSettingsPageState extends State<RedactionSettingsPage> {
  late RedactionSettings switches = preferences.redactionSwitches;

  Future<void> update(RedactionSettings settings) async {
    setState(() => switches = settings);
    await preferences.setRedactionSwitches(settings);
  }

  @override
  Widget build(BuildContext context) {
    final preset = RedactionPreset.matching(switches);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Panel(
          header: labelSettingsRedactedMode,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BooleanToggle(
                getValue: () => preferences.redactionEnabled.value,
                setValue: (v) => preferences.redactionEnabled.set(v),
                title: labelSettingsRedactedMode,
                description: redactedModeDescription,
                searchId: preferences.redactionEnabled.key,
              ),
              // Vommet: say what isn't covered, so nobody shares their
              // screen trusting it fully.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                        child: tiamat.Text.labelLow(redactedModeNotCovered)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: redactedModeLevel,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in RedactionPreset.values)
                _PresetTile(
                  title: "${p.level}. ${redactedModePresetTitle(p.level)}",
                  description: redactedModePresetDescription(p.level),
                  selected: preset == p,
                  onTap: () => update(p.applyTo(switches)),
                ),
              if (preset == null)
                _PresetTile(
                    title: redactedModeCustom, selected: true, onTap: null),
            ],
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: redactedModeDetails,
          mode: tiamat.TileType.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChoiceRow<NameRedaction>(
                title: redactedModeNames,
                value: switches.names,
                labels: {
                  NameRedaction.keep: redactedModeKeep,
                  NameRedaction.hide: redactedModeHide,
                  NameRedaction.scramble: redactedModeScramble,
                },
                onChanged: (v) => update(switches.copyWith(names: v)),
              ),
              _ChoiceRow<TextRedaction>(
                title: redactedModeText,
                value: switches.text,
                labels: {
                  TextRedaction.keep: redactedModeKeep,
                  TextRedaction.hide: redactedModeHide,
                  TextRedaction.scramble: redactedModeScramble,
                },
                onChanged: (v) => update(switches.copyWith(text: v)),
              ),
              _SwitchRow(
                title: redactedModeAvatars,
                value: switches.avatars,
                onChanged: (v) => update(switches.copyWith(avatars: v)),
              ),
              _SwitchRow(
                title: redactedModeDistinguishable,
                description: redactedModeDistinguishableDescription,
                value: switches.distinguishable,
                onChanged: (v) => update(switches.copyWith(distinguishable: v)),
              ),
              _SwitchRow(
                title: redactedModeRoomNames,
                description: redactedModeRoomNamesDescription,
                value: switches.roomNames,
                onChanged: (v) => update(switches.copyWith(roomNames: v)),
              ),
              _SwitchRow(
                title: redactedModeImages,
                value: switches.images,
                onChanged: (v) => update(switches.copyWith(images: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        tiamat.Panel(
          header: redactedModePreview,
          mode: tiamat.TileType.surfaceContainerLow,
          child: RedactionScope.withSettings(
            settings: switches,
            child: const RedactionPreview(),
          ),
        ),
      ],
    );
  }
}

/// Sample messages drawn through the nearest [RedactionScope].
class RedactionPreview extends StatelessWidget {
  const RedactionPreview({super.key});

  static const _people = [
    ("@ada:example.org", "Ada Lovelace", Color(0xFFE57373)),
    ("@grace:example.org", "Grace Hopper", Color(0xFF64B5F6)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget message(int person, String text, {Widget? attachment}) {
      final (id, name, color) = _people[person];
      return TimelineEventLayoutMessage(
        senderId: id,
        senderName: name,
        senderColor: color,
        timestamp: "12:0${person + 1}",
        formattedContent: RedactedText(text),
        attachments: attachment,
      );
    }

    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          message(0, "Has anyone tried the new build on Wayland yet?"),
          message(1, "Yes, screen sharing works now. Here's my desktop:",
              attachment: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RedactedImage(
                    child: Container(
                      width: 200,
                      height: 90,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                        scheme.primary,
                        scheme.tertiary,
                      ])),
                      alignment: Alignment.center,
                      child: Icon(Icons.desktop_windows,
                          size: 40, color: scheme.onPrimary),
                    ),
                  ),
                ),
              )),
          message(0, "Nice, thanks!"),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile(
      {required this.title,
      this.description,
      required this.selected,
      required this.onTap});

  final String title;
  final String? description;
  final bool selected;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(title),
                  if (description != null) tiamat.Text.labelLow(description!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(
      {required this.title,
      this.description,
      required this.value,
      required this.onChanged});

  final String title;
  final String? description;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(title),
                if (description != null) tiamat.Text.labelLow(description!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
            child: tiamat.Switch(state: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow(
      {required this.title,
      required this.value,
      required this.labels,
      required this.onChanged});

  final String title;
  final T value;
  final Map<T, String> labels;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          tiamat.Text.labelEmphasised(title),
          SegmentedButton<T>(
            showSelectedIcon: false,
            style: selectedSegmentStyle(Theme.of(context).colorScheme),
            segments: [
              for (final e in labels.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}
