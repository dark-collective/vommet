import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:commet/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/emoticon_names.dart';
import 'package:commet/utils/library_ops.dart';
import 'package:commet/utils/library_sharing.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 731: one room pack as the Library shows it.
class LibraryPack {
  LibraryPack(this.room, this.stateKey, this.content);

  final matrix.Room room;
  final String stateKey;
  final Map<String, dynamic> content;

  String get name {
    final n = (content["pack"] as Map?)?["display_name"];
    return n is String && n.isNotEmpty ? n : stateKey;
  }

  List<MapEntry<String, Map<String, dynamic>>> get images =>
      LibraryOps.orderedImages(content);

  /// The pack's MSC2545 usage (empty: both).
  List<String> get usage {
    final u = (content["pack"] as Map?)?["usage"];
    return u is List ? u.whereType<String>().toList() : const [];
  }

  bool get editable => LibraryStore.canEdit(room);

  String get roomName => room.getLocalizedDisplayname();

  bool sameAs(LibraryPack other) =>
      other.room.id == room.id && other.stateKey == stateKey;
}

/// A room or space with packs, as a Library sidebar group shows it.
class LibraryPackRoom {
  LibraryPackRoom(this.room, this.packs);

  final matrix.Room room;
  final List<LibraryPack> packs;
}

/// A pack still turned on everywhere though we are no longer in its room.
class LibraryGonePack {
  const LibraryGonePack(this.roomId, this.stateKey);

  final String roomId;
  final String stateKey;
}

/// Vommet issue 731: the Library page's reads and writes. Every pack write
/// first reads the pack's current content from the server (falling back to
/// the synced state), applies the change to that, checks the size, and
/// writes once per pack.
class LibraryStore {
  LibraryStore(this.mx);

  final matrix.Client mx;

  static bool canEdit(matrix.Room room) =>
      ImagePackTypes.roomPackTypes.any(room.canChangeStateEvent);

  static List<LibraryPack> packsOf(matrix.Room room) => [
        for (final e in ImagePackTypes.roomPacks(room).entries)
          if (e.value.isNotEmpty && e.value["images"] is Map)
            LibraryPack(room, e.key, e.value),
      ];

  Iterable<matrix.Room> get _joined =>
      mx.rooms.where((r) => r.membership == matrix.Membership.join);

  /// Sticker rooms we may edit, our own first.
  List<LibraryPackRoom> get stickerRooms {
    final rooms = _joined
        .where((r) => MatrixEmoticonComponent.isStickerRoom(r) && canEdit(r))
        .toList();
    return [
      for (final room in [
        ...rooms.where(MatrixEmoticonComponent.isOwnStickerRoom),
        ...rooms.where((r) => !MatrixEmoticonComponent.isOwnStickerRoom(r)),
      ])
        LibraryPackRoom(room, packsOf(room)),
    ];
  }

  /// Vommet issue 731, phase 2: pack rooms we follow (are in but may not
  /// edit).
  List<LibraryPackRoom> get followedRooms => [
        for (final room in _joined)
          if (MatrixEmoticonComponent.isStickerRoom(room) && !canEdit(room))
            LibraryPackRoom(room, packsOf(room)),
      ];

  /// Other rooms and spaces holding packs we may edit.
  List<LibraryPackRoom> get editableRooms => [
        for (final room in _joined)
          if (!MatrixEmoticonComponent.isStickerRoom(room) && canEdit(room))
            if (packsOf(room) case final packs when packs.isNotEmpty)
              LibraryPackRoom(room, packs),
      ];

  /// Packs in either enable list whose room we left (or never joined).
  List<LibraryGonePack> get gonePacks => [
        for (final e in mx.enabledImagePackRooms.entries)
          if (mx.getRoomById(e.key)?.membership != matrix.Membership.join)
            for (final key in e.value) LibraryGonePack(e.key, key),
      ];

  Future<void> turnOff(LibraryGonePack pack) =>
      mx.removeEmoticonRoomPack(pack.roomId, pack.stateKey);

