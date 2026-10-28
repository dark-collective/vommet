// ignore_for_file: invalid_use_of_visible_for_testing_member

// Vommet issues 859, 860: the screen share quality (Go live step and the
// stream menu).
import 'package:commet/client/components/voip/share_quality.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _init([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  await preferences.init();
  MediaAutoDownload.resetForTest(network: MediaNetwork.wifi);
  CallDataSaver.updateForTest();
  ShareQuality.resetForTest();
}

void main() {
  setUp(() => _init());

  group("sizes", () {
    test("1440p and 4K exist, between 1080p and Source", () {
      expect(ShareResolution.values, [
        ShareResolution.auto,
        ShareResolution.p720,
        ShareResolution.p1080,
        ShareResolution.p1440,
        ShareResolution.p2160,
        ShareResolution.source,
      ]);
      expect(ShareResolution.p1440.height, 1440);
      expect(ShareResolution.p2160.height, 2160);
      expect(ShareResolution.auto.height, isNull);
      expect(ShareResolution.source.height, isNull);
      expect(ShareResolution.parse("p2160"), ShareResolution.p2160);
      expect(ShareResolution.parse("nope"), ShareResolution.auto);
    });

    test("labels", () {
      String label(ShareResolution r) =>
          ShareQuality.sizeLabel(r, auto: "Auto", source: "Source");
      expect(ShareResolution.values.map(label),
          ["Auto", "720p", "1080p", "1440p", "4K", "Source"]);
      expect(
          ShareQuality.describe(ShareResolution.p2160, 60,
              auto: "Auto", source: "Source"),
          "4K · 60");
    });

    test("Auto is Settings › Stream resolution, 1080p by default", () async {
      expect(ShareQuality.autoHeight, 1080);
      expect(ShareQuality.targetHeight(ShareResolution.auto), 1080);
      await preferences.streamResolution.set("3840x2160");
      expect(ShareQuality.targetHeight(ShareResolution.auto), 2160);
      await preferences.streamResolution.set("garbage");
      expect(ShareQuality.autoHeight, 1080);
    });

    test("the capture is asked for the picked size, never 720p regardless", () {
      expect(ShareQuality.captureSize(ShareResolution.p1440),
          (width: 2560, height: 1440));
      expect(ShareQuality.captureSize(ShareResolution.p2160),
          (width: 3840, height: 2160));
      expect(ShareQuality.captureSize(ShareResolution.source),
          (width: 3840, height: 2160));
      expect(ShareQuality.captureSize(ShareResolution.auto),
          (width: 1920, height: 1080));
      expect(ShareQuality.targetHeight(ShareResolution.source), isNull);
    });
  });

  group("bitrate", () {
    test("per size, half again at 60 fps", () {
      int mbps(ShareResolution r, double fps) =>
          ShareQuality.bitrate(r, fps) ~/ 1000;
      expect(mbps(ShareResolution.p720, 30), 3000);
      expect(mbps(ShareResolution.p720, 60), 4500);
      expect(mbps(ShareResolution.p1080, 30), 6000);
      expect(mbps(ShareResolution.p1080, 60), 9000);
      expect(mbps(ShareResolution.p1440, 15), 10000);
      expect(mbps(ShareResolution.p1440, 30), 10000);
      expect(mbps(ShareResolution.p1440, 60), 15000);
      expect(mbps(ShareResolution.p2160, 30), 20000);
      expect(mbps(ShareResolution.p2160, 60), 30000);
    });

    test("Auto keeps Settings; Source at least 12 Mbps", () async {
      expect(ShareQuality.bitrate(ShareResolution.auto, 60), 8000000);
      expect(ShareQuality.bitrate(ShareResolution.source, 30), 12000000);
      expect(ShareQuality.bitrate(ShareResolution.source, 60), 18000000);
      await preferences.streamBitrate.set(25);
      expect(ShareQuality.bitrate(ShareResolution.source, 60), 25000000);
    });

    test("the hint's numbers", () {
      expect(ShareQuality.mbps(9000000), "9");
      expect(ShareQuality.mbps(4500000), "4.5");
      final sent = ShareQuality.sent(ShareResolution.p1080, 60);
      expect(sent.bitrate, 9000000);
      expect(sent.framerate, 60);
    });
  });

  group("Use less data for calls", () {
    setUp(() => MediaAutoDownload.setNetworkForTest(MediaNetwork.mobile));

    test("only Auto and 720p can be picked", () {
      expect(CallDataSaver.isActive, isTrue);
      expect(ShareResolution.values.where((r) => !r.aboveDataSaver),
          [ShareResolution.auto, ShareResolution.p720]);
    });

    test("caps the size and what's sent", () {
      for (final r in ShareResolution.values) {
        expect(ShareQuality.targetHeight(r), 720, reason: r.name);
      }
      expect(ShareQuality.captureSize(ShareResolution.p2160),
          (width: 1280, height: 720));
      final sent = ShareQuality.sent(ShareResolution.p2160, 60);
      expect(sent.bitrate, CallDataSaver.shareBitrate);
      expect(sent.framerate, CallDataSaver.shareFramerate);
    });
  });

  group("defaults", () {
    test("a fresh install", () {
      expect(ShareQuality.resolution, ShareResolution.auto);
      expect(ShareQuality.framerate, preferences.streamFramerate.value);
      expect(ShareQuality.framerateChoice, 60);
      expect(ShareQuality.codec, ShareCodec.auto);
      expect(ShareQuality.optimize, ShareOptimize.smooth);
      expect(ShareQuality.advancedOpen.value, isFalse);
      expect(preferences.shareSimulcast.value, isTrue);
      expect(ShareQuality.simulcast, isTrue);
    });

    test("Auto codec is the Settings codec", () async {
      expect(ShareQuality.codecName(ShareCodec.auto), "h264");
      await preferences.streamCodec.set("vp9");
      expect(ShareQuality.codecName(ShareCodec.auto), "vp9");
      expect(ShareQuality.codecName(ShareCodec.av1), "av1");
      expect(ShareQuality.codecLabel("h264"), "H.264");
    });

    test("saved choices come back", () async {
      await ShareQuality.save(ShareResolution.p1440, 30,
          codec: ShareCodec.vp9, optimize: ShareOptimize.text);
      expect(ShareQuality.resolution, ShareResolution.p1440);
      expect(ShareQuality.framerate, 30);
      expect(ShareQuality.codec, ShareCodec.vp9);
      expect(ShareQuality.optimize, ShareOptimize.text);
    });

    test("a Settings frame rate that isn't a choice picks the nearest", () {
      expect(ShareQuality.nearestFramerate(24), 30);
      expect(ShareQuality.nearestFramerate(5), 15);
      expect(ShareQuality.nearestFramerate(50), 60);
    });
  });

  group("simulcast", () {
    test("one stream's choice doesn't change Settings", () {
      ShareQuality.simulcast = false;
      expect(ShareQuality.simulcast, isFalse);
      expect(preferences.shareSimulcast.value, isTrue);
    });

    test("cameras keep Use Simulcast", () async {
      await preferences.shareSimulcast.set(false);
      expect(preferences.doSimulcast.value, isTrue);
      expect(ShareQuality.simulcast, isFalse);
    });

    test("Use Simulcast switched off: shares stay without it, once", () async {
      await _init({"livekit_use_simulcast": false});
      expect(preferences.shareSimulcast.value, isFalse);
      expect(ShareQuality.simulcast, isFalse);

      // After that the two are separate.
      await preferences.shareSimulcast.set(true);
      await preferences.init();
      expect(preferences.shareSimulcast.value, isTrue);
      expect(preferences.doSimulcast.value, isFalse);
    });

    test("Use Simulcast on (or never set): shares get it", () async {
      await _init({"livekit_use_simulcast": true});
      expect(preferences.shareSimulcast.value, isTrue);
    });

    test("an explicit share setting wins over the migration", () async {
      await _init({
        "livekit_use_simulcast": false,
        "vommet_share_simulcast": true,
      });
      expect(preferences.shareSimulcast.value, isTrue);
    });
  });
}
