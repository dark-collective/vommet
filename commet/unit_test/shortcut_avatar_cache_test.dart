import 'dart:io';
import 'dart:typed_data';

import 'package:commet/cache/file_cache.dart';
import 'package:commet/client/client.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/shortcuts_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 342: a room's shortcut (and the Android conversation
// notifications tied to it) kept the old icon after the avatar changed.

class _MemoryFileCache implements FileCache {
  _MemoryFileCache(this.dir);

  final Directory dir;
  final Map<String, Uint8List> files = {};

  Uri _uri(String identifier) =>
      File("${dir.path}/${files.keys.toList().indexOf(identifier)}").uri;

  @override
  Future<Uri?> getFile(String identifier) async =>
      files.containsKey(identifier) ? _uri(identifier) : null;

  @override
  Future<bool> hasFile(String identifier) async =>
      files.containsKey(identifier);

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    files[identifier] = bytes;
    var uri = _uri(identifier);
    await File.fromUri(uri).writeAsBytes(bytes);
    return uri;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  String get identifier => "client";

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom(this.avatarId);

  @override
  String? avatarId;

  @override
  String get identifier => "!room:example.org";

  @override
  String get displayName => "Room";

  @override
  Color get defaultColor => Colors.blue;

  @override
  Client get client => _FakeClient();

  @override
  Future<ImageProvider?> getShortcutImage() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group("cachedAvatarKey", () {
    String key({String? imageId, ImageProvider? provider}) =>
        ShortcutsManager.cachedAvatarKey(
            identifier: "!room:example.org",
            format: ShortcutIconFormat.jpeg,
            imageId: imageId,
            imageProvider: provider,
            doCircleMask: false);

    test("a changed avatar gets a new key", () {
      expect(key(imageId: "mxc://example.org/old"),
          isNot(key(imageId: "mxc://example.org/new")));
      expect(key(imageId: "mxc://example.org/old"),
          key(imageId: "mxc://example.org/old"));
    });

    test("an image provider's id stands in for a missing image id", () {
      var oldImage = LODImageProvider(id: "mxc://example.org/old-64-512");
      var newImage = LODImageProvider(id: "mxc://example.org/new-64-512");

      expect(key(provider: oldImage), isNot(key(provider: newImage)));
      expect(key(provider: oldImage), contains("mxc://example.org/old"));
      expect(key(imageId: "explicit", provider: oldImage),
          isNot(contains("mxc://example.org/old")));
    });

    test("placeholder, zoom, mask and format stay part of the key", () {
      expect(key(), "shortcutAvatar_!room:example.org_placeholder_zoomed.jpg");
      expect(
          ShortcutsManager.cachedAvatarKey(
              identifier: "@a:b",
              format: ShortcutIconFormat.png,
              imageId: "mxc://b/1",
              shouldZoomOut: false),
          "shortcutAvatar_@a:b_placeholder_mxc://b/1_circle.png");
    });
  });

  group("getCachedAvatarImage", () {
    late _MemoryFileCache cache;

    setUp(() {
      cache = _MemoryFileCache(Directory.systemTemp.createTempSync());
      fileCache = cache;
      isHeadless = false;
    });

    tearDown(() {
      fileCache = null;
      cache.dir.deleteSync(recursive: true);
    });

    testWidgets("returns the image it just generated", (tester) async {
      await tester.runAsync(() async {
        var uri = await ShortcutsManager.getCachedAvatarImage(
            placeholderColor: Colors.blue,
            placeholderText: "Room",
            identifier: "!room:example.org",
            imageId: "mxc://example.org/new",
            format: ShortcutIconFormat.png);

        expect(uri, isNotNull);
        expect(cache.files.keys.single, contains("mxc://example.org/new"));
        expect(File.fromUri(uri!).readAsBytesSync(), cache.files.values.single);
      });
    });

    testWidgets("room shortcut icon is keyed on the room's avatar",
        (tester) async {
      await tester.runAsync(() async {
        var manager = ShortcutsManager();
        var room = _FakeRoom("mxc://example.org/old");

        await manager.createShortcutForRoom(room);
        room.avatarId = "mxc://example.org/new";
        await manager.createShortcutForRoom(room);

        expect(cache.files.keys, hasLength(2));
        expect(cache.files.keys.last, contains("mxc://example.org/new"));
      });
    });
  });
}
