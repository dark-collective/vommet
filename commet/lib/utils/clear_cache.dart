import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/debug/log.dart';

/// Vommet: Settings › Advanced › Clear cache, like Element's "Clear cache
/// and reload". Drops what each account has synced (rooms, messages,
/// members, receipts, the sync position and the encrypted search index) so
/// the next start downloads it again. The login, the device and its encryption keys stay, and so does
/// the media cache.
class ClearCache {
  /// Whether Vommet comes back by itself afterwards; otherwise it closes.
  static bool get restartsItself => ExperimentRegistry.canRelaunch;

  /// Clears every account's synced data, then restarts (or closes) Vommet.
  static Future<void> clearAndRestart(ClientManager clients) async {
    await clearAll(clients);
    await ExperimentRegistry.restart();
  }

  /// Clears every account's synced data and leaves the sync loops stopped:
  /// the next start syncs from scratch.
  static Future<void> clearAll(ClientManager clients) async {
    for (final client in clients.clients) {
      if (client is! MatrixClient) continue;
      final mx = client.getMatrixClient();
      try {
        // Stop syncing first so nothing writes back while it is cleared.
        await mx.abortSync();
        // The database call, not Client.clearCache(): that one starts the
        // sync loop again, which would store a new position before the
        // restart. The restart drops all in-memory state anyway. Since SDK
        // drift db.7 this clears rooms, events, members, receipts and the
        // sync position, which also holds the sliding sync connection id
        // (missed messages after a server outage).
        await mx.database.clearCache();
        // Vommet: the encrypted search index is part of the message cache.
        await client
            .getComponent<MatrixEncryptedSearchIndexComponent>()
            ?.clear();
      } catch (e, s) {
        Log.onError(e, s, content: "Could not clear the cache");
      }
    }
  }
}
