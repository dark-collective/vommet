import 'dart:convert';

import 'package:commet/main.dart';
import 'package:commet/utils/release_notice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("release name from the build's version tag", () {
    expect(ReleaseNotice.releaseName("testing-2026-10-10d (1754)"),
        "testing-2026-10-10d");
    expect(ReleaseNotice.releaseName("testing-2026-10-10 (1700)"),
        "testing-2026-10-10");
    expect(ReleaseNotice.releaseName("development"), null);
    expect(ReleaseNotice.releaseName("feat/foo.123"), null);
  });

  test("later days and later letters are newer", () {
    expect(ReleaseNotice.isNewer("testing-2026-10-11", "testing-2026-10-10d"),
        isTrue);
    expect(ReleaseNotice.isNewer("testing-2026-10-10b", "testing-2026-10-10"),
        isTrue);
    expect(ReleaseNotice.isNewer("testing-2026-10-10", "testing-2026-10-10b"),
        isFalse);
    expect(ReleaseNotice.isNewer("testing-2026-10-10c", "testing-2026-10-10c"),
        isFalse);
  });

  test("newest published release, skipping drafts and other tags", () {
    expect(
        ReleaseNotice.newestOf([
          {"tag_name": "testing-2026-10-10c", "draft": false},
          {"tag_name": "testing-2026-10-11", "draft": true},
          {"tag_name": "windows-ci-123", "draft": false},
          {"tag_name": "testing-2026-10-10d", "draft": false},
        ]),
        "testing-2026-10-10d");
    expect(ReleaseNotice.newestOf([]), null);
  });

  // Vommet issue 670: Settings › About's manual check needs the outcome.
  group("check() result", () {
    const tag = "testing-2026-10-10b (1700)";
    final releases = jsonEncode([
      {"tag_name": "testing-2026-10-10b", "draft": false},
      {"tag_name": "testing-2026-10-11", "draft": true},
    ]);

    setUp(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await preferences.init();
      ReleaseNotice.newer.value = null;
      ReleaseNotice.newerRelease = null;
    });

    MockClient respond(int status, String body) =>
        MockClient((_) async => http.Response(body, status));

    test("up to date", () async {
      expect(
          await ReleaseNotice.check(
              client: respond(200, releases), manual: true, versionTag: tag),
          ReleaseCheckResult.upToDate);
      expect(ReleaseNotice.newer.value, null);
    });

    test("a newer release is found and re-opens the bar", () async {
      final reopened = ReleaseNotice.reopen.value;
      final newer = jsonEncode([
        {"tag_name": "testing-2026-10-11", "draft": false, "assets": []},
      ]);
      expect(
          await ReleaseNotice.check(
              client: respond(200, newer), manual: true, versionTag: tag),
          ReleaseCheckResult.newer);
      expect(ReleaseNotice.newer.value, "testing-2026-10-11");
      expect(ReleaseNotice.reopen.value, reopened + 1);
    });

    test("network and server failures", () async {
      expect(
          await ReleaseNotice.check(
              client: respond(502, ""), manual: true, versionTag: tag),
          ReleaseCheckResult.failed);
      expect(
          await ReleaseNotice.check(
              client: MockClient((_) => throw http.ClientException("offline")),
              manual: true,
              versionTag: tag),
          ReleaseCheckResult.failed);
    });

    test("dev builds can't check", () async {
      expect(
          await ReleaseNotice.check(
              client: respond(200, releases),
              manual: true,
              versionTag: "development"),
          ReleaseCheckResult.notReleaseBuild);
    });

    test("only the launch check respects the setting", () async {
      await preferences.releaseNotice.set(false);
      expect(
          await ReleaseNotice.check(
              client: respond(200, releases), versionTag: tag),
          ReleaseCheckResult.disabled);
      expect(
          await ReleaseNotice.check(
              client: respond(200, releases), manual: true, versionTag: tag),
          ReleaseCheckResult.upToDate);
    });
  });
}
