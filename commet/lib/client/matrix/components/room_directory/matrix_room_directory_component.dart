import 'dart:async';

import 'package:commet/client/components/room_directory/room_directory_component.dart';
import 'package:commet/client/matrix/components/space_banner/matrix_space_banner_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/room_directory/directory_accounts.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

class MatrixRoomDirectoryComponent
    implements RoomDirectoryComponent<MatrixClient> {
  @override
  MatrixClient client;

  MatrixRoomDirectoryComponent(this.client);

  matrix.Client get _mx => client.matrixClient;

  @override
  String get homeserverName => _mx.userID?.domain ?? "";

  @override
  Future<DirectoryPage> query({
    String? server,
    String? search,
    DirectoryTypeFilter type = DirectoryTypeFilter.all,
    String? since,
    int limit = 30,
  }) async {
    var remote = server != null && server != homeserverName ? server : null;
    var term = search?.trim();

    try {
      var response = await _mx.queryPublicRooms(
        server: remote,
        limit: limit,
        since: since,
        filter: matrix.PublicRoomQueryFilter(
          genericSearchTerm: term == null || term.isEmpty ? null : term,
          roomTypes: switch (type) {
            DirectoryTypeFilter.all => null,
            DirectoryTypeFilter.rooms => [null],
            DirectoryTypeFilter.spaces => ["m.space"],
          },
        ),
      );

      return DirectoryPage(
        response.chunk.map(_entryFromChunk).toList(),
        nextBatch: response.nextBatch,
        totalEstimate: response.totalRoomCountEstimate,
      );
    } catch (e) {
      int? status;
      String? errcode;
      if (e is matrix.MatrixException) {
        status = e.response?.statusCode;
        errcode = e.errcode;
      }

      bool? alive;
      if (remote != null) alive = await _probeServer(remote);

      var kind = DirectoryErrors.classify(
        statusCode: status,
        errcode: errcode,
        isLocal: remote == null,
        serverAlive: alive,
      );
      Log.i("Directory query for ${server ?? homeserverName} failed "
          "($status $errcode, alive: $alive) -> $kind");
      throw DirectoryException(kind, server ?? homeserverName, e);
    }
  }

  DirectoryEntry _entryFromChunk(matrix.PublishedRoomsChunk c) =>
      DirectoryEntry(
        roomId: c.roomId,
        name: c.name,
        topic: c.topic,
        avatarUrl: c.avatarUrl,
        canonicalAlias: c.canonicalAlias,
        memberCount: c.numJoinedMembers,
        isSpace: c.roomType == "m.space",
        worldReadable: c.worldReadable,
        guestCanJoin: c.guestCanJoin,
        joinRule: c.joinRule,
      );

  /// Is [server] a live Matrix server? Tuwunel answers a failed federated
  /// directory query with the same error whether the server doesn't share
  /// its directory or doesn't exist, so we ask the server directly.
  Future<bool> _probeServer(String server) async {
    var candidates = [
      Uri.https(server, "/.well-known/matrix/server"),
      Uri.https(server, "/_matrix/federation/v1/version"),
      if (!server.contains(":"))
        Uri.https("$server:8448", "/_matrix/federation/v1/version"),
    ];

    for (var uri in candidates) {
      try {
        var response =
            await _mx.httpClient.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) return true;
      } catch (_) {
        // try the next one
      }
    }
    return false;
  }

  @override
  Future<DirectoryDetails> details(DirectoryEntry entry, {String? via}) async {
    var viaList = via != null ? [via] : null;

    var results = await Future.wait([
      _try(() => _mx.getRoomSummary(entry.roomId, via: viaList)),
      _try(() => _mx.getRoomStateWithKey(
          entry.roomId, MatrixSpaceBannerComponent.key, "")),
      if (entry.isSpace)
        _try(() => _mx.getSpaceHierarchy(entry.roomId, maxDepth: 1, limit: 50))
      else
        Future.value(null),
    ]);

    var summary = results[0] as matrix.GetRoomSummaryResponse$3?;
    var bannerState = results[1] as Map<String, Object?>?;
    var hierarchy = results[2] as matrix.GetSpaceHierarchyResponse?;

    Uri? banner;
    var url = bannerState?["url"];
    if (url is String && url.startsWith("mxc://")) banner = Uri.tryParse(url);

    var aliases = <String>[
      if (summary?.canonicalAlias != null)
        summary!.canonicalAlias!
      else if (entry.canonicalAlias != null)
        entry.canonicalAlias!,
    ];

    return DirectoryDetails(
      bannerUrl: banner,
      topic: summary?.topic ?? entry.topic,
      aliases: aliases,
      roomVersion: summary?.roomVersion,
      encrypted: summary?.encryption == null ? null : true,
      children: hierarchy == null
          ? const []
          : hierarchy.rooms
              .where((r) => r.roomId != entry.roomId)
              .map((r) => DirectoryChild(
                    roomId: r.roomId,
                    name: r.name ?? r.canonicalAlias,
                    topic: r.topic,
                    avatarUrl: r.avatarUrl,
                    memberCount: r.numJoinedMembers,
                    isSpace: r.roomType == "m.space",
                  ))
              .toList(),
    );
  }

  @override
  ImageProvider? image(Uri? url, {bool banner = false}) {
    if (url == null || url.scheme != "mxc") return null;
    return MatrixMxcImage(url, _mx,
        doThumbnail: true,
        doFullres: banner,
        autoLoadFullRes: banner,
        thumbnailHeight: banner ? 240 : 96);
  }

  static Future<T?> _try<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }
}