  /// The pack's content as the server has it now; the synced copy if the
  /// server can't be asked.
  Future<Map<String, dynamic>> fresh(matrix.Room room, String key) async {
    final found = <String, (Map<String, dynamic>, int?)>{};
    var failed = false;
    for (final type in ImagePackTypes.roomPackTypes) {
      try {
        final r = await mx.getRoomStateWithKey(room.id, type, key,
            format: matrix.Format.event);
        // Servers that don't know `format` send just the content.
        final isEvent = r["content"] is Map && r["origin_server_ts"] is int;
        found[type] = isEvent
            ? (
                Map<String, dynamic>.from(r["content"] as Map),
                r["origin_server_ts"] as int
              )
            : (Map<String, dynamic>.from(r), null);
      } on matrix.MatrixException catch (e) {
        if (e.error != matrix.MatrixError.M_NOT_FOUND) failed = true;
      } catch (e) {
        failed = true;
      }
    }
    if (found.isEmpty) {
      if (failed) Log.w("Library: using synced state of pack $key");
      return ImagePackTypes.roomPacks(room)[key] ?? {};
    }
    final stable = found[ImagePackTypes.roomPack];
    final legacy = found[ImagePackTypes.legacyRoomPack];
    return ImagePackTypes.pick(
        stable: stable?.$1,
        stableTs: stable?.$2,
        legacy: legacy?.$1,
        legacyTs: legacy?.$2);
  }

  /// Writes [content] after the size check (nothing written if too big).
  Future<void> _write(
      matrix.Room room, String key, Map<String, dynamic> content) {
    LibraryOps.checkSize(content);
    return MatrixEmoticonRoomStateManager.writeRoomPack(room, key, content);
  }

  /// Copies (or moves) [keys] from [source] to [target]: the target is
  /// written first. Returns the shortcodes renamed in the target.
  Future<Map<String, String>> transfer(
      LibraryPack source, List<String> keys, LibraryPack target,
      {required bool move}) async {
    final t = LibraryOps.transfer(
        source: await fresh(source.room, source.stateKey),
        target: await fresh(target.room, target.stateKey),
        keys: keys,
        move: move);
    await _write(target.room, target.stateKey, t.target);
    if (t.source != null) {
      await _write(source.room, source.stateKey, t.source!);
    }
    return t.renamed;
  }

  /// Where "New pack…" puts a pack made from [source]'s images: the same
  /// room if we may edit it, else our first own sticker room (made if
  /// there is none).
  Future<matrix.Room> newPackRoom(
      LibraryPack source, Future<String> Function() createStickerRoom) async {
    if (source.editable) return source.room;
    for (final r in stickerRooms) {
      if (MatrixEmoticonComponent.isOwnStickerRoom(r.room) && canEdit(r.room)) {
        return r.room;
      }
    }
    final id = await createStickerRoom();
    final room = mx.getRoomById(id) ?? await _waitForRoom(id);
    return room;
  }

  Future<matrix.Room> _waitForRoom(String id) async {
    await mx.waitForRoomInSync(id, join: true);
    return mx.getRoomById(id)!;
  }

