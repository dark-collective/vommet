import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/molecules/timeline_events/message_translation_fold.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/translation/composer_translation.dart';
import 'package:commet/utils/translation/message_translation.dart';
import 'package:commet/utils/translation/model_spec.dart';
import 'package:commet/utils/translation/paragraph_translation.dart';
import 'package:commet/utils/translation/room_translation.dart';
import 'package:flutter/foundation.dart' show listEquals;
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

/// "Spanish + German" for "es+de" (the languages a message went out in).
String languageNames(String joined) =>
    splitLanguages(joined).map(translationLanguageName).join(" + ");

/// "ES" for Spanish, "ZH" for either Chinese.
String shortLanguageCode(String code) => code.split("-").first.toUpperCase();

/// Translating what you write in one room's composer (Vommet issue 680
/// phase 2; per paragraph, on send, since the phone composer round 3). The
/// composer hands it every draft change and asks it what to show; changes
/// to the draft text stay with the composer.
///
/// Each paragraph (one line, see `paragraph_translation.dart`) has an
/// optional target. Tapping 文A sets the one under the caret; a new
/// paragraph inherits the target of the one above; in a room that
/// translates what you write, paragraphs default to the room's language.
/// Sending translates the paragraphs that have a target and joins them;
/// when one can't be translated, nothing is sent and [error] names it.
class ComposerTranslation extends ChangeNotifier {
  ComposerTranslation({
    required this.roomId,
    required this.recentTextsFromOthers,
    MessageTranslation? translation,
    ComposerTranslationPrefs? prefs,
    RoomTranslation? rooms,
    SentTranslations? sent,
    this.confirmDownload = askToDownload,
  })  : translation = translation ?? MessageTranslation.instance,
        prefs = prefs ?? ComposerTranslationPrefs.instance,
        rooms = rooms ?? RoomTranslation.instance,
        sent = sent ?? SentTranslations.instance {
    this.rooms.addListener(_onRoomsChanged);
  }

  final String roomId;
  final Iterable<String> Function() recentTextsFromOthers;
  final MessageTranslation translation;
  final ComposerTranslationPrefs prefs;
  final RoomTranslation rooms;
  final SentTranslations sent;
  final Future<bool?> Function(
      BuildContext context, String title, String prompt) confirmDownload;

  /// What [prepareSend] translated last: sent text → what you wrote.
  ({String sent, String original, String to})? _outgoing;

  /// The last translation made for the "Will send" preview, reused by the
  /// send that follows it.
  ({String draft, List<String?> resolved, _Translated result})? _prepared;

  void _onRoomsChanged() {
    _prepared = null;
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
    rooms.removeListener(_onRoomsChanged);
    super.dispose();
  }

  /// "Translate what I write" is on here (with or without the room
  /// translated).
  bool get writeMode => rooms.translatesWriting(roomId);

  bool get roomMode => rooms.isOn(roomId);

  bool busy = false;

  /// Shown above the composer until the draft changes.
  String? error;

  /// After "Translate now": what you wrote, the languages ("es+de"), and the
  /// paragraph targets to restore on Undo.
  ({String original, String to, List<String?> targets})? translated;

  String? _detected;
  bool _detectedOnce = false;
  DateTime? _detectedAt;

  /// The language others write in here, from their recent messages.
  String? get detectedTarget {
    if (!_detectedOnce) {
      _detectedOnce = true;
      _detectedAt = DateTime.now();
      _detected =
          dominantLanguage(recentTextsFromOthers(), translation.detectLanguage);
    }
    return _detected;
  }

  /// Guess again (the chip appears for a new draft).
  void refreshDetected() => _detectedOnce = false;

  /// What 文A translates into: in a translated room, the room's language;
  /// else the language picked for this room, else the one others write in.
  String? get target => roomMode
      ? rooms.roomLanguage(
          roomId, () => prefs.targetFor(roomId) ?? detectedTarget)
      : prefs.targetFor(roomId) ?? detectedTarget;

