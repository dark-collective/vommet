import 'dart:io';

import 'package:commet/utils/file_transfer.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("parseUriList", () {
    test("reads CRLF lists and skips comments and blank lines", () {
      expect(
          FileTransfer.parseUriList(
              "# copied by a file manager\r\nfile:///home/me/a.png\r\n\r\nfile:///home/me/b.txt\r\n"),
          ["/home/me/a.png", "/home/me/b.txt"]);
    });

    test("decodes percent-encoded names", () {
      expect(
          FileTransfer.parseUriList(
              "file:///home/me/My%20Photos/caf%C3%A9%20%231.jpg"),
          ["/home/me/My Photos/café #1.jpg"]);
    });

    test("keeps document portal paths", () {
      expect(
          FileTransfer.parseUriList(
              "file:///run/user/1000/doc/3f2a1b9c/holiday.jpg\n"),
          ["/run/user/1000/doc/3f2a1b9c/holiday.jpg"]);
    });

    test("skips URIs that aren't local files", () {
      expect(
          FileTransfer.parseUriList("https://example.org/a.png\n"
              "sftp://server/home/a.png\n"
              "file://otherhost/home/a.png\n"
              "file://localhost/tmp/ok.png\n"
              "not a uri at all"),
          ["/tmp/ok.png"]);
    });

    test("empty text gives no paths", () {
      expect(FileTransfer.parseUriList(""), isEmpty);
    });
  });

  group("parseGnomeCopiedFiles", () {
    test("copy", () {
      expect(
          FileTransfer.parseGnomeCopiedFiles(
              "copy\nfile:///home/me/a.png\nfile:///home/me/b%20c.pdf"),
          ["/home/me/a.png", "/home/me/b c.pdf"]);
    });

    test("cut", () {
      expect(
          FileTransfer.parseGnomeCopiedFiles("cut\nfile:///tmp/x"), ["/tmp/x"]);
    });

    test("without an action line it isn't a file list", () {
      expect(FileTransfer.parseGnomeCopiedFiles("file:///tmp/x"), isEmpty);
    });
  });

  group("parseClipboard", () {
    test("picks the parser by format", () {
      expect(
          FileTransfer.parseClipboard(
              "x-special/gnome-copied-files", "copy\nfile:///tmp/a"),
          ["/tmp/a"]);
      expect(FileTransfer.parseClipboard("text/uri-list", "file:///tmp/a"),
          ["/tmp/a"]);
    });

    test("nothing on the clipboard", () {
      expect(FileTransfer.parseClipboard(null, null), isEmpty);
      expect(FileTransfer.parseClipboard("text/uri-list", ""), isEmpty);
    });
  });

  group("reading files", () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp("file_transfer_test");
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test("check gives the size of a readable file", () async {
      final file = File("${dir.path}/a.txt");
      await file.writeAsString("hello");
      expect(await FileTransfer.check(file.path), 5);
    });

    test("check gives null for a path the app can't open", () async {
      expect(await FileTransfer.check("${dir.path}/missing.png"), isNull);
      // A directory has no contents to attach.
      expect(await FileTransfer.check(dir.path), isNull);
    });

    test("load keeps readable files and names the others", () async {
      final file = File("${dir.path}/photo.png");
      await file.writeAsBytes([1, 2, 3]);
      final loaded = await FileTransfer.load([
        (path: file.path, name: "photo.png"),
        (path: "${dir.path}/gone.pdf", name: "gone.pdf"),
      ]);
      expect(loaded.unreadable, ["gone.pdf"]);
      expect(loaded.files, hasLength(1));
      expect(loaded.files.single.name, "photo.png");
      expect(loaded.files.single.path, file.path);
      expect(loaded.files.single.size, 3);
      expect(loaded.files.single.data, [1, 2, 3]);
    });

    test("loadPaths names files after their last segment", () async {
      final file = File("${dir.path}/notes.txt");
      await file.writeAsString("x");
      final loaded = await FileTransfer.loadPaths([file.path]);
      expect(loaded.files.single.name, "notes.txt");
    });
  });

  group("unreadableMessage", () {
    test("nothing to say for no files", () {
      expect(FileTransfer.unreadableMessage([]), isNull);
    });

    test("in the Flatpak it explains the sandbox", () {
      final message =
          FileTransfer.unreadableMessage(["a.png", "b.pdf"], inSandbox: true)!;
      expect(message, contains("“a.png”, “b.pdf”"));
      expect(message, contains("Flatpak"));
      expect(message, contains("attach button"));
    });

    test("outside it only names the files", () {
      final message =
          FileTransfer.unreadableMessage(["a.png"], inSandbox: false)!;
      expect(message, contains("“a.png”"));
      expect(message, isNot(contains("Flatpak")));
    });
  });

  group("macOSFiles", () {
    test("a link copied in Safari is not a file (Vommet issue 504)", () {
      expect(ClipboardFiles.macOSFiles([""], "https://example.com"), isEmpty);
      expect(
          ClipboardFiles.macOSFiles(
              ["/some/page.html"], "https://example.com/some/page.html"),
          isEmpty);
      expect(
          ClipboardFiles.macOSFiles(
              ["/etc/hosts"], " https://example.com/etc/hosts\n"),
          isEmpty);
    });

    test("files copied in Finder are kept", () {
      expect(
          ClipboardFiles.macOSFiles(
              ["/Users/me/a.png", "/Users/me/b c.txt"], "a.png\nb c.txt"),
          ["/Users/me/a.png", "/Users/me/b c.txt"]);
      expect(ClipboardFiles.macOSFiles(["/Users/me/a.png"], null),
          ["/Users/me/a.png"]);
      expect(
          ClipboardFiles.macOSFiles(
              ["/Users/me/a.png"], "file:///Users/me/a.png"),
          ["/Users/me/a.png"]);
    });

    test("empty and relative paths are dropped", () {
      expect(ClipboardFiles.macOSFiles(["", "page"], "some text"), isEmpty);
    });
  });

  group("isLink", () {
    test("web links", () {
      expect(ClipboardFiles.isLink("https://example.com/a?b=c#d"), isTrue);
      expect(ClipboardFiles.isLink("http://example.com"), isTrue);
    });

    test("not links", () {
      expect(ClipboardFiles.isLink(null), isFalse);
      expect(ClipboardFiles.isLink(""), isFalse);
      expect(ClipboardFiles.isLink("a.png"), isFalse);
      expect(ClipboardFiles.isLink("file:///Users/me/a.png"), isFalse);
      expect(ClipboardFiles.isLink("see https://example.com"), isFalse);
      expect(ClipboardFiles.isLink("note: today"), isFalse);
    });
  });

  group("isPasteModifier", () {
    test("is Cmd in the macOS app", () {
      expect(
          ClipboardFiles.isPasteModifier(
              control: false,
              meta: true,
              platform: TargetPlatform.macOS,
              web: false),
          isTrue);
      expect(
          ClipboardFiles.isPasteModifier(
              control: true,
              meta: false,
              platform: TargetPlatform.macOS,
              web: false),
          isFalse);
    });

    test("is Cmd on an iPad's keyboard", () {
      expect(
          ClipboardFiles.isPasteModifier(
              control: false,
              meta: true,
              platform: TargetPlatform.iOS,
              web: false),
          isTrue);
      expect(
          ClipboardFiles.isPasteModifier(
              control: true,
              meta: false,
              platform: TargetPlatform.iOS,
              web: false),
          isFalse);
    });

    test("stays Ctrl on the web, where the paste event handles Cmd", () {
      expect(
          ClipboardFiles.isPasteModifier(
              control: false,
              meta: true,
              platform: TargetPlatform.macOS,
              web: true),
          isFalse);
    });

    test("is Ctrl elsewhere", () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.android,
      ]) {
        expect(
            ClipboardFiles.isPasteModifier(
                control: true, meta: false, platform: platform, web: false),
            isTrue);
        expect(
            ClipboardFiles.isPasteModifier(
                control: false, meta: true, platform: platform, web: false),
            isFalse);
      }
    });
  });
}
