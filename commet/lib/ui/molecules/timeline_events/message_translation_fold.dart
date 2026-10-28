import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/ui/molecules/composer_translation.dart';
import 'package:commet/ui/molecules/room_translation_views.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The language [room]'s messages are in, for messages whose own language
/// can't be told: picked, else detected from others' recent messages
/// (reused for [RoomTranslation.detectedTtl]).
String? roomReadingLanguage(Room room, {RoomTranslation? rooms}) {
  final r = rooms ?? RoomTranslation.instance;
  return r.roomLanguage(
      room.identifier,
      () => r.detectedFor(
          room.identifier, () => roomDetectedLanguage(room, rooms: r)));
}

/// On-device translation under a message (Vommet issue 680): a "Translate"
/// pill at the end of a message in another language; tapping it shows the
/// translation under the original, behind a divider, with a caption and a
/// chevron that folds it away again, like a voice message transcript.
///
/// In a room with "Translate this room" on (phase 2), the translation is
/// made as the message is built and shown instead of the original, with a
/// small 文A that shows the original under it.
///
/// [wrap] leaves [child] alone where translation can't run (web, macOS,
/// iOS, Android before 9, Linux CPUs without SSE4.2).
class MessageTranslationFold extends StatefulWidget {
  const MessageTranslationFold({
    required this.eventId,
    required this.text,
    required this.child,
    this.roomId,
    this.roomLanguage,
    this.autoTranslatable = true,
    this.translation,
    this.rooms,
    this.confirmDownload = askToDownload,
    super.key,
  });

  final String eventId;
  final String text;
  final Widget child;

  /// The room the message is in, for "Translate this room".
  final String? roomId;

  /// The room's language, for messages whose own language can't be told
  /// while the room is translated.
  final String? Function()? roomLanguage;

  /// False for messages the room mode leaves alone (code blocks); the
  /// Translate pill still works on them.
  final bool autoTranslatable;

  /// Defaults to [MessageTranslation.instance].
  final MessageTranslation? translation;

  /// Defaults to [RoomTranslation.instance].
  final RoomTranslation? rooms;

  /// Asks before the first download from a language; tests answer it.
  final Future<bool?> Function(
      BuildContext context, String title, String prompt) confirmDownload;

  /// [child] with a Translate pill when [text] is in a language we can
  /// translate; [child] unchanged otherwise.
  static Widget wrap({
    required String eventId,
    required String text,
    required Widget child,
    String? roomId,
    String? Function()? roomLanguage,
    bool autoTranslatable = true,
    MessageTranslation? translation,
    RoomTranslation? rooms,
    Future<bool?> Function(BuildContext context, String title, String prompt)
        confirmDownload = askToDownload,
  }) {
    final t = translation ?? MessageTranslation.instance;
    // The master switch is followed by the fold itself, so flipping it
    // updates messages already on screen (Vommet issue 820).
    if (!t.available || text.trim().isEmpty) return child;
    return MessageTranslationFold(
        eventId: eventId,
        text: text,
        roomId: roomId,
        roomLanguage: roomLanguage,
        autoTranslatable: autoTranslatable,
        translation: t,
        rooms: rooms,
        confirmDownload: confirmDownload,
        child: child);
  }

  @override
  State<MessageTranslationFold> createState() => _MessageTranslationFoldState();
}

class _MessageTranslationFoldState extends State<MessageTranslationFold> {
  late MessageTranslation translation;
  late RoomTranslation rooms;
  late ValueNotifier<TranslationState> state;
  String? language;
  bool collapsed = false;

  /// Room mode: queued for translation, the models were declined, the
  /// original is shown under the translation.
  bool autoPending = false;
  bool autoDeclined = false;
  bool showOriginal = false;

  /// Settings: "Translate button on messages".
  bool buttonOn = MessageTranslation.buttonPreference.value;
  StreamSubscription<bool>? buttonSub;

