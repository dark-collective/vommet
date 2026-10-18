import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Vommet: tells you when a newer tester release is out, so a notice at the
/// bottom of the app can link to the download page. Checks once per launch,
/// against our own release list (not Commet's update feed), and only in
/// release builds, which are labelled with their release name.
class ReleaseNotice {
  static final Uri releasesUrl = Uri.parse(
      "https://nether.codes/api/v1/repos/nether/vommet/releases?limit=10");

  static final Uri downloadUrl = Uri.parse("https://vommet.app/#download");

  /// The newer release's name, or null when there is none (or it isn't
  /// known yet).
  static final ValueNotifier<String?> newer = ValueNotifier(null);

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
  static String? newestOf(List<dynamic> releases) {
    String? newest;
    for (final r in releases.whereType<Map<String, dynamic>>()) {
      if (r["draft"] == true) continue;
      final tag = r["tag_name"];
      if (tag is! String || releaseName(tag) != tag) continue;
      if (newest == null || isNewer(tag, newest)) newest = tag;
    }
    return newest;
  }

  static Future<void> check({http.Client? client}) async {
    if (!preferences.releaseNotice.value) return;
    final current = releaseName(BuildConfig.VERSION_TAG);
    if (current == null) return;

    try {
      final response = await (client ?? http.Client())
          .get(releasesUrl)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        Log.w("Release check: HTTP ${response.statusCode}");
        return;
      }
      final latest = newestOf(jsonDecode(response.body) as List<dynamic>);
      if (latest != null && isNewer(latest, current)) {
        Log.i("Release check: $latest is out (this is $current)");
        newer.value = latest;
      }
    } catch (e) {
      Log.w("Release check failed: $e");
    }
  }
}
