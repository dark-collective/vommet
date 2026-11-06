// Vommet (New Home cards, round 4): the Text card's content. Pure Dart, so it
// can be unit tested: its buttons, the limits, splitting the body into text
// and images for drawing, the toolbar's edits, and Vommet's own Text cards
// shipped in the app (assets/data/home_text_cards.json). Drawn and edited by
// new_home_text.dart. A Text card is stored in the Home layout like any
// card ("options": {"name", "body", "buttons"}, new_home_layout.dart); one
// of Vommet's has "preset": <id> instead and takes its content from the
// app.

import 'dart:convert';

/// The most a Text card's body holds (it's saved in the Home layout, which
/// is account data).
const int maxTextBody = 20000;

/// The most buttons a Text card has.
const int maxTextButtons = 3;

/// About how many lines a Text card shows before "Show more".
const int textCollapsedLines = 12;

/// One of a Text card's buttons: a label and what it opens.
class TextButtonTarget {
  const TextButtonTarget(this.label,
      {required this.kind, required this.target});

  final String label;

  /// [link], [room] or [screen].
  final String kind;

  /// The URL, the room's id or address, or the screen's id ([screens]).
  final String target;

  static const String link = "link";
  static const String room = "room";
  static const String screen = "screen";
  static const List<String> kinds = [link, room, screen];

  /// The Vommet screens a button can open, with their names.
  static const Map<String, String> screens = {
    "settings": "Settings",
    "whats_new": "What's new",
    "guides": "Guides",
    "getting_started": "Getting started",
  };

  bool get valid =>
      label.trim().isNotEmpty &&
      target.trim().isNotEmpty &&
      switch (kind) {
        link => _isWebLink(target.trim()),
        room => target.trim().startsWith("!") || target.trim().startsWith("#"),
        screen => screens.containsKey(target),
        _ => false,
      };

  static bool _isWebLink(String s) {
    final uri = Uri.tryParse(s);
    return uri != null &&
        (uri.scheme == "https" || uri.scheme == "http") &&
        uri.host.isNotEmpty;
  }

  TextButtonTarget copyWith({String? label, String? kind, String? target}) =>
      TextButtonTarget(label ?? this.label,
          kind: kind ?? this.kind, target: target ?? this.target);

  static TextButtonTarget? fromJson(Object? json) {
    if (json is! Map) return null;
    final label = json["label"];
    final kind = json["kind"];
    final target = json["target"];
    if (label is! String || kind is! String || target is! String) return null;
    final button = TextButtonTarget(label, kind: kind, target: target);
    return button.valid ? button : null;
  }

  Map<String, dynamic> toJson() =>
      {"label": label, "kind": kind, "target": target};

  @override
  bool operator ==(Object other) =>
      other is TextButtonTarget &&
      other.label == label &&
      other.kind == kind &&
      other.target == target;

  @override
  int get hashCode => Object.hash(label, kind, target);
}

/// A Text card's buttons from "buttons": the valid ones, at most
/// [maxTextButtons].
List<TextButtonTarget> readTextButtons(Object? json) => json is List
    ? [
        for (final b in json)
          if (TextButtonTarget.fromJson(b) case final button?) button
      ].take(maxTextButtons).toList()
    : const [];

/// A Text card's body as read: at most [maxTextBody] characters.
String? readTextBody(Object? body) {
  if (body is! String || body.isEmpty) return null;
  return body.length > maxTextBody ? body.substring(0, maxTextBody) : body;
}

/// A piece of a Text card's body: Markdown text, or an image on a line of
/// its own (`![alt](mxc://…)`).
class TextBlock {
  const TextBlock.text(this.text)
      : image = null,
        alt = null;
  const TextBlock.image(String this.image, {this.alt}) : text = "";

  final String text;

  /// The image's `mxc://` URL.
  final String? image;
  final String? alt;

  bool get isImage => image != null;

  @override
  bool operator ==(Object other) =>
      other is TextBlock &&
      other.text == text &&
      other.image == image &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(text, image, alt);

  @override
  String toString() => isImage ? "image($image)" : "text($text)";
}

final RegExp _imageLine = RegExp(r"^\s*!\[([^\]]*)\]\((mxc://[^)\s]+)\)\s*$");

