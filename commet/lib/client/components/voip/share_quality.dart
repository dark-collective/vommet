import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/call_data_saver.dart';

/// Vommet: the quality of your screen share, as Discord's Go live step:
/// a size (Auto, 720p, 1080p, 1440p, 4K, Source) and a frame rate (15, 30,
/// 60), plus Advanced (codec, optimize for, simulcast). Chosen each time you
/// share, in the source picker, and changeable while you're live (the gear
/// on your stream). Vommet issues 859, 860.
enum ShareResolution {
  auto,
  p720,
  p1080,
  p1440,
  p2160,
  source;

  static ShareResolution parse(String value) =>
      ShareResolution.values.where((r) => r.name == value).firstOrNull ??
      ShareResolution.auto;

  /// The tallest the stream gets sent, or null for Auto (see
  /// [ShareQuality.autoHeight]) and Source (as captured).
  int? get height => switch (this) {
        ShareResolution.p720 => 720,
        ShareResolution.p1080 => 1080,
        ShareResolution.p1440 => 1440,
        ShareResolution.p2160 => 2160,
        _ => null
      };

  /// Can't be picked while "Use less data for calls" is on (that sends
  /// 720p at most).
  bool get aboveDataSaver => switch (this) {
        ShareResolution.auto || ShareResolution.p720 => false,
        _ => true
      };
}

/// Vommet: the video codec of a share. Auto: the codec from Settings ›
/// Voice & video.
enum ShareCodec {
  auto,
  h264,
  vp9,
  av1;

  static ShareCodec parse(String value) =>
      ShareCodec.values.where((c) => c.name == value).firstOrNull ??
      ShareCodec.auto;
}

/// Vommet: what the encoder keeps when the connection can't carry it all:
/// the frame rate (games, video) or the resolution (text, code, slides).
enum ShareOptimize {
  smooth,
  text;

  static ShareOptimize parse(String value) =>
      ShareOptimize.values.where((o) => o.name == value).firstOrNull ??
      ShareOptimize.smooth;
}

/// Vommet issue 903: the lower qualities a screen share also sends
/// (simulcast), so viewers on a slow link or a busy computer can step down.
/// Auto: 720p and 360p (1080p and 360p above 1440p); Light: one half-size
/// copy (LiveKit's default); Off: none.
enum ShareLowerQualities {
  auto,
  light,
  off;

  static ShareLowerQualities parse(String value) =>
      ShareLowerQualities.values.where((q) => q.name == value).firstOrNull ??
      ShareLowerQualities.auto;
}

/// One lower quality of a share: its height, bits per second and frame rate.
typedef ShareLayer = ({int height, int bitrate, double framerate});

class ShareQuality {
  static final StringPreference resolutionPreference =
      StringPreference("vommet_share_quality", defaultValue: "auto");

  /// 0: the frame rate from Settings › Voice & video.
  static final DoublePreference frameratePreference =
      DoublePreference("vommet_share_fps", defaultValue: 0);

  static final StringPreference codecPreference =
      StringPreference("vommet_share_codec", defaultValue: "auto");

  static final StringPreference optimizePreference =
      StringPreference("vommet_share_optimize", defaultValue: "smooth");

  /// The picker's Advanced section is open.
  static final BoolPreference advancedOpen =
      BoolPreference("vommet_share_advanced_open", defaultValue: false);

  static const List<double> framerates = [15, 30, 60];

  static ShareResolution get resolution =>
      ShareResolution.parse(resolutionPreference.value);

  static double get framerate {
    final fps = frameratePreference.value;
    return fps > 0 ? fps : preferences.streamFramerate.value;
  }

  /// [framerate], or the nearest of [framerates] when Settings has another.
  static double get framerateChoice => nearestFramerate(framerate);

  static double nearestFramerate(double fps) =>
      framerates.reduce((a, b) => (a - fps).abs() <= (b - fps).abs() ? a : b);

  static ShareCodec get codec => ShareCodec.parse(codecPreference.value);

  static ShareOptimize get optimize =>
      ShareOptimize.parse(optimizePreference.value);

  /// The codec from Settings › Voice & video (what Auto uses).
  static String get settingsCodec => preferences.streamCodec.value;

  /// The codec name LiveKit gets for [codec].
  static String codecName(ShareCodec codec) =>
      codec == ShareCodec.auto ? settingsCodec : codec.name;

  static ShareLowerQualities? _lowerQualities;

  /// The lower qualities for the current (or next) share: what the Go live
  /// step or the stream menu picked, else the setting. Never written back
  /// to Settings.
  static ShareLowerQualities get lowerQualities =>
      _lowerQualities ??
      ShareLowerQualities.parse(preferences.shareLowerQualities.value);
  static set lowerQualities(ShareLowerQualities value) =>
      _lowerQualities = value;

  /// Whether the share sends lower qualities at all.
  static bool get simulcast => lowerQualities != ShareLowerQualities.off;

  /// What [lowerQualities] sends now: Auto acts like Light while "Use less
  /// data for calls" is on.
  static ShareLowerQualities get effectiveLowerQualities =>
      lowerQualities == ShareLowerQualities.auto && CallDataSaver.isActive
          ? ShareLowerQualities.light
          : lowerQualities;

  /// Back to the setting (tests).
  static void resetForTest() => _lowerQualities = null;

  /// The smallest copy's frame rate and bitrate (previews watch it).
  static const double smallestFramerate = 15;
  static const int smallestBitrate = 300_000;

