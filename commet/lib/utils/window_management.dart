import 'package:commet/telemetry/main_spans.dart';
import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/space.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/app_exit.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/hang_up_on_quit.dart';
import 'package:commet/utils/desktop_session_linux.dart';
import 'package:commet/utils/app_icon.dart';
import 'package:commet/utils/start_in_tray.dart';
import 'package:commet/utils/tray/app_tray.dart';
import 'package:commet/utils/window_close_handler.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagement {
  /// Whether the app manages its own window here (Linux and Windows), so it
  /// can minimize on close and offer [quit].
  static bool get isSupported =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  static Future<void> init() async {
    if (!isSupported) return;

    await windowManager.ensureInitialized();
    _WindowListener listener = _WindowListener();

    windowManager.setPreventClose(true);
    windowManager.addListener(listener);

    _listenForSessionEnd();

    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    EventBus.onSelectedRoomChanged.stream.listen(_onSelectedRoomChanged);
    EventBus.onSelectedSpaceChanged.stream.listen(_onSelectedSpaceChanged);

    // Vommet issue 454: the tray icon, before --minimize so it can start
    // hidden in the tray instead.
    // Vommet: the tray (badge updates, D-Bus) in a span of its own.
    await MainSpans.zone("Tray", AppTray.init, phase: true)
        .timeout(const Duration(seconds: 2), onTimeout: () {});

    // Vommet issue 591: the window icon picked in Settings › Appearance.
    unawaited(AppIcon.init());

    if (StartInTray.requested(commandLineArgs)) {
      unawaited(StartInTray.run(
        isVisible: windowManager.isVisible,
        waitForTray: AppTray.waitUntilAvailable,
        hideToTray: AppTray.hideWindow,
        showMinimized: () async {
          await windowManager.show(inactive: true);
          closeHandler.onMinimizedByApp();
          await windowManager.minimize();
        },
      ));
    } else if (commandLineArgs.contains("--minimize")) {
      if (AppTray.closesToTray) {
        AppTray.hideWindow();
      } else {
        closeHandler.onMinimizedByApp();
        windowManager.minimize();
      }
    }
  }

  static final WindowCloseHandler closeHandler = WindowCloseHandler(
    minimizeOnClose: () => preferences.minimizeOnClose.value,
    minimize: () => windowManager.minimize(),
    quit: quit,
    isMinimized: () => windowManager.isMinimized(),
    desktopSessionEnding: () async =>
        PlatformUtils.isLinux && await kdeSessionIsEnding(),
    closeToTray: () => AppTray.closesToTray,
    hideToTray: AppTray.hideWindow,
  );

  static Future<void>? _quitting;

  /// Quits the app for real, whatever "Minimize on close" says: closes every
  /// client (so their databases are written out) and exits. Safe to call more
  /// than once.
  static Future<void> quit() => _quitting ??= _quit();

  static Future<void> _quit() async {
    // Vommet issue 285: leave calls first, or we stay "in the call".
    if (clientManager != null) {
      await hangUpCallsForQuit(clientManager!.callManager.currentSessions);
    }

    try {
      if (clientManager != null) {
        await Future.wait(clientManager!.clients.map((c) => c.close()))
            .timeout(const Duration(seconds: 5));
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to close clients before quitting");
    }

    await exitApp();
  }

  /// When the session ends, quit instead of minimizing: a logout or shutdown
  /// otherwise waits for the app (Vommet issue 331).
  static void _listenForSessionEnd() {
    void onSessionEnd(String reason) {
      Log.i("Session is ending ($reason), quitting");
      closeHandler.sessionEnding = true;
      quit();
    }

    if (PlatformUtils.isLinux) {
      // systemd stops the session with SIGTERM; SIGHUP when the terminal
      // goes away, SIGINT for Ctrl+C.
      for (final signal in [
        ProcessSignal.sigterm,
        ProcessSignal.sighup,
        ProcessSignal.sigint,
      ]) {
        signal.watch().listen((s) => onSessionEnd(s.name));
      }
    }

    if (PlatformUtils.isWindows) {
      // Sent by the runner on WM_QUERYENDSESSION / WM_ENDSESSION
      // (windows/runner/flutter_window.cpp).
      windowsSessionChannel.setMessageHandler((message) async {
        if (message == "end") onSessionEnd("Windows end session");
        return null;
      });
    }
  }

  static bool _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    return false;
  }

  static void _toggleFullscreen() async {
    var isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
  }

  static String? _currentSpaceName;
  static String? _currentRoomName;

  static void _onSelectedRoomChanged(Room? event) {
    _currentRoomName = event?.displayName;
    _updateTitle();
  }

  static void _onSelectedSpaceChanged(Space? event) {
    _currentSpaceName = event?.displayName;
    _updateTitle();
  }

  static void _updateTitle() {
    final result = [
      _currentRoomName,
      _currentSpaceName,
      BuildConfig.app,
    ].whereNot((a) => a == null).join(" | ");
    windowManager.setTitle(result);
  }
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    super.onWindowClose();

    await WindowManagement.closeHandler.onCloseRequested();
  }

  @override
  void onWindowFocus() {
    WindowManagement.closeHandler.onWindowShown();
    AppTray.onWindowShown();
  }

  @override
  void onWindowRestore() {
    WindowManagement.closeHandler.onWindowShown();
  }
}