  /// Once turned on in Settings, in every room.
  bool get buttonEnabled =>
      translation.supported && ComposerTranslationPrefs.buttonPreference.value;

  bool showChip(String draft) =>
      (buttonEnabled || roomMode || writeMode) && draft.trim().isNotEmpty;

  // Paragraphs.

  List<String> _lines = const [""];
  List<String?> _targets = const [null];

  /// What "Translate what I write" sends in: [target], else the language
  /// you picked last anywhere.
  String? get writingTarget => target ?? prefs.recentLanguages.firstOrNull;

  /// What paragraphs without a target of their own go out in.
  String? get defaultTarget => writeMode ? writingTarget : null;

  /// The language each paragraph of the current draft goes out in (null =
  /// as written).
  List<String?> get resolved => _skipsTranslation(_lines.join("\n"))
      ? List<String?>.filled(_lines.length, null)
      : resolveTargets(_lines, _targets, fallback: defaultTarget);

  /// The runs of paragraphs that will be translated, for the tint and the
  /// "→ Spanish" tags: first and last paragraph and the language.
  List<({int first, int last, String to})> get translatedRuns {
    final runs = <({int first, int last, String to})>[];
    final r = resolved;
    for (final b in sendBlocks(_lines, r)) {
      final to = b.to;
      if (to == null) continue;
      runs.add((
        first: b.first,
        last: b.first + "\n".allMatches(b.text).length,
        to: to
      ));
    }
    return runs;
  }

  /// The paragraph's own target (null = none, [keepAsWritten] = don't).
  String? targetOf(int line) =>
      line >= 0 && line < _targets.length ? _targets[line] : null;

  void onDraftChanged(String draft) {
    if (error != null) error = null;
    final lines = draftParagraphs(draft);
    if (!listEquals(lines, _lines)) {
      _targets = carryTargets(_lines, _targets, lines);
      _lines = lines;
    }
    notifyListeners();
  }

  void setParagraphTarget(int line, String? code) {
    if (line < 0 || line >= _lines.length) return;
    _targets = [..._targets]..[line] = code;
    _prepared = null;
    notifyListeners();
  }

  /// "Use for the whole message".
  void useForWholeMessage(String? code) {
    _targets = List<String?>.filled(_lines.length, code);
    _prepared = null;
    notifyListeners();
  }

  /// Commands go out as typed.
  static bool _skipsTranslation(String draft) =>
      draft.trimLeft().startsWith("/");

  Future<bool?> _confirm(BuildContext context, String from, String to,
      List<TranslationModelSpec> missing) {
    if (!context.mounted) return Future.value(false);
    return confirmDownload(
        context, downloadTitle(from, to), downloadPrompt(from, to, missing));
  }

  Future<_Translated> _translate(
      BuildContext context, List<SendBlock> blocks) async {
    final translations = <int, String>{};
    final languages = <String>[];
    for (final block in blocks) {
      final to = block.to;
      if (to == null) continue;
      final result = await translateDraft(translation,
          draft: block.text,
          to: to,
          confirmDownload: (from, to, missing) =>
              _confirm(context, from, to, missing));
      switch (result) {
        case DraftTranslated(:final text):
          translations[block.first] = text;
          languages.add(to);
        case DraftUnchanged():
          break;
        case DraftBlocked(:final message):
          return _Translated(translations, languages,
              error: paragraphError(block, message));
      }
    }
    return _Translated(translations, languages);
  }

  /// "Paragraph 2 (German): Can't translate …".
  static String paragraphError(SendBlock block, String message) {
    final to = block.to;
    final which = "Paragraph ${block.number}";
    return to == null
        ? "$which: $message"
        : "$which (${translationLanguageName(to)}): $message";
  }

