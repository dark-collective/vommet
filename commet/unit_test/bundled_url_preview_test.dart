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
      // "Never in this chat" hides them.
      expect(
          resolveBundledPreview(
              fromSelf: false, chatAllowed: false, askInNewChats: true),
          BundledPreviewDecision.hide);
      expect(
          resolveBundledPreview(
              fromSelf: false, chatAllowed: true, askInNewChats: true),
          BundledPreviewDecision.show);
      expect(resolveBundledPreview(fromSelf: false, askInNewChats: false),
          BundledPreviewDecision.show);
      expect(resolveBundledPreview(fromSelf: true, askInNewChats: true),
          BundledPreviewDecision.show);
    });

    test("unencrypted chats show others' previews without asking", () {
      // Vommet issue 779: the homeserver reads those messages anyway.
      expect(
          resolveBundledPreview(
              fromSelf: false, askInNewChats: true, encrypted: false),
          BundledPreviewDecision.show);
      expect(
          resolveBundledPreview(
              fromSelf: false, askInNewChats: true, encrypted: true),
          BundledPreviewDecision.ask);
      // The hide choices still win.
      expect(
          resolveBundledPreview(
              fromSelf: false,
              chatAllowed: false,
              askInNewChats: true,
              encrypted: false),
          BundledPreviewDecision.hide);
      expect(
          resolveBundledPreview(
              fromSelf: false,
              person: BundledPreviewPersonTrust.never,
              askInNewChats: true,
              encrypted: false),
          BundledPreviewDecision.hide);
      expect(
          resolveBundledPreview(
              fromSelf: false,
              chatPreviewsOff: true,
              askInNewChats: true,
              encrypted: false),
          BundledPreviewDecision.hide);
    });

    test("consent content", () {
      expect(bundledConsentFromContent(null), isNull);
      expect(bundledConsentFromContent({"allowed": true}), isTrue);
      expect(bundledConsentFromContent({"allowed": "yes"}), isNull);
    });
  });

  group("whose bundled previews show (resolveBundledPreview)", () {
    const always = BundledPreviewPersonTrust.always;
    const never = BundledPreviewPersonTrust.never;

    BundledPreviewDecision decide({
      bool fromSelf = false,
      bool chatPreviewsOff = false,
      bool? chatAllowed,
      BundledPreviewPersonTrust? person,
      bool trustVerified = false,
      bool fromVerifiedSession = false,
      bool trustContacts = false,
      bool fromContact = false,
      bool ask = true,
    }) =>
        resolveBundledPreview(
            fromSelf: fromSelf,
            chatPreviewsOff: chatPreviewsOff,
            chatAllowed: chatAllowed,
            person: person,
            trustVerified: trustVerified,
            fromVerifiedSession: fromVerifiedSession,
            trustContacts: trustContacts,
            fromContact: fromContact,
            askInNewChats: ask);

    test("your own always show", () {
      expect(decide(fromSelf: true, chatPreviewsOff: true, person: never),
          BundledPreviewDecision.show);
      expect(decide(fromSelf: true, chatAllowed: false),
          BundledPreviewDecision.show);
    });

    test("previews off in the chat hide even trusted people", () {
      expect(decide(chatPreviewsOff: true, person: always),
          BundledPreviewDecision.hide);
      expect(decide(chatPreviewsOff: true, ask: false),
          BundledPreviewDecision.hide);
    });

    test("Never in this chat beats Always and Ask off", () {
      expect(decide(chatAllowed: false, person: always),
          BundledPreviewDecision.hide);
      expect(
          decide(
              chatAllowed: false,
              trustVerified: true,
              fromVerifiedSession: true),
          BundledPreviewDecision.hide);
      expect(
          decide(chatAllowed: false, ask: false), BundledPreviewDecision.hide);
    });

    test("the Never list beats an allowed chat and Ask off", () {
      expect(decide(person: never, chatAllowed: true),
          BundledPreviewDecision.hide);
      expect(decide(person: never, ask: false), BundledPreviewDecision.hide);
      expect(
          decide(person: never, trustVerified: true, fromVerifiedSession: true),
          BundledPreviewDecision.hide);
    });

    test("the Always list shows without asking", () {
      expect(decide(person: always), BundledPreviewDecision.show);
    });

    test("verified people only with the switch on and a verified session", () {
      expect(decide(trustVerified: true, fromVerifiedSession: true),
          BundledPreviewDecision.show);
      expect(decide(trustVerified: true, fromVerifiedSession: false),
          BundledPreviewDecision.ask);
      expect(decide(trustVerified: false, fromVerifiedSession: true),
          BundledPreviewDecision.ask);
    });

    test("contacts only with the switch on (Vommet issue 792)", () {
      expect(decide(trustContacts: true, fromContact: true),
          BundledPreviewDecision.show);
      expect(decide(trustContacts: true, fromContact: false),
          BundledPreviewDecision.ask);
      expect(decide(trustContacts: false, fromContact: true),
          BundledPreviewDecision.ask);
      expect(decide(person: never, trustContacts: true, fromContact: true),
          BundledPreviewDecision.hide);
      expect(decide(chatAllowed: false, trustContacts: true, fromContact: true),
          BundledPreviewDecision.hide);
    });

    test("an allowed chat shows", () {
      expect(decide(chatAllowed: true), BundledPreviewDecision.show);
    });

    test("Ask off shows", () {
      expect(decide(ask: false), BundledPreviewDecision.show);
    });

    test("otherwise ask", () {
      expect(decide(), BundledPreviewDecision.ask);
    });
  });

  group("Always/Never lists", () {
    test("read from account data", () {
      final people = BundledPreviewPeople.fromContent({
        "always": ["@alex:lanterns.chat", 3, ""],
        "never": ["@pip:spamhaven.example"],
      });
      expect(people.always, {"@alex:lanterns.chat"});
      expect(people.never, {"@pip:spamhaven.example"});
      expect(people.trustOf("@alex:lanterns.chat"),
          BundledPreviewPersonTrust.always);
      expect(people.trustOf("@pip:spamhaven.example"),
          BundledPreviewPersonTrust.never);
      expect(people.trustOf("@someone:else.example"), isNull);
      expect(BundledPreviewPeople.fromContent(null).isEmpty, isTrue);
      expect(BundledPreviewPeople.fromContent({"always": "x"}).isEmpty, isTrue);
    });

    test("Never wins when someone is on both", () {
      final people = BundledPreviewPeople.fromContent({
        "always": ["@a:x.example"],
        "never": ["@a:x.example"],
      });
      expect(people.trustOf("@a:x.example"), BundledPreviewPersonTrust.never);
    });

    test("moving someone between lists", () {
      var people = BundledPreviewPeople.empty
          .withTrust("@a:x.example", BundledPreviewPersonTrust.always);
      expect(people.always, {"@a:x.example"});
      people =
          people.withTrust("@a:x.example", BundledPreviewPersonTrust.never);
      expect(people.always, isEmpty);
      expect(people.never, {"@a:x.example"});
      people = people.withTrust("@a:x.example", null);
      expect(people.isEmpty, isTrue);
    });

    test("written back sorted, keeping other keys", () {
      final people = BundledPreviewPeople.empty
          .withTrust("@b:x.example", BundledPreviewPersonTrust.always)
          .withTrust("@a:x.example", BundledPreviewPersonTrust.always);
      expect(people.toContent({"other": 1, "always": []}), {
        "other": 1,
        "always": ["@a:x.example", "@b:x.example"],
        "never": <String>[],
      });
      expect(
          people.sameAs(BundledPreviewPeople.fromContent(people.toContent())),
          isTrue);
    });
  });

  group("unencrypted chats prefer the homeserver", () {
    test("only unencrypted chats with homeserver previews", () {
      expect(homeserverPreviewFirst(encrypted: false, mode: UrlPreviewMode.all),
          isTrue);
      expect(homeserverPreviewFirst(encrypted: true, mode: UrlPreviewMode.all),
          isFalse);
      expect(
          homeserverPreviewFirst(
              encrypted: false, mode: UrlPreviewMode.bundledOnly),
          isFalse);
      expect(homeserverPreviewFirst(encrypted: false, mode: UrlPreviewMode.off),
          isFalse);
    });
  });

  group("site mismatch", () {
    BundledUrlPreview preview(String link,
            {String? ogUrl, String? siteName = "Site"}) =>
        BundledUrlPreview.fromEntry({
          "matrix:matched_url": link,
          "og:title": "Title",
          if (ogUrl != null) "og:url": ogUrl,
          if (siteName != null) "og:site_name": siteName,
        })!;

    test("registrable domain", () {
      expect(BundledUrlPreview.registrableDomain("store.steampowered.com"),
          "steampowered.com");
      expect(BundledUrlPreview.registrableDomain("www.example.com"),
          "example.com");
      expect(BundledUrlPreview.registrableDomain("example.com"), "example.com");
      expect(
          BundledUrlPreview.registrableDomain("news.bbc.co.uk"), "bbc.co.uk");
      expect(BundledUrlPreview.registrableDomain("shop.example.com.au"),
          "example.com.au");
      expect(
          BundledUrlPreview.registrableDomain("Example.COM."), "example.com");
      expect(
          BundledUrlPreview.registrableDomain("192.168.1.10"), "192.168.1.10");
    });

    test("same site, subdomains and www. don't warn", () {
      expect(
          preview("https://store.steampowered.com/app/1",
                  ogUrl: "https://steampowered.com/app/1")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://example.com/a", ogUrl: "https://www.example.com/a")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://m.youtube.com/watch?v=x",
                  ogUrl: "https://www.youtube.com/watch?v=x")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://news.bbc.co.uk/x",
                  ogUrl: "https://www.bbc.co.uk/news/x")
              .mismatchedHost,
          isNull);
    });

    test("another site's og:url warns", () {
      expect(
          preview("https://paypa1-account-check.example/login",
                  ogUrl: "https://www.paypal.com/signin")
              .mismatchedHost,
          "paypal.com");
      // Sharing a public suffix isn't the same site.
      expect(
          preview("https://evil.co.uk/x", ogUrl: "https://bank.co.uk/x")
              .mismatchedHost,
          "bank.co.uk");
    });

    test("without og:url only a domain-like site name counts", () {
      expect(
          preview("https://paypa1-account-check.example/login",
                  siteName: "PayPal")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://paypa1-account-check.example/login",
                  siteName: "paypal.com")
              .mismatchedHost,
          "paypal.com");
      expect(
          preview("https://www.paypal.com/x", siteName: "PayPal.com")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://example.com/x", siteName: "Example Inc.")
              .mismatchedHost,
          isNull);
    });

    test("og:url wins over the site name; non-web og:url is ignored", () {
      expect(
          preview("https://example.com/x",
                  ogUrl: "https://example.com/x", siteName: "other.example")
              .mismatchedHost,
          isNull);
      expect(
          preview("https://example.com/x",
                  ogUrl: "javascript:alert(1)", siteName: "Example")
              .mismatchedHost,
          isNull);
    });
  });
}
