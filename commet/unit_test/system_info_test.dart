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
      expect(info.product, "Pixel 8");
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
