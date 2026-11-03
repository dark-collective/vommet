import 'dart:async';
import 'dart:collection';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_encrypted.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/foundation.dart';

/// Per-open-list event cache and bounded lookup queue. No history or media loads.
/// An unfinished request keeps its worker slot, including across filter changes.
class SavedMessageEvents extends ChangeNotifier {
  SavedMessageEvents(this.fetch);

  static const batchSize = 24;
  static const concurrency = 3;
  final Future<TimelineEvent?> Function(Bookmark) fetch;
  final Map<String, TimelineEvent?> _events = {};
  final Map<String, int> _versions = {};
  final _redacted = <String>{};
  final _queue = LinkedHashMap<String, Bookmark>();
  final _running = <String>{};
  final _wanted = <String>{};
  List<Bookmark> _scope = [];
  Set<String>? _retained;
  bool _media = false;
  bool _closed = false;
  Timer? _slowTimer;
  bool slow = false;

  static String key(Bookmark b) => '${b.roomId}\n${b.eventId}';
  bool checked(Bookmark b) => _events.containsKey(key(b));
  TimelineEvent? event(Bookmark b) => _events[key(b)];
  bool unavailable(Bookmark b) {
    if (!checked(b) || _redacted.contains(key(b))) return false;
    final e = event(b);
    // Not decrypted yet: it may still be matching media, so the media scan
    // can't count it as checked. The plain list shows it as it is.
    return e == null || (_media && e is TimelineEventEncrypted);
  }

  bool get busy => _wanted.any((k) => !_events.containsKey(k));
  int get checkedCount => _scope.where(checked).length;
  int get unavailableCount => _scope.where(unavailable).length;
  int get remaining =>
      _scope.where((b) => !checked(b) && !_wanted.contains(key(b))).length;

  /// Room/tag changes discard queued work; in-flight requests remain bounded.
  void configure(List<Bookmark> scope, {required bool media}) {
    final unchanged = media == _media &&
        listEquals(scope.map(key).toList(), _scope.map(key).toList());
    _scope = scope;
    _media = media;
    // Switching Photos/Videos or updating a note must not advance the scan.
    if (unchanged) return;
    _wanted.clear();
    _queue.clear();
    _slowTimer?.cancel();
    _slowTimer = null;
    slow = false;
    if (media) more();
  }

  void more() {
    for (final b in _scope
        .where((b) => !checked(b) && !_wanted.contains(key(b)))
        .take(batchSize)) {
      request(b);
    }
  }

  /// Only called for lazily built preview cards or an explicitly admitted batch.
  void request(Bookmark b) {
    if (_closed || checked(b)) return;
    final k = key(b);
    _wanted.add(k);
    // Retain one follow-up request even if this key has an older version
    // in flight. A valid completion will make it redundant; an invalidated
    // completion must hand its worker slot to this retry.
    _queue[k] = b;
    _drain();
  }

  void retry() {
    for (final b in _scope.where(unavailable).take(batchSize).toList()) {
      _events.remove(key(b));
      request(b);
    }
  }

  /// A sync redaction must win even over a stale request already in flight.
  void redacted(String roomId, String eventId) {
    final k = '$roomId\n$eventId';
    _versions[k] = (_versions[k] ?? 0) + 1;
    _events[k] = null;
    _redacted.add(k);
    _queue.remove(k);
    if (!_closed) notifyListeners();
  }

  void roomUnavailable(Iterable<Bookmark> items) {
    for (final b in items) {
      final k = key(b);
      _versions[k] = (_versions[k] ?? 0) + 1;
      _events[k] = null;
      _queue.remove(k);
    }
    if (!_closed) notifyListeners();
  }

  void retain(List<Bookmark> bookmarks) {
    final keys = bookmarks.map(key).toSet();
    _retained = keys;
    _events.removeWhere((k, _) => !keys.contains(k));
    _queue.removeWhere((k, _) => !keys.contains(k));
    _wanted.removeWhere((k) => !keys.contains(k));
  }

  void _drain() {
    while (!_closed && _running.length < concurrency && _queue.isNotEmpty) {
      String? next;
      for (final k in _queue.keys) {
        if (!_running.contains(k)) {
          next = k;
          break;
        }
      }
      if (next == null) break;
      final k = next;
      final b = _queue.remove(k)!;
      if (!_wanted.contains(k) || checked(b)) continue;
      _running.add(k);
      final version = _versions[k] ?? 0;
      unawaited(_resolve(b, version));
    }
    if (busy && _slowTimer == null) {
      _slowTimer = Timer(const Duration(seconds: 15), () {
        _slowTimer = null;
        if (!_closed && busy) {
          slow = true;
          notifyListeners();
        }
      });
    }
  }

  Future<void> _resolve(Bookmark b, int version) async {
    TimelineEvent? result;
    try {
      // Keep polls, deleted and undecrypted messages: the plain list draws
      // them, and the media filter only matches messages anyway.
      result = await fetch(b);
    } catch (_) {
      // Failure is unknown media type, never a confirmed nonmatch.
    }
    final k = key(b);
    _running.remove(k);
    if (_closed) return;
    if ((_versions[k] ?? 0) == version &&
        (_retained?.contains(k) ?? _scope.any((b) => key(b) == k))) {
      _events[k] = result;
    }
    _drain();
    if (!busy) {
      _slowTimer?.cancel();
      _slowTimer = null;
      slow = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _queue.clear();
    _slowTimer?.cancel();
    super.dispose();
  }
}

/// Use the room Media tab's conventions, retaining the whole saved message.
/// Stickers are distinct events, and GIFs are a separate media kind there.
bool savedMediaMatches(TimelineEvent? event, RoomAttachmentFilter filter) =>
    event is TimelineEventMessage &&
    (event.attachments ?? const <Attachment>[]).whereType<FileAttachment>().any(
          filter.matches,
        );