  /// Settings: the master switch and "Languages I read" (Vommet issues 820,
  /// 821).
  final List<StreamSubscription<Object?>> prefSubs = [];

  /// Edits change the text, so the key covers it too.
  String get key => "${widget.eventId}\u0000${widget.text.hashCode}";

  bool get auto =>
      widget.roomId != null &&
      widget.autoTranslatable &&
      !autoDeclined &&
      language != null &&
      rooms.isOn(widget.roomId!);

  @override
  void initState() {
    super.initState();
    translation = widget.translation ?? MessageTranslation.instance;
    rooms = widget.rooms ?? RoomTranslation.instance;
    rooms.addListener(onRoomsChanged);
    buttonSub = MessageTranslation.buttonPreference.onChanged.listen((v) {
      if (mounted) setState(() => buttonOn = v);
    });
    for (final changes in <Stream<Object?>>[
      MessageTranslation.enabledPreference.onChanged,
      MessageTranslation.readPreference.onChanged,
      MessageTranslation.languagePreference.onChanged,
    ]) {
      prefSubs.add(changes.listen((_) => onPrefsChanged()));
    }
    bind();
    scheduleAuto();
  }

  @override
  void dispose() {
    rooms.removeListener(onRoomsChanged);
    buttonSub?.cancel();
    for (final sub in prefSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(MessageTranslationFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId || oldWidget.text != widget.text) {
      autoPending = false;
      showOriginal = false;
      bind();
      scheduleAuto();
    }
  }

  void bind() {
    language = bindLanguage();
    state = translation.stateFor(key);
    // Translations the room mode made fold away once it's off.
    collapsed = !auto && rooms.wasAutoTranslated(key);
  }

  /// In a translated room, a message whose language can't be told is taken
  /// to be in the room's.
  String? bindLanguage() {
    final roomId = widget.roomId, roomLanguage = widget.roomLanguage;
    return roomId != null && roomLanguage != null && rooms.isOn(roomId)
        ? translation.translatableLanguageOr(key, widget.text, roomLanguage)
        : translation.translatableLanguage(key, widget.text);
  }

  void onPrefsChanged() {
    if (!mounted) return;
    setState(() {
      bind();
      scheduleAuto();
    });
  }

  void onRoomsChanged() {
    if (!mounted) return;
    setState(() {
      // Turning the room on gives unsure messages its language.
      language = bindLanguage();
      if (!auto && rooms.wasAutoTranslated(key)) collapsed = true;
      scheduleAuto();
    });
  }

  /// Room mode: translate once the message is on screen.
  void scheduleAuto() {
    if (!auto || autoPending || state.value is! TranslationIdle) return;
    autoPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ok = await rooms.autoTranslate(
          widget.roomId!, key, widget.text, language!,
          wanted: () => mounted, confirm: confirmForRoom);
      if (!mounted) return;
      setState(() {
        autoPending = false;
        if (!ok) autoDeclined = true;
      });
    });
  }

  /// Null when this message is gone and can't ask.
  Future<bool?> confirmForRoom(
      String from, String to, List<TranslationModelSpec> missing) async {
    if (!mounted) return null;
    final ok = await widget.confirmDownload(
        context, downloadTitle(from, to), downloadPrompt(from, to, missing));
    return ok == true;
  }

  Future<void> start() async {
    final from = language;
    if (from == null) return;
    final to = translation.targetLanguage;
    final route = translation.route(from, to);
    if (route == null) return;
    final missing = await translation.missingModels(route);
    if (missing.isNotEmpty) {
      if (!mounted) return;
      final ok = await widget.confirmDownload(
          context,
          "Download the ${translationLanguageName(from)} language model?",
          downloadPrompt(from, to, missing));
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => collapsed = false);
    await translation.translate(key, widget.text, from);
  }

  void onPill(TranslationState value) {
    switch (value) {
      case TranslationDownloading() || TranslationRunning():
        translation.cancel(key);
      case TranslationDone():
        setState(() => collapsed = false);
      case TranslationIdle() || TranslationFailed():
        start();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (language == null) return widget.child;
    return ValueListenableBuilder<TranslationState>(
      valueListenable: state,
      builder: (context, value, _) {
        if (auto) {
          switch (value) {
            case TranslationDone(:final text, :final from):
              return autoTranslated(text, from);
            case TranslationRunning() || TranslationDownloading():
              return dimmed();
            case TranslationIdle() when autoPending:
              return dimmed();
            default:
              break;
          }
        }
        if (value case TranslationDone(:final text, :final from, :final to)
            when !collapsed) {
          return translated(text, from, to);
        }
        // Turned off in Settings: the message only, no Translate button.
        if (!buttonOn) return widget.child;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Vommet issue 822: the pill sits under the message, so the
            // text wraps as it would without it.
            widget.child,
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child:
                  TranslatePill(state: value, onPressed: () => onPill(value)),
            ),
            if (value case TranslationFailed(:final message))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        );
      },
    );
  }

  /// The original, dimmed, while the room mode translates it.
  Widget dimmed() => Opacity(opacity: 0.5, child: widget.child);

  /// Room mode: the translation in place of the original, a small 文A that
  /// shows the original under it in a quiet box with Copy.
  Widget autoTranslated(String text, String from) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
                child: SelectableText(text, style: theme.textTheme.bodyMedium)),
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Tooltip(
                message: showOriginal
                    ? "Hide the original"
                    : "Translated from ${translationLanguageName(from)} on this device. Show the original",
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => showOriginal = !showOriginal),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.translate,
                        size: 14,
                        color: showOriginal
                            ? scheme.primary
                            : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showOriginal)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text("Original (${translationLanguageName(from)})",
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: widget.text)),
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text("Copy"),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6)),
                    ),
                  ],
                ),
                widget.child,
              ],
            ),
          ),
      ],
    );
  }

  Widget translated(String text, String from, String to) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.child,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        SelectableText(text, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                "${translationLanguageName(from)} → ${translationLanguageName(to)}"
                " · translated on this device",
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: "Hide translation",
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => collapsed = true),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle),
                  child: Icon(Icons.keyboard_arrow_up,
                      size: 18, color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<bool?> askToDownload(
        BuildContext context, String title, String prompt) =>
    AdaptiveDialog.confirmation(context,
        title: title,
        prompt: prompt,
        confirmationText: "Download",
        cancelText: "Cancel");

/// The dialog text before the first translation from a language.
String downloadPrompt(
    String from, String to, List<TranslationModelSpec> missing) {
  final size = formatModelSize(missing.fold(0, (sum, s) => sum + s.bytes));
  final what = missing.length == 1
      ? "a language model ($size)"
      : "${missing.length} language models ($size, through English)";
  return "Translation runs on this device, so messages never leave it. "
      "Translating ${translationLanguageName(from)} into "
      "${translationLanguageName(to)} needs $what, downloaded once from "
      "Mozilla (the models Firefox uses). You can delete it later in Settings, under Translation.";
}

String formatModelSize(int bytes) {
  final mb = bytes / 1000000;
  return mb >= 10 ? "${mb.round()} MB" : "${mb.toStringAsFixed(1)} MB";
}

/// "Translate" in a rounded pill; while busy it shows progress and cancels.
class TranslatePill extends StatelessWidget {
  const TranslatePill(
      {required this.state, required this.onPressed, super.key});

  final TranslationState state;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final (String label, String tooltip, double? progress, bool busy) =
        switch (state) {
      TranslationDownloading(:final progress) => (
          progress == null ? "Downloading" : "${(progress * 100).round()}%",
          "Cancel the download",
          progress,
          true
        ),
      TranslationRunning() => ("Translating", "Cancel", null, true),
      TranslationDone() => (
          "Show translation",
          "Show translation",
          null,
          false
        ),
      _ => ("Translate", "Translate on this device", null, false),
    };
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, value: progress, color: scheme.primary),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(label, style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
