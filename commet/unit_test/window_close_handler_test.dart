import 'package:commet/utils/window_close_handler.dart';
import 'package:test/test.dart';

class _Window {
  bool minimizeOnClose = true;
  bool minimized = false;
  bool desktopEnding = false;
  bool closeToTray = false;
  int hideCalls = 0;
  int minimizeCalls = 0;
  int quitCalls = 0;
  int sessionQueries = 0;

  late final WindowCloseHandler handler = WindowCloseHandler(
    minimizeOnClose: () => minimizeOnClose,
    minimize: () async {
      minimizeCalls++;
    },
    quit: () async {
      quitCalls++;
    },
    isMinimized: () async => minimized,
    desktopSessionEnding: () async {
      sessionQueries++;
      return desktopEnding;
    },
    closeToTray: () => closeToTray,
    hideToTray: () async {
      hideCalls++;
    },
  );
}

void main() {
  test("quits on close when Minimize on close is off", () async {
    final w = _Window()..minimizeOnClose = false;
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.minimizeCalls, 0);
    expect(w.sessionQueries, 0);
  });

  test("minimizes a visible window when Minimize on close is on", () async {
    final w = _Window();
    await w.handler.onCloseRequested();
    expect(w.minimizeCalls, 1);
    expect(w.quitCalls, 0);
    expect(w.handler.minimizedByApp, isTrue);
  });

  test("a second close (taskbar Close) after minimizing quits", () async {
    // GTK on Wayland can't tell that the window is minimized, so this relies
    // on the handler remembering that it minimized the window itself.
    final w = _Window();
    await w.handler.onCloseRequested();
    await w.handler.onCloseRequested();
    expect(w.minimizeCalls, 1);
    expect(w.quitCalls, 1);
  });

  test("close of a window the window manager reports minimized quits",
      () async {
    final w = _Window()..minimized = true;
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.minimizeCalls, 0);
  });

  test("restoring the window makes the next close minimize again", () async {
    final w = _Window();
    await w.handler.onCloseRequested();
    w.handler.onWindowShown();
    expect(w.handler.minimizedByApp, isFalse);
    await w.handler.onCloseRequested();
    expect(w.minimizeCalls, 2);
    expect(w.quitCalls, 0);
  });

  test("started with --minimize, a taskbar close quits", () async {
    final w = _Window();
    w.handler.onMinimizedByApp();
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.minimizeCalls, 0);
  });

  test("close during a desktop logout quits", () async {
    final w = _Window()..desktopEnding = true;
    await w.handler.onCloseRequested();
    expect(w.sessionQueries, 1);
    expect(w.quitCalls, 1);
    expect(w.minimizeCalls, 0);
  });

  test("close after the session was reported ending quits", () async {
    final w = _Window();
    w.handler.sessionEnding = true;
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.minimizeCalls, 0);
    expect(w.sessionQueries, 0);
  });

  test("close to tray hides the window, whatever Minimize on close says",
      () async {
    for (final minimize in [false, true]) {
      final w = _Window()
        ..closeToTray = true
        ..minimizeOnClose = minimize;
      await w.handler.onCloseRequested();
      await w.handler.onCloseRequested();
      expect(w.hideCalls, 2);
      expect(w.minimizeCalls, 0);
      expect(w.quitCalls, 0);
    }
  });

  test("close to tray still quits during a desktop logout", () async {
    final w = _Window()
      ..closeToTray = true
      ..desktopEnding = true;
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.hideCalls, 0);
  });

  test("close to tray still quits once the session is ending", () async {
    final w = _Window()..closeToTray = true;
    w.handler.sessionEnding = true;
    await w.handler.onCloseRequested();
    expect(w.quitCalls, 1);
    expect(w.hideCalls, 0);
  });
}
