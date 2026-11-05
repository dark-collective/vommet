import 'package:commet/utils/notifying_list.dart';

/// Vommet: an id → item map kept in step with a [NotifyingList], so finding
/// an item by id doesn't scan the whole list. The client looked up every
/// room by a linear scan, once per room and on every sync, which made the
/// room list update quadratic in the number of rooms.
///
/// The list's add and remove events keep the map current. Whatever those
/// events don't describe exactly (an item replaced in place, a length change
/// without events, an event for an item that isn't indexed) makes the next
/// lookup rebuild the map from the list. While two items share an id,
/// lookups scan the list, so they always return the first match, exactly as
/// a scan would.
///
/// The list must deliver its events synchronously (the default for
/// [NotifyingList]).
class NotifyingListIndex<T> {
  NotifyingListIndex(this._list, this._keyOf) {
    _list.onAdd.listen(_added);
    _list.onRemove.listen(_removed);
    _list.onItemUpdated.listen((_) => _stale = true);
  }

  final NotifyingList<T> _list;
  final String Function(T item) _keyOf;
  final Map<String, T> _map = {};

  /// How many list items [_map] accounts for.
  int _count = 0;
  bool _stale = true;
  bool _duplicates = false;

  /// The first item with [key], or null.
  T? operator [](String key) {
    _ensure();
    if (_duplicates) {
      for (final item in _list) {
        if (_keyOf(item) == key) return item;
      }
      return null;
    }
    return _map[key];
  }

  bool containsKey(String key) {
    _ensure();
    return _map.containsKey(key);
  }

  void _ensure() {
    if (!_stale && _count == _list.length) return;
    _map.clear();
    _duplicates = false;
    for (final item in _list) {
      final key = _keyOf(item);
      if (_map.containsKey(key)) {
        _duplicates = true;
      } else {
        _map[key] = item;
      }
    }
    _count = _list.length;
    _stale = false;
  }

  void _added(T item) {
    if (_stale) return;
    final key = _keyOf(item);
    final indexed = _map[key];
    // Already indexed: a lookup during this event rebuilt the map.
    if (identical(indexed, item)) return;
    if (indexed != null || _map.containsKey(key)) {
      // A second item with this id.
      _stale = true;
      return;
    }
    _map[key] = item;
    _count++;
  }

  void _removed(T item) {
    if (_stale) return;
    if (_duplicates) {
      _stale = true;
      return;
    }
    final key = _keyOf(item);
    // Not indexed: a lookup during this event rebuilt the map without it.
    if (!_map.containsKey(key)) return;
    if (!identical(_map[key], item)) {
      _stale = true;
      return;
    }
    _map.remove(key);
    _count--;
  }
}
