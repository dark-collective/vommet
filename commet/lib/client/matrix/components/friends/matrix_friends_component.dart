import 'dart:async';

import 'package:commet/client/components/friends/friends_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart';

/// Vommet: the friends list in private account data (Vommet issue 93).
class MatrixFriendsComponent implements FriendsComponent<MatrixClient> {
  static const String key = "im.nether.vommet.friends";

  @override
  MatrixClient client;

  final StreamController<void> _changed = StreamController.broadcast();

  MatrixFriendsComponent(this.client) {
    client.matrixClient.onSync.stream.listen(_onSync);
  }

  void _onSync(SyncUpdate update) {
    if (update.accountData?.any((e) => e.type == key) ?? false) {
      _changed.add(null);
    }
  }

  Map<String, dynamic>? get _content =>
      client.matrixClient.accountData[key]?.content;

  @override
  Set<String> get friends => FriendsListContent.parse(_content);

  @override
  Stream<void> get onFriendsChanged => _changed.stream;

  @override
  Future<void> addFriends(Iterable<String> userIds) =>
      _write(FriendsListContent.withFriends(
          _content, userIds, DateTime.now().millisecondsSinceEpoch));

  @override
  Future<void> removeFriend(String userId) =>
      _write(FriendsListContent.without(_content, userId));

  @override
  Future<List<(String, String)>> searchDirectory(String term) async {
    try {
      final result =
          await client.matrixClient.searchUserDirectory(term, limit: 20);
      return [
        for (final p in result.results)
          (p.userId, p.displayName ?? p.userId.localpart ?? p.userId)
      ];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<bool?> accountExists(String userId) async {
    try {
      await client.matrixClient.getUserProfile(userId);
      return true;
    } on MatrixException catch (e) {
      return e.errcode == "M_NOT_FOUND" ? false : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(Map<String, dynamic> content) async {
    await client.matrixClient
        .setAccountData(client.matrixClient.userID!, key, content);
    _changed.add(null);
  }
}
