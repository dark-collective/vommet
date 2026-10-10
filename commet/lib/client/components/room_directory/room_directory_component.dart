import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:flutter/widgets.dart';

enum DirectoryTypeFilter { all, rooms, spaces }

/// One room or space listed in a server's public room directory.
class DirectoryEntry {
  final String roomId;
  final String? name;
  final String? topic;
  final Uri? avatarUrl;
  final String? canonicalAlias;
  final int memberCount;
  final bool isSpace;
  final bool worldReadable;
  final bool guestCanJoin;

  /// "public", "knock", ... as reported by the directory, when present
  final String? joinRule;

  const DirectoryEntry({
    required this.roomId,
    this.name,
    this.topic,
    this.avatarUrl,
    this.canonicalAlias,
    this.memberCount = 0,
    this.isSpace = false,
    this.worldReadable = false,
    this.guestCanJoin = false,
    this.joinRule,
  });

  String get displayName => name ?? canonicalAlias ?? roomId;
}

class DirectoryPage {
  final List<DirectoryEntry> entries;
  final String? nextBatch;
  final int? totalEstimate;

  const DirectoryPage(this.entries, {this.nextBatch, this.totalEstimate});
}

/// A child of a space, as returned by the space hierarchy.
class DirectoryChild {
  final String roomId;
  final String? name;
  final String? topic;
  final Uri? avatarUrl;
  final int memberCount;
  final bool isSpace;

  const DirectoryChild({
    required this.roomId,
    this.name,
    this.topic,
    this.avatarUrl,
    this.memberCount = 0,
    this.isSpace = false,
  });
}

/// Extra information loaded when a directory row is expanded.
class DirectoryDetails {
  /// Banner image; only readable for world-readable rooms our server is in,
  /// so this is often null.
  final Uri? bannerUrl;
  final String? topic;
  final List<String> aliases;
  final String? roomVersion;
  final bool? encrypted;
  final List<DirectoryChild> children;

  const DirectoryDetails({
    this.bannerUrl,
    this.topic,
    this.aliases = const [],
    this.roomVersion,
    this.encrypted,
    this.children = const [],
  });
}

enum DirectoryProblemKind {
  /// A remote server is up but doesn't share its directory with other servers
  remoteNotShared,

  /// Our own homeserver refuses to show its directory to its own users
  ownServerRestricted,

  /// The server doesn't exist or couldn't be reached
  unreachable,

  /// Anything else
  failed,
}

class DirectoryException implements Exception {
  final DirectoryProblemKind kind;
  final String server;
  final Object? cause;

  const DirectoryException(this.kind, this.server, [this.cause]);

  @override
  String toString() => "DirectoryException($kind, $server, $cause)";
}

abstract class RoomDirectoryComponent<T extends Client>
    implements Component<T> {
  /// Server name of this account's homeserver, e.g. "matrix.org"
  String get homeserverName;

  /// Query [server]'s directory (defaults to our own homeserver).
  /// Throws [DirectoryException] on failure.
  Future<DirectoryPage> query({
    String? server,
    String? search,
    DirectoryTypeFilter type = DirectoryTypeFilter.all,
    String? since,
    int limit = 30,
  });

  /// Load extra details for an expanded row. Never throws; fields that can't
  /// be loaded are left empty.
  Future<DirectoryDetails> details(DirectoryEntry entry, {String? via});

  /// Image for an avatar or banner url from the directory.
  ImageProvider? image(Uri? url, {bool banner = false});
}