  Future<_Translated?> _translateDraft(
      BuildContext context, String draft) async {
    if (busy) return null;
    onDraftChanged(draft);
    final r = resolved;
    final blocks = sendBlocks(_lines, r);
    final p = _prepared;
    if (p != null && p.draft == draft && listEquals(p.resolved, r)) {
      return p.result;
    }
    if (blocks.every((b) => b.to == null)) {
      return _Translated(const {}, const []);
    }
    busy = true;
    error = null;
    notifyListeners();
    final result = await _translate(context, blocks);
    busy = false;
    if (result.error == null) {
      _prepared = (draft: draft, resolved: r, result: result);
    }
    notifyListeners();
    return result;
  }

  /// Send: what to send for [draft] (as typed, untrimmed), its tagged
  /// paragraphs translated; null when one couldn't be (the draft stays,
  /// with [error] naming it). Never sends untranslated without saying so.
  Future<String?> prepareSend(BuildContext context, String draft) async {
    _outgoing = null;
    if (_skipsTranslation(draft)) return draft;
    final result = await _translateDraft(context, draft);
    if (result == null) return null;
    final message = result.error;
    if (message != null) {
      error = "Not sent. $message";
      notifyListeners();
      return null;
    }
    if (result.translations.isEmpty) return draft;
    final text =
        assembleSend(sendBlocks(_lines, resolved), result.translations);
    _outgoing = (
      sent: text.trim(),
      original: draft.trim(),
      to: joinLanguages(result.languages)
    );
    return text;
  }

  /// Long-press send: the message as it will go out, block by block, or
  /// null when it can't be translated ([error] says why).
  Future<List<({String text, String? to})>?> previewSend(
      BuildContext context, String draft) async {
    if (_skipsTranslation(draft)) return [(text: draft.trim(), to: null)];
    final result = await _translateDraft(context, draft);
    if (result == null) return null;
    final message = result.error;
    if (message != null) {
      error = message;
      notifyListeners();
      return null;
    }
    final blocks = <({String text, String? to})>[];
    for (final b in sendBlocks(_lines, resolved)) {
      if (b.text.trim().isEmpty) continue;
      final text = result.translations[b.first];
      blocks.add((text: text ?? b.text, to: text == null ? null : b.to));
    }
    return blocks;
  }

  /// 文A: sets the target of the paragraph under the caret (asking for the
  /// language when there's no usual one, or the paragraph is already in
  /// it). On a paragraph that already has one, opens its menu; the result
  /// is the new draft when that translated it in place.
  Future<String?> tapChip(BuildContext context, String draft, int caret) async {
    onDraftChanged(draft);
    final line = paragraphAt(draft, caret);
    if (resolved[line] != null) return paragraphMenu(context, draft, line);
    final text = _lines[line].trim().isEmpty ? draft : _lines[line];
    final from = translation.draftLanguage(text);
    final to = tapTarget(usual: target, from: from) ??
        await pickLanguage(context, from);
    if (to == null) return null;
    setParagraphTarget(line, to);
    return null;
  }

  /// A paragraph's menu (its tag, or a long-press on 文A): languages,
  /// More languages…, Don't translate, Use for the whole message, Translate
  /// now. The result is the new draft after Translate now.
  Future<String?> paragraphMenu(
      BuildContext context, String draft, int line) async {
    onDraftChanged(draft);
    if (line < 0 || line >= _lines.length) return null;
    final current = resolved[line];
    final text = _lines[line].trim().isEmpty ? draft : _lines[line];
    final from = translation.draftLanguage(text);
    final reachable = translation.reachableFrom(from);
    final languages = paragraphMenuLanguages(
        roomLanguage: roomMode ? target : null,
        recent: [if (current != null) current, ...prefs.recentLanguages],
        reachable: reachable);
    final action = await showParagraphMenu(context,
        languages: languages,
        current: current,
        canTranslateNow: resolved.any((t) => t != null));
    if (action == null || !context.mounted) return null;
    switch (action) {
      case ParagraphMenuLanguage(:final code):
        await prefs.setTarget(roomId, code);
        setParagraphTarget(line, code);
      case ParagraphMenuMore():
        final code = await pickLanguage(context, from);
        if (code != null) setParagraphTarget(line, code);
      case ParagraphMenuKeep():
        setParagraphTarget(line, keepAsWritten);
      case ParagraphMenuWhole():
        useForWholeMessage(current ?? keepAsWritten);
      case ParagraphMenuTranslateNow():
        return translateNow(context, draft);
    }
    return null;
  }

