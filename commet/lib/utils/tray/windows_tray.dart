import 'dart:async';
import 'dart:typed_data';

import 'package:commet/utils/tray/linux_tray.dart';
import 'package:commet/utils/tray/tray_backend.dart';
import 'package:flutter/services.dart';

/// A tray icon on Windows (Vommet issue 632), drawn by the runner with
/// Shell_NotifyIcon (windows/runner/tray_icon.cpp) over the channel
/// "im.nether.vommet/tray". The runner adds the icon again by itself when
/// Explorer restarts and reports it through [onAvailableChanged].
class WindowsTray implements TrayBackend {
  WindowsTray._(this._channel, this._title, this._menu, this._onActivate);

  static const defaultChannel = MethodChannel("im.nether.vommet/tray");

  final MethodChannel _channel;
  final String _title;
  final List<LinuxTrayMenuItem> _menu;
  final void Function() _onActivate;

  bool _available = false;
  bool _disposed = false;

  @override
  bool get available => _available;

  final StreamController<bool> _availableChanged = StreamController.broadcast();

  @override
  Stream<bool> get onAvailableChanged => _availableChanged.stream;

  /// Puts an icon in the tray. [onActivate] runs on a left click; [menu] is
  /// the right-click menu. Returns null when the runner has no tray channel.
  static Future<WindowsTray?> start({
    required String title,
    required List<LinuxTrayPixmap> iconPixmaps,
    required void Function() onActivate,
    required List<LinuxTrayMenuItem> menu,
    MethodChannel channel = defaultChannel,
  }) async {
    final tray = WindowsTray._(channel, title, menu, onActivate);
    channel.setMethodCallHandler(tray._handleCall);
    try {
      final added = await channel.invokeMethod<bool>("start", {
        "tooltip": title,
        "icons": encodePixmaps(iconPixmaps),
        "menu": [for (final item in menu) item.label],
      });
      tray._setAvailable(added == true);
      return tray;
    } on MissingPluginException {
      channel.setMethodCallHandler(null);
      return null;
    }
  }

  /// [pixmaps] as the runner reads them.
  static List<Map<String, Object>> encodePixmaps(
          List<LinuxTrayPixmap> pixmaps) =>
      [
        for (final pixmap in pixmaps)
          {
            "width": pixmap.width,
            "height": pixmap.height,
            "argb": Uint8List.fromList(pixmap.argb),
          }
      ];

  Future<void> _handleCall(MethodCall call) async {
    if (_disposed) return;
    switch (call.method) {
      case "activate":
        _onActivate();
      case "menuClicked":
        final index = call.arguments;
        if (index is int && index >= 0 && index < _menu.length) {
          _menu[index].onClicked?.call();
        }
      case "available":
        _setAvailable(call.arguments == true);
    }
  }

  void _setAvailable(bool value) {
    if (value == _available) return;
    _available = value;
    _availableChanged.add(value);
  }

  @override
  Future<void> setIcon({
    required String iconName,
    required List<LinuxTrayPixmap> iconPixmaps,
    String description = "",
  }) =>
      _channel.invokeMethod("setIcon", {
        "tooltip": description.isEmpty ? _title : "$_title\n$description",
        "icons": encodePixmaps(iconPixmaps),
      });

  @override
  Future<void> setMenuLabel(int index, String label) =>
      _channel.invokeMethod("setMenuLabel", {"index": index, "label": label});

  @override
  Future<void> dispose() async {
    _disposed = true;
    _setAvailable(false);
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod("dispose");
    } catch (_) {}
  }
}
