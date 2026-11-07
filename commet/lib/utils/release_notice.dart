import 'dart:async';
import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/release_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

  /// Whether this build can check for releases (release builds only). On
  /// web the browser blocks the release list (CORS), so the web app checks
  /// its own site's [webVersionFile] instead (Vommet issue 975); any labelled
  /// web build can do that.
  static bool get canCheck => kIsWeb
      ? isLabelled(BuildConfig.VERSION_TAG)
      : releaseName(BuildConfig.VERSION_TAG) != null;

  /// Written next to index.html by the web build (vommet-web.yml):
  /// {"version_tag": ..., "git_hash": ...}, the VERSION_TAG the build was
  /// made with. Relative, so it works from any path the app is served at.
  static const String webVersionFile = "vommet-version.json";

  /// How often an open web app looks for a new version, and how soon after
  /// one check returning to the tab may check again.
  static const Duration webInterval = Duration(hours: 3);
  static const Duration webThrottle = Duration(minutes: 10);

  static DateTime? _lastWebCheck;
  static AppLifecycleListener? _webLifecycle;

  /// Whether a build carries a CI label (local builds say "development").
  static bool isLabelled(String versionTag) =>
      versionTag.trim().isNotEmpty && versionTag.trim() != "development";

  /// Web: checks now, every [webInterval], and when the tab is shown or
  /// focused again, at most once per [webThrottle]. Started once by the bar.
  static void watchWeb() {
    if (_webLifecycle != null) return;
    _webLifecycle =
        AppLifecycleListener(onShow: autoCheckWeb, onResume: autoCheckWeb);
    Timer.periodic(webInterval, (_) => autoCheckWeb());
    autoCheckWeb();
  }

  /// A throttled automatic web check; null when skipped (too soon).
  static Future<ReleaseCheckResult?> autoCheckWeb(
      {http.Client? client, String? versionTag, DateTime? now}) async {
    now ??= DateTime.now();
    final last = _lastWebCheck;
    if (last != null && now.difference(last) < webThrottle) return null;
    _lastWebCheck = now;
    return checkWeb(client: client, versionTag: versionTag);
  }

  /// For tests: lets the next automatic web check run at once.
  static void resetWebThrottle() => _lastWebCheck = null;

  /// The web check: same-origin [webVersionFile], so no CORS. Any version
  /// other than this build's counts (a rollback asks for a reload too); the
  /// bar then offers to reload the page. A missing or unreadable file (dev
  /// servers, old images) does nothing.
  static Future<ReleaseCheckResult> checkWeb(
      {http.Client? client, bool manual = false, String? versionTag}) async {
    if (!manual && !preferences.releaseNotice.value) {
      return ReleaseCheckResult.disabled;
    }
    final current = (versionTag ?? BuildConfig.VERSION_TAG).trim();
    if (!isLabelled(current)) return ReleaseCheckResult.notReleaseBuild;

    try {
      final url = Uri.base.resolve(webVersionFile).replace(
          queryParameters: {"t": "${DateTime.now().millisecondsSinceEpoch}"});
      final response = await (client ?? http.Client()).get(url, headers: {
        "Cache-Control": "no-cache"
      }).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        Log.d("Web version check: HTTP ${response.statusCode}");
        return ReleaseCheckResult.failed;
      }
      final json = jsonDecode(response.body);
      final served = json is Map ? json["version_tag"] : null;
      if (served is! String || !isLabelled(served)) {
        Log.d("Web version check: no version_tag in $webVersionFile");
        return ReleaseCheckResult.failed;
      }
      if (served.trim() == current) return ReleaseCheckResult.upToDate;
      final name = releaseName(served) ?? served.trim();
      if (newer.value != name) {
        Log.i("Web version check: $served is served (this is $current)");
      }
      newerRelease = null;
      newer.value = name;
      if (manual) reopen.value++;
      return ReleaseCheckResult.newer;
    } catch (e) {
      Log.d("Web version check failed: $e");
      return ReleaseCheckResult.failed;
    }
  }

  /// Looks for a newer release. The launch-time check respects Settings ›
  /// General › "New releases"; a [manual] check (Settings › About) runs
  /// anyway, since the user asked for it, and re-opens a closed bar.
  static Future<ReleaseCheckResult> check(
      {http.Client? client, bool manual = false, String? versionTag}) async {
    if (kIsWeb) {
      return checkWeb(client: client, manual: manual, versionTag: versionTag);
    }
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
