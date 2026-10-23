import 'package:commet/client/components/room_directory/room_directory_component.dart';

typedef DirectoryFetch = Future<DirectoryPage> Function(String? since);

/// Paging state for one directory query (server + search + type filter).
/// Starting a new query with [reset] invalidates any page still in flight, so
/// a slow answer to an old search never lands in the new list.
class DirectoryPager {
  DirectoryFetch? _fetch;
  int _generation = 0;
  final List<DirectoryEntry> _entries = [];
  final Set<String> _seen = {};
  String? _nextBatch;
  bool _started = false;
  bool _loading = false;
  Object? _error;
  int? _totalEstimate;

  List<DirectoryEntry> get entries => List.unmodifiable(_entries);
  bool get loading => _loading;
  Object? get error => _error;
  int? get totalEstimate => _totalEstimate;

  /// True until the server says there are no more pages.
  bool get hasMore => !_started || _nextBatch != null;

  /// Loaded at least one page and the directory is empty.
  bool get isEmpty =>
      _started && !_loading && _error == null && _entries.isEmpty && !hasMore;

  void reset(DirectoryFetch fetch) {
    _generation++;
    _fetch = fetch;
    _entries.clear();
    _seen.clear();
    _nextBatch = null;
    _started = false;
    _loading = false;
    _error = null;
    _totalEstimate = null;
  }

  /// Loads the next page. Returns false if nothing was loaded (already
  /// loading, no more pages, superseded by [reset], or failed: see [error]).
  Future<bool> loadMore() async {
    var fetch = _fetch;
    if (fetch == null || _loading || !hasMore) return false;

    var generation = _generation;
    _loading = true;
    _error = null;

    try {
      var page = await fetch(_started ? _nextBatch : null);
      if (generation != _generation) return false;

      for (var entry in page.entries) {
        // servers may repeat a room across pages if the list changed
        if (_seen.add(entry.roomId)) _entries.add(entry);
      }

      // a token that doesn't move would page forever
      var next = page.nextBatch;
      _nextBatch =
          (next == null || next.isEmpty || next == _nextBatch) ? null : next;
      _totalEstimate = page.totalEstimate ?? _totalEstimate;
      _started = true;
      return true;
    } catch (e) {
      if (generation != _generation) return false;
      _error = e;
      return false;
    } finally {
      if (generation == _generation) _loading = false;
    }
  }
}
