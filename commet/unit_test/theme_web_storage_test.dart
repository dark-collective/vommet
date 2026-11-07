import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:commet/config/theme_config.dart';
import 'package:commet/config/theme_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

// Vommet issue 605: on web, custom themes are kept in the browser's storage
// as a name -> files map instead of folders.

ArchiveFile _entry(String name, String text) {
  final bytes = utf8.encode(text);
  return ArchiveFile(name, bytes.length, bytes);
}

Uint8List _zip(List<ArchiveFile> files) {
  final archive = Archive();
  for (final f in files) {
    archive.addFile(f);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('a theme zip becomes its files, skipping entries outside the theme', () {
    final files = ThemeConfig.themeFilesFromZip(_zip([
      _entry("theme.json", "{}"),
      _entry("images/bg.png", "png"),
      _entry("../../evil.txt", "relative"),
      _entry("images/../../evil.txt", "nested"),
      _entry("/etc/evil.txt", "absolute"),
    ]))!;

    expect(files.keys, unorderedEquals(["theme.json", "images/bg.png"]));
    expect(utf8.decode(files["theme.json"]!), "{}");
  });

  test('a zip without theme.json is not a theme', () {
    expect(ThemeConfig.themeFilesFromZip(_zip([_entry("a.txt", "x")])), isNull);
  });

  test('exported files import back unchanged', () {
    final files = {
      "theme.json": Uint8List.fromList(utf8.encode('{"base": "dark"}')),
      "background.png": Uint8List.fromList([1, 2, 3]),
    };
    final back = ThemeConfig.themeFilesFromZip(ThemeDraft.zipFiles(files))!;
    expect(back.keys, unorderedEquals(files.keys));
    expect(back["background.png"], [1, 2, 3]);
    expect(ThemeConfig.webThemeJson(back), {"base": "dark"});
  });

  test('a stored background image opens in the editor by its file name',
      () async {
    final draft = ThemeDraft.fromTheme(ThemeDark.theme, "Pic")
      ..background = ThemeBackground.image
      ..imageFile = "background.png";
    final json = draft.toJson();
    final files = {
      "background.png": Uint8List.fromList([1, 2, 3])
    };

    final theme = await ThemeJsonConverter.fromJson(json, null,
        imageResolver: ThemeConfig.memoryImages(files));
    final image = theme!.extension<FoundationSettings>()!.image;
    expect(image, isA<MemoryImage>());
    expect((image as MemoryImage).bytes, [1, 2, 3]);

    final reopened = ThemeDraft.fromTheme(theme, "Pic", raw: json);
    expect(reopened.background, ThemeBackground.image);
    expect(reopened.imageFile, "background.png");
    expect(reopened.imageIsNew, isFalse);
  });

  test('a theme whose picture is missing still loads, without the picture',
      () async {
    final draft = ThemeDraft.fromTheme(ThemeDark.theme, "Pic")
      ..background = ThemeBackground.image
      ..imageFile = "background.png";
    final theme = await ThemeJsonConverter.fromJson(draft.toJson(), null,
        imageResolver: ThemeConfig.memoryImages(const {}));
    expect(theme, isNotNull);
    expect(theme!.extension<FoundationSettings>()?.image, isNull);
  });

  test('a picked picture (bytes, no path) counts as new until saved', () {
    final draft = ThemeDraft.fromTheme(ThemeDark.theme, "Pic")
      ..background = ThemeBackground.image
      ..imageFile = "cat.jpg"
      ..imageBytes = Uint8List.fromList([9]);
    expect(draft.imageIsNew, isTrue);
    expect(draft.copy().imageBytes, [9]);
  });
}
