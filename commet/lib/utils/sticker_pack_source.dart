import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/emoticon_names.dart';
import 'package:commet/utils/sticker_pack_links.dart';
import 'package:http/http.dart' as http;
import 'package:signal_sticker_api/signal_sticker_api.dart';

/// Vommet: a pack's images, ready to upload.
class StickerPackImages {
  StickerPackImages(this.names, this.datas, this.avatarIndex);
  final List<String> names;
  final List<Uint8List> datas;
  final int avatarIndex;
}

/// Vommet: what the multi-link import knows about one pasted link: the
/// pack's name, size and cover (fetched through the proxy), or why it
/// couldn't be loaded. [loadImages] downloads the images when its turn in
/// the import queue comes.
class StickerPackSource {
  StickerPackSource._(this.link,
      {this.name = "",
      this.imageCount = 0,
      this.usage,
      this.thumbnail,
      this.error,
      Future<StickerPackImages> Function(
              void Function(int done, int total) onProgress)?
          loader})
      : _loader = loader;

  final StickerPackLink link;
  final String name;
  final int imageCount;

  /// Emoji for Telegram custom-emoji sets; null (both) otherwise.
  final EmoticonUsage? usage;
  final Uint8List? thumbnail;

  /// Set when the pack can't be imported.
  final String? error;

  final Future<StickerPackImages> Function(
      void Function(int done, int total) onProgress)? _loader;

  bool get ok => error == null;

  String get displayName => name.isNotEmpty
      ? name
      : link.telegram?.setName ?? link.signal?.packId ?? link.raw;

  Future<StickerPackImages> loadImages(
      void Function(int done, int total) onProgress) {
    if (_loader == null) throw StateError(error ?? "Pack not loaded");
    return _loader(onProgress);
  }

  static String get errorNotAPackLink => "Not a sticker pack link";

  /// Looks up the pack behind [link] through [proxy]. Never throws: a
  /// failure comes back as a source with [error] set.
  static Future<StickerPackSource> fetch(StickerPackLink link,
      {required String proxy}) async {
    try {
      if (link.telegram != null) return await _fetchTelegram(link, proxy);
      if (link.signal != null) return await _fetchSignal(link, proxy);
      return StickerPackSource._(link, error: errorNotAPackLink);
    } catch (e) {
      Log.w("Could not load pack ${link.raw}: $e");
      return StickerPackSource._(link, error: _describe(e));
    }
  }

  static String _describe(Object e) {
    var text = e.toString();
    if (text.startsWith("Exception: ")) text = text.substring(11);
    return text;
  }

  /// Runs [fetch] for every link, at most [concurrency] at a time so a
  /// long list doesn't hammer the proxy. [onEach] gets each result as it
  /// arrives, with its index.
  static Future<List<StickerPackSource>> fetchAll(List<StickerPackLink> links,
      {required String proxy,
      int concurrency = 3,
      void Function(int index, StickerPackSource source)? onEach,
      bool Function()? isCancelled}) async {
    final results = List<StickerPackSource?>.filled(links.length, null);
    await runLimited(links.length, concurrency, (i) async {
      if (isCancelled?.call() == true) return;
      final source = await fetch(links[i], proxy: proxy);
      results[i] = source;
      if (isCancelled?.call() != true) onEach?.call(i, source);
    });
    return results.nonNulls.toList();
  }

  static String _shortcodeFor(String? emoji, int index) {
    if (emoji != null && emoji.isNotEmpty) {
      final code = UnicodeEmojis.findShortcode(emoji);
      if (code != null && code.isNotEmpty) return code;
    }
    return "sticker_$index";
  }

