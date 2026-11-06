import 'package:commet/client/components/room_directory/room_directory_component.dart';

/// A signed-in account, as far as the room directory cares.
class DirectoryAccount {
  final String id;
  final String homeserver;

  const DirectoryAccount(this.id, this.homeserver);

  @override
  bool operator ==(Object other) =>
      other is DirectoryAccount &&
      other.id == id &&
      other.homeserver == homeserver;

  @override
  int get hashCode => Object.hash(id, homeserver);
}

/// How a server's directory is fetched: through [account], asking
/// [serverParam] (null = the account's own homeserver, a local query).
class DirectoryFetchPlan {
  final DirectoryAccount account;
  final String? serverParam;

  const DirectoryFetchPlan(this.account, this.serverParam);

  bool get isLocal => serverParam == null;
}

class DirectoryAccounts {
  /// Picks the account to fetch [server]'s directory with. An account that
  /// lives on [server] wins (a local query works even when the server doesn't
  /// share its directory over federation), preferring [joining] when it is
  /// one of them. Otherwise [joining] asks its own homeserver to query
  /// [server] over federation.
  static DirectoryFetchPlan plan(
      String server, DirectoryAccount joining, List<DirectoryAccount> all) {
    if (joining.homeserver == server) return DirectoryFetchPlan(joining, null);

    for (var account in all) {
      if (account.homeserver == server) {
        return DirectoryFetchPlan(account, null);
      }
    }

    return DirectoryFetchPlan(joining, server);
  }

  /// Homeservers of all accounts, [current]'s first, without duplicates.
  static List<String> ownServers(
      DirectoryAccount current, List<DirectoryAccount> all) {
    var result = <String>[current.homeserver];
    for (var account in all) {
      if (!result.contains(account.homeserver)) result.add(account.homeserver);
    }
    return result;
  }

  /// After [joining] failed to join a room listed on [server], an account
  /// that lives on that server is the best one to suggest ("Join as ...").
  static DirectoryAccount? suggestAfterJoinFailure(
      String server, DirectoryAccount joining, List<DirectoryAccount> all) {
    if (joining.homeserver == server) return null;
    for (var account in all) {
      if (account != joining && account.homeserver == server) return account;
    }
    return null;
  }
}

class DirectoryErrors {
  /// Maps a failed directory request to the warning shown to the user.
  ///
  /// [statusCode]/[errcode] come from our own homeserver. [isLocal] means we
  /// asked our homeserver for its own directory. [serverAlive] is the result
  /// of probing a remote server after a failure (null = not probed): Tuwunel
  /// returns the same 502 M_CONNECTION_FAILED whether a remote server doesn't
  /// share its directory or doesn't exist at all, so only the probe can tell.
  static DirectoryProblemKind classify({
    required int? statusCode,
    required String? errcode,
    required bool isLocal,
    bool? serverAlive,
  }) {
    if (isLocal) {
      if (statusCode == 403 || errcode == "M_FORBIDDEN") {
        return DirectoryProblemKind.ownServerRestricted;
      }
      return DirectoryProblemKind.failed;
    }

    if (statusCode == 403 || errcode == "M_FORBIDDEN") {
      // our server or the remote refused the federation query
      return serverAlive == false
          ? DirectoryProblemKind.unreachable
          : DirectoryProblemKind.remoteNotShared;
    }

    if (statusCode == 502 ||
        statusCode == 504 ||
        statusCode == 404 ||
        errcode == "M_CONNECTION_FAILED" ||
        errcode == "M_NOT_FOUND") {
      if (serverAlive == true) return DirectoryProblemKind.remoteNotShared;
      if (serverAlive == false) return DirectoryProblemKind.unreachable;
      return DirectoryProblemKind.failed;
    }

    return DirectoryProblemKind.failed;
  }
}
