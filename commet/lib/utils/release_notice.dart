import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/release_update.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Vommet: tells you when a newer tester release is out, so a notice at the
/// bottom of the app can link to the download page. Checks once per launch,
/// against our own release list (not Commet's update feed), and only in
/// release builds, which are labelled with their release name. Settings ›
/// About can also run the check by hand (Vommet issue 670).
class ReleaseNotice {
  static final Uri releasesUrl = Uri.parse(
      "https://nether.codes/api/v1/repos/nether/vommet/releases?limit=10");

  static final Uri downloadUrl = Uri.parse("https://vommet.app/#download");

  /// The newer release's name, or null when there is none (or it isn't
  /// known yet).
  static final ValueNotifier<String?> newer = ValueNotifier(null);

  /// The newer release's API entry (its files), once [newer] is set.
  static Map<String, dynamic>? newerRelease;

  /// Bumped when a manual check finds a newer release, so the bar shows
  /// again even if it was closed earlier this launch.
  static final ValueNotifier<int> reopen = ValueNotifier(0);

  static final RegExp _name = RegExp(r"^testing-\d{4}-\d{2}-\d{2}[a-z]?");

  /// The release a build's VERSION_TAG names ("testing-2026-10-10d (1754)" →
  /// "testing-2026-10-10d"), or null for other builds.
  static String? releaseName(String versionTag) =>
      _name.firstMatch(versionTag.trim())?.group(0);

  /// Release names sort by date, then by suffix: the bare name is a day's
  /// first release, then b, c, ...
  static bool isNewer(String candidate, String current) =>
      candidate.compareTo(current) > 0;

  /// The newest published release name in a releases API response.
  static String? newestOf(List<dynamic> releases) =>
      newestReleaseOf(releases)?["tag_name"] as String?;

  /// The newest published release in a releases API response.
  static Map<String, dynamic>? newestReleaseOf(List<dynamic> releases) {
    Map<String, dynamic>? newest;
    for (final r in releases.whereType<Map<String, dynamic>>()) {
      if (r["draft"] == true) continue;
      final tag = r["tag_name"];
      if (tag is! String || releaseName(tag) != tag) continue;
      if (newest == null || isNewer(tag, newest["tag_name"] as String)) {
        newest = r;
      }
    }
    return newest;
  }

  /// Whether this build can check for releases (release builds only). Never
  /// on web: the browser blocks the cross-origin request (CORS), and the web
  /// app updates itself on reload anyway.
  static bool get canCheck =>
      !kIsWeb && releaseName(BuildConfig.VERSION_TAG) != null;

  /// Looks for a newer release. The launch-time check respects Settings ›
  /// General › "New releases"; a [manual] check (Settings › About) runs
  /// anyway, since the user asked for it, and re-opens a closed bar.
  static Future<ReleaseCheckResult> check(
      {http.Client? client, bool manual = false, String? versionTag}) async {
    if (kIsWeb) return ReleaseCheckResult.notReleaseBuild;
    if (!manual && !preferences.releaseNotice.value) {
      return ReleaseCheckResult.disabled;
    }
    final current = releaseName(versionTag ?? BuildConfig.VERSION_TAG);
    if (current == null) return ReleaseCheckResult.notReleaseBuild;

    try {
      final response = await (client ?? http.Client())
          .get(releasesUrl)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        Log.w("Release check: HTTP ${response.statusCode}");
        return ReleaseCheckResult.failed;
      }
      final release =
          newestReleaseOf(jsonDecode(response.body) as List<dynamic>);
      final latest = release?["tag_name"] as String?;
      if (latest == null || !isNewer(latest, current)) {
        return ReleaseCheckResult.upToDate;
      }
      final seen = newer.value == latest;
      if (!seen) Log.i("Release check: $latest is out (this is $current)");
      newerRelease = release;
      newer.value = latest;
      if (manual) reopen.value++;
      // Vommet issue 593: "Download automatically" fetches the file now;
      // installing it still takes a tap. Once per release, so a manual
      // re-check doesn't restart a download that already finished.
      if (!seen &&
          preferences.releaseAutoDownload.value &&
          ReleaseUpdate.canDownload(release)) {
        ReleaseUpdate.download(release!);
      }
      return ReleaseCheckResult.newer;
    } catch (e) {
      Log.w("Release check failed: $e");
      return ReleaseCheckResult.failed;
    }
  }
}

enum ReleaseCheckResult {
  /// A newer release is out; [ReleaseNotice.newer] names it.
  newer,

  /// This is the newest release.
  upToDate,

  /// The release list couldn't be fetched or read.
  failed,

  /// Not a release build (no release name in its version tag).
  notReleaseBuild,

  /// Automatic checks are off in Settings › General.
  disabled,
}