  static Future<StickerPackSource> _fetchTelegram(
      StickerPackLink link, String proxy) async {
    final tg = link.telegram!;
    final response = await http
        .get(Uri.https(proxy, "/proxy/telegram/stickers/${tg.setName}"));
    final body = jsonDecode(response.body);
    if (response.statusCode != 200) {
      final reason = body is Map ? body["error"] : null;
      throw Exception(reason ??
          (response.statusCode == 404
              ? "pack not found"
              : "HTTP ${response.statusCode}"));
    }
    final set = body as Map<String, dynamic>;
    final all = (set["stickers"] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    // As in the single-pack import: tgs/webm can't be shown in Matrix.
    final usable = all.where((s) => s["format"] == "webp").toList();
    if (usable.isEmpty) {
      throw Exception(all.isEmpty
          ? "the pack is empty"
          : "its animated stickers can't be converted");
    }

    final urls = [
      for (final s in usable) Uri.parse("https://$proxy${s["url"]}"),
    ];
    final thumbnail = await _download(urls.first);
    final usage = tg.isEmojiSet || set["sticker_type"] == "custom_emoji"
        ? EmoticonUsage.emoji
        : null;

    return StickerPackSource._(
      link,
      name: (set["title"] as String?) ?? tg.setName,
      imageCount: usable.length,
      usage: usage,
      thumbnail: thumbnail,
      loader: (onProgress) async {
        await UnicodeEmojis.loadShortcodeData();
        final names = [
          for (var i = 0; i < usable.length; i++)
            _shortcodeFor(usable[i]["emoji"] as String?, i)
        ];
        final datas = List<Uint8List?>.filled(urls.length, null);
        datas[0] = thumbnail;
        var done = thumbnail != null ? 1 : 0;
        onProgress(done, urls.length);
        await runLimited(urls.length, 4, (i) async {
          if (datas[i] != null) return;
          datas[i] = await _download(urls[i]);
          onProgress(++done, urls.length);
        });
        return _collect(names, datas, 0);
      },
    );
  }

  static Future<StickerPackSource> _fetchSignal(
      StickerPackLink link, String proxy) async {
    final client = SignalStickerClient(host: proxy, rootPath: "/proxy/signal");
    final pack = await client.getPack(link.signal!);
    if (pack == null) throw Exception("pack not found");
    if (pack.stickers.isEmpty) throw Exception("the pack is empty");

    var cover = pack.stickers.indexWhere((s) => s.id == pack.cover);
    if (cover < 0) cover = 0;
    final coverData = await pack.stickers[cover].getData();

    return StickerPackSource._(
      link,
      name: pack.name,
      imageCount: pack.stickers.length,
      thumbnail: coverData == null ? null : Uint8List.fromList(coverData),
      loader: (onProgress) async {
        await UnicodeEmojis.loadShortcodeData();
        final stickers = pack.stickers;
        final names = [
          for (var i = 0; i < stickers.length; i++)
            _shortcodeFor(stickers[i].emoji, i)
        ];
        final datas = List<Uint8List?>.filled(stickers.length, null);
        var done = 0;
        await runLimited(stickers.length, 4, (i) async {
          try {
            final bytes = await stickers[i].getData();
            if (bytes != null) datas[i] = Uint8List.fromList(bytes);
          } catch (e) {
            Log.w("Signal sticker download failed: $e");
          }
          onProgress(++done, stickers.length);
        });
        return _collect(names, datas, cover);
      },
    );
  }

  /// Drops the images that failed to download, keeping names aligned.
  static StickerPackImages _collect(
      List<String> names, List<Uint8List?> datas, int avatarIndex) {
    final keptNames = <String>[];
    final keptDatas = <Uint8List>[];
    var avatar = 0;
    for (var i = 0; i < datas.length; i++) {
      if (datas[i] == null) continue;
      if (i == avatarIndex) avatar = keptDatas.length;
      keptNames.add(names[i]);
      keptDatas.add(datas[i]!);
    }
    if (keptDatas.isEmpty) {
      throw Exception("none of its images could be downloaded");
    }
    return StickerPackImages(
        EmoticonNames.uniqueAll(keptNames, const []), keptDatas, avatar);
  }

  static Future<Uint8List?> _download(Uri url) async {
    // Converted stickers can take a few seconds on first request; retry once.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.get(url);
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
        Log.w("Sticker download $url failed: HTTP ${response.statusCode}");
      } catch (e) {
        Log.w("Sticker download $url failed: $e");
      }
    }
    return null;
  }
}

/// Runs [work] for indices 0..[count)-1, at most [concurrency] at a time.
Future<void> runLimited(
    int count, int concurrency, Future<void> Function(int index) work) async {
  var next = 0;
  Future<void> worker() async {
    while (next < count) {
      final i = next++;
      await work(i);
    }
  }

  await Future.wait([
    for (var w = 0; w < concurrency && w < count; w++) worker(),
  ]);
}
