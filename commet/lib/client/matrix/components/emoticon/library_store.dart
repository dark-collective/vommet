import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_state_manager.dart';
import 'package:commet/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:commet/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/emoticon_names.dart';
import 'package:commet/utils/library_ops.dart';
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
          if (e.value["images"] case Map images
              when images.isNotEmpty || e.value["pack"] is Map)
            LibraryPack(room, e.key, e.value),
      ];

  Iterable<matrix.Room> get _joined =>
      mx.rooms.where((r) => r.membership == matrix.Membership.join);

  /// Sticker rooms, our own first.
  List<LibraryPackRoom> get stickerRooms {
    final rooms = _joined.where(MatrixEmoticonComponent.isStickerRoom).toList();
    return [
      for (final room in [
        ...rooms.where(MatrixEmoticonComponent.isOwnStickerRoom),
        ...rooms.where((r) => !MatrixEmoticonComponent.isOwnStickerRoom(r)),
      ])
        LibraryPackRoom(room, packsOf(room)),
    ];
  }

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

  // My GIFs folders (account data `chat.commet.favorite_stickers`).

  Map<String, dynamic> get gifContent => Map<String, dynamic>.from(
      mx.accountData[MatrixGifComponent.favoritesKey]?.content ?? const {});

  Future<void> writeGifs(Map<String, dynamic> content) =>
      mx.setAccountData(mx.userID!, MatrixGifComponent.favoritesKey, content);

  Future<void> editGifs(
          Map<String, dynamic> Function(Map<String, dynamic> content) edit) =>
      writeGifs(edit(gifContent));
}
