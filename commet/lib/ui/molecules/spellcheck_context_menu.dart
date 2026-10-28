// Vommet: spellcheck rows on top of the message box's right-click menu:
// suggestions for the misspelled word under the pointer, "Add to dictionary"
// and "Ignore in this message"; or, before any dictionary is downloaded, a
// one-click offer for the device's language.
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/rich_text_field.dart';
import 'package:commet/utils/spellcheck/spellcheck.dart';
import 'package:commet/utils/spellcheck/spellcheck_text.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SpellcheckContextMenu {
  static String get labelSpellcheckNoSuggestions => Intl.message(
      "No suggestions",
      desc:
          "Greyed-out row in the message box's right-click menu when the spellchecker has no replacement for a misspelled word",
      name: "labelSpellcheckNoSuggestions");

  static String labelSpellcheckAddToDictionary(String word) => Intl.message(
      "Add “$word” to dictionary",
      desc:
          "Right-click menu row that adds a misspelled word to the user's personal spellcheck dictionary",
      args: [word],
      name: "labelSpellcheckAddToDictionary");

  static String get labelSpellcheckIgnoreInMessage => Intl.message(
      "Ignore in this message",
      desc:
          "Right-click menu row that stops underlining a misspelled word until the message is sent",
      name: "labelSpellcheckIgnoreInMessage");

  static String labelSpellcheckTurnOn(String language) => Intl.message(
      "Check spelling in $language",
      desc:
          "Right-click menu row that downloads a spellcheck dictionary for the device's language; the language name is in that language",
      args: [language],
      name: "labelSpellcheckTurnOn");

  static (String, int, Future<List<String>>)? _suggestions;

  static Future<List<String>> _suggest(String word) {
    final spellcheck = Spellcheck.instance;
    final cached = _suggestions;
    if (cached != null &&
        cached.$1 == word &&
        cached.$2 == spellcheck.generation) {
      return cached.$3;
    }
    final future = spellcheck.suggest(word);
    _suggestions = (word, spellcheck.generation, future);
    return future;
  }

  /// [toolbar] with spellcheck rows on top, or [toolbar] itself when there is
  /// nothing to add.
  static Widget wrap(
      EditableTextState state,
      RichTextEditingController controller,
      AdaptiveTextSelectionToolbar toolbar) {
    final spellcheck = Spellcheck.instance;
    final edit = toolbar.buttonItems;
    if (!Spellcheck.supported || !spellcheck.enabled.value || edit == null) {
      return toolbar;
    }

    if (spellcheck.ready &&
        spellcheck.installed.isEmpty &&
        spellcheck.downloads.isEmpty) {
      final offer = spellcheck.offer;
      if (offer == null) return toolbar;
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: toolbar.anchors,
        buttonItems: [
          ContextMenuButtonItem(
              label: labelSpellcheckTurnOn(offer.name),
              onPressed: () {
                state.hideToolbar();
                spellcheck.download(offer).catchError((Object e, StackTrace s) {
                  Log.onError(e, s,
                      content: "Spellcheck: download of ${offer.code} failed");
                });
              }),
          ...edit,
        ],
      );
    }

    final range = _rangeAtPointer(state, controller);
    if (range == null) return toolbar;
    final word = range.textInside(controller.text);

    void replace(String replacement) {
      final value = controller.value;
      state.userUpdateTextEditingValue(
          TextEditingValue(
              text:
                  value.text.replaceRange(range.start, range.end, replacement),
              selection: TextSelection.collapsed(
                  offset: range.start + replacement.length)),
          SelectionChangedCause.toolbar);
      state.hideToolbar();
    }

    return FutureBuilder<List<String>>(
        future: _suggest(word),
        builder: (context, snapshot) {
          final suggestions = snapshot.data;
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: toolbar.anchors,
            buttonItems: [
              if (suggestions == null)
                const ContextMenuButtonItem(label: "…", onPressed: null)
              else if (suggestions.isEmpty)
                ContextMenuButtonItem(
                    label: labelSpellcheckNoSuggestions, onPressed: null)
              else
                for (final s in suggestions)
                  ContextMenuButtonItem(label: s, onPressed: () => replace(s)),
              ContextMenuButtonItem(
                  label: labelSpellcheckAddToDictionary(word),
                  onPressed: () {
                    state.hideToolbar();
                    spellcheck.addWord(word);
                  }),
              ContextMenuButtonItem(
                  label: labelSpellcheckIgnoreInMessage,
                  onPressed: () {
                    state.hideToolbar();
                    controller.spellcheckIgnored.add(word);
                    spellcheck.refresh();
                  }),
              ...edit,
            ],
          );
        });
  }

  /// The underlined word that was right-clicked (or holds the caret).
  static TextRange? _rangeAtPointer(
      EditableTextState state, RichTextEditingController controller) {
    final spellcheck = Spellcheck.instance;
    if (!spellcheck.active) return null;
    final render = state.renderEditable;
    final tap = render.lastSecondaryTapDownPosition;
    final offset = tap != null
        ? render.getPositionForPoint(tap).offset
        : controller.selection.baseOffset;
    final ranges = SpellcheckText.withoutWordBeingTyped(
        spellcheck.misspelled(controller.text,
            ignored: controller.spellcheckIgnored),
        controller.selection);
    for (final r in ranges) {
      if (r.start <= offset && offset <= r.end) return r;
    }
    return null;
  }
}
