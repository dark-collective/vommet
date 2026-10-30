import 'dart:convert';

import 'package:commet/client/components/room_media_history/room_media_history_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/room_media_history/index_media_history.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/room_stream_router.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: [RoomMediaHistoryComponent] with a `contains_url` /messages
/// filter (in the spec; Synapse and Tuwunel apply it before the limit) in
/// unencrypted rooms, and from the encrypted search index in encrypted ones
/// ([IndexMediaHistory]) where there is one and its setting allows it on
/// this network (not the web version, not Off, not "Wi-Fi only" on mobile
/// data). Elsewhere it isn't [available] and the tabs page the timeline.
class MatrixRoomMediaHistoryComponent
    extends RoomMediaHistoryComponent<MatrixClient, MatrixRoom> {
  MatrixRoomMediaHistoryComponent(this.client, this.room);

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  /// Messages with a `url` field. Encrypted files keep theirs under `file`,
  /// which is one more reason this is for unencrypted rooms only.
  static final String filter = jsonEncode({
    "contains_url": true,
    "types": [matrix.EventTypes.Message],
    "lazy_load_members": true,
  });

  @override
  bool get available => !room.isE2EE || _indexed != null;

  /// The index's pages, in an encrypted room that may use them now.
  IndexMediaHistory? get _indexed {
    if (!room.isE2EE) return null;
    final index = client.getComponent<MatrixEncryptedSearchIndexComponent>();
    if (index == null || !index.available || !index.usableNow) return null;
    return _index ??= IndexMediaHistory(index, room.identifier,
        convert: (json) =>
            room.convertEvent(matrix.Event.fromJson(json, room.matrixRoom)));
  }

  IndexMediaHistory? _index;

  @override
  Future<RoomMediaPage> loadPage(String? from, {int limit = 50}) async {
    if (room.isE2EE) {
      final indexed = _indexed;
      if (indexed == null) {
        throw StateError("No search index for the encrypted room's media");
      }
      return indexed.loadPage(from, limit: limit);
    }
    final mxRoom = room.matrixRoom;
    final response = await client.matrixClient.getRoomEvents(
        mxRoom.id, matrix.Direction.b,
        from: from, limit: limit, filter: filter);
    final events = [
      for (final raw in response.chunk)
        room.convertEvent(matrix.Event.fromMatrixEvent(raw, mxRoom))
    ];
    // A page ending where it started (no end token, or the same one) is
    // the start of the room. An empty page with a new token isn't: the
    // server may have looked through a stretch with no files.
    final end = response.end;
    return RoomMediaPage(events, next: end == from ? null : end);
  }

  @override
  Stream<String> get onRedacted => RoomStreamRouter.of(client.matrixClient)
      .events(room.identifier)
      .where((update) => update.content["type"] == matrix.EventTypes.Redaction)
      .map((update) {
        final content = update.content;
        return content["redacts"] ??
            (content["content"] as Map<String, dynamic>?)?["redacts"];
      })
      .where((id) => id is String)
      .cast<String>();
}
