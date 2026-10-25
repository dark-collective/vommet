import 'package:commet/client/components/url_preview/bundled_url_preview.dart';
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/client/components/url_preview/url_preview_suppression.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 676: MSC4095 bundled URL previews on receive.
void main() {
  final link = Uri.parse("https://lakeside-tours.example/spring");

  Map<String, dynamic> content(List<Map<String, dynamic>> previews,
          {String key = "m.url_previews"}) =>
      {
        "msgtype": "m.text",
        "body": "Here's the trip: https://lakeside-tours.example/spring",
        key: previews,
      };

  final encryptedFile = {
    "url": "mxc://example.org/abc",
    "key": {
      "k": "GRAgOUnbbkcd-UWoX5kTiIXJII81qwpSCnxLd5X6pxU",
      "alg": "A256CTR",
      "ext": true,
      "kty": "oct",
      "key_ops": ["encrypt", "decrypt"],
    },
    "iv": "kZeoJfx4ehoAAAAAAAAAAA",
    "hashes": {"sha256": "WDOJYFegjAHNlaJmOhEPpE/3reYeD1pRvPVcta4Tgbg"},
    "v": "v2",
  };

  group("BundledUrlPreview.forLink", () {
    test("reads the stable keys", () {
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matrix:matched_url": link.toString(),
              "og:title": "Spring trip",
              "og:description": "Three days\nby the lake",
              "og:site_name": "Lakeside Tours",
              "og:image": "mxc://example.org/img",
              "og:image:type": "image/jpeg",
              "og:image:width": 800,
              "og:image:height": "400",
              "matrix:image:size": 16588,
            }
          ]),
          link)!;

      expect(preview.title, "Spring trip");
      expect(preview.description, "Three days    by the lake");
      expect(preview.siteName, "Lakeside Tours");
      expect(preview.image, Uri.parse("mxc://example.org/img"));
      expect(preview.imageMxc, Uri.parse("mxc://example.org/img"));
      expect(preview.imageWidth, 800);
      expect(preview.imageHeight, 400);
      expect(preview.imageSize, 16588);
      expect(preview.encryptedImage, isNull);
    });

    test("reads the unstable Beeper keys", () {
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matched_url": link.toString(),
              "og:title": "Spring trip",
              "beeper:image:encryption": encryptedFile,
            }
          ], key: "com.beeper.linkpreviews"),
          link)!;

      expect(preview.title, "Spring trip");
      expect(preview.encryptedImage, isNotNull);
      expect(preview.imageMxc, Uri.parse("mxc://example.org/abc"));
      expect(preview.image, isNull);
    });

    test("an entry with only the matched URL carries no preview", () {
      expect(
          BundledUrlPreview.forLink(
              content([
                {"matrix:matched_url": link.toString()}
              ]),
              link),
          isNull);
    });

    test("only the entry for this link counts", () {
      expect(
          BundledUrlPreview.forLink(
              content([
                {
                  "matrix:matched_url": "https://other.example/",
                  "og:title": "Elsewhere",
                }
              ]),
              link),
          isNull);
    });

    test("no list, no preview", () {
      expect(
          BundledUrlPreview.forLink({"body": link.toString()}, link), isNull);
      expect(BundledUrlPreview.forLink(null, link), isNull);
    });

    test("web image addresses are ignored", () {
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matrix:matched_url": link.toString(),
              "og:title": "Spring trip",
              "og:image": "https://tracker.example/pixel.png",
            }
          ]),
          link)!;

      expect(preview.image, isNull);
      expect(preview.imageMxc, isNull);
    });

    test("an encrypted image without a decrypt key is ignored", () {
      final broken = Map<String, dynamic>.from(encryptedFile)
        ..["key"] = {
          "k": "x",
          "key_ops": ["encrypt"]
        };
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matrix:matched_url": link.toString(),
              "og:title": "Spring trip",
              "matrix:image:encrypted": broken,
            }
          ]),
          link)!;

      expect(preview.encryptedImage, isNull);
      expect(preview.imageMxc, isNull);
    });

    test("an encrypted image must live on mxc", () {
      final web = Map<String, dynamic>.from(encryptedFile)
        ..["url"] = "https://example.org/abc";
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matrix:matched_url": link.toString(),
              "og:title": "Spring trip",
              "matrix:image:encrypted": web,
            }
          ]),
          link)!;

      expect(preview.encryptedImage, isNull);
    });

    test("long text is cut", () {
      final preview = BundledUrlPreview.forLink(
          content([
            {
              "matrix:matched_url": link.toString(),
              "og:title": "x" * 5000,
            }
          ]),
          link)!;

      expect(preview.title!.length, BundledUrlPreview.maxTextLength + 1);
    });
  });

  group("UrlPreviewSuppression with the stable key", () {
    test("matrix:matched_url allows only the listed link", () {
      final body = "$link and https://other.example/";
      final suppression = UrlPreviewSuppression(body, content: {
        "body": body,
        "m.url_previews": [
          {"matrix:matched_url": link.toString()}
        ],
      });

      expect(suppression.allowsPreview(link), isTrue);
      expect(suppression.allowsPreview(Uri.parse("https://other.example/")),
          isFalse);
    });
  });

  group("bundled preview policy", () {
    test("allowed unless previews are turned off", () {
      expect(bundledPreviewsAllowed(encrypted: true), isTrue);
      expect(bundledPreviewsAllowed(encrypted: false), isTrue);
      expect(
          bundledPreviewsAllowed(encrypted: true, userChoice: false), isFalse);
      expect(bundledPreviewsAllowed(encrypted: false, roomDefault: false),
          isFalse);
      expect(
          bundledPreviewsAllowed(
              encrypted: false, roomDefault: false, userChoice: true),
          isTrue);
      // The admins' default only covers unencrypted rooms.
      expect(
          bundledPreviewsAllowed(encrypted: true, roomDefault: false), isTrue);
    });

    test("others' previews ask until the chat is allowed", () {
      expect(resolveBundledPreview(fromSelf: false, askInNewChats: true),
          BundledPreviewDecision.ask);
      expect(
          resolveBundledPreview(
              fromSelf: false, chatAllowed: false, askInNewChats: true),
          BundledPreviewDecision.ask);
      expect(
          resolveBundledPreview(
              fromSelf: false, chatAllowed: true, askInNewChats: true),
          BundledPreviewDecision.show);
      expect(resolveBundledPreview(fromSelf: false, askInNewChats: false),
          BundledPreviewDecision.show);
      expect(resolveBundledPreview(fromSelf: true, askInNewChats: true),
          BundledPreviewDecision.show);
    });

    test("consent content", () {
      expect(bundledConsentFromContent(null), isNull);
      expect(bundledConsentFromContent({"allowed": true}), isTrue);
      expect(bundledConsentFromContent({"allowed": "yes"}), isNull);
    });
  });
}
