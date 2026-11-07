import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_pack.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 824: a "public" sticker pack is one whose room anyone can
/// read (history visibility "world_readable"). Such a pack is read straight
/// from the room's state without joining, so tapping one of its stickers
/// shows the whole pack and lets you add it. Read-only.
class PeekedEmoticonPack implements EmoticonPack {
  PeekedEmoticonPack(this.client, this.roomId, this.stateKey, this.state,
      {this.roomName});

  final matrix.Client client;
  final String roomId;
  final String stateKey;
  final Map<String, dynamic> state;
  final String? roomName;

  /// Reads the [tag]ged pack from its room's state. Null when the server
  /// won't show it (the room isn't world-readable, or our server isn't in
  /// it) or the pack is empty.
  static Future<PeekedEmoticonPack?> peek(
      matrix.Client client, StickerPackTag tag) async {
    final found = <String, (Map<String, dynamic>, int?)>{};
    for (final type in ImagePackTypes.roomPackTypes) {
      try {
        final r = await client.getRoomStateWithKey(
            tag.roomId, type, tag.stateKey,
            format: matrix.Format.event);
        // Servers that don't know `format` send just the content.
        final isEvent = r["content"] is Map && r["origin_server_ts"] is int;
        found[type] = isEvent
            ? (
                Map<String, dynamic>.from(r["content"] as Map),
                r["origin_server_ts"] as int
              )
            : (Map<String, dynamic>.from(r), null);
      } catch (e) {
        Log.d("Sticker pack ${tag.roomId}/${tag.stateKey} ($type): $e");
      }
    }
    if (found.isEmpty) return null;
    final stable = found[ImagePackTypes.roomPack];
    final legacy = found[ImagePackTypes.legacyRoomPack];
    final state = ImagePackTypes.pick(
        stable: stable?.$1,
        stableTs: stable?.$2,
        legacy: legacy?.$1,
        legacyTs: legacy?.$2);

    String? name;
    try {
      final r = await client.getRoomStateWithKey(
          tag.roomId, matrix.EventTypes.RoomName, "");
      if (r["name"] case final String n when n.trim().isNotEmpty) name = n;
    } catch (_) {}

    final pack = PeekedEmoticonPack(client, tag.roomId, tag.stateKey, state,
        roomName: name);
    return pack.emotes.isEmpty ? null : pack;
  }

  @override
  String get identifier => stateKey;

  @override
  String get attribution => "";

  @override
  String get displayName =>
      state
          .tryGetMap<String, dynamic>("pack")
          ?.tryGet<String>("display_name") ??
      "Unnamed Pack";

  @override
  String get ownerId => roomId;

  @override
  String get ownerDisplayName => roomName ?? roomId;

  @override
  bool get isGloballyAvailable => false;

  @override
  EmoticonUsage get usage {
    final usage = MatrixEmoticonPack.usagesArrayToUsage(
        state.tryGetMap<String, dynamic>("pack")?.tryGetList<String>("usage"));
    return usage == EmoticonUsage.inherit ? EmoticonUsage.all : usage;
  }

  @override
  List<Emoticon> get emotes {
    final images = state.tryGetMap<String, Map<String, dynamic>>("images");
    if (images == null) return const [];
    final packUsage = usage;
    return [
      for (final e in ImagePackTypes.sortedImages(images))
        if (e.value.tryGet<String>("url") case final String url)
          MatrixEmoticon(Uri.parse(url), client,
              packUsage: packUsage,
              shortcode: e.key,
              usage: MatrixEmoticonPack.usagesArrayToUsage(
                  e.value.tryGetList<String>("usage"))),
    ];
  }

  @override
  List<Emoticon> get emoji => emotes.where((e) => e.isEmoji).toList();

  @override
  List<Emoticon> get stickers => emotes.where((e) => e.isSticker).toList();

  @override
  List<String> getShortcodes() => emoji.map((e) => e.shortcode!).toList();

  @override
  Emoticon? getByShortcode(String shortcode) =>
      emotes.firstWhereOrNull((e) => e.shortcode == shortcode);

  @override
  ImageProvider? get image {
    final url =
        state.tryGetMap<String, dynamic>("pack")?.tryGet<String>("avatar_url");
    if (url == null) return null;
    return MatrixMxcImage(Uri.parse(url), client,
        doFullres: true, fullResHeight: 64);
  }

  @override
  IconData? get icon => Icons.sticky_note_2_outlined;

  @override
  bool get isStickerPack =>
      [EmoticonUsage.sticker, EmoticonUsage.all].contains(usage);

  @override
  bool get isEmojiPack =>
      [EmoticonUsage.emoji, EmoticonUsage.all].contains(usage);

  @override
  Future<void> addEmoticon(
          {required String slug,
          String? shortcode,
          required Uint8List data,
          String? mimeType,
          EmoticonUsage? usage}) =>
      throw UnsupportedError("A peeked pack is read-only");

  @override
  Future<void> updateEmoticon(
          {String? slug,
          String? shortcode,
          Uint8List? data,
          String? mimeType,
          EmoticonUsage? usage,
          required Emoticon previous}) =>
      throw UnsupportedError("A peeked pack is read-only");

  @override
  Future<void> deleteEmoticon(Emoticon emoticon) =>
      throw UnsupportedError("A peeked pack is read-only");

  @override
  Future<void> setPackUsage(EmoticonUsage usage) =>
      throw UnsupportedError("A peeked pack is read-only");

  @override
  Future<void> updatePack(
          {EmoticonUsage? usage, String? name, Uint8List? imageData}) =>
      throw UnsupportedError("A peeked pack is read-only");

  @override
  Future<void> markAsGlobal(bool isGlobal) =>
      throw UnsupportedError("A peeked pack is read-only");
}
