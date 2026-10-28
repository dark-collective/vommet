import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:commet/config/theme_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

ArchiveFile _entry(String name, String text) {
  final bytes = utf8.encode(text);
  return ArchiveFile(name, bytes.length, bytes);
}

void main() {
  late Directory root;
  late String destination;

  setUp(() {
    root = Directory.systemTemp.createTempSync("vommet_theme_zip_");
    destination = path.join(root.path, "themes", "mytheme");
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('writes the theme files inside the theme folder', () {
    final archive = Archive()
      ..addFile(_entry("theme.json", "{}"))
      ..addFile(_entry("images/bg.png", "png"));

    ThemeConfig.extractThemeArchive(archive, destination);

    expect(File(path.join(destination, "theme.json")).readAsStringSync(), "{}");
    expect(
        File(path.join(destination, "images", "bg.png")).existsSync(), isTrue);
  });

  test('skips entries that would land outside the theme folder', () {
    final outside = path.join(root.path, "evil.txt");
    final archive = Archive()
      ..addFile(_entry("theme.json", "{}"))
      ..addFile(_entry("../../evil.txt", "relative"))
      ..addFile(_entry("images/../../../evil.txt", "nested"))
      ..addFile(_entry(outside, "absolute"));

    ThemeConfig.extractThemeArchive(archive, destination);

    expect(File(outside).existsSync(), isFalse);
    expect(File(path.join(destination, "theme.json")).existsSync(), isTrue);
    expect(
        root
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .toList(),
        [path.join(destination, "theme.json")]);
  });
}
