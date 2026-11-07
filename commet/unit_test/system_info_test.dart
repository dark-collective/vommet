import 'package:commet/config/platform_utils.dart';
import 'package:commet/utils/system_info.dart';
import 'package:test/test.dart';

const _kdeNeonOsRelease = '''
PRETTY_NAME="KDE neon 6.4"
NAME="KDE neon"
VERSION_ID="24.04"
VERSION="6.4"
# a comment
ID=neon
ID_LIKE="ubuntu debian"
''';

const _runtimeData = {"name": "GNOME", "version": "48 (Flatpak runtime)"};

void main() {
  group("parseOsRelease", () {
    test("unquotes values and skips comments and blank lines", () {
      final result = SystemInfo.parseOsRelease(_kdeNeonOsRelease);
      expect(result["NAME"], "KDE neon");
      expect(result["VERSION"], "6.4");
      expect(result["ID"], "neon");
      expect(result["ID_LIKE"], "ubuntu debian");
      expect(result.containsKey("# a comment"), isFalse);
    });

    test("handles single quotes and backslash escapes", () {
      final result = SystemInfo.parseOsRelease(
          "NAME='Arch Linux'\nPRETTY_NAME=\"Say \\\"hi\\\" \\\$x\"\nBAD LINE");
      expect(result["NAME"], "Arch Linux");
      expect(result["PRETTY_NAME"], 'Say "hi" \$x');
      expect(result.length, 2);
    });
  });

  group("fromDeviceData", () {
    test("uses the device info outside a sandbox", () {
      final info = SystemInfo.fromDeviceData(_runtimeData);
      expect(info.name, "GNOME");
      expect(info.version, "48 (Flatpak runtime)");
    });

    test("prefers the host os-release over the Flatpak runtime", () {
      final info = SystemInfo.fromDeviceData(_runtimeData,
          hostOsRelease: _kdeNeonOsRelease);
      expect(info.name, "KDE neon");
      expect(info.version, "6.4");
    });

    test("falls back to ID and VERSION_ID", () {
      final info = SystemInfo.fromDeviceData(_runtimeData,
          hostOsRelease: "ID=arch\nVERSION_ID=rolling\n");
      expect(info.name, "arch");
      expect(info.version, "rolling");
    });

    test("keeps the device info when the host os-release is empty", () {
      final info = SystemInfo.fromDeviceData(_runtimeData, hostOsRelease: "");
      expect(info.name, "GNOME");
      expect(info.version, "48 (Flatpak runtime)");
    });

    test("ignores non-string and empty values", () {
      final info = SystemInfo.fromDeviceData(
          {"name": 3, "version": "", "product": "Pixel 8"});
      expect(info.name, isNull);
      expect(info.version, isNull);
    });
  });

  group("fromDeviceData per platform", () {
    test("Android reports the release and API level, not the device", () {
      final info = SystemInfo.fromDeviceData({
        "name": "Alice's Pixel",
        "product": "husky",
        "model": "Pixel 8 Pro",
        "brand": "google",
        "version": {"release": "15", "sdkInt": 35, "codename": "REL"},
      });
      expect(info.name, "Android");
      expect(info.version, "15 (API 35)");
      expect(info.toMarkdown(), "Name: `Android`\nVersion: `15 (API 35)`");
    });

    test("Android without a release still reports the API level", () {
      final info = SystemInfo.fromDeviceData({
        "version": {"release": "", "sdkInt": 34},
      });
      expect(info.name, "Android");
      expect(info.version, "(API 34)");
    });

    test("iOS reports the system, not the device name", () {
      final info = SystemInfo.fromDeviceData({
        "name": "Alice's iPhone",
        "systemName": "iOS",
        "systemVersion": "18.1",
        "model": "iPhone",
        "modelName": "iPhone 16",
      });
      expect(info.name, "iOS");
      expect(info.version, "18.1");
    });

    test("macOS reports the version, not the computer name", () {
      final info = SystemInfo.fromDeviceData({
        "computerName": "Alice's MacBook",
        "model": "Mac15,3",
        "osRelease": "Version 14.1 (Build 23B74)",
        "majorVersion": 14,
        "minorVersion": 1,
        "patchVersion": 0,
      });
      expect(info.name, "macOS");
      expect(info.version, "14.1.0");
    });

    test("Windows reports the version, not the computer or user", () {
      final info = SystemInfo.fromDeviceData({
        "computerName": "ALICE-PC",
        "userName": "alice",
        "productName": "Windows 10 Pro",
        "displayVersion": "23H2",
        "buildNumber": 22631,
      });
      expect(info.name, "Windows");
      expect(info.version, "23H2 (build 22631)");
    });
  });

  test("toMarkdown lists only known values", () {
    final info = SystemInfo.fromDeviceData(_runtimeData,
        hostOsRelease: _kdeNeonOsRelease,
        displayServer: "wayland",
        desktopEnvironment: "KDE");
    expect(
        info.toMarkdown(),
        "Name: `KDE neon`\n"
        "Version: `6.4`\n"
        "Display Server: `wayland`\n"
        "Desktop Environment: `KDE`");
    expect(const SystemInfo().toMarkdown(), "");
  });

  group("desktopEnvironmentFrom", () {
    test("reads XDG_CURRENT_DESKTOP, not the session type", () {
      expect(
          PlatformUtils.desktopEnvironmentFrom(
              {"XDG_CURRENT_DESKTOP": "KDE", "XDG_SESSION_TYPE": "wayland"}),
          "KDE");
    });

    test("is null when unset or empty", () {
      expect(PlatformUtils.desktopEnvironmentFrom({"XDG_SESSION_TYPE": "x11"}),
          isNull);
      expect(PlatformUtils.desktopEnvironmentFrom({"XDG_CURRENT_DESKTOP": ""}),
          isNull);
    });
  });
}