  /// "Translate now": the paragraphs with a target translated in place
  /// (editable, with Undo); with none, the whole draft into the usual
  /// language (asking when there's none, or it's already in it). Null when
  /// nothing changed.
  Future<String?> translateNow(BuildContext context, String draft) async {
    onDraftChanged(draft);
    if (!resolved.any((t) => t != null)) {
      final to =
          tapTarget(usual: target, from: translation.draftLanguage(draft)) ??
              await pickLanguage(context, translation.draftLanguage(draft));
      if (to == null || !context.mounted) return null;
      useForWholeMessage(to);
    }
    var result = await _translateDraft(context, draft);
    if (result == null || !context.mounted) return null;
    if (result.error == null && result.translations.isEmpty) {
      // Everything is already in its language: ask where to, not "this is
      // already in English".
      final to = await pickLanguage(context, translation.draftLanguage(draft));
      if (to == null || !context.mounted) return null;
      useForWholeMessage(to);
      result = await _translateDraft(context, draft);
      if (result == null || result.translations.isEmpty) return null;
    }
    final message = result.error;
    if (message != null) {
      error = message;
      notifyListeners();
      return null;
    }
    final blocks = sendBlocks(_lines, resolved);
    final text = assembleSend(blocks, result.translations);
    translated = (
      original: draft,
      to: joinLanguages(result.languages),
      targets: [..._targets]
    );
    // What was translated is now in its language: keep it as it is.
    final lines = draftParagraphs(text);
    final targets = List<String?>.filled(lines.length, null);
    if (lines.length == _lines.length) {
      for (final b in blocks) {
        if (!result.translations.containsKey(b.first)) continue;
        final count = "\n".allMatches(b.text).length + 1;
        for (var i = b.first; i < b.first + count; i++) {
          targets[i] = keepAsWritten;
        }
      }
      for (var i = 0; i < lines.length; i++) {
        targets[i] ??= _targets[i];
      }
    } else {
      targets.fillRange(0, targets.length, keepAsWritten);
    }
    _lines = lines;
    _targets = targets;
    _prepared = null;
    notifyListeners();
    return text;
  }

