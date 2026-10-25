import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:commet/utils/notification_utils.dart';
import 'package:commet/utils/tray/linux_tray.dart';
import 'package:commet/utils/tray/tray_backend.dart';
import 'package:commet/utils/tray/tray_badge.dart';
import 'package:commet/utils/tray/windows_tray.dart';
import 'package:commet/utils/window_management.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';

/// The app's tray icon (Linux, Vommet issue 454; Windows, Vommet issue 632):
/// a left click shows or hides the window; the menu has Show/Hide and Quit.
/// Shown while "Show tray icon" is on and the desktop has a tray
/// (StatusNotifierItem host on Linux). With "Close to tray" on, closing the window hides it instead.
/// With "Unread badge on tray icon" on, the icon carries the taskbar badge's
/// unread count (Vommet issue 536). The icon is the design picked under
/// Settings › Appearance › App icon, in colour or one colour (Vommet issue
/// 591).
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

  static String trayTooltipUnread(int count) => Intl.message("$count unread",
      args: [count],
      name: "trayTooltipUnread",
      desc:
          "Second line of the tray icon's tooltip: how many chats have notifications for the user",
      examples: const {"count": 3});

  static bool get isSupported =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  static const _iconAsset =
      "assets/images/app_icon/app_icon_transparent_cropped.png";
  // Windows' small icon is 16 px at 100 % scaling, 24 at 150 %, 32 at 200 %.
  static List<int> get _iconSizes => PlatformUtils.isWindows
      ? const [16, 20, 24, 32, 48]
      : const [22, 32, 48, 64];

  static TrayBackend? _tray;
  static Future<void>? _starting;
  static StreamSubscription? _availability;
  static bool _hidden = false;

  static String _iconName = "";
  static List<LinuxTrayPixmap> _plainPixmaps = [];
  static final Map<String, List<LinuxTrayPixmap>> _badgePixmaps = {};
  static int _shownUnread = 0;
  static Future<void> _iconUpdate = Future.value();
  static bool _watchingUnread = false;

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

    preferences.trayUnreadBadge.onChanged.listen((_) => _updateBadge());
    appIconDesignPreference.onChanged.listen((_) => _reloadIcon());
    appIconCustomPathPreference.onChanged.listen((_) => _reloadIcon());
    trayIconColoursPreference.onChanged.listen((_) => _reloadIcon());

    if (preferences.showTrayIcon.value) await _start();
  }

  static Future<void> _start() => _starting ??= _doStart();

  static Future<void> _doStart() async {
    try {
      final app = BuildConfig.app;
      _iconName = _themeIconName();
      _plainPixmaps = await _loadPixmaps();
      final menu = [
        LinuxTrayMenuItem(trayMenuHide(app), onClicked: toggleWindow),
        const LinuxTrayMenuItem.separator(),
        LinuxTrayMenuItem(trayMenuQuit(app), onClicked: WindowManagement.quit),
      ];
      final TrayBackend? tray = PlatformUtils.isWindows
          ? await WindowsTray.start(
              title: app,
              iconPixmaps: _plainPixmaps,
              onActivate: toggleWindow,
              menu: menu,
            )
          : await LinuxTray.start(
              id: "im.nether.chat",
              title: app,
              iconName: _iconName,
              iconPixmaps: _plainPixmaps,
              onActivate: toggleWindow,
              menu: menu,
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

      _shownUnread = 0;
      _watchUnread();
      _updateBadge();
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

  /// The Flatpak exports its (original, colour) icon into the host's theme;
  /// elsewhere, or for another design, hosts use the pixmaps.
  static String _themeIconName() =>
      Platform.environment.containsKey("FLATPAK_ID") &&
              appIconDesign != AppIconDesign.custom &&
              trayIconSvgAsset(appIconDesign, trayIconColours) == null
          ? "im.nether.chat"
          : "";

  /// Redraws the icon after the design or its colours changed.
  static void _reloadIcon() {
    _iconUpdate = _iconUpdate.then((_) async {
      if (_tray == null) return;
      try {
        _iconName = _themeIconName();
        _plainPixmaps = await _loadPixmaps();
        _badgePixmaps.clear();
        _shownUnread = -1;
      } catch (e, s) {
        Log.onError(e, s, content: "Failed to redraw the tray icon");
      }
    });
    _updateBadge();
  }

  /// Recounts on the same events as the taskbar badge (LinuxNotifier).
  static void _watchUnread() {
    final manager = clientManager;
    if (_watchingUnread || manager == null) return;
    _watchingUnread = true;
    manager.directMessages.highlightedRoomsList.onListUpdated
        .listen((_) => _updateBadge());
    manager.onSpaceUpdated.stream.listen((_) => _updateBadge());
  }

  /// Puts the current unread count on the icon, one update at a time.
  static void _updateBadge() {
    _iconUpdate = _iconUpdate.then((_) => _applyBadge());
  }

  static Future<void> _applyBadge() async {
    final tray = _tray;
    if (tray == null) return;
    try {
      final count = preferences.trayUnreadBadge.value && clientManager != null
          ? NotificationUtils.getNotificationCounts().$2
          : 0;
      if (count == _shownUnread) return;
      _shownUnread = count;

      if (count == 0) {
        await tray.setIcon(iconName: _iconName, iconPixmaps: _plainPixmaps);
        return;
      }

      final label = trayBadgeLabel(count);
      final pixmaps = _badgePixmaps[label] ??= await _loadBadgePixmaps(label);
      // An icon name would win over the badged pixmaps.
      await tray.setIcon(
          iconName: "",
          iconPixmaps: pixmaps,
          description: trayTooltipUnread(count));
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to update the tray icon's badge");
    }
  }

  static Future<List<LinuxTrayPixmap>> _loadBadgePixmaps(String label) async {
    final icon = await _loadIconImage();
    try {
      return [
        for (final size in _iconSizes) await drawTrayBadge(icon, size, label)
      ];
    } finally {
      icon.dispose();
    }
  }

  /// The icon to draw the badge on.
  static Future<ui.Image> _loadIconImage() async {
    // Vommet issue 681: an uploaded icon.
    if (appIconDesign == AppIconDesign.custom) {
      return AppIcon.renderIcon(AppIconPlace.window, AppIconDesign.custom, 128,
          argb: trayIconColours.argb);
    }
    final svg = trayIconSvgAsset(appIconDesign, trayIconColours);
    if (svg != null) {
      return AppIcon.renderSvg(svg, 128, argb: trayIconColours.argb);
    }
    final data = await rootBundle.load(_iconAsset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  static Future<List<LinuxTrayPixmap>> _loadPixmaps() async {
    if (appIconDesign == AppIconDesign.custom) {
      return [
        for (final size in _iconSizes)
          await _pixmap(
              await AppIcon.renderIcon(
                  AppIconPlace.window, AppIconDesign.custom, size,
                  argb: trayIconColours.argb),
              size)
      ];
    }
    final svg = trayIconSvgAsset(appIconDesign, trayIconColours);
    if (svg != null) {
      return [
        for (final size in _iconSizes)
          await _svgPixmap(svg, size, trayIconColours.argb)
      ];
    }
    final data = await rootBundle.load(_iconAsset);
    final source = img.decodePng(data.buffer.asUint8List());
    if (source == null) return [];
    return [
      for (final size in _iconSizes) LinuxTrayPixmap.fromImage(source, size)
    ];
  }

  /// [asset] drawn at [size] for its own crisp edges at each size.
  static Future<LinuxTrayPixmap> _svgPixmap(
      String asset, int size, int? argb) async {
    return _pixmap(await AppIcon.renderSvg(asset, size, argb: argb), size);
  }

  /// [image] ([size] px square) as a tray pixmap; disposes [image].
  static Future<LinuxTrayPixmap> _pixmap(ui.Image image, int size) async {
    try {
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      if (bytes == null) throw StateError("Could not read the tray icon");
      return LinuxTrayPixmap.fromRgba(size, size, bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
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
