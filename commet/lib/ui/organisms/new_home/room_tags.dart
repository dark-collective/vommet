// Vommet: your own room tags (Matrix `m.tag` room account data). Pure Dart,
// so it can be unit tested. Tags you make are `u.<name>`, as the spec says
// and as Nheko writes them, so other apps show the same groups. Favourite
// (`m.favourite`) and Low priority (`m.lowpriority`) are the built-in ones;
// other tags (another app's own, or the server notices tag) aren't listed.

const String userTagPrefix = "u.";

/// The longest tag name you can type.
const int maxTagName = 64;

/// Whether [tag] is one of your own tags.
bool isUserTag(String tag) =>
    tag.startsWith(userTagPrefix) && tag.length > userTagPrefix.length;

/// A tag's name as shown: `u.Gaming` is "Gaming".
String tagName(String tag) =>
    isUserTag(tag) ? tag.substring(userTagPrefix.length) : tag;

/// The tag for a name typed in, or null when it's empty after trimming.
String? tagFromName(String name) {
  var trimmed = name.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxTagName) {
    trimmed = trimmed.substring(0, maxTagName).trim();
  }
  return "$userTagPrefix$trimmed";
}

/// Every one of your tags on [roomTags] (each room's tags), each once,
/// sorted by name (ignoring case).
List<String> userTagsOf(Iterable<Iterable<String>> roomTags) {
  final tags = {
    for (final tags in roomTags)
      for (final tag in tags)
        if (isUserTag(tag)) tag
  }.toList();
  tags.sort((a, b) {
    final byName = tagName(a).toLowerCase().compareTo(tagName(b).toLowerCase());
    return byName != 0 ? byName : a.compareTo(b);
  });
  return tags;
}

/// How many rooms in [roomTags] have each of your tags.
Map<String, int> userTagCounts(Iterable<Iterable<String>> roomTags) {
  final counts = <String, int>{};
  for (final tags in roomTags) {
    for (final tag in tags.toSet()) {
      if (isUserTag(tag)) counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  return counts;
}
