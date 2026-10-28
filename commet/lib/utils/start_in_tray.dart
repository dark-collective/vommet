/// Vommet issue 714: `--start-in-tray` starts the app hidden in the tray,
/// whatever "Close to tray" says, e.g. from an autostart entry. The Linux and
/// Windows runners don't show the window for it, not even the splash; [run]
/// then hides it to the tray once the icon is up or, with no tray, shows it
/// minimized so the app can still be reached. Only that launch is affected.
class StartInTray {
  static const flag = "--start-in-tray";

  /// How long to wait for a tray host, e.g. a panel that starts after the
  /// app at login.
  static const trayWait = Duration(seconds: 10);

  static bool requested(List<String> args) => args.contains(flag);

  static Future<void> run({
    required Future<bool> Function() isVisible,
    required Future<bool> Function(Duration timeout) waitForTray,
    required Future<void> Function() hideToTray,
    required Future<void> Function() showMinimized,
  }) async {
    final tray = await waitForTray(trayWait);
    // Launching the app again meanwhile showed the window: leave it.
    if (await isVisible()) return;
    if (tray) {
      await hideToTray();
    } else {
      await showMinimized();
    }
  }
}
