import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 328: files dropped onto the app or copied in a file manager.
///
/// Inside the Flatpak a file manager can hand over a path on the host that the
/// sandbox can't open. desktop_drop and [ClipboardFiles] ask for the document
/// portal's copy (`/run/user/N/doc/...`) when the other app offers one; when
/// it doesn't, [FileTransfer.check] says so instead of failing silently.
class FileTransfer {
  static String get labelFileTransferUnreadableTitle => Intl.message(
      "Couldn't attach file",
      desc:
          "Title of the message shown when a dropped or pasted file can't be read",
      name: "labelFileTransferUnreadableTitle");

  static String labelFileTransferUnreadableSandboxed(String names) => Intl.message(
      "Vommet can't open $names. The Flatpak can only read files it was given. Use the attach button to pick the file, or move it into your Downloads folder first.",
      desc:
          "Shown when a dropped or pasted file can't be read inside the Flatpak sandbox",
      args: [names],
      name: "labelFileTransferUnreadableSandboxed");

  static String labelFileTransferUnreadable(String names) =>
      Intl.message("Vommet can't open $names.",
          desc: "Shown when a dropped or pasted file can't be read",
          args: [names],
          name: "labelFileTransferUnreadable");

  static bool get sandboxed =>
      BuildConfig.IS_FLATPAK ||
      (PlatformUtils.isLinux && Platform.environment.containsKey("FLATPAK_ID"));

  /// The size of the file at [path], or null when it can't be read.
  static Future<int?> check(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      // length() only needs stat; make sure the contents can be opened too.
      final handle = await file.open();
      await handle.close();
      return size;
    } catch (e) {
      Log.w("Can't read transferred file $path: $e");
      return null;
    }
  }

  /// Files up to this size are read into memory when attached; larger ones
  /// are sent from their path.
  static const int maxInMemorySize = 50000000;

  /// Attachments for the files at the given paths, and the names of the ones
  /// that couldn't be read.
  static Future<({List<PendingFileAttachment> files, List<String> unreadable})>
      load(Iterable<({String path, String name})> files) async {
    final loaded = <PendingFileAttachment>[];
    final unreadable = <String>[];
    for (final file in files) {
      final size = await check(file.path);
      if (size == null) {
        unreadable.add(file.name);
        continue;
      }
      Uint8List? data;
      if (size < maxInMemorySize) {
        try {
          data = await File(file.path).readAsBytes();
        } catch (e) {
          Log.w("Can't read transferred file ${file.path}: $e");
          unreadable.add(file.name);
          continue;
        }
      }
      loaded.add(PendingFileAttachment(
          name: file.name, path: file.path, size: size, data: data));
    }
    return (files: loaded, unreadable: unreadable);
  }

  /// [load] for paths, named after their last segment.
  static Future<({List<PendingFileAttachment> files, List<String> unreadable})>
      loadPaths(Iterable<String> paths) =>
          load(paths.map((p) => (path: p, name: nameOf(p))));

  /// Tells the user which files couldn't be attached; nothing when [names] is
  /// empty.
  static void showUnreadable(BuildContext context, List<String> names) {
    final message = unreadableMessage(names);
    if (message == null) return;
    AdaptiveDialog.show(context,
        builder: (_) => tiamat.Text.body(message),
        title: labelFileTransferUnreadableTitle);
  }

  /// The message for files that couldn't be read, or null when [names] is
  /// empty.
  static String? unreadableMessage(List<String> names, {bool? inSandbox}) {
    if (names.isEmpty) return null;
    final quoted = names.map((n) => "“$n”").join(", ");
    return (inSandbox ?? sandboxed)
        ? labelFileTransferUnreadableSandboxed(quoted)
        : labelFileTransferUnreadable(quoted);
  }

  /// Local paths in a `text/uri-list`: one URI per line, `#` lines are
  /// comments. Anything that isn't a `file:` URI is skipped.
  static List<String> parseUriList(String text) {
    final paths = <String>[];
    for (var line in text.split(RegExp(r"\r?\n"))) {
      line = line.trim();
      if (line.isEmpty || line.startsWith("#")) continue;
      final path = filePathOf(line);
      if (path != null) paths.add(path);
    }
    return paths;
  }

  /// Local paths in GNOME's `x-special/gnome-copied-files`: `copy` or `cut`
  /// on the first line, then one URI per line.
  static List<String> parseGnomeCopiedFiles(String text) {
    final lines = text.split(RegExp(r"\r?\n"));
    if (lines.isEmpty) return const [];
    final action = lines.first.trim();
    if (action != "copy" && action != "cut") return const [];
    return parseUriList(lines.skip(1).join("\n"));
  }

  /// The paths in the clipboard [text] of the given [format], as the Linux
  /// clipboard channel reports it.
  static List<String> parseClipboard(String? format, String? text) {
    if (text == null || text.isEmpty) return const [];
    if (format == "x-special/gnome-copied-files") {
      return parseGnomeCopiedFiles(text);
    }
    return parseUriList(text);
  }

  /// The local path of a `file:` URI, or null for any other URI.
  static String? filePathOf(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != "file") return null;
    // file://host/path names another machine; only take local files.
    if (parsed.host.isNotEmpty && parsed.host != "localhost") return null;
    try {
      // toFilePath refuses any authority, even localhost.
      return Uri(scheme: "file", path: parsed.path).toFilePath(windows: false);
    } catch (_) {
      return null;
    }
  }

  /// The file name of [path].
  static String nameOf(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    return i < 0 ? path : path.substring(i + 1);
  }
}

