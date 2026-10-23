import 'package:commet/utils/release_notice.dart';
import 'package:test/test.dart';

void main() {
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
}
