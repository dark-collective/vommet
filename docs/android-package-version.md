# Android tester package identity (Vommet issue 1191)

The installed package name comes from the existing tester release identity, not
from a new version scheme. `VERSION_TAG=testing-2026-11-05b (185)` names release
`testing-2026-11-05b`; the parenthesized number identifies a CI run, not a release.
Android's Gradle configuration decodes Flutter's `dart-defines` and uses that
release name as `versionName`. The value matches the published release tag that
external trackers compare with the installed package. About retains its full tag.

Only the existing tester label grammar is recognized. Local builds, non-tester
CI fallback labels, and the semver release builder retain their existing Flutter
`--build-name`/pubspec behavior. No channel selection, release generation, updater,
application ID, signing configuration, or versionCode logic changes.

## Evidence without a Flutter build

Published signed CI APKs downloaded from these canonical releases (SHA-256
05b: `823d313d306199ff8d3d70cb6920a37edc0a19f04cc780eb65c0d620220c67a1`;
05c: `a3e9c6d12210771c83058a370a9dc4e26252ed0309cf963cc5b60ea439158cc4`):

- https://nether.codes/nether/vommet/releases/tag/testing-2026-11-05b
- https://nether.codes/nether/vommet/releases/tag/testing-2026-11-05c

`aapt2 dump badging <apk>` reports these actual package values:

| Published APK | Application ID | versionName | versionCode |
| --- | --- | --- | --- |
| 05b | im.nether.chat | 0.5.1 | 445854 |
| 05c | im.nether.chat | 0.5.1 | 446620 |

The targeted regression executes the version configuration in the real
`commet/android/app/build.gradle`, stubbing only Gradle project properties. It
uses the build numbers underlying those APKs (443854 and 444620). On the base,
the 05b assertion fails with `[0.5.1, 443854]`. With the fix the configuration
produces:

| Same build inputs with fix | versionName | arm64 versionCode |
| --- | --- | --- |
| 05b, run 185, build number 443854 | testing-2026-11-05b | 445854 |
| 05c, run 186, build number 444620 | testing-2026-11-05c | 446620 |

The optional `aapt2` probe packages those executed configuration values into
minimal APK binary-manifest fixtures and reads them back. Its actual output is:

```text
package: name='im.nether.chat' versionCode='445854' versionName='testing-2026-11-05b'
package: name='im.nether.chat' versionCode='446620' versionName='testing-2026-11-05c'
```

The same fixture probe on the base reports `versionName='0.5.1'` for both and
fails all four tester-identity cases. These fixtures verify Android metadata
serialization; they are **not rebuilt signed app APKs**. Final packaged metadata requires the CI Android
build; no local Flutter build is needed. The regression also covers the first
release of a day, the following date, labels without a run suffix, non-tester
release/local names, unrelated defines and absent properties.

Run from the repository root with a Groovy runtime (the standalone Groovy core
JAR is sufficient):

```sh
java -cp /path/to/groovy.jar groovy.ui.GroovyMain \
  commet/android/test/package_version_test.groovy
# Include binary-manifest packaging/readback (optional):
AAPT2=/path/to/aapt2 ANDROID_FRAMEWORK_JAR=/path/to/android.jar \
  java -cp /path/to/groovy.jar groovy.ui.GroovyMain \
  commet/android/test/package_version_test.groovy
# Against the base, retaining the new regression:
git show origin/main:commet/android/app/build.gradle > /tmp/base.gradle
java -cp /path/to/groovy.jar groovy.ui.GroovyMain \
  commet/android/test/package_version_test.groovy /tmp/base.gradle
```

## Ordering and compatibility

Release names already sort by UTC date, then suffix: the bare date is first,
then b, c, ... . This is the same identity and order used by `version-tag.sh`
and `ReleaseNotice`; no semver prefix or independent counter is introduced.
Matching package and release names allows trackers to identify an installed
release. The reporter's unspecified Obtainium fork has not been run here, so
its comparison behavior is not independently verified.

Android uses `versionCode`, not versionName, for install downgrade checks. Both
active CI builders already pass the Flutter build number
`floor((UTC epoch seconds - 1767225600) / 60)`. Flutter 3.41.9 adds 2000 for a
split arm64 APK. Thus `versionCode = 2000 + minutes since 2026-01-01 UTC` is
preserved: 445854 < 446620, both above the pubspec fallback 1014 and the former
run-number codes. Rebuilds within one minute can share a code, as before; this
change does not promise strict ordering within a minute or fix older candidates
built later. Release-name order and build-time code order serve different uses.

The application ID stays `im.nether.chat` and existing CI signing keys stay in
use. Existing installs can update under the same signing and code requirements.
The shared Gradle configuration covers Forgejo `.forgejo/workflows/android.yml`
and the mirrored builder `.github/workflows/vommet-android.yml` maintained on
`ci/windows-release`, without requiring the two workflows to duplicate parsing.
The older `scripts/build_release.dart` already passes a semantic build name;
its non-tester behavior is preserved. Other platforms are outside this Android
metadata fix. No sync, unread, receipt, push, call, or hot-path code is touched;
no integration coverage changes are required for those paths.
