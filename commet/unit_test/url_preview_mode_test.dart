import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 676 phase 3: one link preview mode per chat.
void main() {
  test("mode names round-trip, unknown and unset are Automatic", () {
    for (final mode in [null, ...UrlPreviewMode.values]) {
      expect(urlPreviewModeFromName(urlPreviewModeName(mode)), mode);
    }
    expect(urlPreviewModeFromName(null), isNull);
    expect(urlPreviewModeFromName("sideways"), isNull);
  });

  group("globalUrlPreviewMode", () {
    test("a stored choice wins", () {
      expect(globalUrlPreviewMode(stored: "off", legacyEncryptedOn: true),
          UrlPreviewMode.off);
      expect(globalUrlPreviewMode(stored: "auto", legacyEncryptedOn: true),
          isNull);
    });

    test("the old encrypted-chats switch becomes Bundled + homeserver", () {
      expect(globalUrlPreviewMode(stored: null, legacyEncryptedOn: true),
          UrlPreviewMode.all);
      expect(
          globalUrlPreviewMode(stored: null, legacyEncryptedOn: false), isNull);
    });
  });

  group("Automatic", () {
    test("bundled only in encrypted chats", () {
      expect(automaticUrlPreviewMode(encrypted: true, roomDefault: true),
          UrlPreviewMode.bundledOnly);
    });

    test("everything in others unless the room turns previews off", () {
      expect(automaticUrlPreviewMode(encrypted: false, roomDefault: null),
          UrlPreviewMode.all);
      expect(automaticUrlPreviewMode(encrypted: false, roomDefault: false),
          UrlPreviewMode.off);
    });
  });

  group("userUrlPreviewMode", () {
    test("Element's switch, with Vommet's bundled marker", () {
      expect(userUrlPreviewMode(elementChoice: null), isNull);
      expect(userUrlPreviewMode(elementChoice: true), UrlPreviewMode.all);
      expect(userUrlPreviewMode(elementChoice: false), UrlPreviewMode.off);
      expect(
          userUrlPreviewMode(
              elementChoice: false, vommetContent: {"mode": "bundled"}),
          UrlPreviewMode.bundledOnly);
      // Element turned previews on later; that wins over the marker.
      expect(
          userUrlPreviewMode(
              elementChoice: true, vommetContent: {"mode": "bundled"}),
          UrlPreviewMode.all);
    });
  });

  group("resolveUrlPreviewMode", () {
    test("room choice, then global choice, then Automatic", () {
      expect(
          resolveUrlPreviewMode(
              encrypted: true,
              userMode: UrlPreviewMode.off,
              globalMode: UrlPreviewMode.all),
          UrlPreviewMode.off);
      expect(
          resolveUrlPreviewMode(
              encrypted: false,
              roomDefault: false,
              globalMode: UrlPreviewMode.bundledOnly),
          UrlPreviewMode.bundledOnly);
      expect(
          resolveUrlPreviewMode(encrypted: true), UrlPreviewMode.bundledOnly);
      expect(resolveUrlPreviewMode(encrypted: false), UrlPreviewMode.all);
    });
  });
}