  /// "Translate into": asks for a language and remembers it as this room's
  /// pick (and a recent one).
  Future<String?> pickLanguage(BuildContext context, String from) async {
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
        itemBuilder: (context, code, onTap) => _LanguageRow(
            name: translationLanguageName(code),
            checked: code == current,
            onTap: onTap));
    if (picked == null) return null;
    await prefs.setTarget(roomId, picked);
    notifyListeners();
    return picked;
  }

  /// Undo: what you wrote before "Translate now".
  String? undo() {
    final t = translated;
    translated = null;
    if (t != null) {
      _lines = draftParagraphs(t.original);
      _targets = t.targets.length == _lines.length
          ? t.targets
          : List<String?>.filled(_lines.length, null);
    }
    notifyListeners();
    return t?.original;
  }

  /// ⊗ on the line: keep the translation, hide the line.
  void hideLine() {
    translated = null;
    notifyListeners();
  }

  /// After [sentText] went out: remember what you wrote when it was
  /// translated, and start the next message without targets.
  void onSent(String sentText) {
    final out = _outgoing;
    _outgoing = null;
    if (out != null && out.sent == sentText.trim()) {
      sent.remember(roomId,
          sent: out.sent, original: out.original, language: out.to);
    }
    _lines = const [""];
    _targets = const [null];
    _prepared = null;
    translated = null;
    error = null;
    notifyListeners();
  }

  // "This room is mostly in Spanish. Translate it?"

  /// Rooms whose suggestion was answered (either way), newest last.
  static final JsonPreference _suggested =
      JsonPreference("vommet_room_translation_suggested", empty: "[]");

  static const maxSuggested = 500;

  bool _suggestionAnswered() {
    final v = _suggested.read();
    return v is List && v.contains(roomId);
  }

  /// The language to suggest translating this room from, once per room:
  /// when it's mostly in a language other than yours and that translates
  /// on this device. Null otherwise.
  String? get suggestedLanguage {
    if (!translation.supported ||
        roomMode ||
        !ComposerTranslationPrefs.suggestPreference.value ||
        _suggestionAnswered()) {
      return null;
    }
    final at = _detectedAt;
    if (_detected == null &&
        at != null &&
        DateTime.now().difference(at) > const Duration(seconds: 10)) {
      refreshDetected();
    }
    final room = detectedTarget;
    // In a language you read (yours or one of "Languages I read"): no offer.
    if (room == null || rooms.readsRoom(roomId, () => room)) return null;
    if (translation.route(room, translation.targetLanguage) == null) {
      return null;
    }
    return room;
  }

  Future<void> _answerSuggestion() async {
    final v = _suggested.read();
    final list = [
      ...(v is List ? v.whereType<String>() : const <String>[])
          .where((id) => id != roomId),
      roomId
    ];
    await _suggested.write(list
        .skip(list.length > maxSuggested ? list.length - maxSuggested : 0)
        .toList());
  }

  /// [Translate]: turns "Translate this room" on.
  Future<void> acceptSuggestion() async {
    await _answerSuggestion();
    await rooms.setOn(roomId, true);
    notifyListeners();
  }

  /// [✕] › "Not in this room": not asked again in this room.
  Future<void> dismissSuggestion() async {
    await _answerSuggestion();
    notifyListeners();
  }

  /// [✕] › "Don't suggest in any room" (Vommet issue 834): the banner is off
  /// everywhere until turned back on in Settings.
  Future<void> stopSuggesting() async {
    await ComposerTranslationPrefs.suggestPreference.set(false);
    notifyListeners();
  }
}

class _Translated {
  _Translated(this.translations, this.languages, {this.error});

  /// By [SendBlock.first].
  final Map<int, String> translations;
  final List<String> languages;
  final String? error;
}

/// What was picked in a paragraph's menu.
sealed class ParagraphMenuAction {
  const ParagraphMenuAction();
}

class ParagraphMenuLanguage extends ParagraphMenuAction {
  const ParagraphMenuLanguage(this.code);
  final String code;
}

class ParagraphMenuMore extends ParagraphMenuAction {
  const ParagraphMenuMore();
}

class ParagraphMenuKeep extends ParagraphMenuAction {
  const ParagraphMenuKeep();
}

class ParagraphMenuWhole extends ParagraphMenuAction {
  const ParagraphMenuWhole();
}

class ParagraphMenuTranslateNow extends ParagraphMenuAction {
  const ParagraphMenuTranslateNow();
}

/// The menu of a paragraph's "→ Spanish" tag (or 文A long-pressed).
Future<ParagraphMenuAction?> showParagraphMenu(BuildContext context,
    {required List<String> languages,
    required String? current,
    required bool canTranslateNow}) {
  final items = <ParagraphMenuAction>[
    for (final c in languages) ParagraphMenuLanguage(c),
    const ParagraphMenuMore(),
    const ParagraphMenuKeep(),
    if (current != null) const ParagraphMenuWhole(),
    if (canTranslateNow) const ParagraphMenuTranslateNow(),
  ];
  return AdaptiveDialog.pickOne<ParagraphMenuAction>(context,
      title: "Send this paragraph in",
      items: items,
      itemBuilder: (context, item, onTap) => switch (item) {
            ParagraphMenuLanguage(:final code) => _LanguageRow(
                name: translationLanguageName(code),
                checked: code == current,
                onTap: onTap),
            ParagraphMenuMore() => _LanguageRow(
                name: "More languages…", icon: Icons.language, onTap: onTap),
            ParagraphMenuKeep() => _LanguageRow(
                name: "Don't translate",
                icon: Icons.block,
                checked: current == null,
                onTap: onTap),
            ParagraphMenuWhole() => _LanguageRow(
                name: "Use for the whole message",
                icon: Icons.select_all,
                onTap: onTap),
            ParagraphMenuTranslateNow() => _LanguageRow(
                name: "Translate now", icon: Icons.translate, onTap: onTap),
          });
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow(
      {required this.name,
      required this.onTap,
      this.checked = false,
      this.icon});

  final String name;
  final bool checked;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: checked,
      child: SizedBox(
        height: 44,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: checked
                    ? const Icon(Icons.check, size: 18)
                    : icon == null
                        ? null
                        : Icon(icon, size: 18),
              ),
              Expanded(child: tiamat.Text(name)),
            ],
          ),
        ),
      ),
    );
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
                  "Translated to ${languageNames(to)} on this device"),
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

