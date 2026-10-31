import 'package:commet/client/client.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/settings_entry_bool.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// "Translate this room" in the room header and its settings sheet (Vommet
// issue 680 phase 2).

/// The language [room]'s messages are in: picked, else detected from
/// others' recent messages in its timeline.
String? roomTranslationLanguage(Room room, {RoomTranslation? rooms}) {
  final r = rooms ?? RoomTranslation.instance;
  return r.roomLanguage(
      room.identifier,
      () => dominantLanguage(
          recentTextsFromOthers(room.timeline, room.client.self?.identifier),
          r.translation.detectLanguage));
}

/// `文A Translating from Spanish ▾` in the header while the room is
/// translated; nothing otherwise. Tapping it opens [showRoomTranslationSheet].
class RoomTranslationChip extends StatefulWidget {
  const RoomTranslationChip({required this.room, super.key});

  final Room room;

  @override
  State<RoomTranslationChip> createState() => _RoomTranslationChipState();
}

class _RoomTranslationChipState extends State<RoomTranslationChip> {
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
    if (!rooms.isOn(id)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final language = roomTranslationLanguage(widget.room);
    final downloading = rooms.downloading.contains(id);
    final mobile = MediaQuery.of(context).mobile;
    final label = downloading
        ? "Downloading the language model"
        : language == null
            ? (mobile ? "Translating" : "Translating this room")
            : mobile
                ? shortLanguageCode(language)
                : "Translating from ${translationLanguageName(language)}";
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: scheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showRoomTranslationSheet(context, widget.room),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  downloading
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.primary))
                      : Icon(Icons.translate, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(label, style: style),
                  Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
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
            settings.translateWriting,
            title: "Translate what I write before sending",
            description:
                "Sends it in the room's language; you keep seeing what you wrote.",
            onChanged: (value) => rooms.setTranslateWriting(id, value),
          ),
        ],
      ),
    );
  }
}

/// Your own message sent through "Translate what I write": what you wrote,
/// with a quiet "Sent in Spanish: …" under it.
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
              child: Text("Sent in ${translationLanguageName(language)}: $sent",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ],
    );
  }
}