/// Files copied in a file manager (Vommet issue 328). The pasteboard plugin
/// asks GTK for `text/uri-list` only, which inside the Flatpak gives host
/// paths the sandbox can't read, so Linux uses our clipboard channel
/// (linux/my_application.cc), which takes the document portal's copy first.
class ClipboardFiles {
  static const _channel = MethodChannel("im.nether.vommet/clipboard");

  static bool get supported =>
      PlatformUtils.isLinux || PlatformUtils.isWindows || _isMacOS;

  static bool get _isMacOS => !kIsWeb && Platform.isMacOS;

  /// Vommet issue 412: paste is Cmd+V in the macOS app, Ctrl+V elsewhere.
  /// Only Ctrl counted before, so there a copied image or files never got
  /// attached. Not on the web: browsers hand pasted pictures to the DOM
  /// paste event, whichever key pasted them (WebPaste on ci/xplat-web).
  static bool isPasteModifier(
      {required bool control,
      required bool meta,
      TargetPlatform? platform,
      bool web = kIsWeb}) {
    if (web) return control;
    return (platform ?? defaultTargetPlatform) == TargetPlatform.macOS
        ? meta
        : control;
  }

  /// Vommet issue 504: on macOS the pasteboard plugin reads every URL on
  /// the clipboard, not just file URLs, and returns its path, so a link
  /// copied in Safari came back as a "file" ("" or "/some/page") and paste
  /// showed "Couldn't attach file" instead of pasting the link. A copied
  /// link also puts the link itself on the clipboard as text, while files
  /// copied in Finder come with their names; so when the text is a web
  /// link, the clipboard holds no files.
  static List<String> macOSFiles(List<String> paths, String? text) {
    if (isLink(text)) return const [];
    return paths.where((p) => p.startsWith("/")).toList();
  }

  /// Whether [text] is a single link such as `https://example.com/page`
  /// (any scheme with a host, except `file:`).
  static bool isLink(String? text) {
    if (text == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r"\s"))) return false;
    final uri = Uri.tryParse(trimmed);
    return uri != null &&
        uri.scheme.isNotEmpty &&
        uri.scheme != "file" &&
        uri.hasAuthority;
  }

  /// Paths of the copied files, or an empty list.
  static Future<List<String>> read() async {
    if (!supported) return const [];
    try {
      if (PlatformUtils.isLinux) {
        final result =
            await _channel.invokeMapMethod<String, Object?>("readFiles");
        if (result == null) return const [];
        return FileTransfer.parseClipboard(
            result["format"] as String?, result["text"] as String?);
      }
      final paths = await Pasteboard.files();
      if (!_isMacOS) return paths;
      final text = await Clipboard.getData(Clipboard.kTextPlain);
      return macOSFiles(paths, text?.text);
    } catch (e, s) {
      Log.onError(e, s, content: "Reading copied files failed");
      return const [];
    }
  }
}
