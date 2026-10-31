import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:commet/config/theme_store.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:tiamat/config/style/theme_json_converter.dart';

class ThemeConfig {
  static Future<Directory> getCustomThemesDir() async {
    var dir = await getApplicationSupportDirectory();
    var p = dir.path;

    var directory = Directory(path.join(p, "theme", "custom"));
    var exists = await directory.exists();
    if (!exists) {
      directory.create(recursive: true);
    }

    return directory;
  }

  static Future<List<Directory>> getCustomThemes() async {
    var dir = await getCustomThemesDir();

    var directories = await dir.list().where((e) => e is Directory).toList();
    return List<Directory>.from(directories);
  }

  static Future<File?> getFileFromThemeDir(Directory dir) async {
    var file = File(path.join(dir.path, "theme.json"));
    if ((await file.exists()) == false) {
      return null;
    }

    return file;
  }

  static Future<File?> getThemeByName(String name) async {
    var dir = await getCustomThemesDir();
    var themeDir = Directory(path.join(dir.path, name));

    return getFileFromThemeDir(themeDir);
  }

  static Future<void> removeTheme(Directory directory) async {
    await directory.delete(recursive: true);
  }

  static Future<void> installThemeFromZip(File file) async {
    final inputStream = InputFileStream(file.path);

    var dir = await getCustomThemesDir();
    var destination =
        (path.join(dir.path, path.basenameWithoutExtension(file.path)));

    final archive = ZipDecoder().decodeBuffer(inputStream);

    if (!archive.files.any((file) => file.name == "theme.json")) {
      await inputStream.close();
      Log.w("Invalid theme archive: ${file.path}");
      return;
    }

    extractThemeArchive(archive, destination);

    await inputStream.close();
  }

  /// Writes the archive's files into [destination]. Vommet: entry names come
  /// from whoever made the theme, so one like "../../autostart/x.desktop" or
  /// an absolute path is skipped instead of written outside the theme folder.
  static void extractThemeArchive(Archive archive, String destination) {
    for (var file in archive.files) {
      if (file.isFile) {
        final target = path.normalize(path.join(destination, file.name));
        if (!path.isWithin(destination, target)) {
          Log.w("Skipping theme archive entry outside the theme: ${file.name}");
          continue;
        }
        final outputStream = OutputFileStream(target);

        file.writeContent(outputStream);
        outputStream.close();
      }
    }
  }

  // Vommet: on web, custom themes are kept in the browser (IndexedDB) by
  // name, with their background image, instead of in folders.
  static final _webChanges = StreamController<void>.broadcast();

  /// Fires after a theme kept in the browser was saved, imported or deleted.
  static Stream<void> get webThemesChanged => _webChanges.stream;

  static Future<List<String>> getWebThemeNames() => WebThemeStore.names();

  static Future<Map<String, Uint8List>> getWebThemeFiles(String name) =>
      WebThemeStore.files(name);

  static Future<void> saveWebTheme(
      String name, Map<String, Uint8List> files) async {
    await WebThemeStore.put(name, files);
    _webChanges.add(null);
  }

  static Future<void> removeWebTheme(String name) async {
    await WebThemeStore.remove(name);
    _webChanges.add(null);
  }

  /// The theme.json among a stored theme's files, or null.
  static Map<String, dynamic>? webThemeJson(Map<String, Uint8List> files) {
    var bytes = files["theme.json"];
    if (bytes == null) return null;
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
  }

  /// Background images straight from a stored theme's files.
  static ThemeImageResolver memoryImages(Map<String, Uint8List> files) =>
      (name) {
        var bytes = files[name];
        return bytes == null ? null : MemoryImage(bytes);
      };

  /// A theme kept in the browser, or null when there is none by that name.
  static Future<ThemeData?> loadWebTheme(String name) async {
    var files = await WebThemeStore.files(name);
    var json = webThemeJson(files);
    if (json == null) return null;
    return ThemeJsonConverter.fromJson(json, null,
        imageResolver: memoryImages(files));
  }

  /// The files of a theme .zip, or null when it has no theme.json. Entries
  /// that would land outside the theme ("..", absolute) are skipped.
  static Map<String, Uint8List>? themeFilesFromZip(List<int> bytes) {
    var archive = ZipDecoder().decodeBytes(bytes);
    if (!archive.files.any((file) => file.name == "theme.json")) return null;

    var files = <String, Uint8List>{};
    for (var file in archive.files) {
      if (!file.isFile) continue;
      var name = path.posix.normalize(file.name);
      if (path.posix.isAbsolute(name) ||
          name == ".." ||
          name.startsWith("../")) {
        Log.w("Skipping theme archive entry outside the theme: ${file.name}");
        continue;
      }
      files[name] = Uint8List.fromList(file.content as List<int>);
    }
    return files;
  }

  /// Web's + button: stores a picked theme .zip under its file name.
  static Future<void> installWebThemeFromZip(
      String fileName, List<int> bytes) async {
    var files = themeFilesFromZip(bytes);
    if (files == null) {
      Log.w("Invalid theme archive: $fileName");
      return;
    }
    await saveWebTheme(path.basenameWithoutExtension(fileName), files);
  }
}
