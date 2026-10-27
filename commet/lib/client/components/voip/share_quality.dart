import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/double_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';

/// Vommet: the quality of your screen share, as Discord's Go live step:
/// a size (Auto, 720p, 1080p, Source) and a frame rate (15, 30, 60). Asked
/// the first time you share (then remembered, unless "Show this every time"
/// is on) and changeable while you're live (the gear on your stream).
enum ShareResolution {
  auto,
  p720,
  p1080,
  source;

  static ShareResolution parse(String value) =>
      ShareResolution.values.where((r) => r.name == value).firstOrNull ??
      ShareResolution.auto;

  /// The tallest the stream gets sent, or null for as captured.
  int? get height => switch (this) {
        ShareResolution.p720 => 720,
        ShareResolution.p1080 => 1080,
        _ => null,
      };
}

class ShareQuality {
  static final StringPreference resolutionPreference =
      StringPreference("vommet_share_quality", defaultValue: "auto");

  /// 0: the frame rate from Settings › Voice & video.
  static final DoublePreference frameratePreference =
      DoublePreference("vommet_share_fps", defaultValue: 0);

  static final BoolPreference askEveryTime =
      BoolPreference("vommet_share_quality_ask", defaultValue: false);

  static final BoolPreference asked =
      BoolPreference("vommet_share_quality_asked", defaultValue: false);

  static const List<double> framerates = [15, 30, 60];

  /// The quality step shows before sharing.
  static bool get shouldAsk => askEveryTime.value || !asked.value;

  static ShareResolution get resolution =>
      ShareResolution.parse(resolutionPreference.value);

  static double get framerate {
    final fps = frameratePreference.value;
    return fps > 0 ? fps : preferences.streamFramerate.value;
  }

  static Future<void> save(ShareResolution resolution, double framerate,
      {bool? everyTime}) async {
    await resolutionPreference.set(resolution.name);
    await frameratePreference.set(framerate);
    await asked.set(true);
    if (everyTime != null) await askEveryTime.set(everyTime);
  }

  /// The most bits per second to send: Auto keeps the maximum from Settings;
  /// the sizes get what they need at [framerate] (more for 60 fps).
  static int bitrate(ShareResolution resolution, double framerate) {
    final settings = (preferences.streamBitrate.value * 1_000_000).toInt();
    final fast = framerate > 30 ? 1.5 : 1.0;
    return switch (resolution) {
      ShareResolution.auto => settings,
      ShareResolution.p720 => (3_000_000 * fast).toInt(),
      ShareResolution.p1080 => (6_000_000 * fast).toInt(),
      ShareResolution.source =>
        settings > 12_000_000 ? settings : (12_000_000 * fast).toInt(),
    };
  }

  /// Short form for the stream's tag and the settings footer, e.g.
  /// "1080p · 60".
  static String describe(ShareResolution resolution, double framerate,
      {required String auto, required String source}) {
    final size = switch (resolution) {
      ShareResolution.auto => auto,
      ShareResolution.p720 => "720p",
      ShareResolution.p1080 => "1080p",
      ShareResolution.source => source,
    };
    return "$size · ${framerate.round()}";
  }
}

/// Vommet: a call that can change its screen share's quality while live.
abstract class ShareQualityTarget {
  /// Applies [ShareQuality]'s current choice to the share being sent.
  Future<void> applyShareQuality();
}