  /// A new pack [name] in [room] holding [keys] of [source]; with [move]
  /// they are then removed from [source].
  Future<void> toNewPack(
      LibraryPack source, List<String> keys, matrix.Room room, String name,
      {required bool move}) async {
    final content = LibraryOps.newPackFrom(
        name, await fresh(source.room, source.stateKey), keys);
    final live = ImagePackTypes.roomPacks(room)
        .entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => e.key);
    final key = EmoticonNames.unique(name, live);
    await _write(room, key, content);
    if (MatrixEmoticonComponent.isStickerRoom(room)) {
      try {
        await mx.addEmoticonRoomPack(room.id, key);
      } catch (e) {
        Log.w("Library: could not turn on the new pack $key: $e");
      }
    }
    if (move) {
      final now = await fresh(source.room, source.stateKey);
      await _write(source.room, source.stateKey,
          LibraryOps.removeImages(now, keys.toSet()));
    }
  }

  Future<void> clone(LibraryPack pack, List<String> keys) async {
    final now = await fresh(pack.room, pack.stateKey);
    await _write(pack.room, pack.stateKey, LibraryOps.cloneImages(now, keys));
  }

  Future<void> deleteImages(LibraryPack pack, Set<String> keys) async {
    final now = await fresh(pack.room, pack.stateKey);
    await _write(pack.room, pack.stateKey, LibraryOps.removeImages(now, keys));
  }

  Future<void> reorder(LibraryPack pack, List<String> order) async {
    final now = await fresh(pack.room, pack.stateKey);
    await _write(pack.room, pack.stateKey, LibraryOps.reorder(now, order));
  }

  /// Deletes the pack (an empty `images`, no `pack` metadata) and takes it
  /// off the enable lists.
  Future<void> deletePack(LibraryPack pack) async {
    await _write(pack.room, pack.stateKey, LibraryOps.deletedPack());
    if (mx.isEmoticonPackGloballyAvailable(pack.room.id, pack.stateKey)) {
      await mx.removeEmoticonRoomPack(pack.room.id, pack.stateKey);
    }
  }

  // Sharing (Vommet issue 731, phase 2). A collection is a sticker room;
  // its mode sets who may follow and who may edit its packs.

  /// Whether we may change how [room] is shared: an admin of a pack room.
  static bool canShare(matrix.Room room) =>
      MatrixEmoticonComponent.isStickerRoom(room) &&
      room.ownPowerLevel >= LibrarySharing.adminLevel &&
      room.canChangePowerLevel &&
      room.canChangeJoinRules;

  static Map<String, dynamic>? _powerLevels(matrix.Room room) =>
      room.getState(matrix.EventTypes.RoomPowerLevels)?.content;

  static String? joinRuleOf(matrix.Room room) =>
      room.getState(matrix.EventTypes.RoomJoinRules)?.content["join_rule"]
          as String?;

  static CollectionMode modeOf(matrix.Room room) => LibrarySharing.modeOf(
      modeContent: room.getState(LibrarySharing.modeType)?.content,
      joinRule: joinRuleOf(room),
      powerLevels: _powerLevels(room));

  static Set<String> contributorsOf(matrix.Room room) =>
      LibrarySharing.contributorsOf(_powerLevels(room));

  static bool _creatorsRankHighest(matrix.Room room) =>
      LibrarySharing.creatorsRankHighest(room.roomVersion);

  /// Whether we are [room]'s only admin while others are in it.
  bool isOnlyAdmin(matrix.Room room) => LibrarySharing.isOnlyAdmin(
      mx.userID!,
      LibrarySharing.adminsOf(_powerLevels(room),
          creators: room.creatorUserIds,
          creatorsRankHighest: _creatorsRankHighest(room)),
      room.summary.mJoinedMemberCount ?? room.getParticipants().length);

  /// Who a [sendCopy] room went to, while they haven't joined it.
  String? copyNotJoinedYet(matrix.Room room) {
    final to = room.getState(LibrarySharing.modeType)?.content["sent_to"];
    if (to is! String) return null;
    final member = room.getState(matrix.EventTypes.RoomMember, to);
    return member?.content["membership"] == "join" ? null : to;
  }

  /// A link to follow [room]: its alias, else its id with servers to join
  /// through.
  String linkTo(matrix.Room room) {
    final alias = room.canonicalAlias;
    if (alias.isNotEmpty) return LibrarySharing.matrixToLink(alias);
    return LibrarySharing.matrixToLink(room.id,
        via: viaServers(
            room.getParticipants([matrix.Membership.join]).map((u) => u.id)));
  }

  Future<Map<String, dynamic>> _freshPowerLevels(matrix.Room room) async {
    try {
      return Map<String, dynamic>.from(await mx.getRoomStateWithKey(
          room.id, matrix.EventTypes.RoomPowerLevels, ""));
    } catch (e) {
      Log.w("Library: using synced power levels of ${room.id}: $e");
      return Map<String, dynamic>.from(_powerLevels(room) ?? const {});
    }
  }

  /// Writes [room]'s power levels for [mode] (from the server's current
  /// ones); [contributors] defaults to the room's current ones.
  Future<void> _applyPowerLevels(matrix.Room room, CollectionMode mode,
      {Iterable<String>? contributors}) async {
    final current = await _freshPowerLevels(room);
    final next = LibrarySharing.powerLevelsFor(
        current: current,
        markerType: MatrixEmoticonComponent.stickerRoomStateKey,
        mode: mode,
        contributors: contributors ?? LibrarySharing.contributorsOf(current),
        creators: room.creatorUserIds,
        creatorsRankHighest: _creatorsRankHighest(room));
    if (const DeepCollectionEquality().equals(current, next)) return;
    await mx.setRoomStateWithKey(
        room.id, matrix.EventTypes.RoomPowerLevels, "", next);
  }

  /// Shares [room] as [mode]: permissions first (so the mode state may be
  /// written), then the join rule, then the mode.
  Future<void> setMode(matrix.Room room, CollectionMode mode,
      {bool anyoneCanFollow = true}) async {
    await _applyPowerLevels(room, mode);
    final rule =
        LibrarySharing.joinRuleFor(mode, anyoneCanFollow: anyoneCanFollow);
    if (joinRuleOf(room) != rule) {
      await room.setJoinRules(
          rule == "public" ? matrix.JoinRules.public : matrix.JoinRules.invite);
    }
    final stored = room.getState(LibrarySharing.modeType)?.content;
    if (stored?["mode"] != mode.id) {
      await mx.setRoomStateWithKey(
          room.id, LibrarySharing.modeType, "", {...?stored, "mode": mode.id});
    }
  }

  /// Makes [userId] a contributor of [room], inviting them if they aren't
  /// in it.
  Future<void> addContributor(matrix.Room room, String userId) async {
    final membership = room
        .getState(matrix.EventTypes.RoomMember, userId)
        ?.content["membership"];
    if (membership != "join" && membership != "invite") {
      await room.invite(userId);
    }
    await _applyPowerLevels(room, CollectionMode.community,
        contributors: {...contributorsOf(room), userId});
  }

  Future<void> removeContributor(matrix.Room room, String userId) =>
      _applyPowerLevels(room, CollectionMode.community,
          contributors: contributorsOf(room)..remove(userId));

  /// Joins the collection [link] names and turns on all its packs. Throws
  /// [NotAPackRoomException] when it isn't a pack room (leaving it again
  /// unless we were in it already).
  Future<matrix.Room> follow(PackRoomLink link) async {
    final before = {for (final r in _joined) r.id};
    final id = await mx.joinRoom(link.idOrAlias,
        via: link.via.isEmpty ? null : link.via);
    if (mx.getRoomById(id)?.membership != matrix.Membership.join) {
      await mx
          .waitForRoomInSync(id, join: true)
          .timeout(const Duration(seconds: 60));
    }
    final room = mx.getRoomById(id)!;
    if (!MatrixEmoticonComponent.isStickerRoom(room)) {
      if (!before.contains(id)) {
        try {
          await room.leave();
        } catch (e) {
          Log.w("Library: could not leave $id again: $e");
        }
      }
      throw NotAPackRoomException(id);
    }
    final keys = [for (final p in packsOf(room)) p.stateKey];
    if (keys.isNotEmpty) {
      await mx.setEmoticonRoomPacks(id, keys, enabled: true);
    }
    _markRoomSeen(room);
    await flushSeen();
    return room;
  }

  /// Turns [room]'s packs off in both enable lists, then leaves it.
  Future<void> leave(matrix.Room room) async {
    final keys = mx.enabledImagePackRooms[room.id] ?? const <String>{};
    if (keys.isNotEmpty) {
      await mx.setEmoticonRoomPacks(room.id, keys, enabled: false);
    }
    await room.leave();
  }

  /// A new private sticker room holding [keys] of [source] as one pack
  /// named [packName], for [userId]: they are invited as an admin.
  /// The images keep their mxc URLs. Returns the room id.
  Future<String> sendCopy(LibraryPack source, List<String> keys,
      {required String userId,
      required String roomName,
      required String packName}) async {
    final content = LibraryOps.newPackFrom(
        packName, await fresh(source.room, source.stateKey), keys);
    LibraryOps.checkSize(content);
    final id = await MatrixEmoticonComponent.createStickerRoomFor(mx, roomName,
        inviteAdmins: [
          userId
        ],
        initialState: [
          matrix.StateEvent(
              type: LibrarySharing.modeType,
              stateKey: "",
              content: {"mode": CollectionMode.private.id, "sent_to": userId}),
        ]);
    final room = mx.getRoomById(id) ?? await _waitForRoom(id);
    // Servers that don't apply the preset's invitee level: set it now.
    if (room.getPowerLevelByUserId(userId) < LibrarySharing.adminLevel) {
      final pl = await _freshPowerLevels(room);
      final users = Map<String, dynamic>.from(pl["users"] as Map? ?? {});
      users[userId] = LibrarySharing.adminLevel;
      await mx.setRoomStateWithKey(room.id, matrix.EventTypes.RoomPowerLevels,
          "", {...pl, "users": users});
    }
    final key = EmoticonNames.unique(packName, const []);
    await _write(room, key, content);
    return id;
  }

  // Changed since you last looked (account data `im.vommet.library_seen`).

  Map<String, dynamic> get _seen => Map<String, dynamic>.from(
      mx.accountData[LibrarySharing.seenType]?.content ?? const {});

  /// What we noted but sync doesn't show yet.
  Map<String, dynamic>? _pendingSeen;
  bool _seenDirty = false;
  Timer? _seenTimer;

  Map<String, dynamic> get _seenNow {
    final pending = _pendingSeen;
    final synced = _seen;
    if (pending != null &&
        const DeepCollectionEquality().equals(pending, synced)) {
      _pendingSeen = null;
    }
    return _pendingSeen ?? synced;
  }

  /// Whether the change dot applies to [pack]: followed and community
  /// collections, not our own private or followed ones.
  bool tracksChanges(LibraryPack pack) =>
      !pack.editable ||
      (MatrixEmoticonComponent.isStickerRoom(pack.room) &&
          modeOf(pack.room) == CollectionMode.community);

  /// The pack's event when someone else changed it since we last looked.
  matrix.Event? changedEvent(LibraryPack pack) {
    if (!tracksChanges(pack)) return null;
    final event = ImagePackTypes.packEvent(pack.room, pack.stateKey);
    if (event is! matrix.Event) return null;
    final changed = LibrarySharing.isChanged(
        _seenNow, pack.room.id, pack.stateKey,
        eventId: event.eventId, sender: event.senderId, me: mx.userID!);
    return changed ? event : null;
  }

  /// Notes the current events of [packs] as seen (written a moment later,
  /// once for a burst, and not at all when nothing changed).
  void markSeen(matrix.Room room, Iterable<LibraryPack> packs) {
    final events = <String, String>{
      for (final p in packs)
        if (ImagePackTypes.packEvent(room, p.stateKey)
            case final matrix.Event e)
          p.stateKey: e.eventId,
    };
    final next = LibrarySharing.markSeen(_seenNow, room.id, events);
    if (next == null) return;
    _pendingSeen = next;
    _seenDirty = true;
    _seenTimer?.cancel();
    _seenTimer = Timer(const Duration(seconds: 2), flushSeen);
  }

  void _markRoomSeen(matrix.Room room) => markSeen(room, packsOf(room));

  /// Notes rooms we track but never looked at, so only later changes show.
  void seedSeen(Iterable<matrix.Room> rooms) {
    final seen = _seenNow;
    for (final room in rooms) {
      if (seen[room.id] is! Map) _markRoomSeen(room);
    }
  }

  Future<void> flushSeen() async {
    _seenTimer?.cancel();
    final next = _pendingSeen;
    if (next == null || !_seenDirty) return;
    _seenDirty = false;
    try {
      await mx.setAccountData(mx.userID!, LibrarySharing.seenType, next);
    } catch (e) {
      _seenDirty = true;
      Log.w("Library: could not save what you've seen: $e");
    }
  }

  // My GIFs folders (account data `chat.commet.favorite_stickers`).

  Map<String, dynamic> get gifContent => Map<String, dynamic>.from(
      mx.accountData[MatrixGifComponent.favoritesKey]?.content ?? const {});

  Future<void> writeGifs(Map<String, dynamic> content) =>
      mx.setAccountData(mx.userID!, MatrixGifComponent.favoritesKey, content);

  Future<void> editGifs(
          Map<String, dynamic> Function(Map<String, dynamic> content) edit) =>
      writeGifs(edit(gifContent));
}

/// Vommet issue 731: a room followed by link holds no packs.
class NotAPackRoomException implements Exception {
  const NotAPackRoomException(this.roomId);

  final String roomId;

  @override
  String toString() => "Not a pack room: $roomId";
}
