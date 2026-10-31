import 'dart:async';

import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/sticker_shelf/sticker_shelf_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/debounce.dart';

/// Vommet issue 890: sticker Favorites and Recent, kept in account data
/// (`im.nether.vommet.sticker_favorites`, `im.nether.vommet.recent_stickers`).
/// Each entry keeps the image and its name, so it still works when its pack
/// is gone.
class MatrixStickerShelfComponent
    implements StickerShelfComponent<MatrixClient>, NeedsPostLoginInit {
  MatrixStickerShelfComponent(this.client);

  static const String favoritesKey = "im.nether.vommet.sticker_favorites";
  static const String recentKey = "im.nether.vommet.recent_stickers";

  @override
  MatrixClient client;

  List<ShelfSticker> _favorites = [];
  List<ShelfSticker> _recent = [];
  final Map<String, Emoticon> _emoticons = {};
  final StreamController<void> _changed = StreamController.broadcast();
  final Debouncer _recentDebouncer = Debouncer(delay: Duration(seconds: 5));
  StreamSubscription? _syncSub;

  @override
  Stream<void> get onChanged => _changed.stream;

  @override
  List<Emoticon> get favorites => _favorites.map(_emoticon).toList();

  @override
  List<Emoticon> get recent => _recent.map(_emoticon).toList();

  @override
  void postLoginInit() {
    _load();
    _syncSub ??= client.matrixClient.onSync.stream.listen((update) {
      if (update.accountData
              ?.any((i) => i.type == favoritesKey || i.type == recentKey) ==
          true) {
        _load();
        _changed.add(null);
      }
    });
  }

  void _load() {
    _favorites = ShelfSticker.listFromContent(
        client.matrixClient.accountData[favoritesKey]?.content);
    _recent = ShelfSticker.listFromContent(
        client.matrixClient.accountData[recentKey]?.content);
  }

  Emoticon _emoticon(ShelfSticker sticker) => _emoticons[sticker.url] ??=
      MatrixEmoticon(Uri.parse(sticker.url), client.matrixClient,
          packUsage: EmoticonUsage.sticker,
          shortcode: sticker.shortcode,
          usage: EmoticonUsage.sticker,
          packKey: sticker.packKey);

  @override
  Emoticon? stickerFor(String url, {required String shortcode}) {
    if (!url.startsWith("mxc://")) return null;
    return _emoticon(ShelfSticker(url: url, shortcode: shortcode));
  }

  @override
  bool isFavorite(Emoticon sticker) =>
      _favorites.any((i) => i.url == sticker.key);

  @override
  bool isRecent(Emoticon sticker) => _recent.any((i) => i.url == sticker.key);

  @override
  Future<bool> setFavorite(Emoticon sticker, bool favorite) async {
    final entry = ShelfSticker.fromEmoticon(sticker);
    if (entry == null) return false;
    var replaced = false;
    if (favorite) {
      final result = ShelfSticker.push(
          _favorites, entry, StickerShelfComponent.maxFavorites);
      _favorites = result.list;
      replaced = result.dropped;
    } else {
      _favorites = _favorites.where((i) => i.url != entry.url).toList();
    }
    _changed.add(null);
    await _store(favoritesKey, _favorites);
    return replaced;
  }

  @override
  Future<void> stickerSent(Emoticon sticker) async {
    final entry = ShelfSticker.fromEmoticon(sticker);
    if (entry == null) return;
    _recent =
        ShelfSticker.push(_recent, entry, StickerShelfComponent.maxRecent).list;
    _changed.add(null);
    _recentDebouncer.run(() => _store(recentKey, _recent));
  }

  @override
  Future<void> removeRecent(Emoticon sticker) async {
    _recent = _recent.where((i) => i.url != sticker.key).toList();
    _changed.add(null);
    await _store(recentKey, _recent);
  }

  Future<void> _store(String type, List<ShelfSticker> list) async {
    final mx = client.matrixClient;
    if (mx.userID == null) return;
    try {
      await mx.setAccountData(
          mx.userID!, type, ShelfSticker.listToContent(list));
    } catch (e) {
      Log.w("Could not save $type: $e");
    }
  }
}

/// One saved sticker: its mxc URL, name and (when known) pack key.
class ShelfSticker {
  const ShelfSticker(
      {required this.url, required this.shortcode, this.packKey});

  final String url;
  final String shortcode;
  final String? packKey;

  static ShelfSticker? fromEmoticon(Emoticon sticker) {
    if (sticker is! MatrixEmoticon) return null;
    final url = sticker.emojiUrl.toString();
    if (!url.startsWith("mxc://")) return null;
    return ShelfSticker(
        url: url,
        shortcode: sticker.shortcode ?? "sticker",
        packKey: sticker.packKey);
  }

  static ShelfSticker? fromJson(Object? json) {
    if (json is! Map) return null;
    final url = json["url"];
    if (url is! String || !url.startsWith("mxc://")) return null;
    final shortcode = json["shortcode"];
    final pack = json["pack"];
    return ShelfSticker(
        url: url,
        shortcode:
            shortcode is String && shortcode.isNotEmpty ? shortcode : "sticker",
        packKey: pack is String ? pack : null);
  }

  Map<String, Object> toJson() => {
        "url": url,
        "shortcode": shortcode,
        if (packKey != null) "pack": packKey!,
      };

  static List<ShelfSticker> listFromContent(Map<String, Object?>? content) {
    final list = content?["stickers"];
    if (list is! List) return [];
    final seen = <String>{};
    return list.map(fromJson).nonNulls.where((i) => seen.add(i.url)).toList();
  }

  static Map<String, Object> listToContent(List<ShelfSticker> list) =>
      {"stickers": list.map((i) => i.toJson()).toList()};

  /// Puts [sticker] first (moving it if already there) and keeps at most
  /// [max] entries; [dropped] says whether the oldest one had to go.
  static ({List<ShelfSticker> list, bool dropped}) push(
      List<ShelfSticker> list, ShelfSticker sticker, int max) {
    final result = [sticker, ...list.where((i) => i.url != sticker.url)];
    final dropped = result.length > max;
    return (list: dropped ? result.sublist(0, max) : result, dropped: dropped);
  }
}
