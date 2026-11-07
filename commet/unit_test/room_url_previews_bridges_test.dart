// Vommet: per-room URL preview settings (Element's storage and order) and the
// Bridges tab's reading of m.bridge / uk.half-shot.bridge.
import 'package:commet/client/components/url_preview/url_preview_room_policy.dart';
import 'package:commet/ui/pages/settings/categories/room/bridges/room_bridges_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('URL previews in a room', () {
    test('reads {"disable": bool}', () {
      expect(previewsEnabledFromContent({"disable": true}), isFalse);
      expect(previewsEnabledFromContent({"disable": false}), isTrue);
      expect(previewsEnabledFromContent({}), isNull);
      expect(previewsEnabledFromContent({"disable": "yes"}), isNull);
      expect(previewsEnabledFromContent(null), isNull);
    });

    test('unencrypted: own choice, then room default, then on', () {
      expect(
          resolveRoomUrlPreviews(
              encrypted: false, roomDefault: null, encryptedGlobal: false),
          isTrue);
      expect(
          resolveRoomUrlPreviews(
              encrypted: false, roomDefault: false, encryptedGlobal: true),
          isFalse);
      expect(
          resolveRoomUrlPreviews(
              encrypted: false,
              userChoice: true,
              roomDefault: false,
              encryptedGlobal: false),
          isTrue);
      expect(
          resolveRoomUrlPreviews(
              encrypted: false,
              userChoice: false,
              roomDefault: true,
              encryptedGlobal: true),
          isFalse);
    });

    test(
        'encrypted: own choice, then the app-wide preference; room default '
        'ignored', () {
      expect(
          resolveRoomUrlPreviews(
              encrypted: true, roomDefault: true, encryptedGlobal: false),
          isFalse);
      expect(
          resolveRoomUrlPreviews(
              encrypted: true, roomDefault: false, encryptedGlobal: true),
          isTrue);
      expect(
          resolveRoomUrlPreviews(
              encrypted: true,
              userChoice: true,
              roomDefault: false,
              encryptedGlobal: false),
          isTrue);
    });

    test('encrypted choice keeps the other web settings', () {
      final content = {"foo": 1, urlPreviewsE2eeKey: false};
      expect(webSettingsWithPreviews(content, true),
          {"foo": 1, urlPreviewsE2eeKey: true});
      expect(webSettingsWithPreviews(content, null), {"foo": 1});
      expect(webSettingsWithPreviews(null, false), {urlPreviewsE2eeKey: false});
      expect(
          previewsEnabledFromWebSettings({urlPreviewsE2eeKey: true}), isTrue);
      expect(previewsEnabledFromWebSettings({}), isNull);
    });
  });

  group('room bridges', () {
    Map<String, Object?> bridge(String protocol, {String? channel}) => {
          "bridgebot": "@bridgebot:example.org",
          "creator": "@alice:example.org",
          "protocol": {
            "id": protocol.toLowerCase(),
            "displayname": protocol,
            "avatar_url": "mxc://example.org/abc",
          },
          "network": {"id": "n1", "displayname": "Example Network"},
          if (channel != null) "channel": {"id": "c1", "displayname": channel},
        };

    test('reads both event types, m.bridge first, one per state key', () {
      final bridges = parseRoomBridges({
        "uk.half-shot.bridge": {
          "a": bridge("Old name"),
          "b": bridge("IRC", channel: "#lobby"),
        },
        "m.bridge": {
          "a": bridge("Telegram", channel: "Example chat"),
        },
      });
      expect(bridges.map((b) => b.protocol.label), ["Telegram", "IRC"]);
      expect(bridges.first.channel?.label, "Example chat");
      expect(bridges.first.network?.label, "Example Network");
      expect(bridges.first.bridgeBot, "@bridgebot:example.org");
      expect(bridges.first.creator, "@alice:example.org");
      expect(
          bridges.first.protocol.avatarUrl, Uri.parse("mxc://example.org/abc"));
    });

    test('leaves out events without a protocol; falls back to ids', () {
      final bridges = parseRoomBridges({
        "m.bridge": {
          "x": {"bridgebot": "@b:example.org"},
          "y": {
            "protocol": {"id": "slack"},
            "channel": {"id": "C123", "displayname": "  "},
          },
        },
      });
      expect(bridges, hasLength(1));
      expect(bridges.single.protocol.label, "slack");
      expect(bridges.single.channel?.label, "C123");
      expect(bridges.single.bridgeBot, isNull);
    });

    test('no bridge events: empty', () {
      expect(parseRoomBridges({}), isEmpty);
    });
  });
}