  /// Vommet issue 903: the lower qualities of a share sent [height] tall at
  /// [framerate], smallest first. Empty for Light and Off (Light leaves
  /// LiveKit's one half-size copy). Auto: 360p, plus 720p above 720p, or
  /// 1080p above 1440p.
  static List<ShareLayer> lowerLayers(
      ShareLowerQualities choice, int height, double framerate) {
    if (choice != ShareLowerQualities.auto || height <= 360) return const [];
    final fast = framerate > 30;
    final ShareLayer smallest = (
      height: 360,
      bitrate: smallestBitrate,
      framerate: framerate < smallestFramerate ? framerate : smallestFramerate
    );
    if (height <= 720) return [smallest];
    final ShareLayer middle = height > 1440
        ? (
            height: 1080,
            bitrate: bitrate(ShareResolution.p1080, framerate),
            framerate: framerate
          )
        : (
            height: 720,
            bitrate: fast ? 2_250_000 : 1_500_000,
            framerate: framerate
          );
    return [smallest, middle];
  }

  /// The size Auto sends at most: the height of Settings › Voice & video ›
  /// Stream resolution (1080 unless changed).
  static int get autoHeight {
    final parts = preferences.streamResolution.value.split("x");
    if (parts.length == 2) {
      final h = int.tryParse(parts[1]);
      if (h != null && h > 0) return h;
    }
    return 1080;
  }

  /// The tallest the share gets sent with [resolution], or null for as
  /// captured; "Use less data for calls" caps it.
  static int? targetHeight(ShareResolution resolution) {
    int? target =
        resolution == ShareResolution.auto ? autoHeight : resolution.height;
    if (CallDataSaver.isActive &&
        (target == null || target > CallDataSaver.shareHeight)) {
      target = CallDataSaver.shareHeight;
    }
    return target;
  }

  /// The size asked of the capture: 16:9 at [targetHeight], or 4K for as
  /// captured, so a browser never captures below the choice. Desktop and
  /// Android capture ignore it (the encoder scales, see
  /// MatrixLivekitVoipSession.applyShareQuality).
  static ({int width, int height}) captureSize(ShareResolution resolution) {
    final h = targetHeight(resolution) ?? 2160;
    return (width: (h * 16 / 9).round(), height: h);
  }

  static Future<void> save(ShareResolution resolution, double framerate,
      {ShareCodec? codec, ShareOptimize? optimize}) async {
    await resolutionPreference.set(resolution.name);
    await frameratePreference.set(framerate);
    if (codec != null) await codecPreference.set(codec.name);
    if (optimize != null) await optimizePreference.set(optimize.name);
  }

  /// The most bits per second to send: Auto keeps the maximum from Settings;
  /// the sizes get what they need at [framerate] (half again for 60 fps).
  static int bitrate(ShareResolution resolution, double framerate) {
    final settings = (preferences.streamBitrate.value * 1_000_000).toInt();
    final fast = framerate > 30 ? 1.5 : 1.0;
    return switch (resolution) {
      ShareResolution.auto => settings,
      ShareResolution.p720 => (3_000_000 * fast).toInt(),
      ShareResolution.p1080 => (6_000_000 * fast).toInt(),
      ShareResolution.p1440 => (10_000_000 * fast).toInt(),
      ShareResolution.p2160 => (20_000_000 * fast).toInt(),
      ShareResolution.source =>
        settings > 12_000_000 ? settings : (12_000_000 * fast).toInt()
    };
  }

  /// What a share with these choices sends at most, after "Use less data
  /// for calls".
  static ({double framerate, int bitrate}) sent(
      ShareResolution resolution, double framerate) {
    final caps = CallDataSaver.screenShare(
        width: 1 << 16,
        height: 1 << 16,
        framerate: framerate,
        bitrate: bitrate(resolution, framerate));
    return (framerate: caps.framerate, bitrate: caps.bitrate);
  }

  /// Megabits per second for the hint: "9", "4.5".
  static String mbps(int bitrate) {
    final m = bitrate / 1_000_000;
    return m == m.roundToDouble() ? m.round().toString() : m.toStringAsFixed(1);
  }

  /// The size's short label: "1080p", "4K", or [auto] / [source].
  static String sizeLabel(ShareResolution resolution,
          {required String auto, required String source}) =>
      switch (resolution) {
        ShareResolution.auto => auto,
        ShareResolution.p720 => "720p",
        ShareResolution.p1080 => "1080p",
        ShareResolution.p1440 => "1440p",
        ShareResolution.p2160 => "4K",
        ShareResolution.source => source
      };

  /// How a codec reads: "H.264", "VP9", "AV1".
  static String codecLabel(String codec) => switch (codec.toLowerCase()) {
        "h264" => "H.264",
        "h265" => "H.265",
        "vp8" => "VP8",
        "vp9" => "VP9",
        "av1" => "AV1",
        _ => codec.toUpperCase()
      };

  /// Short form for the stream's tag and the settings footer, e.g.
  /// "1080p · 60".
  static String describe(ShareResolution resolution, double framerate,
      {required String auto, required String source}) {
    final size = sizeLabel(resolution, auto: auto, source: source);
    return "$size · ${framerate.round()}";
  }
}

/// Vommet: a call that can change its screen share's quality while live.
abstract class ShareQualityTarget {
  /// Applies [ShareQuality]'s size, frame rate and optimize-for to the
  /// share being sent, live.
  Future<void> applyShareQuality();

  /// The share can be restarted without asking the system again (for a
  /// codec or simulcast change). Not with the Wayland portal, in a browser
  /// or on Android, which would show their prompt again.
  bool get canRestartShare;

  /// Republishes the share with [ShareQuality]'s codec and simulcast.
  Future<void> restartShare();
}
