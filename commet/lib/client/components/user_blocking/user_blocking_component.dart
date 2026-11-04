import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';

/// Vommet: blocking users. On Matrix this is the account's ignore list
/// (`m.ignored_user_list`): the server stops sending their messages,
/// invites and calls, and every client of yours honours it.
abstract class UserBlockingComponent<T extends Client> implements Component<T> {
  /// The users you've blocked.
  List<String> get blockedUsers;

  bool isBlocked(String userId);

  Future<void> block(String userId);

  Future<void> unblock(String userId);

  /// Fires when the block list changes (here or on another device).
  Stream<void> get onChanged;
}
