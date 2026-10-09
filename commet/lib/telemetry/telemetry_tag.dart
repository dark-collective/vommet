// Vommet: the optional diagnostics name tag. The one piece of free text in
// diagnostics, so it is kept tight: typed by the user only (never filled in
// from their account or display name), at most 32 letters, digits, spaces,
// '-' and '_', no leading or trailing space. The collector enforces the same
// pattern (schema envelope "tag").

class TelemetryTag {
  static const maxLength = 32;

  /// Characters allowed while typing.
  static final allowedChars = RegExp(r"[A-Za-z0-9 _-]");

  static final _pattern =
      RegExp(r"^[A-Za-z0-9_-]([A-Za-z0-9 _-]{0,30}[A-Za-z0-9_-])?$");

  /// The tag to store and send for what the user typed: trimmed, or null when
  /// it is empty or not allowed (null = no tag).
  static String? normalize(String? raw) {
    final tag = raw?.trim() ?? "";
    if (tag.isEmpty) return null;
    return _pattern.hasMatch(tag) ? tag : null;
  }

  static bool isValid(String raw) =>
      raw.trim().isEmpty || normalize(raw) != null;
}
