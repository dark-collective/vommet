import 'dart:async';

import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The plain text of other people's text messages in [timeline], newest
/// first (Vommet issue 680 phase 2: the language they write in).
Iterable<String> recentTextsFromOthers(Timeline? timeline, String? selfId,
    {int limit = 30}) sync* {
  if (timeline == null) return;
  var seen = 0;
  for (final event in timeline.events) {
    if (seen >= limit) return;
    if (event is! TimelineEventMessage || event.senderId == selfId) continue;
    if (event.attachments?.isNotEmpty == true) continue;
    seen++;
    yield event.getPlaintextBody(timeline);
  }
}

/// The dialog title before downloading the model(s) for [from] → [to]:
/// names the side that isn't English.
String downloadTitle(String from, String to) =>
    "Download the ${translationLanguageName(from == "en" ? to : from)} language model?";

/// "ES" for Spanish, "ZH" for either Chinese.
String shortLanguageCode(String code) => code.split("-").first.toUpperCase();

/// Translating what you write in one room's composer (Vommet issue 680
/// phase 2). The composer asks it what to show and hands it the draft;
/// changes to the draft stay with the composer.
class ComposerTranslation extends ChangeNotifier {
  ComposerTranslation({
    required this.roomId,
    required this.isDirectMessage,
    required this.recentTextsFromOthers,
    MessageTranslation? translation,
    ComposerTranslationPrefs? prefs,
    RoomTranslation? rooms,
    SentTranslations? sent,
    this.confirmDownload = askToDownload,
    this.previewDelay = const Duration(milliseconds: 500),
  })  : translation = translation ?? MessageTranslation.instance,
        prefs = prefs ?? ComposerTranslationPrefs.instance,
        rooms = rooms ?? RoomTranslation.instance,
        sent = sent ?? SentTranslations.instance {
    this.rooms.addListener(_onRoomsChanged);
  }

  final String roomId;
  final bool isDirectMessage;
  final Iterable<String> Function() recentTextsFromOthers;
  final MessageTranslation translation;
  final ComposerTranslationPrefs prefs;
  final RoomTranslation rooms;
  final SentTranslations sent;
  final Future<bool?> Function(
      BuildContext context, String title, String prompt) confirmDownload;
  final Duration previewDelay;

  /// "Will send in Spanish:" while you type, when the room translates what
  /// you write. [text] is null until it's ready (or when [note] says why
  /// there won't be one).
  ({String draft, String to, String? text, String? note})? preview;

  /// What [prepareSend] translated last: sent text → what you wrote.
  ({String sent, String original, String to})? _outgoing;

  Timer? _previewTimer;
  int _previewRun = 0;

  void _onRoomsChanged() {
    if (!writeMode) {
      _previewTimer?.cancel();
      preview = null;
    }
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _previewTimer?.cancel();
    rooms.removeListener(_onRoomsChanged);
    super.dispose();
  }

  /// "Translate this room" is on with "Translate what I write".
  bool get writeMode => rooms.translatesWriting(roomId);

  bool get roomMode => rooms.isOn(roomId);

  bool busy = false;

  /// Shown above the composer until the draft changes.
  String? error;

  /// After the button translated the draft: what you wrote, and into what.
  ({String original, String to})? translated;

  String? _detected;
  bool _detectedOnce = false;

  /// The language the other person writes in, from their recent messages.
  String? get detectedTarget {
    if (!_detectedOnce) {
      _detectedOnce = true;
      _detected =
          dominantLanguage(recentTextsFromOthers(), translation.detectLanguage);
    }
    return _detected;
  }

  /// Guess again (the chip appears for a new draft).
  void refreshDetected() => _detectedOnce = false;

  /// What the button translates into: in a translated room, the room's
  /// language; else the language picked for this room, else the one the
  /// other person writes in.
  String? get target => roomMode
      ? rooms.roomLanguage(
          roomId, () => prefs.targetFor(roomId) ?? detectedTarget)
      : prefs.targetFor(roomId) ?? detectedTarget;

  bool get buttonEnabled =>
      translation.supported &&
      isDirectMessage &&
      ComposerTranslationPrefs.buttonPreference.value;

  bool showChip(String draft) =>
      (buttonEnabled || roomMode) && draft.trim().isNotEmpty;

