import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/room_directory/directory_account_handle.dart';
import 'package:commet/ui/pages/room_directory/room_directory_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:flutter/widgets.dart';

/// Opens the room directory for the signed-in accounts.
class RoomDirectoryLauncher {
  static Future<void> open(
    BuildContext context, {
    Client? current,
    void Function(Space space)? onSpaceJoined,
  }) async {
    var navigator = Navigator.of(context);
    var clients = clientManager?.clients
            .where((c) =>
                c.isLoggedIn() &&
                c.getComponent<RoomDirectoryComponent>() != null)
            .toList() ??
        [];
    if (clients.isEmpty) return;

    void close() {
      if (navigator.canPop()) navigator.pop();
    }

    var handles = clients.map((c) {
      var directory = c.getComponent<RoomDirectoryComponent>()!;
      return DirectoryAccountHandle(
        account: DirectoryAccount(c.identifier, directory.homeserverName),
        userId: c.self?.identifier ?? c.identifier,
        displayName: c.self?.displayName ?? c.identifier,
        avatar: c.self?.avatar,
        directory: directory,
        isJoined: (id) => c.hasRoom(id) || c.hasSpace(id),
        join: (entry, server) async {
          var address = "${entry.roomId}?via=${Uri.encodeComponent(server)}";
          if (entry.isSpace) {
            var space = await c.joinSpace(address);
            close();
            onSpaceJoined?.call(space);
          } else {
            var room = await c.joinRoom(address);
            close();
            EventBus.doOpenRoom(room.identifier, clientId: c.identifier);
          }
        },
        open: (entry) {
          close();
          if (entry.isSpace && c.hasSpace(entry.roomId)) {
            onSpaceJoined?.call(c.getSpace(entry.roomId)!);
          } else {
            EventBus.doOpenRoom(entry.roomId, clientId: c.identifier);
          }
        },
      );
    }).toList();

    await NavigationUtils.navigateTo(
      context,
      RoomDirectoryPage(
        accounts: handles,
        store: PreferencesDirectoryServerStore(),
        initialAccountId: current?.identifier,
      ),
    );
  }
}

class PreferencesDirectoryServerStore implements DirectoryServerStore {
  @override
  List<String> get saved => preferences.roomDirectorySavedServers.value;

  @override
  Future<void> setSaved(List<String> servers) =>
      preferences.roomDirectorySavedServers.set(servers);

  @override
  bool get showSuggestions => preferences.roomDirectoryShowSuggestions.value;

  @override
  Future<void> setShowSuggestions(bool show) =>
      preferences.roomDirectoryShowSuggestions.set(show);
}
