import 'dart:async';

import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart'
    as index;
import 'package:commet/client/room.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter/foundation.dart';

/// Vommet: "Shared in this chat" counts of an encrypted room from the
/// encrypted-chat search index (Vommet issues 602 and 611): the whole chat
/// once the index has reached its start, without loading the history into
/// the timeline. While the counts are on screen, [countMore] scans the next
/// page itself, whatever the index setting.
class IndexSharedContentCounts extends ChangeNotifier
    implements SharedContentCounts {
  IndexSharedContentCounts(this.component, this.roomId) {
    _updates = component.onRoomUpdated.where((id) => id == roomId).listen((_) {
      _idle = 0;
      _reload();
    });
    _reload();
  }

  /// The index's counts for [room], or null where there is none (the web
  /// version, unencrypted rooms): those count from the timeline instead.
  static IndexSharedContentCounts? maybeFor(Room room) {
    if (!room.isE2EE) return null;
    final component =
        room.client.getComponent<MatrixEncryptedSearchIndexComponent>();
    if (component == null || !component.available) return null;
    return IndexSharedContentCounts(component, room.identifier);
  }

  final MatrixEncryptedSearchIndexComponent component;
  final String roomId;
  StreamSubscription? _updates;
  index.SharedContentCounts _counts = const index.SharedContentCounts();
  index.RoomCoverage _coverage = index.RoomCoverage.unknown;
  bool _scanning = false;
  bool _disposed = false;

  // Scans in a row that found nothing and got no further (a room the
  // index can't page, an error; a page of only state events also adds
  // nothing, hence a few). Past [_maxIdle], no more scans from here until
  // the index updates the room some other way, or every rebuild would
  // start the next one.
  int _idle = 0;
  static const _maxIdle = 5;
  bool get _stalled => _idle >= _maxIdle;

  Future<void> _reload() async {
    final counts = await component.counts(roomId);
    final coverage = await component.coverage(roomId);
    if (_disposed) return;
    _counts = counts;
    _coverage = coverage;
    notifyListeners();
  }

  @override
  SharedCount count(SharedCategory category) => SharedCount(
      switch (category) {
        SharedCategory.photosAndVideos => _counts.photosAndVideos,
        SharedCategory.gifs => _counts.gifs,
        SharedCategory.files => _counts.filesAndAudio,
        SharedCategory.voice => _counts.voice,
        SharedCategory.links => _counts.links,
      },
      complete: complete);

  @override
  bool get complete => _coverage.complete;

  @override
  DateTime? get scannedBackTo => switch (_coverage.oldestTs) {
        final ts? => DateTime.fromMillisecondsSinceEpoch(ts),
        null => null,
      };

  @override
  void countMore() async {
    if (_scanning || _stalled || complete || _disposed) return;
    _scanning = true;
    try {
      final before = _coverage;
      final step = await component.indexOlder(roomId);
      final after = step.coverage;
      final moved = step.added > 0 ||
          after.complete != before.complete ||
          after.oldestTs != before.oldestTs ||
          after.pendingSegments != before.pendingSegments;
      _idle = moved ? 0 : _idle + 1;
      if (!_disposed) await _reload();
    } finally {
      _scanning = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _updates?.cancel();
    super.dispose();
  }
}
