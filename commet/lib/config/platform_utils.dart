import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:flutter/foundation.dart';

// This exists as a replacement for `Platform` because currently things like `Platform.isLinux` doesnt work on web...
class PlatformUtils {
  static bool get isLinux {
    if (kIsWeb) return false;
    return Platform.isLinux;
  }

  static bool get isWindows {
    if (kIsWeb) return false;
    return Platform.isWindows;
  }

  static bool get isAndroid {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get isWeb {
    return kIsWeb;
  }

  static String get displayServer {
    if (kIsWeb) return "unknown";

    final env = Platform.environment;

    if (env.containsKey("XDG_SESSION_TYPE")) {
      return env["XDG_SESSION_TYPE"]!;
    }

    return "unknown";
  }

  /// The desktop from `XDG_CURRENT_DESKTOP` (e.g. "KDE", "ubuntu:GNOME"), or
  /// null when it isn't set. Flatpak passes it through from the host.
  static String? get desktopEnvironment {
    if (!isLinux) return null;

    return desktopEnvironmentFrom(Platform.environment);
  }

  static String? desktopEnvironmentFrom(Map<String, String> env) {
    final desktop = env["XDG_CURRENT_DESKTOP"];
    if (desktop == null || desktop.isEmpty) return null;
    return desktop;
  }

  /// Whether the app runs inside the Flatpak sandbox.
  static bool get isFlatpak {
    if (!isLinux) return false;

    return BuildConfig.IS_FLATPAK ||
        Platform.environment.containsKey("FLATPAK_ID") ||
        File("/.flatpak-info").existsSync();
  }

  static bool isDesktopEnvironment(DesktopEnvironment desktopEnvironment) {
    if (!isLinux) return false;

    final env = Platform.environment;
    var str = env["XDG_CURRENT_DESKTOP"];

    if (str == null) return false;

    var set = str.split(":").toSet();
    return switch (desktopEnvironment) {
      DesktopEnvironment.KDEPlasma => set.contains("KDE"),
      DesktopEnvironment.GNOME => set.contains("GNOME"),
    };
  }

  static bool isDisplayServer(DisplayServer server) {
    return switch (server) {
      DisplayServer.Wayland => displayServer == "wayland",
      DisplayServer.X11 => displayServer == "x11",
    };
  }
}

enum DisplayServer {
  Wayland,
  X11,
}

enum DesktopEnvironment {
  KDEPlasma,
  GNOME,
}
