import 'dart:typed_data';

import 'package:commet/client/components/url_preview/bundled_url_preview.dart';
import 'package:commet/client/components/url_preview/link_preview_fetcher_io.dart';
import 'package:commet/client/components/url_preview/outgoing_url_preview.dart';
import 'package:commet/ui/organisms/chat/composer_link_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Vommet issue 676 phase 2: previews this device makes and sends.
void main() {
  final link = Uri.parse("https://lakeside-tours.example/spring");

  group("linkFor", () {
    test("the first previewable http(s) link", () {
      expect(
          OutgoingUrlPreview.linkFor(
              "Trip: https://lakeside-tours.example/spring and https://b.example"),
          link);
    });

    test("skips links written as <url>", () {
      expect(
          OutgoingUrlPreview.linkFor(
              "<https://lakeside-tours.example/spring> or https://b.example/x"),
          Uri.parse("https://b.example/x"));
      expect(
          OutgoingUrlPreview.linkFor("<https://lakeside-tours.example/spring>"),
          isNull);
    });

    test("no preview for matrix.to or text without links", () {
      expect(OutgoingUrlPreview.linkFor("https://matrix.to/#/#room:example"),
          isNull);
      expect(OutgoingUrlPreview.linkFor("no links here"), isNull);
    });
  });

  group("toEntry", () {
    final image = OutgoingPreviewImage(
        bytes: Uint8List(1234),
        mimeType: "image/jpeg",
        width: 800,
        height: 400);
    final preview = OutgoingUrlPreview(
        matchedUrl: link,
        title: "Spring tours",
        description: "Boats leave at nine",
        siteName: "Lakeside Tours",
        image: image);

    test("plain image round-trips through the receive parser", () {
      final entry =
          preview.toEntry(imageMxc: Uri.parse("mxc://example.org/plain"));
      expect(entry["matched_url"], link.toString());
      expect(entry["og:image"], "mxc://example.org/plain");
      expect(entry.containsKey("beeper:image:encryption"), isFalse);

      final parsed = BundledUrlPreview.forLink({
        "body": "https://lakeside-tours.example/spring",
        "com.beeper.linkpreviews": [entry],
      }, link)!;
      expect(parsed.title, "Spring tours");
      expect(parsed.description, "Boats leave at nine");
      expect(parsed.siteName, "Lakeside Tours");
      expect(parsed.imageMxc, Uri.parse("mxc://example.org/plain"));
      expect(parsed.imageSize, 1234);
      expect(parsed.imageWidth, 800);
      expect(parsed.imageHeight, 400);
    });

    test("encrypted image never carries a plain og:image", () {
      final file = {
        "url": "mxc://example.org/enc",
        "mimetype": "image/jpeg",
        "v": "v2",
        "key": {
          "alg": "A256CTR",
          "ext": true,
          "k": "GRAgOUnbbkcd-UWoX5kTiIXJII81qwpSCnxLd5X6pxU",
          "key_ops": ["encrypt", "decrypt"],
          "kty": "oct",
        },
        "iv": "kZeoJfx4ehoAAAAAAAAAAA",
        "hashes": {"sha256": "WDOJYFegjAHNlaJmOhEPpE/3reYeD1pRvPVcta4Tgbg"},
      };
      final entry = preview.toEntry(encryptedImage: file);
      expect(entry.containsKey("og:image"), isFalse);

      final parsed = BundledUrlPreview.fromEntry(entry)!;
      expect(parsed.encryptedImage, isNotNull);
      expect(parsed.imageMxc, Uri.parse("mxc://example.org/enc"));
    });

    test("no image fields when the upload didn't happen", () {
      final entry = preview.toEntry();
      expect(entry.keys.where((k) => k.contains("image")), isEmpty);
      expect(entry["og:title"], "Spring tours");
    });
  });

  group("PageMetadata.parse", () {
    test("reads Open Graph and resolves a relative image", () {
      final meta = PageMetadata.parse("""
<html><head>
<title>Fallback title</title>
<meta property="og:title" content="  Spring
  tours ">
<meta property="og:description" content="Boats leave at nine">
<meta property="og:site_name" content="Lakeside Tours">
<meta property="og:image" content="/img/boat.jpg">
</head></html>""", Uri.parse("https://lakeside-tours.example/spring/"));
      expect(meta.title, "Spring tours");
      expect(meta.description, "Boats leave at nine");
      expect(meta.siteName, "Lakeside Tours");
      expect(
          meta.image, Uri.parse("https://lakeside-tours.example/img/boat.jpg"));
    });

    test("falls back to <title> and the meta description", () {
      final meta = PageMetadata.parse(
          "<title>Plain page</title><meta name=description content=About>",
          link);
      expect(meta.title, "Plain page");
      expect(meta.description, "About");
      expect(meta.image, isNull);
    });

    test("drops non-web images and empty pages", () {
      final meta = PageMetadata.parse(
          '<meta property="og:image" content="file:///etc/passwd">', link);
      expect(meta.image, isNull);
      expect(meta.isEmpty, isTrue);
    });
  });

  group("isPublicAddress", () {
    test("refuses this device and private networks", () {
      for (final raw in [
        [127, 0, 0, 1],
        [10, 1, 2, 3],
        [172, 16, 0, 1],
        [192, 168, 1, 1],
        [169, 254, 169, 254],
        [100, 64, 0, 1],
        [0, 0, 0, 0],
        [224, 0, 0, 1],
        [255, 255, 255, 255],
      ]) {
        expect(isPublicAddress(raw), isFalse, reason: "$raw");
      }
    });

    test("refuses private IPv6 and IPv4 hidden in IPv6", () {
      final loopback = List<int>.filled(16, 0)..[15] = 1;
      final ula = List<int>.filled(16, 0)..[0] = 0xfd;
      final linkLocal = List<int>.filled(16, 0)
        ..[0] = 0xfe
        ..[1] = 0x80;
      final mapped = List<int>.filled(16, 0)
        ..[10] = 0xff
        ..[11] = 0xff
        ..setAll(12, [192, 168, 0, 1]);
      for (final raw in [loopback, ula, linkLocal, mapped]) {
        expect(isPublicAddress(raw), isFalse, reason: "$raw");
      }
    });

    test("allows public addresses", () {
      expect(isPublicAddress([93, 184, 215, 14]), isTrue);
      final global = List<int>.filled(16, 0)
        ..[0] = 0x2a
        ..[1] = 0x01
        ..[15] = 1;
      expect(isPublicAddress(global), isTrue);
      final mapped = List<int>.filled(16, 0)
        ..[10] = 0xff
        ..[11] = 0xff
        ..setAll(12, [93, 184, 215, 14]);
      expect(isPublicAddress(mapped), isTrue);
    });
  });

  test("downscales to 800 px on the longest side and re-encodes", () {
    final source = img.Image(width: 1600, height: 900);
    final out =
        downscaleLinkPreviewImage(Uint8List.fromList(img.encodePng(source)))!;
    expect(out.width, 800);
    expect(out.height, 450);
    expect(out.mimeType, "image/jpeg");
    expect(downscaleLinkPreviewImage(Uint8List.fromList([1, 2, 3])), isNull);
  });

  group("ComposerLinkPreview", () {
    OutgoingUrlPreview made(Uri url) =>
        OutgoingUrlPreview(matchedUrl: url, title: "Title of $url");

    test("fetches after the pause and attaches to the matching message",
        () async {
      final fetched = <Uri>[];
      final composer = ComposerLinkPreview(
          delay: Duration.zero,
          enabled: () => true,
          fetch: (url) async {
            fetched.add(url);
            return made(url);
          });

      composer.update("see https://lakeside-tours.example/spring");
      expect(composer.loading, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fetched, [link]);
      expect(composer.preview?.title, "Title of $link");

      // Typing around the link doesn't fetch again.
      composer.update("see https://lakeside-tours.example/spring !");
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fetched, [link]);

      final sent =
          composer.takeForSend("see https://lakeside-tours.example/spring !");
      expect(sent?.single.matchedUrl, link);
      expect(composer.link, isNull);
    });

    test("× drops the preview for this message", () async {
      final composer = ComposerLinkPreview(
          delay: Duration.zero,
          enabled: () => true,
          fetch: (url) async => made(url));
      composer.update("https://lakeside-tours.example/spring");
      await Future<void>.delayed(const Duration(milliseconds: 10));
      composer.dismiss();
      composer.update("https://lakeside-tours.example/spring ok");
      expect(composer.link, isNull);
      expect(composer.takeForSend("https://lakeside-tours.example/spring ok"),
          isNull);
    });

    test("nothing when switched off or the link changed", () async {
      final off = ComposerLinkPreview(
          delay: Duration.zero,
          enabled: () => false,
          fetch: (url) async => made(url));
      off.update("https://lakeside-tours.example/spring");
      expect(off.link, isNull);

      final composer = ComposerLinkPreview(
          delay: Duration.zero,
          enabled: () => true,
          fetch: (url) async => made(url));
      composer.update("https://lakeside-tours.example/spring");
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(composer.takeForSend("now https://other.example/page"), isNull);
    });
  });
}