  void onDraftChanged(String draft) {
    if (error != null) {
      error = null;
      notifyListeners();
    }
    if (!writeMode) return;
    _previewTimer?.cancel();
    if (draft.trim().isEmpty || _skipsTranslation(draft)) {
      if (preview != null) {
        preview = null;
        notifyListeners();
      }
      return;
    }
    _previewTimer = Timer(previewDelay, () => _makePreview(draft.trim()));
  }

  /// Commands go out as typed.
  static bool _skipsTranslation(String draft) =>
      draft.trimLeft().startsWith("/");

  Future<void> _makePreview(String draft) async {
    final run = ++_previewRun;
    final to = target;
    void show(String? text, String? note) {
      if (run != _previewRun || !writeMode) return;
      preview =
          to == null ? null : (draft: draft, to: to, text: text, note: note);
      notifyListeners();
    }

    if (to == null) {
      preview = null;
      error = "Pick the language to send in: right-click or long-press 文A.";
      notifyListeners();
      return;
    }
    final from = translation.draftLanguage(draft);
    if (from == to) {
      show(draft, null);
      return;
    }
    final models = translation.route(from, to);
    if (models == null) {
      show(null,
          "Can't translate ${translationLanguageName(from)} into ${translationLanguageName(to)} yet.");
      return;
    }
    if ((await translation.missingModels(models)).isNotEmpty) {
      show(null, "The language model downloads when you send.");
      return;
    }
    show(null, null);
    try {
      show(await translation.translateText(draft, from, to), null);
    } catch (_) {
      show(null, "Couldn't translate this yet.");
    }
  }

  /// Send: what to send for [draft], translated when the room translates
  /// what you write; null when it couldn't be translated (the draft stays,
  /// with [error] saying why). Never sends untranslated without saying so.
  Future<String?> prepareSend(BuildContext context, String draft) async {
    _outgoing = null;
    if (!writeMode || _skipsTranslation(draft)) return draft;
    if (busy) return null;
    final to = target;
    final p = preview;
    busy = true;
    error = null;
    notifyListeners();
    final result = await translateDraft(translation,
        draft: draft,
        to: to,
        ready: p != null && p.draft == draft && p.to == to ? p.text : null,
        confirmDownload: (from, to, missing) =>
            _confirm(context, from, to, missing));
    busy = false;
    switch (result) {
      case DraftTranslated(:final text, to: final language):
        _outgoing = (sent: text, original: draft, to: language);
        notifyListeners();
        return text;
      case DraftUnchanged():
        notifyListeners();
        return draft;
      case DraftBlocked(:final message):
        error = "Not sent. $message";
        notifyListeners();
        return null;
    }
  }

  /// The chip in a translated room: turns "Translate what I write" off and
  /// on.
  Future<void> toggleWriting() => rooms.setTranslateWriting(roomId, !writeMode);

  Future<bool?> _confirm(BuildContext context, String from, String to,
      List<TranslationModelSpec> missing) {
    if (!context.mounted) return Future.value(false);
    return confirmDownload(
        context, downloadTitle(from, to), downloadPrompt(from, to, missing));
  }

