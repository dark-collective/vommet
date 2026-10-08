import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:flutter/widgets.dart';

/// What the room directory page needs to know about one signed-in account.
/// Built from the live clients by `RoomDirectoryLauncher`; widget tests pass
/// fakes.
class DirectoryAccountHandle {
  final DirectoryAccount account;

  /// e.g. "@me:matrix.org"
  final String userId;
  final String displayName;
  final ImageProvider? avatar;
  final RoomDirectoryComponent directory;

  /// Whether this account is already in the room / space.
  final bool Function(String roomId) isJoined;

  /// Joins [entry] (found in [server]'s directory) and opens it.
  final Future<void> Function(DirectoryEntry entry, String server) join;

  /// Opens a room / space this account is already in.
  final void Function(DirectoryEntry entry) open;

  const DirectoryAccountHandle({
    required this.account,
    required this.userId,
    required this.displayName,
    required this.directory,
    required this.isJoined,
    required this.join,
    required this.open,
    this.avatar,
  });
}

/// Where the server chooser keeps its state.
abstract class DirectoryServerStore {
  List<String> get saved;
  Future<void> setSaved(List<String> servers);

  bool get showSuggestions;
  Future<void> setShowSuggestions(bool show);
}

class MemoryDirectoryServerStore implements DirectoryServerStore {
  @override
  List<String> saved;

  @override
  bool showSuggestions;

  MemoryDirectoryServerStore({List<String>? saved, this.showSuggestions = true})
      : saved = saved ?? [];

  @override
  Future<void> setSaved(List<String> servers) async => saved = servers;

  @override
  Future<void> setShowSuggestions(bool show) async => showSuggestions = show;
}