/// Above the composer, once per room: "This room is mostly in Spanish.
/// Translate it?" [Translate] [✕]. ✕ asks: "Not in this room" or "Don't
/// suggest in any room" (Vommet issue 834).
class ComposerTranslationSuggestion extends StatelessWidget {
  const ComposerTranslationSuggestion({
    required this.language,
    required this.onTranslate,
    required this.onDismiss,
    this.onStopSuggesting,
    super.key,
  });

  final String language;
  final VoidCallback onTranslate;

  /// Not in this room.
  final VoidCallback onDismiss;

  /// In no room; defaults to turning "Suggest translating rooms" off, then
  /// [onDismiss].
  final VoidCallback? onStopSuggesting;

  Future<void> stopSuggesting() async {
    if (onStopSuggesting != null) return onStopSuggesting!();
    await ComposerTranslationPrefs.suggestPreference.set(false);
    onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 4),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
          child: Row(
            children: [
              Icon(Icons.translate, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    "This room is mostly in ${translationLanguageName(language)}. Translate it?",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              TextButton(
                key: const ValueKey("composer-translate-suggestion"),
                onPressed: onTranslate,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text("Translate"),
              ),
              PopupMenuButton<bool>(
                key: const ValueKey("composer-translate-suggestion-close"),
                tooltip: "Don't suggest again",
                iconSize: 18,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.close),
                onSelected: (everywhere) =>
                    everywhere ? stopSuggesting() : onDismiss(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                      key: ValueKey("composer-translate-suggestion-room"),
                      value: false,
                      child: Text("Not in this room")),
                  PopupMenuItem(
                      key: ValueKey("composer-translate-suggestion-never"),
                      value: true,
                      child: Text("Don't suggest in any room")),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The paragraph tint's colors: a faint wash behind the text and a thin bar
/// at the left, in the theme's accent.
Color paragraphTintColor(ColorScheme scheme) => scheme.primary.withAlpha(26);
Color paragraphBarColor(ColorScheme scheme) => scheme.primary.withAlpha(150);

/// The "→ Spanish" label of a tag.
String paragraphTagLabel(String code) => "→ ${translationLanguageName(code)}";

/// How wide the widest tag for [codes] is, so the text can leave room for
/// it at the right of the message box.
double paragraphTagsWidth(BuildContext context, Iterable<String> codes) {
  var widest = 0.0;
  for (final code in codes.toSet()) {
    final painter = TextPainter(
      text: TextSpan(
          text: paragraphTagLabel(code),
          style: Theme.of(context).textTheme.labelSmall),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  return widest == 0 ? 0 : widest + 14;
}

/// Over the message box: a thin accent bar left of each run of paragraphs
/// that will be translated, and a "→ Spanish" tag at its first line.
/// Tapping a tag opens that paragraph's menu.
class ComposerParagraphMarks extends StatefulWidget {
  const ComposerParagraphMarks({
    required this.text,
    required this.runs,
    required this.editable,
    required this.scrollController,
    required this.onTapTag,
    super.key,
  });

  final String text;
  final List<({int first, int last, String to})> runs;
  final EditableTextState? Function() editable;
  final ScrollController scrollController;
  final void Function(int line) onTapTag;

  @override
  State<ComposerParagraphMarks> createState() => _ComposerParagraphMarksState();
}

class _ComposerParagraphMarksState extends State<ComposerParagraphMarks> {
  List<({double top, double bottom, double tagTop, int line, String to})>
      marks = const [];

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ComposerParagraphMarks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_schedule);
      widget.scrollController.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_schedule);
    super.dispose();
  }

  bool _scheduled = false;

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    final box = context.findRenderObject();
    final editable = widget.editable()?.renderEditable;
    final next =
        <({double top, double bottom, double tagTop, int line, String to})>[];
    if (box is RenderBox &&
        box.hasSize &&
        editable != null &&
        editable.attached &&
        editable.hasSize) {
      final ranges = paragraphRanges(widget.text);
      final length =
          editable.text?.toPlainText(includeSemanticsLabels: false).length ?? 0;
      final origin = box.globalToLocal(editable.localToGlobal(Offset.zero));
      final visible = editable.size.height;
      for (final run in widget.runs) {
        if (run.last >= ranges.length) continue;
        final start = ranges[run.first].start.clamp(0, length);
        final end = ranges[run.last].end.clamp(0, length);
        if (end <= start) continue;
        final boxes = editable.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end));
        if (boxes.isEmpty) continue;
        var top = double.infinity, bottom = -double.infinity;
        for (final b in boxes) {
          if (b.top < top) top = b.top;
          if (b.bottom > bottom) bottom = b.bottom;
        }
        final tagTop = top;
        top = top.clamp(0, visible);
        bottom = bottom.clamp(0, visible);
        if (bottom - top < 2) continue;
        next.add((
          top: origin.dy + top,
          bottom: origin.dy + bottom,
          tagTop: tagTop >= 0 && tagTop < visible - 4 ? origin.dy + tagTop : -1,
          line: run.first,
          to: run.to,
        ));
      }
    }
    if (!_same(next)) setState(() => marks = next);
  }