  /// The button: [draft] translated into [target] (asking for the language
  /// first when there's none), or null when nothing changes.
  Future<String?> translateWithButton(
      BuildContext context, String draft) async {
    var to = target;
    if (to == null) {
      to = await pickLanguage(context, draft);
      if (to == null || !context.mounted) return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    final result = await translateDraft(translation,
        draft: draft,
        to: to,
        confirmDownload: (from, to, missing) =>
            _confirm(context, from, to, missing));
    busy = false;
    switch (result) {
      case DraftTranslated(:final text):
        translated = (original: draft, to: to);
        notifyListeners();
        return text;
      case DraftUnchanged():
        error = "This is already in ${translationLanguageName(to)}.";
      case DraftBlocked(:final message):
        error = message;
    }
    notifyListeners();
    return null;
  }

  /// "Translate into": asks for a language and remembers it for this room.
  Future<String?> pickLanguage(BuildContext context, String draft) async {
    final from = translation.draftLanguage(draft);
    final current = target;
    final items = menuLanguages(translation, from, prefs.recentLanguages);
    if (items.isEmpty) {
      error =
          "Nothing translates ${translationLanguageName(from)} on this device yet.";
      notifyListeners();
      return null;
    }
    final picked = await AdaptiveDialog.pickOne<String>(context,
        title: "Translate into",
        items: items,
        itemBuilder: (context, code, onTap) => SizedBox(
              height: 40,
              child: InkWell(
                onTap: onTap,
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: code == current
                          ? const Icon(Icons.check, size: 18)
                          : null,
                    ),
                    Expanded(child: tiamat.Text(translationLanguageName(code))),
                  ],
                ),
              ),
            ));
    if (picked == null) return null;
    if (roomMode) {
      await rooms.setFrom(roomId, picked);
    } else {
      await prefs.setTarget(roomId, picked);
    }
    notifyListeners();
    return picked;
  }

  /// Undo: what you wrote before the button translated it.
  String? undo() {
    final original = translated?.original;
    translated = null;
    notifyListeners();
    return original;
  }

  /// ⊗ on the line: keep the translation, hide the line.
  void hideLine() {
    translated = null;
    notifyListeners();
  }

  /// After [sentText] went out: remember what you wrote when it was
  /// translated, and clear the lines.
  void onSent(String sentText) {
    final out = _outgoing;
    _outgoing = null;
    if (out != null && out.sent == sentText) {
      sent.remember(roomId,
          sent: out.sent, original: out.original, language: out.to);
    }
    _previewTimer?.cancel();
    if (translated == null && error == null && preview == null) return;
    translated = null;
    error = null;
    preview = null;
    notifyListeners();
  }
}

/// `文A ES` inside the text field, left of the emoji button. Tap
/// translates; right-click or long-press picks the language.
class ComposerTranslateChip extends StatelessWidget {
  const ComposerTranslateChip({
    required this.language,
    required this.onTap,
    required this.onPickLanguage,
    this.busy = false,
    this.active = false,
    super.key,
  });

  final String? language;
  final bool busy;

  /// Filled: what you write is translated before it's sent.
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onPickLanguage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.onPrimary : scheme.primary;
    final tooltip = language == null
        ? "Translate on this device (pick a language)"
        : "Translate into ${translationLanguageName(language!)} on this device";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? scheme.primary : scheme.surfaceContainerHighest,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: busy ? null : onTap,
            onLongPress: onPickLanguage,
            onSecondaryTap: onPickLanguage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: fg))
                      : Icon(Icons.translate, size: 16, color: fg),
                  if (language != null) ...[
                    const SizedBox(width: 4),
                    Text(shortLanguageCode(language!),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
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

/// Above the composer after the button translated the draft, in the style
/// of the Reply/Edit line: ⊗ · 文A "Translated to Spanish on this device" ·
/// "Yours: …" · Undo.
class ComposerTranslatedLine extends StatelessWidget {
  const ComposerTranslatedLine({
    required this.to,
    required this.original,
    required this.onHide,
    required this.onUndo,
    super.key,
  });

  final String to;
  final String original;
  final VoidCallback onHide;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: tiamat.IconButton(
                icon: Icons.cancel_outlined,
                size: 16,
                onPressed: onHide,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.translate, size: 16, color: scheme.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              child: tiamat.Text.labelEmphasised(
                  "Translated to ${translationLanguageName(to)} on this device"),
            ),
            Flexible(
              child: tiamat.Text.labelLow(
                "Yours: ${original.replaceAll("\n", " ")}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text("Undo"),
            ),
          ],
        ),
      ),
    );
  }
}

/// A translation problem above the composer.
class ComposerTranslationError extends StatelessWidget {
  const ComposerTranslationError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          Icon(Icons.translate, size: 16, color: scheme.error),
          const SizedBox(width: 6),
          Flexible(
            child: Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Above the composer while you type in a room that translates what you
/// write: accent bar · 文A "Will send in Spanish:" · the translation.
class ComposerTranslationStrip extends StatelessWidget {
  const ComposerTranslationStrip(
      {required this.to, this.text, this.note, super.key});

  final String to;
  final String? text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.translate, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: "Will send in ${translationLanguageName(to)}: ",
                      style: small?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: text ?? note ?? "…",
                      style: small?.copyWith(
                          color: text == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface)),
                ]),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