/// [body] as text blocks and images, in order. Only images on a line of
/// their own whose URL is `mxc://` (uploaded to a homeserver) are images;
/// anything else stays text.
List<TextBlock> textBlocks(String body) {
  final blocks = <TextBlock>[];
  final text = <String>[];
  void flush() {
    final joined = text.join("\n").trim();
    if (joined.isNotEmpty) blocks.add(TextBlock.text(joined));
    text.clear();
  }

  for (final line in const LineSplitter().convert(body)) {
    final m = _imageLine.firstMatch(line);
    if (m == null) {
      text.add(line);
      continue;
    }
    flush();
    final alt = m.group(1)!.trim();
    blocks.add(TextBlock.image(m.group(2)!, alt: alt.isEmpty ? null : alt));
  }
  flush();
  return blocks;
}

/// Whether [body] is long enough to collapse: more than about
/// [textCollapsedLines] lines, counting an image as several.
bool textCollapses(String body) {
  var lines = 0;
  for (final block in textBlocks(body)) {
    lines += block.isImage ? 8 : '\n'.allMatches(block.text).length + 1;
  }
  return lines > textCollapsedLines;
}

/// A toolbar edit's result: the new text and the selection after it.
typedef TextEdit = ({String text, int start, int end});

/// Bold or italic: wraps the selection ([start]..[end]) in [mark], or puts
/// an empty pair at the cursor with the cursor between.
TextEdit wrapSelection(String text, int start, int end, String mark) {
  final s = start.clamp(0, text.length), e = end.clamp(s, text.length);
  final inner = text.substring(s, e);
  final next = text.replaceRange(s, e, "$mark$inner$mark");
  return (
    text: next,
    start: s + mark.length,
    end: s + mark.length + inner.length
  );
}

/// Heading or list: puts [prefix] before each line the selection touches
/// ("1. ", "2. "… when [numbered]).
TextEdit prefixLines(String text, int start, int end, String prefix,
    {bool numbered = false}) {
  final s = start.clamp(0, text.length), e = end.clamp(s, text.length);
  final lineStart = s == 0 ? 0 : text.lastIndexOf("\n", s - 1) + 1;
  final nl = text.indexOf("\n", e);
  final lineEnd = nl < 0 ? text.length : nl;
  final lines = text.substring(lineStart, lineEnd).split("\n");
  final changed = [
    for (var i = 0; i < lines.length; i++)
      "${numbered ? "${i + 1}. " : prefix}${lines[i]}"
  ].join("\n");
  final next = text.replaceRange(lineStart, lineEnd, changed);
  return (text: next, start: lineStart, end: lineStart + changed.length);
}

/// Inserts [snippet] at the selection, on a line of its own when [ownLine]
/// (images), and puts the cursor after it.
TextEdit insertSnippet(String text, int start, int end, String snippet,
    {bool ownLine = false}) {
  final s = start.clamp(0, text.length), e = end.clamp(s, text.length);
  var piece = snippet;
  if (ownLine) {
    if (s > 0 && text[s - 1] != "\n") piece = "\n$piece";
    if (e < text.length && text[e] != "\n") piece = "$piece\n";
  }
  final next = text.replaceRange(s, e, piece);
  return (text: next, start: s + piece.length, end: s + piece.length);
}

/// One of Vommet's own Text cards, shipped in the app.
class TextPreset {
  const TextPreset(this.id,
      {required this.title, required this.body, this.buttons = const []});
  final String id;
  final String title;
  final String body;
  final List<TextButtonTarget> buttons;
}

/// assets/data/home_text_cards.json: {"cards": {"<id>": {"title", "body",
/// "buttons"}}}. Broken entries are left out.
Map<String, TextPreset> parseTextPresets(String json) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return const {};
  }
  final cards = decoded is Map ? decoded["cards"] : null;
  if (cards is! Map) return const {};
  return {
    for (final e in cards.entries)
      if (e.key is String &&
          e.value is Map &&
          (e.value as Map)["title"] is String &&
          readTextBody((e.value as Map)["body"]) != null)
        e.key as String: TextPreset(e.key as String,
            title: (e.value as Map)["title"] as String,
            body: readTextBody((e.value as Map)["body"])!,
            buttons: readTextButtons((e.value as Map)["buttons"])),
  };
}