  bool _same(
      List<({double top, double bottom, double tagTop, int line, String to})>
          next) {
    if (next.length != marks.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i] != marks[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    var number = 0;
    final numbers = <int, int>{};
    final lines = draftParagraphs(widget.text);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().isNotEmpty) number++;
      numbers[i] = number;
    }
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final m in marks)
          Positioned(
            left: 2,
            top: m.top,
            height: m.bottom - m.top,
            width: 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: paragraphBarColor(scheme),
                    borderRadius: BorderRadius.circular(1)),
              ),
            ),
          ),
        for (final m in marks)
          if (m.tagTop >= 0)
            Positioned(
              right: 2,
              top: m.tagTop,
              child: Semantics(
                button: true,
                label:
                    "Paragraph ${numbers[m.line] ?? 1} will be sent in ${translationLanguageName(m.to)}. Change",
                excludeSemantics: true,
                child: Material(
                  key: ValueKey("composer-paragraph-tag-${m.line}"),
                  color: scheme.primary.withAlpha(30),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => widget.onTapTag(m.line),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      child: Text(paragraphTagLabel(m.to), style: style),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Long-press send: "Will send", block by block with its language, and
/// Edit / Send. True = send.
Future<bool?> showWillSendSheet(
    BuildContext context, List<({String text, String? to})> blocks) {
  return AdaptiveDialog.show<bool>(context,
      title: "Will send", builder: (context) => _WillSend(blocks: blocks));
}

class _WillSend extends StatelessWidget {
  const _WillSend({required this.blocks});

  final List<({String text, String? to})> blocks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: b.to == null
                            ? scheme.outlineVariant
                            : paragraphBarColor(scheme),
                        width: 2)),
                color: b.to == null ? null : paragraphTintColor(scheme),
              ),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      b.to == null
                          ? "As written"
                          : "Translated to ${translationLanguageName(b.to!)}",
                      style: label),
                  const SizedBox(height: 2),
                  SelectableText(b.text,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Edit"),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey("will-send-send"),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Send"),
            ),
          ],
        ),
      ],
    );
  }
}
