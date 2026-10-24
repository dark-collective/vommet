// Vommet: reads and writes the archive and the chat folders (Vommet issue
// 291, phase 2) in account data; the formats are in chat_folders_model.dart.
//
// Changes show at once: until the server echoes a write back in sync, the
// store keeps it locally and lays it over what account data says.
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:flutter/foundation.dart';

class ChatFoldersStore extends ChangeNotifier {
  ChatFoldersStore._();

  static final ChatFoldersStore instance = ChatFoldersStore._();

  /// Archive changes not yet seen in sync: client id -> room id -> the time
  /// it was archived, or null for unarchived.
  final Map<String, Map<String, int?>> _pendingArchive = {};

  /// The folders as last saved here, until sync brings a newer copy.
  ChatFoldersDoc? _localFolders;

  Object? _accountData(Client client, String key) {
    if (client is! MatrixClient) return null;
    try {
      return client.matrixClient.accountData[key]?.content;
    } catch (e, s) {
      Log.onError(e, s);
      return null;
    }
  }

  /// [client]'s archived chats, with changes made here laid over them.
  Map<String, int?> archivedOf(Client client) {
    final stored =
        readArchivedChats(_accountData(client, archivedChatsAccountDataKey));
    final pending = _pendingArchive[client.identifier];
    if (pending == null || pending.isEmpty) return stored;

    final result = Map.of(stored);
    pending.removeWhere((roomId, ts) {
      // Synced: account data says the same now.
      final synced =
          ts == null ? !stored.containsKey(roomId) : stored.containsKey(roomId);
      if (ts == null) {
        result.remove(roomId);
      } else {
        result[roomId] = ts;
      }
      return synced;
    });
    return result;
  }

  /// Every [clients]' archived chats together, like the pins.
  Map<String, int?> archivedFor(Iterable<Client> clients) => {
        for (final client in clients) ...archivedOf(client),
      };

  /// Archives (or unarchives) [roomIds] on [client], the account they
  /// belong to.
  Future<void> setArchived(
      Client client, Iterable<String> roomIds, bool archive,
      {DateTime? at}) async {
    if (client is! MatrixClient) return;
    final ids = roomIds.toList();
    if (ids.isEmpty) return;
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final pending = _pendingArchive.putIfAbsent(client.identifier, () => {});
    for (final id in ids) {
      pending[id] = archive ? ts : null;
    }
    notifyListeners();

    try {
      final matrix = client.matrixClient;
      await matrix.setAccountData(matrix.userID!, archivedChatsAccountDataKey,
          archivedChatsContent(archivedOf(client)));
    } catch (e, s) {
      Log.onError(e, s);
      for (final id in ids) {
        pending.remove(id);
      }
      notifyListeners();
      rethrow;
    }
  }

  /// The folders: the newest copy across [clients] and what was saved here.
  ChatFoldersDoc foldersFor(Iterable<Client> clients) {
    final copies = [
      for (final client in clients)
        if (client is MatrixClient)
          ChatFoldersDoc.fromJson(
              _accountData(client, chatFoldersAccountDataKey)),
      if (_localFolders != null) _localFolders!,
    ];
    return ChatFoldersDoc.newest(copies);
  }

  /// Saves [doc] to every account in [clients], so all of them (and every
  /// device) show the same folders.
  Future<void> saveFolders(Iterable<Client> clients, ChatFoldersDoc doc) async {
    final stamped = doc.copyWith(
        updated: max(DateTime.now().millisecondsSinceEpoch,
            foldersFor(clients).updated + 1));
    _localFolders = stamped;
    notifyListeners();

    Object? error;
    StackTrace? trace;
    for (final client in clients.whereType<MatrixClient>()) {
      try {
        final matrix = client.matrixClient;
        await matrix.setAccountData(
            matrix.userID!, chatFoldersAccountDataKey, stamped.toJson());
      } catch (e, s) {
        Log.onError(e, s);
        error ??= e;
        trace ??= s;
      }
    }
    if (error != null) Error.throwWithStackTrace(error, trace!);
  }
}
