import 'dart:io';

import 'package:commet/config/xdg_config_dirs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Vommet issue 836: customization folders move to $XDG_CONFIG_HOME on Linux.
void main() {
  late Directory root;
  late String data;
  late String config;
  late Map<String, Object> prefs;

  setUp(() {
    root = Directory.systemTemp.createTempSync("xdg_config_dirs_test");
    data = p.join(root.path, "share", "im.nether.chat");
    config = p.join(root.path, "config", "im.nether.chat");
    prefs = {};
  });

  tearDown(() => root.deleteSync(recursive: true));

  XdgConfigDirs dirs() => XdgConfigDirs(dataDir: data, configDir: config);

  Future<void> migrate() => dirs().migrate(
        readStrings: () => Map.of(prefs),
        writeString: (k, v) async => prefs[k] = v,
        writeStringList: (k, v) async => prefs[k] = v,
      );

  void write(String path, String text) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  test("config folder follows XDG_CONFIG_HOME, else ~/.config", () {
    expect(
        XdgConfigDirs.configDirFor("/h/.local/share/im.nether.chat",
            {"XDG_CONFIG_HOME": "/x/conf", "HOME": "/h"}),
        "/x/conf/im.nether.chat");
    // Flatpak sets XDG_CONFIG_HOME to the app's own folder.
    expect(
        XdgConfigDirs.configDirFor(
            "/h/.var/app/im.nether.chat/data/im.nether.chat", {
          "XDG_CONFIG_HOME": "/h/.var/app/im.nether.chat/config",
          "HOME": "/h"
        }),
        "/h/.var/app/im.nether.chat/config/im.nether.chat");
    // Relative or empty values are ignored (XDG spec).
    expect(
        XdgConfigDirs.configDirFor("/h/.local/share/im.nether.chat",
            {"XDG_CONFIG_HOME": "conf", "HOME": "/h"}),
        "/h/.config/im.nether.chat");
    expect(XdgConfigDirs.configDirFor("/d/im.nether.chat", {}), isNull);
    expect(
        XdgConfigDirs.configDirFor(
            "/d/im.nether.chat", {"XDG_CONFIG_HOME": "/d", "HOME": "/h"}),
        isNull);
  });

  test("a new install uses the config folder", () async {
    await migrate();
    expect(dirs().folderPath("fonts"), p.join(config, "fonts"));
    expect(Directory(config).existsSync(), isFalse);
  });

  test("moves folders, rewrites stored paths, deletes the old one later",
      () async {
    final font = p.join(data, "fonts", "app_font_1.ttf");
    write(font, "font bytes");
    write(p.join(data, "theme", "custom", "Mine", "theme.json"), "{}");
    write(p.join(data, "sounds", "a.ogg"), "sound");
    write(p.join(data, "app_icon", "window-1.png"), "png");
    write(p.join(data, "db", "account", "drift"), "secret");
    prefs["font"] = font;
    prefs["sound"] = '{"file":"${p.join(data, "sounds", "a.ogg")}"}';
    prefs["list"] = [p.join(data, "app_icon", "window-1.png"), "x"];
    prefs["other"] = p.join(data, "fonts_other");

    await migrate();

    final newFont = p.join(config, "fonts", "app_font_1.ttf");
    expect(File(newFont).readAsStringSync(), "font bytes");
    expect(
        File(p.join(config, "theme", "custom", "Mine", "theme.json"))
            .existsSync(),
        isTrue);
    expect(prefs["font"], newFont);
    expect(prefs["sound"], '{"file":"${p.join(config, "sounds", "a.ogg")}"}');
    expect(prefs["list"], [p.join(config, "app_icon", "window-1.png"), "x"]);
    expect(prefs["other"], p.join(data, "fonts_other"));
    // Kept until the next start.
    expect(File(font).existsSync(), isTrue);
    // Data never moves.
    expect(File(p.join(data, "db", "account", "drift")).existsSync(), isTrue);
    expect(Directory(p.join(config, "db")).existsSync(), isFalse);

    await migrate();
    expect(Directory(p.join(data, "fonts")).existsSync(), isFalse);
    expect(Directory(p.join(data, "theme")).existsSync(), isFalse);
    expect(File(newFont).existsSync(), isTrue);
    expect(dirs().folderPath("fonts"), p.join(config, "fonts"));
  });

  test("a leftover half copy from a crash is redone from the original",
      () async {
    write(p.join(data, "sounds", "a.ogg"), "sound");
    write(p.join(data, "sounds", "b.ogg"), "sound b");
    write(p.join(config, ".sounds.moving", "a.ogg"), "so");
    // Before the move, the old folder is still the one in use.
    expect(dirs().folderPath("sounds"), p.join(data, "sounds"));

    await migrate();

    expect(File(p.join(config, "sounds", "a.ogg")).readAsStringSync(), "sound");
    expect(
        File(p.join(config, "sounds", "b.ogg")).readAsStringSync(), "sound b");
    expect(Directory(p.join(config, ".sounds.moving")).existsSync(), isFalse);
  });

  test("a crash after the rename still rewrites paths", () async {
    write(p.join(data, "fonts", "f.ttf"), "f");
    write(p.join(config, "fonts", "f.ttf"), "f");
    prefs["font"] = p.join(data, "fonts", "f.ttf");

    await migrate();

    expect(prefs["font"], p.join(config, "fonts", "f.ttf"));
    expect(File(p.join(data, "fonts", "f.ttf")).existsSync(), isTrue);
  });

  test("an old folder with files the new one lacks is kept", () async {
    write(p.join(config, "theme", "custom", "A", "theme.json"), "{}");
    write(p.join(data, "theme", "custom", "B", "theme.json"), "{}");

    await migrate();

    expect(
        File(p.join(data, "theme", "custom", "B", "theme.json")).existsSync(),
        isTrue);
  });
}
