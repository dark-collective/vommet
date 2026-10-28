import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// "Translate this room" and "Translate what I write" in the room header
// and their settings sheet (Vommet issues 680 phase 2, 818).

/// The language what you write in [room] goes out in, as the composer
/// picks it (`ComposerTranslation.writingTarget`): the room's language while
/// it's translated, else the one picked or detected here, else the last one
/// you picked.
String? roomWritingLanguage(Room room,
    {RoomTranslation? rooms, ComposerTranslationPrefs? prefs}) {
  final r = rooms ?? RoomTranslation.instance;
  final p = prefs ?? ComposerTranslationPrefs.instance;
  return writingLanguageFor(
      r, p, room.identifier, () => roomDetectedLanguage(room, rooms: r));
}

/// The language others write in [room], detected from their recent
/// messages in its timeline.
String? roomDetectedLanguage(Room room, {RoomTranslation? rooms}) =>
    dominantLanguage(
        recentTextsFromOthers(room.timeline, room.client.self?.identifier),
        (rooms ?? RoomTranslation.instance).translation.detectLanguage);

/// [roomWritingLanguage] without a [Room], for tests.
String? writingLanguageFor(
    RoomTranslation rooms,
    ComposerTranslationPrefs prefs,
    String roomId,
    String? Function() detected) {
  final picked = prefs.targetFor(roomId);
  final target = rooms.isOn(roomId)
      ? rooms.roomLanguage(roomId, () => picked ?? detected())
      : picked ?? detected();
  return target ?? prefs.recentLanguages.firstOrNull;
}

/// What the header's two translation toggles show (Vommet issue 818).
class RoomTranslationToggleState {
  const RoomTranslationToggleState(
      {required this.visible,
      required this.reading,
      required this.writing,
      this.readLanguage,
      this.writeLanguage,
      this.downloading = false});

  /// Hidden while translation can't run or is switched off.
  final bool visible;

  /// "Translate this room".
  final bool reading;

  /// "Translate what I write".
  final bool writing;

  /// Shown on the 文A toggle while [reading].
  final String? readLanguage;

  /// Shown on the ✎ toggle while [writing].
  final String? writeLanguage;

  final bool downloading;

  static RoomTranslationToggleState of(
      RoomTranslation rooms,
      ComposerTranslationPrefs prefs,
      String roomId,
      String? Function() detected) {
    if (!rooms.supported) {
      return const RoomTranslationToggleState(
          visible: false, reading: false, writing: false);
    }
    final reading = rooms.isOn(roomId);
    final writing = rooms.translatesWriting(roomId);
    return RoomTranslationToggleState(
      visible: true,
      reading: reading,
      writing: writing,
      readLanguage: reading ? rooms.roomLanguage(roomId, detected) : null,
      writeLanguage:
          writing ? writingLanguageFor(rooms, prefs, roomId, detected) : null,
      downloading: reading && rooms.downloading.contains(roomId),
    );
  }
}

/// Short code shown on a toggle: "ES", "DE", "ZH".
String toggleLanguageLabel(String code) =>
    code.split(RegExp("[-_]")).first.toUpperCase();

/// 文A and ✎ in the room header (Vommet issue 818): tap turns "Translate
/// this room" / "Translate what I write" on or off at once; when on, each is
/// filled and names its language ("文A ES", "✎ ES"). Long-press (right-click
/// on desktop) opens [showRoomTranslationSheet]. Same in every layout style;
/// hidden while translation is off.
class RoomTranslationToggles extends StatefulWidget {
  const RoomTranslationToggles({required this.room, super.key});

  final Room room;

  @override
  State<RoomTranslationToggles> createState() => _RoomTranslationTogglesState();
}

class _RoomTranslationTogglesState extends State<RoomTranslationToggles> {
  final rooms = RoomTranslation.instance;

  @override
  void initState() {
    super.initState();
    rooms.addListener(onChanged);
  }

  @override
  void dispose() {
    rooms.removeListener(onChanged);
    super.dispose();
  }

  void onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.room.identifier;
    String? detected;
    var detectedOnce = false;
    String? detect() {
      if (!detectedOnce) {
        detectedOnce = true;
        detected = roomDetectedLanguage(widget.room, rooms: rooms);
      }
      return detected;
    }

    final state = RoomTranslationToggleState.of(
        rooms, ComposerTranslationPrefs.instance, id, detect);
    if (!state.visible) return const SizedBox.shrink();
    void settings() => showRoomTranslationSheet(context, widget.room);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoomTranslationToggle(
              icon: Icons.translate,
              on: state.reading,
              label: state.readLanguage,
              busy: state.downloading,
              tooltip: state.reading
                  ? "Stop translating this room (hold for settings)"
                  : "Translate this room (hold for settings)",
              onTap: () => rooms.setOn(id, !state.reading),
              onSettings: settings,
            ),
            const SizedBox(width: 4),
            RoomTranslationToggle(
              icon: Icons.edit_outlined,
              on: state.writing,
              label: state.writeLanguage,
              tooltip: state.writing
                  ? "Stop translating what I write (hold for settings)"
                  : "Translate what I write (hold for settings)",
              onTap: () {
                rooms.setTranslateWriting(id, !state.writing);
                // Nothing to write in yet: pick it in the sheet.
                if (!state.writing &&
                    writingLanguageFor(rooms, ComposerTranslationPrefs.instance,
                            id, detect) ==
                        null) {
                  settings();
                }
              },
              onSettings: settings,
            ),
          ],
        ),
      ),
    );
  }
}

