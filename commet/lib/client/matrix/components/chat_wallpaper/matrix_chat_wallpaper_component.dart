import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/matrix/components/matrix_sync_listener.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart' as matrix;

/// Vommet issue 746: the shared wallpaper of a chat (1:1 or group), and the
/// one only we see.
///
/// Matrix state events are never encrypted, so the state event
/// ([stateType], state key "") only points at an ordinary room event of
/// [eventType] by its id (`{"event_id": ...}`, `{}` = no wallpaper). That
/// event is encrypted like any message in an encrypted room and holds the
/// picture (`file`, encrypted, or `url`), its `info`, and the adjustments
/// `dim` and `blur` plus `source` (one value per picture), or instead of a
/// picture `fill` (`{"colors": ["#rrggbb", ...], "animate": bool,
/// "pattern": {"name", "strength"}}`, see [WallpaperFill]), which needs no
/// upload. The homeserver can
/// see that the wallpaper changed, never the picture. Other clients don't
/// know the event type and hide it.
///
/// Our own choices live in room account data of [accountDataType]:
/// `hidden` (we don't want to see it here) and `recent` (event ids of the
/// wallpapers we applied, newest first, one per picture), and `own` (the
/// wallpaper only we see here: the same fields as the event, the picture
/// always uploaded encrypted; its key sits in this account data, which the
/// homeserver can read).
class MatrixChatWallpaperComponent
    implements
        ChatWallpaperComponent<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener {
  static const String stateType = "im.nether.chat_wallpaper";
  static const String eventType = "im.nether.chat_wallpaper";
  static const String accountDataType = "im.nether.chat_wallpaper";

  /// Longest side of an uploaded wallpaper, in pixels.
  static const int maxSide = 2560;
  static const int maxRecent = 24;

  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  MatrixChatWallpaperComponent(this.client, this.room);

  final StreamController<void> _onChanged = StreamController.broadcast();

  /// Wallpapers already read, by event id (they never change).
  static final Map<String, ChatWallpaper> _cache = {};

  bool _fetchedState = false;

  matrix.Room get _mx => room.matrixRoom;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  bool get isAvailable => experimentChatWallpapers.value;

  @override
  bool get isOneToOne => isOneToOneRoom(room, client);

  /// A direct message with at most two people in it (joined or invited).
  static bool isOneToOneRoom(MatrixRoom room, MatrixClient client) {
    final direct = client.getComponent<DirectMessagesComponent>();
    if (direct?.isRoomDirectMessage(room) != true) return false;
    final summary = room.matrixRoom.summary;
    final people =
        (summary.mJoinedMemberCount ?? 0) + (summary.mInvitedMemberCount ?? 0);
    return people <= 2;
  }

  @override
  bool get canChange =>
      _mx.canChangeStateEvent(stateType) && _mx.canSendEvent(eventType);

  Map<String, Object?> get _accountData =>
      _mx.roomAccountData[accountDataType]?.content ?? const {};

  @override
  bool get hiddenHere => _accountData["hidden"] == true;

  @override
  Future<void> setHiddenHere(bool hidden) async {
    await _setAccountData({..._accountData, "hidden": hidden});
  }

  /// The id of the wallpaper's event, from the state event's content, or
  /// null when there is none.
  static String? currentEventId(Map<String, Object?>? content) {
    final id = content?["event_id"];
    return id is String && id.startsWith("\$") ? id : null;
  }

  /// Our Recent list from the account data's content, newest first.
  static List<String> recentIds(Map<String, Object?> content) {
    final list = content["recent"];
    if (list is! List) return [];
    return list.whereType<String>().where((e) => e.startsWith("\$")).toList();
  }

  /// [ids] with [id] moved to the front, [replaces] (the entries for the same
  /// picture) dropped, and no more than [maxRecent] entries.
  static List<String> withRecent(List<String> ids, String id,
      {Set<String> replaces = const {}}) {
    return [
      id,
      ...ids.where((e) => e != id && !replaces.contains(e)),
    ].take(maxRecent).toList();
  }

  /// -1..1 and 0..1 from an event's content, 0 when missing or invalid.
  static double adjustment(Object? value, {double min = -1}) {
    if (value is! num || value.isNaN) return 0;
    return value.toDouble().clamp(min, 1);
  }

  Future<String?> _currentId() async {
    var id = currentEventId(_mx.getState(stateType)?.content);
    if (id == null && !_fetchedState) {
      // With sliding sync the room's full state may not be here yet.
      _fetchedState = true;
      try {
        final content = await client.matrixClient
            .getRoomStateWithKey(_mx.id, stateType, "");
        id = currentEventId(content);
      } on matrix.MatrixException catch (e) {
        if (e.errcode != "M_NOT_FOUND") rethrow;
      }
    }
    return id;
  }

  @override
  Future<ChatWallpaper?> current() async => await own() ?? await shared();

  @override
  Future<ChatWallpaper?> shared() async {
    final id = await _currentId();
    if (id == null) return null;
    return _read(id);
  }

  Map<String, Object?>? get _ownContent {
    final content = _accountData["own"];
    return content is Map ? Map<String, Object?>.from(content) : null;
  }

  @override
  bool get hasOwn => _ownContent != null;

  @override
  Future<ChatWallpaper?> own() async {
    final content = _ownContent;
    if (content == null) return null;
    final id = "own:${sha256.convert(utf8.encode(jsonEncode(content)))}";
    final cached = _cache[id];
    if (cached != null) return cached;
    try {
      final wallpaper = await _fromContent(id, content, own: true);
      if (wallpaper != null) _cache[id] = wallpaper;
      return wallpaper;
    } catch (e, s) {
      Log.onError(e, s, content: "Own chat wallpaper unreadable");
      return null;
    }
  }

  @override
  Future<List<ChatWallpaper>> recent() async {
    final result = <ChatWallpaper>[];
    for (final id in recentIds(_accountData)) {
      final wallpaper = await _read(id);
      if (wallpaper != null) result.add(wallpaper);
    }
    return result;
  }

  Future<ChatWallpaper?> _read(String eventId) async {
    final cached = _cache[eventId];
    if (cached != null) return cached;
    try {
      var event = await _mx.getEventById(eventId);
      if (event != null &&
          event.type == matrix.EventTypes.Encrypted &&
          client.matrixClient.encryptionEnabled) {
        event = await client.matrixClient.encryption!.decryptRoomEvent(event);
      }
      if (event == null || event.type != eventType) return null;

      final wallpaper = await _fromContent(eventId, event.content);
      if (wallpaper == null) return null;
      _cache[eventId] = wallpaper;
      return wallpaper;
    } catch (e, s) {
      Log.onError(e, s, content: "Chat wallpaper $eventId unreadable");
      return null;
    }
  }

  /// The wallpaper an event's (or our `own`) content describes.
  Future<ChatWallpaper?> _fromContent(String id, Map<String, Object?> content,
      {bool own = false}) async {
    final fill = WallpaperFill.fromJson(content["fill"]);
    if (fill != null) {
      return ChatWallpaper(id: id, fill: fill, source: fill.source, own: own);
    }
    final bytes = await _download(content);
    if (bytes == null) return null;
    final source = content["source"];
    return ChatWallpaper(
      id: id,
      bytes: bytes,
      dim: adjustment(content["dim"]),
      blur: adjustment(content["blur"], min: 0),
      source: source is String ? source : null,
      own: own,
    );
  }

  Future<Uint8List?> _download(Map<String, Object?> content) async {
    final file = content["file"];
    final url = file is Map ? file["url"] : content["url"];
    if (url is! String) return null;
    final mxc = Uri.tryParse(url);
    if (mxc == null || mxc.scheme != "mxc") return null;

    final mx = client.matrixClient;
    var data = await mx.database.getFile(mxc);
    if (data == null) {
      final request = http.Request("GET", await mxc.getDownloadUri(mx));
      request.headers["authorization"] = "Bearer ${mx.accessToken}";
      final response = await mx.httpClient.send(request);
      if (response.statusCode != 200) return null;
      data = await response.stream.toBytes();
      if (data.lengthInBytes < mx.database.maxFileSize) {
        await mx.database
            .storeFile(mxc, data, DateTime.now().millisecondsSinceEpoch);
      }
    }

    if (file is! Map) return data;
    final key = file["key"];
    final hashes = file["hashes"];
    if (key is! Map || hashes is! Map) return null;
    return mx.nativeImplementations.decryptFile(matrix.EncryptedFile(
      data: data,
      k: key["k"] as String,
      iv: file["iv"] as String,
      sha256: hashes["sha256"] as String,
    ));
  }

  @override
  Future<void> apply(
      {Uint8List? image,
      WallpaperFill? fill,
      ChatWallpaper? from,
      required double dim,
      required double blur,
      bool onlyForMe = false}) async {
    fill ??= from?.fill;
    Map<String, Object?> content;
    String source;
    if (fill != null) {
      content = {"fill": fill.toJson()};
      source = fill.source;
    } else if (image != null) {
      final prepared = await compute(prepareWallpaperImage, image);
      source = sha256.convert(prepared.bytes).toString();
      // The same picture again (re-picked): reuse its upload.
      final earlier = await _recentWithSource(source);
      final reused = earlier != null ? await _pictureOf(earlier.id) : null;
      content = reused != null && _fits(reused, onlyForMe)
          ? reused
          : await _upload(prepared, encrypt: onlyForMe || _mx.encrypted);
      content.addAll(_adjustments(dim, blur));
    } else if (from != null) {
      content = {
        ...await _pictureFor(from, onlyForMe),
        ..._adjustments(dim, blur),
      };
      source = from.source ?? from.id;
    } else {
      throw ArgumentError("No picture to apply");
    }
    content["source"] = source;

    if (onlyForMe) {
      await _setAccountData({..._accountData, "own": content});
      return;
    }

    final eventId = await _mx.sendEvent({
      "body": "Chat wallpaper",
      ...content,
    }, type: eventType, displayPendingEvent: false);
    if (eventId == null) throw StateError("Wallpaper not sent");

    await client.matrixClient
        .setRoomStateWithKey(_mx.id, stateType, "", {"event_id": eventId});

    final ids = recentIds(_accountData);
    final samePicture = <String>{};
    for (final id in ids) {
      final w = _cache[id];
      if (w != null && w.source == source) samePicture.add(id);
    }
    // What we just set for everyone is what we want to see, too.
    await _setAccountData({
      ..._accountData,
      "recent": withRecent(ids, eventId, replaces: samePicture),
    }..remove("own"));
  }

  static Map<String, Object?> _adjustments(double dim, double blur) => {
        "dim": double.parse(dim.clamp(-1, 1).toStringAsFixed(3)),
        "blur": double.parse(blur.clamp(0, 1).toStringAsFixed(3)),
      };

  /// An encrypted picture never goes into an unencrypted event, and the
  /// other way round. Our own one may be either.
  bool _fits(Map<String, Object?> picture, bool own) =>
      own || (picture["file"] is Map) == _mx.encrypted;

  /// The picture fields of [from], uploaded again when they don't [_fits]
  /// where it goes (from our own wallpaper to everyone's, or after the room
  /// turned on encryption).
  Future<Map<String, Object?>> _pictureFor(
      ChatWallpaper from, bool onlyForMe) async {
    final picture = from.own
        ? _pictureFields(_ownContent ?? const {})
        : await _pictureOf(from.id);
    if (picture != null && _fits(picture, onlyForMe)) return picture;
    final bytes = from.bytes;
    if (bytes == null) throw StateError("Wallpaper picture not found");
    final prepared = await compute(prepareWallpaperImage, bytes);
    return _upload(prepared, encrypt: onlyForMe || _mx.encrypted);
  }

  Future<ChatWallpaper?> _recentWithSource(String source) async {
    for (final w in await recent()) {
      if (w.source == source) return w;
    }
    return null;
  }

  /// The picture fields (`file` or `url`, and `info`) of an applied
  /// wallpaper's event, to send them again with new adjustments.
  Future<Map<String, Object?>?> _pictureOf(String eventId) async {
    var event = await _mx.getEventById(eventId);
    if (event != null && event.type == matrix.EventTypes.Encrypted) {
      event = await client.matrixClient.encryption?.decryptRoomEvent(event);
    }
    if (event == null || event.type != eventType) return null;
    return _pictureFields(event.content);
  }

  static Map<String, Object?>? _pictureFields(Map<String, Object?> content) {
    if (content["file"] == null && content["url"] == null) return null;
    return {
      if (content["file"] != null) "file": content["file"],
      if (content["url"] != null) "url": content["url"],
      if (content["info"] != null) "info": content["info"],
    };
  }

  Future<Map<String, Object?>> _upload(PreparedWallpaper prepared,
      {required bool encrypt}) async {
    final mx = client.matrixClient;
    final info = {
      "mimetype": "image/jpeg",
      "size": prepared.bytes.lengthInBytes,
      "w": prepared.width,
      "h": prepared.height,
    };
    if (!encrypt) {
      final uri = await mx.uploadContent(prepared.bytes,
          filename: "wallpaper.jpg", contentType: "image/jpeg");
      return {"url": uri.toString(), "info": info};
    }

    final encrypted = await matrix.encryptFile(prepared.bytes);
    final uri = await mx.uploadContent(encrypted.data,
        filename: "wallpaper", contentType: "application/octet-stream");
    return {
      "file": {
        "v": "v2",
        "url": uri.toString(),
        "key": {
          "kty": "oct",
          "alg": "A256CTR",
          "ext": true,
          "key_ops": ["encrypt", "decrypt"],
          "k": encrypted.k,
        },
        "iv": encrypted.iv,
        "hashes": {"sha256": encrypted.sha256},
      },
      "info": info,
    };
  }

  @override
  Future<void> remove() async {
    await client.matrixClient.setRoomStateWithKey(_mx.id, stateType, "", {});
  }

  @override
  Future<void> removeOwn() async {
    await _setAccountData({..._accountData}..remove("own"));
  }

  @override
  Future<void> removeRecent(Set<String> ids) async {
    await _setAccountData({
      ..._accountData,
      "recent": recentIds(_accountData).where((e) => !ids.contains(e)).toList(),
    });
  }

  Future<void> _setAccountData(Map<String, Object?> content) async {
    final mx = client.matrixClient;
    await mx.setAccountDataPerRoom(
        mx.userID!, _mx.id, accountDataType, content);
    _onChanged.add(null);
  }

  @override
  onSync(matrix.JoinedRoomUpdate update) {
    final changed = [
          ...?update.state,
          ...?update.timeline?.events,
        ].any((e) => e.type == stateType && e.stateKey == "") ||
        update.accountData?.any((e) => e.type == accountDataType) == true;
    if (changed) _onChanged.add(null);
  }
}

class PreparedWallpaper {
  const PreparedWallpaper(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Turns a picked picture into a wallpaper upload: upright, no bigger than
/// [MatrixChatWallpaperComponent.maxSide] on its longest side, no metadata
/// (EXIF, location), as JPEG. Throws on data that isn't a picture.
PreparedWallpaper prepareWallpaperImage(Uint8List bytes) {
  img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (e) {
    throw UnsupportedError("Not a picture: $e");
  }
  if (image == null) throw UnsupportedError("Not a picture");
  image = img.bakeOrientation(image);
  const max = MatrixChatWallpaperComponent.maxSide;
  if (image.width > max || image.height > max) {
    image = image.width >= image.height
        ? img.copyResize(image, width: max)
        : img.copyResize(image, height: max);
  }
  image.exif.clear();
  return PreparedWallpaper(
      img.encodeJpg(image, quality: 85), image.width, image.height);
}
