/// Decides what a request to close the main window does (Vommet issue 331).
///
/// With "Minimize on close" off, every close request quits. With it on, a
/// close request only minimizes when it can be the user hiding the window.
/// It quits instead when:
/// - the desktop session is ending (logout, restart, shutdown); KDE Plasma on
///   Wayland closes every window before it logs out and waits up to two
///   minutes for them to go away,
/// - the window is already minimized: a close from the taskbar's menu (or a
///   second close) after the window was closed to the taskbar.
///
/// The title bar's close button and the taskbar's Close send the same request
/// on Linux and Windows, so a close of a visible window still minimizes.
class WindowCloseHandler {
  WindowCloseHandler({
    required this.minimizeOnClose,
    required this.minimize,
    required this.quit,
    required this.isMinimized,
    required this.desktopSessionEnding,
  });

  /// Reads the "Minimize on close" preference.
  final bool Function() minimizeOnClose;

  final Future<void> Function() minimize;

  /// Quits the app for real.
  final Future<void> Function() quit;

  /// Asks the window manager whether the window is minimized. Not every
  /// platform can tell (GTK on Wayland always says no), see [onWindowShown].
  final Future<bool> Function() isMinimized;

  /// Asks the desktop whether it is logging out or shutting down.
  final Future<bool> Function() desktopSessionEnding;

  /// Set once the session is known to end (signal, Windows end-session
  /// message): every close request quits from then on.
  bool sessionEnding = false;

  bool _minimizedByApp = false;

  /// Whether the app minimized the window (on a close request, or at start
  /// with `--minimize`) and the user has not brought it back since.
  bool get minimizedByApp => _minimizedByApp;

  Future<void> onCloseRequested() async {
    if (await _shouldQuit()) {
      await quit();
      return;
    }

    onMinimizedByApp();
    await minimize();
  }

  /// Call when the app minimizes the window by itself.
  void onMinimizedByApp() {
    _minimizedByApp = true;
  }

  /// Call when the window is restored or focused again.
  void onWindowShown() {
    _minimizedByApp = false;
  }

  Future<bool> _shouldQuit() async {
    if (!minimizeOnClose() || sessionEnding || _minimizedByApp) {
      return true;
    }

    if (await isMinimized()) return true;

    return desktopSessionEnding();
  }
}
