// Vommet: redacted mode (Vommet issue 400). Pure logic, no widgets: what a
// name, avatar, message text or room name turns into while redaction is on.
// Widgets ask `RedactionScope.of(context)` (ui/atoms/redaction_scope.dart)
// for the policy that applies to them instead of reading preferences.

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

/// What happens to display names (and, with [RedactionSettings.roomNames],
/// room names).
enum NameRedaction { keep, hide, scramble }

/// What happens to message text.
enum TextRedaction { keep, hide, scramble }

/// The independent switches redacted mode is made of. The six levels from
/// the issue are [RedactionPreset]s that set these.
class RedactionSettings {
  const RedactionSettings({
    this.names = NameRedaction.keep,
    this.avatars = false,
    this.text = TextRedaction.keep,
    this.distinguishable = true,
    this.roomNames = false,
    this.images = false,
  });

  /// Nothing is redacted.
  static const off = RedactionSettings();

  final NameRedaction names;

  /// Hide profile pictures, room and space icons.
  final bool avatars;

  final TextRedaction text;

  /// Keep people (and rooms) apart: each gets a stable colour and tag drawn
  /// from a salted hash of their ID, so the ID itself can't be read back.
  final bool distinguishable;

  /// Redact room and space names too. Direct messages are named after a
  /// person, so they follow [names] either way.
  final bool roomNames;

  /// Blur pictures and videos in chats.
  final bool images;

  bool get isOff =>
      names == NameRedaction.keep &&
      !avatars &&
      text == TextRedaction.keep &&
      !roomNames &&
      !images;

  RedactionSettings copyWith({
    NameRedaction? names,
    bool? avatars,
    TextRedaction? text,
    bool? distinguishable,
    bool? roomNames,
    bool? images,
  }) =>
      RedactionSettings(
        names: names ?? this.names,
        avatars: avatars ?? this.avatars,
        text: text ?? this.text,
        distinguishable: distinguishable ?? this.distinguishable,
        roomNames: roomNames ?? this.roomNames,
        images: images ?? this.images,
      );

  @override
  bool operator ==(Object other) =>
      other is RedactionSettings &&
      other.names == names &&
      other.avatars == avatars &&
      other.text == text &&
      other.distinguishable == distinguishable &&
      other.roomNames == roomNames &&
      other.images == images;

  @override
  int get hashCode =>
      Object.hash(names, avatars, text, distinguishable, roomNames, images);
}

/// The six levels from Vommet issue 400. Each sets every switch except
/// [RedactionSettings.roomNames], which stays the user's own choice.
/// Pictures are blurred whenever the level hides or replaces message text.
enum RedactionPreset {
  hideEverything(NameRedaction.hide, TextRedaction.hide, false),
  hideEverythingDistinguishable(NameRedaction.hide, TextRedaction.hide, true),
  hideIdentity(NameRedaction.hide, TextRedaction.keep, false),
  hideIdentityDistinguishable(NameRedaction.hide, TextRedaction.keep, true),
  loremNames(NameRedaction.scramble, TextRedaction.keep, true),
  loremEverything(NameRedaction.scramble, TextRedaction.scramble, true);

  const RedactionPreset(this.names, this.text, this.distinguishable);

  final NameRedaction names;
  final TextRedaction text;
  final bool distinguishable;

  /// The issue's numbering, 1 to 6.
  int get level => index + 1;

  RedactionSettings applyTo(RedactionSettings current) => RedactionSettings(
        names: names,
        avatars: true,
        text: text,
        distinguishable: distinguishable,
        roomNames: current.roomNames,
        images: text != TextRedaction.keep,
      );

  /// The preset [settings] were made from, or null once a switch was
  /// changed by hand.
  static RedactionPreset? matching(RedactionSettings settings) {
    for (final preset in values) {
      if (preset.applyTo(settings) == settings) return preset;
    }
    return null;
  }
}

/// [RedactionSettings] plus the salt that makes the per-person colours and
/// tags. Every method returns its input unchanged for what isn't redacted,
/// so callers don't need to check whether redaction is on.
class RedactionPolicy {
  RedactionPolicy(this.settings, {List<int>? salt})
      : _hmac = Hmac(sha256, salt ?? sessionSalt);

