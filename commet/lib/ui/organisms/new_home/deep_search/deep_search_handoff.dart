// Vommet (Deep Search, stage 2): the sidebar's hand-off row (Decision 3,
// Mockup 2A). The sidebar searches names; its last row, "Search messages
// for “tea” ›", always last (also when no name matches), opens Deep Search
// with the same text and the sidebar's scope as an in: chip. Shift+Enter
// in the sidebar field opens it too.
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';

class DeepSearchHandoff<S> {
  const DeepSearchHandoff._(this.text, this.query);

  /// The row for the sidebar's [text] and [scope], or null when the field
  /// is empty (no row).
  static DeepSearchHandoff<T>? of<T>(String text, {SearchScope<T>? scope}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    var query = DeepSearchQuery<T>(text: trimmed);
    if (scope != null) query = query.withToken(DeepSearchToken.scope(scope));
    return DeepSearchHandoff<T>._(trimmed, query);
  }

  /// Longest text shown in the row before it is cut with "…".
  static const maxShown = 40;

  final String text;

  /// What Deep Search opens with.
  final DeepSearchQuery<S> query;

  /// "Search messages for “tea” ›".
  String get label {
    final shown = text.length <= maxShown
        ? text
        : "${text.substring(0, maxShown).trimRight()}…";
    return "Search messages for “$shown” ›";
  }

  /// The row's key (tests, widget keys).
  static const rowKey = "NewHomeSearchDeepSearchHandoff";
}