/// One header toggle: an outlined icon when off; filled, with [label],
/// when [on].
class RoomTranslationToggle extends StatelessWidget {
  const RoomTranslationToggle(
      {required this.icon,
      required this.on,
      required this.tooltip,
      required this.onTap,
      required this.onSettings,
      this.label,
      this.busy = false,
      super.key});

  final IconData icon;
  final bool on;
  final String? label;
  final bool busy;
  final String tooltip;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = on ? scheme.onPrimary : scheme.onSurfaceVariant;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: fg, fontWeight: FontWeight.w600);
    return Semantics(
      toggled: on,
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: on ? scheme.primary : Colors.transparent,
          shape: StadiumBorder(
              side: on
                  ? BorderSide.none
                  : BorderSide(color: scheme.outlineVariant)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            onLongPress: onSettings,
            onSecondaryTap: onSettings,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: on && label != null ? 8 : 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: fg))
                      : Icon(icon, size: 16, color: fg),
                  if (on && label != null) ...[
                    const SizedBox(width: 4),
                    Text(toggleLanguageLabel(label!), style: style),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showRoomTranslationSheet(BuildContext context, Room room) =>
    AdaptiveDialog.show(context,
        title: "Translation",
        builder: (context) => RoomTranslationSheet(room: room));

/// Translate this room · Messages are in · Translate what I write.
class RoomTranslationSheet extends StatefulWidget {
  const RoomTranslationSheet({required this.room, this.rooms, super.key});

  final Room room;

  /// Defaults to [RoomTranslation.instance].
  final RoomTranslation? rooms;

  @override
  State<RoomTranslationSheet> createState() => _RoomTranslationSheetState();
}

class _RoomTranslationSheetState extends State<RoomTranslationSheet> {
  late final RoomTranslation rooms = widget.rooms ?? RoomTranslation.instance;

  @override
  void initState() {
    super.initState();
    rooms.addListener(onChanged);
  }

  @override
  void dispose() {
    rooms.removeListener(onChanged);
    super.dispose();
  }

  void onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.room.identifier;
    final settings = rooms.settingsFor(id);
    final target = rooms.translation.targetLanguage;
    final detected = dominantLanguage(
        recentTextsFromOthers(
            widget.room.timeline, widget.room.client.self?.identifier),
        rooms.translation.detectLanguage);
    final languages = [
      for (final code in translationLanguageNames.keys)
        if (rooms.translation.route(code, target) != null) code
    ]..sort((a, b) =>
        translationLanguageName(a).compareTo(translationLanguageName(b)));
    final prefs = ComposerTranslationPrefs.instance;
    final writeLanguages = [
      for (final code in translationLanguageNames.keys)
        if (rooms.translation.route(target, code) != null) code
    ]..sort((a, b) =>
        translationLanguageName(a).compareTo(translationLanguageName(b)));
    final picked = writingLanguageFor(rooms, prefs, id, () => detected);
    final writeLanguage =
        picked != null && writeLanguages.contains(picked) ? picked : null;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsEntryBool(
            settings.on,
            title: "Translate this room",
            description:
                "Messages in other languages show in ${translationLanguageName(target)}, translated on this device.",
            onChanged: (value) => rooms.setOn(id, value),
          ),
          const SizedBox(height: 12),
          const tiamat.Text.labelEmphasised("Messages are in"),
          const SizedBox(height: 4),
          tiamat.DropdownSelector<String>(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            items: ["auto", ...languages],
            value: settings.from ?? "auto",
            itemBuilder: (code) => tiamat.Text(code == "auto"
                ? detected == null
                    ? "Detected automatically"
                    : "Detected: ${translationLanguageName(detected)}"
                : translationLanguageName(code)),
            onItemSelected: (code) {
              if (code == null) return;
              rooms.setFrom(id, code == "auto" ? null : code);
            },
          ),
          const SizedBox(height: 12),
          SettingsEntryBool(
            settings.writesTranslated,
            title: "Translate what I write before sending",
            description: settings.on
                ? "Sends it in the room's language; you keep seeing what you wrote."
                : "Sends it in the language below; you keep seeing what you wrote.",
            onChanged: (value) => rooms.setTranslateWriting(id, value),
          ),
          // Outside the room mode, what you write goes out in its own
          // language (the header ✎, Vommet issue 818).
          if (!settings.on && writeLanguages.isNotEmpty) ...[
            const SizedBox(height: 12),
            const tiamat.Text.labelEmphasised("Write in"),
            const SizedBox(height: 4),
            tiamat.DropdownSelector<String?>(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              items: writeLanguages,
              value: writeLanguage,
              hint: const tiamat.Text("Pick a language"),
              itemBuilder: (code) => tiamat.Text(code == null
                  ? "Pick a language"
                  : translationLanguageName(code)),
              onItemSelected: (code) async {
                if (code == null) return;
                await prefs.setTarget(id, code);
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Your own message sent through "Translate what I write": what you wrote,
/// with a quiet "Sent in Spanish: …" (or "Sent in Spanish + German: …")
/// under it. Only you see this; others see what was sent.
class SentTranslationNote extends StatelessWidget {
  const SentTranslationNote(
      {required this.original,
      required this.sent,
      required this.language,
      super.key});

  final String original;
  final String sent;
  final String language;

  /// [child] unchanged unless [text] was sent translated in [roomId].
  static Widget wrap(
      {required String roomId,
      required String text,
      required Widget child,
      SentTranslations? store}) {
    final entry = (store ?? SentTranslations.instance).lookup(roomId, text);
    if (entry == null) return child;
    return SentTranslationNote(
        original: entry.original, sent: text, language: entry.language);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SelectableText(original, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 4),
              child: Icon(Icons.translate,
                  size: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            Flexible(
              child: Text("Sent in ${languageNames(language)}: $sent",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ],
    );
  }
}