  static final RedactionPolicy off = RedactionPolicy(RedactionSettings.off);

  /// New every launch, so the colours and tags in one session's screenshots
  /// can't be matched against another's, nor computed from a user ID.
  static final List<int> sessionSalt = _randomSalt();

  /// Drawn for people and rooms that can't be told apart.
  static const Color neutralColor = Color(0xFF8A8A8A);

  static const _tagAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  static const _lorem = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", //
    "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore",
    "et", "dolore", "magna", "aliqua", "enim", "ad", "minim", "veniam",
    "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi",
    "aliquip", "ex", "ea", "commodo", "consequat", "duis", "aute", "irure",
    "in", "reprehenderit", "voluptate", "velit", "esse", "cillum", "fugiat",
    "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat", "non",
    "proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit",
    "anim", "id", "est", "laborum",
  ];

  final RedactionSettings settings;
  final Hmac _hmac;

  bool get isActive => !settings.isOff;

  bool get hidesAvatars => settings.avatars;

  bool get blursImages => settings.images;

  /// Text from [text] should be drawn as solid bars ([TextRedaction.hide]).
  bool get drawsTextAsBars => settings.text == TextRedaction.hide;

  bool get redactsText => settings.text != TextRedaction.keep;

  bool get redactsNames => settings.names != NameRedaction.keep;

  /// [userId]'s display name.
  String name(String displayName, String userId) =>
      _redactName(settings.names, displayName, userId, "User");

  /// The colour [userId]'s name is drawn in.
  Color nameColor(Color original, String userId) =>
      redactsNames ? identityColor(userId) : original;

  /// A room or space name. For a direct message pass [dmPartnerId]: its name
  /// is the other person's, so it follows the name switch.
  String roomName(String name, String roomId, {String? dmPartnerId}) {
    if (dmPartnerId != null) return this.name(name, dmPartnerId);
    if (!settings.roomNames) return name;
    final mode = settings.names == NameRedaction.scramble
        ? NameRedaction.scramble
        : NameRedaction.hide;
    return _redactName(mode, name, roomId, "Room");
  }

  /// The placeholder colour of a hidden avatar.
  Color identityColor(String id) {
    if (!settings.distinguishable) return neutralColor;
    final hue = _hash("colour", id) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.6).toColor();
  }

  /// The letter in a hidden avatar's placeholder; empty when people can't
  /// be told apart.
  String avatarLetter(String id) =>
      settings.distinguishable ? tag(id).substring(0, 1) : "";

  /// A short stable tag for [id], e.g. "K7".
  String tag(String id) {
    final h = _hash("tag", id);
    return _tagAlphabet[h % _tagAlphabet.length] +
        _tagAlphabet[(h ~/ _tagAlphabet.length) % _tagAlphabet.length];
  }

  /// Message text (bodies, reply previews, room previews).
  String text(String text) {
    switch (settings.text) {
      case TextRedaction.keep:
        return text;
      case TextRedaction.hide:
        // Only the word lengths survive, and those are capped.
        return text.replaceAllMapped(RegExp(r"\S+"),
            (m) => "\u2022" * min(m.group(0)!.runes.length, 12));
      case TextRedaction.scramble:
        var i = 0;
        return text.replaceAllMapped(RegExp(r"\S+"), (m) {
          final word = _lorem[_hash("text${i++}", text) % _lorem.length];
          final original = m.group(0)!;
          return original[0] != original[0].toLowerCase()
              ? _capitalise(word)
              : word;
        });
    }
  }

  String _redactName(
      NameRedaction mode, String original, String id, String noun) {
    switch (mode) {
      case NameRedaction.keep:
        return original;
      case NameRedaction.hide:
        return settings.distinguishable ? "$noun ${tag(id)}" : noun;
      case NameRedaction.scramble:
        final key = settings.distinguishable ? id : "";
        final first = _lorem[_hash("name0", key) % _lorem.length];
        final second = _lorem[_hash("name1", key) % _lorem.length];
        return "${_capitalise(first)} ${_capitalise(second)}";
    }
  }

  int _hash(String purpose, String key) {
    final digest = _hmac.convert(utf8.encode("$purpose\u0000$key")).bytes;
    return (digest[0] << 16) | (digest[1] << 8) | digest[2];
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static List<int> _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }
}
