import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/bookmarks/bookmarks.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

import '../message_selection_download_test.dart'
    show SelectionRoom, SelectionTimeline;

/// SDK writes return before their sync echo; server and local data are separate.
class BookmarkSdk extends Fake implements matrix.Client {
  @override
  final Map<String, matrix.BasicEvent> accountData = {};
  @override
  final onSync = CachedStreamController<matrix.SyncUpdate>();
  @override
  String? userID = '@me:example.org';
  final writes = <Map<String, Object?>>[];
  Map<String, Object?>? server;
  Completer<void>? nextWrite;

  @override
  Future<void> setAccountData(
      String user, String type, Map<String, Object?> body) async {
    if (user != userID || type != Bookmarks.type)
      throw StateError("Wrong bookmark account/type");
    final snapshot =
        Map<String, Object?>.from(jsonDecode(jsonEncode(body)) as Map);
    writes.add(snapshot);
    final gate = nextWrite;
    nextWrite = null;
    if (gate != null) await gate.future;
    server = snapshot;
  }

  void emitBookmarks(List<Bookmark> items) {
    final event = matrix.BasicEvent(
        type: Bookmarks.type, content: Bookmarks.serialize(items));
    accountData[Bookmarks.type] = event;
    onSync.add(
        matrix.SyncUpdate(nextBatch: 'bookmark-fixture', accountData: [event]));
  }
}

class BookmarkClient extends Fake implements MatrixClient {
  BookmarkClient(this.matrixClient, {this.identifier = 'bookmark-account'});
  @override
  final BookmarkSdk matrixClient;
  @override
  final String identifier;
  @override
  T? getComponent<T extends Component>() => null;
}

class BookmarkRoom extends SelectionRoom {
  BookmarkRoom(this.client, {this.identifier = '!fixture'});
  @override
  final BookmarkClient client;
  @override
  final String identifier;
}

class BookmarkTimeline extends SelectionTimeline {
  BookmarkTimeline(super.room, super.events);
  final redacted = <String>{};
  @override
  bool isEventRedacted(event) => redacted.contains(event.eventId);
}
