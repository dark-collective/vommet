import 'dart:convert';
import 'dart:io';

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Vommet: the launcher and app menu icon (Vommet issue 681).
///
/// - Android: two launcher entries (activity-alias, AndroidManifest.xml), one
///   per built-in icon; the channel turns one on and the other off.
/// - iOS: the V is an alternate app icon (AppIconV).
/// - macOS: the Dock icon, while the app runs.
/// - Linux: an icon under the packages' icon name in the user's icon theme,
///   which comes before the system's. Not in the Flatpak, whose sandbox
///   can't write there.
///
/// The V is the default: the Android and iOS builds start with it, and
/// [init] puts it in the Dock and the Linux icon theme.
class LauncherIcon {
  static const _channel = MethodChannel("im.nether.vommet/launcher_icon");

  /// The icon name every Linux package's desktop entry uses.
  static const _linuxIconName = "im.nether.chat";

  static bool get _isMacOS => !PlatformUtils.isWeb && Platform.isMacOS;

  static bool get _isLinuxIconTheme =>
      PlatformUtils.isLinux && !PlatformUtils.isFlatpak;

  /// Whether the launcher icon can be picked here.
  static bool get isSupported =>
      PlatformUtils.isAndroid ||
      PlatformUtils.isIOS ||
      _isMacOS ||
      _isLinuxIconTheme;

  /// Whether the launcher can show an uploaded image. Android and iOS only
  /// take icons built into the app.
  static bool get customSupported => _isMacOS || _isLinuxIconTheme;

  /// Puts the picked (or default) icon back where it doesn't last: the Dock
  /// icon is gone when the app quits, and the Linux icon is redone in case
  /// the app's icon changed in an update. Android and iOS keep theirs.
  static Future<void> init() async {
    if (!isSupported) return;
    if (_isMacOS || _isLinuxIconTheme) await apply();
  }

  /// Shows the picked launcher icon.
  static Future<void> apply() async {
    if (!isSupported) return;
    try {
      var design = launcherIconDesign;
      if (design == AppIconDesign.custom && !customSupported) {
        design = AppIconPlace.launcher.defaultDesign;
      }
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        await _channel.invokeMethod(
            "set", design == AppIconDesign.v ? "v" : "original");
      } else if (_isMacOS) {
        await _channel.invokeMethod(
            "setDockIcon",
            design == AppIconDesign.original
                ? null
                : await AppIcon.iconPng(AppIconPlace.launcher, design, 512));
      } else if (_isLinuxIconTheme) {
        await _applyLinux(design);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to set the launcher icon");
    }
  }

  static Future<void> _applyLinux(AppIconDesign design) async {
    final file = _linuxIconFile();
    if (file == null) return;
    if (design == AppIconDesign.original) {
      if (await file.exists()) await file.delete();
    } else {
      final svg = design == AppIconDesign.v
          ? await rootBundle.loadString(design.svgAsset)
          : _svgAroundPng(
              await AppIcon.iconPng(AppIconPlace.launcher, design, 512));
      await file.parent.create(recursive: true);
      await file.writeAsString(svg, flush: true);
    }
    await _refreshLinuxMenus(file.parent.parent.parent);
  }

  /// `$XDG_DATA_HOME/icons/hicolor/scalable/apps/im.nether.chat.svg`, or
  /// null under `flutter test`, which mustn't touch the real icon theme.
  static File? _linuxIconFile() {
    final env = Platform.environment;
    if (env.containsKey("FLUTTER_TEST")) return null;
    var dataHome = env["XDG_DATA_HOME"] ?? "";
    if (dataHome.isEmpty) {
      final home = env["HOME"] ?? "";
      if (home.isEmpty) return null;
      dataHome = p.join(home, ".local", "share");
    }
    return File(p.join(dataHome, "icons", "hicolor", "scalable", "apps",
        "$_linuxIconName.svg"));
  }

  /// An uploaded image as an SVG, so it can stay in the scalable folder that
  /// wins over the packages' own icon.
  static String _svgAroundPng(Uint8List png) =>
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" '
      'width="512" height="512" viewBox="0 0 512 512">'
      '<image width="512" height="512" '
      'xlink:href="data:image/png;base64,${base64Encode(png)}"/></svg>';

  /// Asks app menus to look again. Best effort: some only notice after the
  /// user signs in again.
  static Future<void> _refreshLinuxMenus(Directory theme) async {
    for (final command in [
      ["touch", theme.path],
      ["xdg-desktop-menu", "forceupdate"],
    ]) {
      try {
        await Process.run(command.first, command.sublist(1));
      } catch (_) {}
    }
  }
}
