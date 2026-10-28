// Vommet: a DM's room topic as a line under the contact's name in the room
// lists (Vommet issue 564). Some bridges (Steam, Signal, iMessage) put the
// other person's "rich presence", e.g. the game they're playing, there.

/// The topic as one line, or null when there's nothing to show.
String? dmTopicLine(String? topic) {
  if (topic == null) return null;
  final line = topic.replaceAll(RegExp(r"\s+"), " ").trim();
  return line.isEmpty ? null : line;
}
