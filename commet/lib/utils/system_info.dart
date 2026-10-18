import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// The system lines shown in Settings › About and in the copied bug-report
/// info. Inside the Flatpak sandbox `DeviceInfoPlugin` reads the runtime's
/// os-release (e.g. "GNOME 48"), so there the host's one is used instead.
class SystemInfo {
  static const hostOsReleasePath = "/run/host/os-release";

  final String? name;
  final String? version;
  final String? product;
  final String? displayServer;
  final String? desktopEnvironment;

  const SystemInfo({
    this.name,
    this.version,
    this.product,
    this.displayServer,
    this.desktopEnvironment,
  });

  static Future<SystemInfo> load() async {
    Map<String, dynamic> data = {};
    try {
      data = (await DeviceInfoPlugin().deviceInfo).data;
    } catch (_) {}

    String? hostOsRelease;
    if (PlatformUtils.isFlatpak) {
      try {
        hostOsRelease = await File(hostOsReleasePath).readAsString();
      } catch (_) {}
    }

    return fromDeviceData(
      data,
      hostOsRelease: hostOsRelease,
      displayServer: PlatformUtils.isLinux ? PlatformUtils.displayServer : null,
      desktopEnvironment: PlatformUtils.desktopEnvironment,
    );
  }

  /// [data] is `BaseDeviceInfo.data`; [hostOsRelease] the contents of the
  /// host's os-release when running sandboxed.
  static SystemInfo fromDeviceData(
    Map<String, dynamic> data, {
    String? hostOsRelease,
    String? displayServer,
    String? desktopEnvironment,
  }) {
    String? nonEmpty(Object? value) =>
        value is String && value.isNotEmpty ? value : null;

    var name = nonEmpty(data["name"]);
    var version = nonEmpty(data["version"]);

    if (hostOsRelease != null) {
      final host = parseOsRelease(hostOsRelease);
      final hostName = nonEmpty(host["NAME"]) ?? nonEmpty(host["ID"]);
      if (hostName != null) {
        name = hostName;
        version = nonEmpty(host["VERSION"]) ?? nonEmpty(host["VERSION_ID"]);
      }
    }

    return SystemInfo(
      name: name,
      version: version,
      product: nonEmpty(data["product"]),
      displayServer: displayServer,
      desktopEnvironment: desktopEnvironment,
    );
  }

  /// Parses os-release(5): `KEY=value` lines, values optionally quoted with
  /// backslash escapes; blank lines and `#` comments are skipped.
  static Map<String, String> parseOsRelease(String content) {
    final result = <String, String>{};
    for (var line in content.split("\n")) {
      line = line.trim();
      if (line.isEmpty || line.startsWith("#")) continue;

      final eq = line.indexOf("=");
      if (eq <= 0) continue;

      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();

      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value
            .substring(1, value.length - 1)
            .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
      }

      result[key] = value;
    }
    return result;
  }

  /// The "System Info" lines of a bug report, one per known value.
  String toMarkdown() {
    return [
      if (name != null) "Name: `$name`",
      if (version != null) "Version: `$version`",
      if (product != null) "Product: `$product`",
      if (displayServer != null) "Display Server: `$displayServer`",
      if (desktopEnvironment != null)
        "Desktop Environment: `$desktopEnvironment`",
    ].join("\n");
  }
}
