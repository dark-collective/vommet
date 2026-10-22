import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:commet/debug/log.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

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
}
