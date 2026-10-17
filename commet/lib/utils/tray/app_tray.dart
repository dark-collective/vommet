import 'dart:async';
import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/tray/linux_tray.dart';
import 'package:commet/utils/window_management.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';

/// The app's tray icon (Linux only for now, Vommet issue 454): a left click
/// shows or hides the window; the menu has Show/Hide and Quit. Shown while
/// "Show tray icon" is on and the desktop has a tray (StatusNotifierItem
/// host). With "Close to tray" on, closing the window hides it instead.
class AppTray {
  static String trayMenuShow(String app) => Intl.message("Show $app",
      args: [app],
      name: "trayMenuShow",
      desc: "Tray icon menu entry that brings the app's window back",
      examples: const {"app": "Vommet"});

  static String trayMenuHide(String app) => Intl.message("Hide $app",
      args: [app],
      name: "trayMenuHide",
      desc: "Tray icon menu entry that hides the app's window to the tray",
      examples: const {"app": "Vommet"});

  static String trayMenuQuit(String app) => Intl.message("Quit $app",
      args: [app],
      name: "trayMenuQuit",
      desc: "Tray icon menu entry that exits the app",
      examples: const {"app": "Vommet"});

  static bool get isSupported => PlatformUtils.isLinux;

  static LinuxTray? _tray;
  static Future<void>? _starting;
  static StreamSubscription? _availability;
  static bool _hidden = false;

  /// Whether a tray host shows the icon right now.
  static bool get available => _tray?.available ?? false;

  /// Whether a close request should hide the window to the tray.
  static bool get closesToTray =>
      isSupported && preferences.closeToTray.value && available;

  static Future<void> init() async {
    if (!isSupported) return;

    preferences.showTrayIcon.onChanged.listen((show) {
      if (show) {
        _start();
      } else {
        _stop();
      }
    });

    if (preferences.showTrayIcon.value) await _start();
  }

  static Future<void> _start() => _starting ??= _doStart();

  static Future<void> _doStart() async {
    try {
      final app = BuildConfig.app;
      final tray = await LinuxTray.start(
        id: "im.nether.chat",
        title: app,
        // The Flatpak exports its icon into the host's theme; elsewhere the
        // name may not resolve, so hosts use the pixmaps.
        iconName: Platform.environment.containsKey("FLATPAK_ID")
            ? "im.nether.chat"
            : "",
        iconPixmaps: await _loadPixmaps(),
        onActivate: toggleWindow,
        menu: [
          LinuxTrayMenuItem(trayMenuHide(app), onClicked: toggleWindow),
          const LinuxTrayMenuItem.separator(),
          LinuxTrayMenuItem(trayMenuQuit(app),
              onClicked: WindowManagement.quit),
        ],
      );
      if (tray == null) {
        _starting = null;
        return;
      }

      _tray = tray;
      _availability = tray.onAvailableChanged.listen((available) {
        Log.i("Tray icon ${available ? "shown" : "no longer shown"}");
        // Never leave the window hidden with no icon to bring it back.
        if (!available && _hidden) showWindow();
      });
      Log.i("Tray icon ${tray.available ? "shown" : "waiting for a tray"}");
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to start the tray icon");
      _starting = null;
    }
  }

  static Future<void> _stop() async {
    await _starting;
    final tray = _tray;
    _tray = null;
    _starting = null;
    await _availability?.cancel();
    _availability = null;
    if (_hidden) await showWindow();
    await tray?.dispose();
  }

  static Future<List<LinuxTrayPixmap>> _loadPixmaps() async {
    final data = await rootBundle
        .load("assets/images/app_icon/app_icon_transparent_cropped.png");
    final source = img.decodePng(data.buffer.asUint8List());
    if (source == null) return [];
    return [
      for (final size in [22, 32, 48, 64])
        LinuxTrayPixmap.fromImage(source, size)
    ];
  }

  static Future<void> toggleWindow() async {
    // Go by the window's real state: other code shows it too (a notification
    // click, launching the app again).
    if (!await windowManager.isVisible() || await windowManager.isMinimized()) {
      await showWindow();
    } else {
      await hideWindow();
    }
  }

  /// Hides the window to the tray (only while the icon is shown).
  static Future<void> hideWindow() async {
    if (!available) return;
    _hidden = true;
    await windowManager.hide();
    await _tray?.setMenuLabel(0, trayMenuShow(BuildConfig.app));
  }

  /// Call when the window came back by other means (e.g. the app was
  /// launched again), so the menu says Hide again.
  static void onWindowShown() {
    if (!_hidden) return;
    _hidden = false;
    _tray?.setMenuLabel(0, trayMenuHide(BuildConfig.app));
  }

  static Future<void> showWindow() async {
    _hidden = false;
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
    await _tray?.setMenuLabel(0, trayMenuHide(BuildConfig.app));
  }
}
