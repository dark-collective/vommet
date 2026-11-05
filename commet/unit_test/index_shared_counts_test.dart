import 'dart:async';

import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart'
    show IndexStepResult, MatrixEncryptedSearchIndexComponent;
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart'
    as index;
import 'package:commet/ui/organisms/room_members_list/index_shared_counts.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 602: the DM Profile tab's counts from the encrypted-chat
// search index.

class _Index extends Fake implements MatrixEncryptedSearchIndexComponent {
  final updated = StreamController<String>.broadcast(sync: true);
  index.SharedContentCounts counted = const index.SharedContentCounts();
  index.RoomCoverage covered =
      const index.RoomCoverage(known: true, complete: false, oldestTs: 1000);
  int steps = 0;

  /// What the next indexOlder call adds (0 = finds nothing new).
  int adds = 0;

  @override
  Stream<String> get onRoomUpdated => updated.stream;

  @override
  Future<index.SharedContentCounts> counts(String roomId) async => counted;

  @override
  Future<index.RoomCoverage> coverage(String roomId) async => covered;

  @override
  Future<IndexStepResult> indexOlder(String roomId) async {
    steps++;
    return IndexStepResult(added: adds, coverage: covered);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test("rows read the index's counts; N+ until the start is reached", () async {
    final idx = _Index()
      ..counted = const index.SharedContentCounts(
          images: 5,
          videos: 2,
          gifs: 3,
          files: 4,
          audio: 1,
          voice: 6,
          links: 9);
    final counts = IndexSharedContentCounts(idx, "!dm:example.org");
    await _settle();

    expect(counts.count(SharedCategory.photosAndVideos).toString(), "7+");
    expect(counts.count(SharedCategory.gifs).count, 3);
    expect(counts.count(SharedCategory.files).count, 5);
    expect(counts.count(SharedCategory.voice).count, 6);
    expect(counts.count(SharedCategory.links).count, 9);
    expect(counts.scannedBackTo, DateTime.fromMillisecondsSinceEpoch(1000));

    idx.covered = const index.RoomCoverage(known: true, complete: true);
    idx.updated.add("!other:example.org");
    await _settle();
    expect(counts.complete, isFalse, reason: "another room's update");
    idx.updated.add("!dm:example.org");
    await _settle();
    expect(counts.complete, isTrue);
    expect(counts.count(SharedCategory.gifs).toString(), "3");
    counts.dispose();
  });

  test("countMore scans, and stops after scans that get nowhere", () async {
    final idx = _Index();
    final counts = IndexSharedContentCounts(idx, "!dm:example.org");
    await _settle();

    for (var i = 0; i < 8; i++) {
      counts.countMore();
      await _settle();
      await _settle();
    }
    expect(idx.steps, 5);

    // The index added something for the room: scanning may go on.
    idx.updated.add("!dm:example.org");
    await _settle();
    counts.countMore();
    await _settle();
    expect(idx.steps, 6);
    counts.dispose();
  });
}
