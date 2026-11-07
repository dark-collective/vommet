// Vommet (Deep Search, stage 2): the UI's pure helpers, kept free of
// widgets and SDKs so unit tests cover them: snippets, "+3 more here"
// groups, the results bar's steps, seen / last-opened marks and the strip's
// counts.
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';

/// [body] cut around its first match of [words] (lowercased), about
/// [radius] characters each side, with "…" where it was cut. Reply
/// fallbacks ("> " quote lines) are left out; whitespace runs become one
/// space.
String deepSearchSnippet(String body, List<String> words, {int radius = 40}) {
  final lines = body.split("\n");
  final kept = lines.where((l) => !l.startsWith("> ")).toList();
  final text = (kept.isEmpty ? lines : kept)
      .join(" ")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (text.length <= radius * 2) return text;
  final lower = text.toLowerCase();
  var at = -1;
  for (final w in words) {
    if (w.isEmpty) continue;
    final i = lower.indexOf(w.toLowerCase());
    if (i >= 0 && (at < 0 || i < at)) at = i;
  }
  if (at < 0) return "${text.substring(0, radius * 2).trimRight()}…";
  var start = at - radius;
  var end = at + radius;
  if (start < 0) {
    end -= start;
    start = 0;
  }
  if (end > text.length) {
    start = (start - (end - text.length)).clamp(0, text.length);
    end = text.length;
  }
  // Don't cut a word in half where it can be helped.
  if (start > 0) {
    final space = text.indexOf(" ", start);
    if (space >= 0 && space < at) start = space + 1;
  }
  if (end < text.length) {
    final space = text.lastIndexOf(" ", end);
    if (space > at) end = space;
  }
  return "${start > 0 ? "…" : ""}${text.substring(start, end).trim()}"
      "${end < text.length ? "…" : ""}";
}

/// One row of the result list: a hit and the nearby hits in the same chat
/// folded under it ("+2 more here").
class DeepSearchRow {
  const DeepSearchRow(this.result, {this.more = const []});
  final DeepSearchResult result;
  final List<DeepSearchResult> more;
}

/// Folds hits that follow one another in the list, in the same chat of the
/// same account and within [window] of the group's first hit, into one row.
/// Groups in [expanded] (by the first hit's event id) stay unfolded.
List<DeepSearchRow> deepSearchCollapse(List<DeepSearchResult> results,
    {Duration window = const Duration(minutes: 30),
    Set<String> expanded = const {}}) {
  final rows = <DeepSearchRow>[];
  var i = 0;
  while (i < results.length) {
    final head = results[i];
    final more = <DeepSearchResult>[];
    var j = i + 1;
    while (j < results.length) {
      final r = results[j];
      if (r.accountId != head.accountId ||
          r.roomId != head.roomId ||
          (r.ts - head.ts).abs() > window.inMilliseconds) {
        break;
      }
      more.add(r);
      j++;
    }
    if (more.isEmpty || expanded.contains(head.eventId)) {
      rows.add(DeepSearchRow(head));
      for (final r in more) {
        rows.add(DeepSearchRow(r));
      }
    } else {
      rows.add(DeepSearchRow(head, more: more));
    }
    i = j;
  }
  return rows;
}

/// The results bar's next position from [current] by [delta] (+1 down,
/// -1 up) in a list of [total]; null when there's nowhere to go.
int? deepSearchStep(int? current, int total, int delta) {
  if (total <= 0) return null;
  if (current == null) return delta >= 0 ? 0 : total - 1;
  final next = current + delta;
  if (next < 0 || next >= total) return null;
  return next;
}

/// The strip's count: "99+" past 99, or when the index stopped counting.
String deepSearchStripCount(int count, {bool capped = false}) =>
    count > 99 || (capped && count >= 99) ? "99+" : "$count";

/// The ✓ seen and last-opened marks of one search (Mockup 4b). A new
/// search starts afresh.
class DeepSearchMarks {
  String? _search;
  final Set<(String, String)> _seen = {};
  (String, String)? _lastOpened;

  /// Keeps the marks while [searchKey] is the same, else clears them.
  void forSearch(String searchKey) {
    if (_search == searchKey) return;
    _search = searchKey;
    _seen.clear();
    _lastOpened = null;
  }

  void opened(DeepSearchResult r) {
    _seen.add(r.key);
    _lastOpened = r.key;
  }

  bool isSeen(DeepSearchResult r) => _seen.contains(r.key);
  bool isLastOpened(DeepSearchResult r) => _lastOpened == r.key;
  int get seenCount => _seen.length;
}

/// The results bar's list: the local section, then the server's.
List<DeepSearchResult> deepSearchOpenOrder(DeepSearchResults results) =>
    [...results.local, ...results.server];
