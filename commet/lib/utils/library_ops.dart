// Vommet issue 731: the Library page's edits as pure functions. Pack edits
// are applied to the pack's content as read right before the write, so a
// change someone else made meanwhile survives; GIF folder edits work on the
// saved GIF list (`chat.commet.favorite_stickers`).
import 'dart:convert';

import 'package:commet/client/matrix/components/emoticon/image_pack_types.dart';

/// The pack would no longer fit in one state event.
class PackFullException implements Exception {
  const PackFullException(this.bytes);

  final int bytes;

  @override
  String toString() => "Pack content is $bytes bytes";
}

/// A move or copy applied to fresh contents: what to write to the target,
/// then to the source (null for a copy), and the shortcodes renamed on the
/// way because the target already used them.
class PackTransfer {
  const PackTransfer(
      {required this.target, required this.source, required this.renamed});

  final Map<String, dynamic> target;
  final Map<String, dynamic>? source;

  /// Old shortcode → the one it got in the target.
  final Map<String, String> renamed;
}

class LibraryOps {
  /// A state event may be 64 KiB in all; keep room for the event around it.
  static const maxPackBytes = 57344;

  static final shortcodePattern = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

  static bool isValidShortcode(String s) => shortcodePattern.hasMatch(s);

  /// [name] in the shortcode grammar: other characters become `_`, at most
  /// 100 long, "image" if nothing is left. Only for new shortcodes.
  static String normalizeShortcode(String name) {
    var s = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), "_")
        .replaceAll(RegExp(r'^_+|_+$'), "");
    if (s.isEmpty) s = "image";
    return s.length > 100 ? s.substring(0, 100) : s;
  }

  /// [base] if free, else the first free `base_2`, `base_3`… A new
  /// shortcode is normalized and shortened so the suffix still fits.
  static String uniqueShortcode(String base, Set<String> taken,
      {bool normalize = true}) {
    if (normalize) base = normalizeShortcode(base);
    if (!taken.contains(base)) return base;
    final stem = normalizeShortcode(base);
    for (var i = 2;; i++) {
      final suffix = "_$i";
      final room = 100 - suffix.length;
      final head = stem.length > room ? stem.substring(0, room) : stem;
      final candidate = "$head$suffix";
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// The pack's images in pack order (MSC4389), each a copy.
  static List<MapEntry<String, Map<String, dynamic>>> orderedImages(
      Map<String, dynamic> content) {
    final images = content["images"];
    if (images is! Map) return [];
    final valid = <String, Map<String, dynamic>>{
      for (final e in images.entries)
        if (e.key is String && e.value is Map)
          e.key as String: Map<String, dynamic>.from(e.value as Map),
    };
    return ImagePackTypes.sortedImages(valid);
  }

  /// [content] with exactly [images], numbered 0, 1, 2… in list order under
  /// both MSC4389 names (any number they carried is replaced).
  static Map<String, dynamic> withImages(Map<String, dynamic> content,
      List<MapEntry<String, Map<String, dynamic>>> images) {
    var i = 0;
    return {
      ...content,
      "images": {
        for (final e in images)
          e.key: {
            ...withoutOrder(e.value),
            ImagePackTypes.order: i,
            ImagePackTypes.unstableOrder: i++,
          },
      },
    };
  }

  static Map<String, dynamic> withoutOrder(Map<String, dynamic> image) => {
        for (final e in image.entries)
          if (e.key != ImagePackTypes.order &&
              e.key != ImagePackTypes.unstableOrder)
            e.key: e.value,
      };

  /// [items] added after the pack's images. A shortcode the pack already
  /// uses gets `_2`, `_3`… ([renamed] records it).
  static Map<String, dynamic> addImages(Map<String, dynamic> content,
      List<MapEntry<String, Map<String, dynamic>>> items,
      {Map<String, String>? renamed}) {
    final images = orderedImages(content);
    final taken = {for (final e in images) e.key};
    for (final item in items) {
      final key = taken.contains(item.key)
          ? uniqueShortcode(item.key, taken)
          : item.key;
      if (key != item.key) renamed?[item.key] = key;
      taken.add(key);
      images.add(MapEntry(key, item.value));
    }
    return withImages(content, images);
  }

  /// [content] without the images named [keys] (gone already is fine).
  static Map<String, dynamic> removeImages(
      Map<String, dynamic> content, Set<String> keys) {
    final images = orderedImages(content);
    if (!images.any((e) => keys.contains(e.key))) return content;
    return withImages(
        content, images.where((e) => !keys.contains(e.key)).toList());
  }

  /// Copies of the images named [keys] right after the last of them, under
  /// new shortcodes.
  static Map<String, dynamic> cloneImages(
      Map<String, dynamic> content, List<String> keys) {
    final images = orderedImages(content);
    final taken = {for (final e in images) e.key};
    final wanted = keys.toSet();
    final clones = <MapEntry<String, Map<String, dynamic>>>[];
    var last = -1;
    for (var i = 0; i < images.length; i++) {
      if (!wanted.contains(images[i].key)) continue;
      last = i;
      final key = uniqueShortcode(images[i].key, taken);
      taken.add(key);
      clones.add(MapEntry(key, Map<String, dynamic>.from(images[i].value)));
    }
    if (clones.isEmpty) return content;
    images.insertAll(last + 1, clones);
    return withImages(content, images);
  }

  /// The images in [order] (names not in the pack are skipped); images
  /// added meanwhile that [order] doesn't name keep their place after.
  static Map<String, dynamic> reorder(
      Map<String, dynamic> content, List<String> order) {
    final images = orderedImages(content);
    final byKey = {for (final e in images) e.key: e};
    final named = order.where(byKey.containsKey).toSet();
    return withImages(content, [
      for (final key in named) byKey[key]!,
      ...images.where((e) => !named.contains(e.key)),
    ]);
  }

  /// [order] with [keys] moved one step up (or down), as a block.
  static List<String> nudge(List<String> order, Set<String> keys, int step) {
    final list = [...order];
    if (step < 0) {
      for (var i = 1; i < list.length; i++) {
        if (keys.contains(list[i]) && !keys.contains(list[i - 1])) {
          final t = list[i - 1];
          list[i - 1] = list[i];
          list[i] = t;
        }
      }
    } else {
      for (var i = list.length - 2; i >= 0; i--) {
        if (keys.contains(list[i]) && !keys.contains(list[i + 1])) {
          final t = list[i + 1];
          list[i + 1] = list[i];
          list[i] = t;
        }
      }
    }
    return list;
  }

  /// [order] with [keys] (as a block, in pack order) put right before
  /// [before], or at the end if it is null. Dropping onto one of [keys]
  /// changes nothing.
  static List<String> moveBefore(
      List<String> order, Set<String> keys, String? before) {
    if (before != null && keys.contains(before)) return order;
    final moving = order.where(keys.contains).toList();
    final rest = order.where((k) => !keys.contains(k)).toList();
    var at = before == null ? rest.length : rest.indexOf(before);
    if (at < 0) at = rest.length;
    rest.insertAll(at, moving);
    return rest;
  }

  /// Copies (or moves, with [move]) the images named [keys] from [source]
  /// to [target], both as just read. Images reuse their file (same mxc
  /// URL). Throws [PackFullException] if the target would be too big; a
  /// move is written target first, so a failure in between leaves a
  /// duplicate, never a loss.
  static PackTransfer transfer(
      {required Map<String, dynamic> source,
      required Map<String, dynamic> target,
      required List<String> keys,
      required bool move}) {
    final wanted = keys.toSet();
    final items = orderedImages(source)
        .where((e) => wanted.contains(e.key))
        .map((e) => MapEntry(e.key, withoutOrder(e.value)))
        .toList();
    final renamed = <String, String>{};
    final newTarget = addImages(target, items, renamed: renamed);
    checkSize(newTarget);
    return PackTransfer(
      target: newTarget,
      source:
          move ? removeImages(source, {for (final e in items) e.key}) : null,
      renamed: renamed,
    );
  }

  /// A new pack named [name] holding the images named [keys] of [source].
  static Map<String, dynamic> newPackFrom(
      String name, Map<String, dynamic> source, List<String> keys) {
    final pack = <String, dynamic>{"display_name": name};
    final usage = (source["pack"] as Map?)?["usage"];
    if (usage != null) pack["usage"] = usage;
    return transfer(
            source: source,
            target: {"pack": pack, "images": <String, dynamic>{}},
            keys: keys,
            move: false)
        .target;
  }

  /// What a deleted pack is written as.
  static Map<String, dynamic> deletedPack() => {"images": <String, dynamic>{}};

  static int sizeOf(Map<String, dynamic> content) =>
      utf8.encode(jsonEncode(content)).length;

  /// Throws [PackFullException] if [content] is over [maxPackBytes].
  static void checkSize(Map<String, dynamic> content) {
    final bytes = sizeOf(content);
    if (bytes > maxPackBytes) throw PackFullException(bytes);
  }
}

/// Vommet issue 731: folders of My GIFs. A GIF's folder is the `folder`
/// field of its entry in `chat.commet.favorite_stickers`; no field means
/// Unsorted. Folder names, empty ones included, are also listed under
/// [foldersKey] in the same content so an empty folder (and the order)
/// survives; other apps that rewrite the list may drop that list, never a
/// GIF.
class GifFolders {
  static const folderField = "folder";
  static const foldersKey = "im.nether.vommet.gif_folders";

  static String? folderOf(Map<String, dynamic> entry) {
    final f = entry[folderField];
    return f is String && f.trim().isNotEmpty ? f : null;
  }

  /// The folder names: the saved list first, then any only GIFs name.
  static List<String> folders(Map<String, dynamic> content) {
    final result = <String>[];
    final listed = content[foldersKey];
    if (listed is List) {
      for (final f in listed) {
        if (f is String && f.trim().isNotEmpty && !result.contains(f)) {
          result.add(f);
        }
      }
    }
    for (final e in entries(content)) {
      final f = folderOf(e);
      if (f != null && !result.contains(f)) result.add(f);
    }
    return result;
  }

  static List<Map<String, dynamic>> entries(Map<String, dynamic> content) {
    final list = content["favorites"];
    if (list is! List) return [];
    return [
      for (final e in list)
        if (e is Map) Map<String, dynamic>.from(e)
    ];
  }

  /// The GIFs in [folder] (null: Unsorted).
  static List<Map<String, dynamic>> inFolder(
          Map<String, dynamic> content, String? folder) =>
      entries(content).where((e) => folderOf(e) == folder).toList();

  static Map<String, dynamic> _with(Map<String, dynamic> content,
          List<Map<String, dynamic>> list, List<String> folders) =>
      {...content, "favorites": list, foldersKey: folders};

  static Map<String, dynamic> _setField(
      Map<String, dynamic> entry, String? folder) {
    final copy = Map<String, dynamic>.from(entry);
    if (folder == null) {
      copy.remove(folderField);
    } else {
      copy[folderField] = folder;
    }
    return copy;
  }

  /// A trimmed folder name, or null if it is empty.
  static String? cleanName(String name) {
    final n = name.trim();
    if (n.isEmpty) return null;
    return n.length > 100 ? n.substring(0, 100) : n;
  }

  static Map<String, dynamic> addFolder(
      Map<String, dynamic> content, String name) {
    final list = folders(content);
    if (list.contains(name)) return content;
    return _with(content, entries(content), [...list, name]);
  }

  /// The GIFs with [urls] moved to [folder] (null: Unsorted).
  static Map<String, dynamic> moveTo(
      Map<String, dynamic> content, Set<String> urls, String? folder) {
    var list = folders(content);
    if (folder != null && !list.contains(folder)) list = [...list, folder];
    return _with(
        content,
        [
          for (final e in entries(content))
            urls.contains(e["url"]) ? _setField(e, folder) : e
        ],
        list);
  }

  static Map<String, dynamic> remove(
          Map<String, dynamic> content, Set<String> urls) =>
      _with(
          content,
          entries(content).where((e) => !urls.contains(e["url"])).toList(),
          folders(content));

  /// [entry] saved into [folder]; a GIF saved already only changes folder.
  static Map<String, dynamic> saveTo(Map<String, dynamic> content,
      Map<String, dynamic> entry, String? folder) {
    final url = entry["url"];
    if (entries(content).any((e) => e["url"] == url)) {
      return moveTo(content, {url as String}, folder);
    }
    var list = folders(content);
    if (folder != null && !list.contains(folder)) list = [...list, folder];
    return _with(
        content, [...entries(content), _setField(entry, folder)], list);
  }

  static Map<String, dynamic> rename(
      Map<String, dynamic> content, String from, String to) {
    if (from == to) return content;
    final list = <String>[];
    for (final f in folders(content)) {
      final n = f == from ? to : f;
      if (!list.contains(n)) list.add(n);
    }
    return _with(
        content,
        [
          for (final e in entries(content))
            folderOf(e) == from ? _setField(e, to) : e
        ],
        list);
  }

  /// Deletes [name]; its GIFs go to Unsorted.
  static Map<String, dynamic> delete(
          Map<String, dynamic> content, String name) =>
      _with(
          content,
          [
            for (final e in entries(content))
              folderOf(e) == name ? _setField(e, null) : e
          ],
          folders(content).where((f) => f != name).toList());
}
