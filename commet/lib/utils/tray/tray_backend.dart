import 'package:commet/utils/tray/linux_tray.dart';

/// What [AppTray] needs from a platform's tray icon: [LinuxTray]
/// (StatusNotifierItem) or [WindowsTray] (Shell_NotifyIcon, Vommet issue
/// 632).
abstract interface class TrayBackend {
  /// Whether the tray currently shows the icon. Closing to the tray is only
  /// safe while this is true.
  bool get available;

  /// Emits [available] whenever it changes.
  Stream<bool> get onAvailableChanged;

  /// Replaces the icon. [iconName] is a theme icon name (Linux only; an empty
  /// name shows the pixmaps). [description] is the tooltip's second line.
  Future<void> setIcon({
    required String iconName,
    required List<LinuxTrayPixmap> iconPixmaps,
    String description = "",
  });

  /// Changes a menu entry's label, e.g. Show/Hide.
  Future<void> setMenuLabel(int index, String label);

  /// Removes the icon from the tray.
  Future<void> dispose();
}
