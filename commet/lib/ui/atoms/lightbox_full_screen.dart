import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Vommet issue 662: full screen in the media viewer on desktop. The app
/// window fills the monitor and the viewer shows only the picture or video:
/// its controls, counter, arrows and thumbnail strip hide. A click on a
/// picture or ESC leaves it; a video keeps its own play / pause and gets a
/// corner X ([LightboxFullScreenExit]) instead.
class LightboxFullScreen {
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Desktops whose window can go full screen (as the call stream view).
  /// Phones have their own full screen for videos ([LightboxSystemBars]).
  static bool get supported => PlatformUtils.isLinux || PlatformUtils.isWindows;

  /// The window calls; swapped by tests.
  static Future<bool> Function() isWindowFullScreen =
      () => windowManager.isFullScreen();
  static Future<void> Function(bool fullScreen) setWindowFullScreen =
      (fullScreen) => windowManager.setFullScreen(fullScreen);

  /// A window that was already full screen (F11, the Steam Deck) stays so.
  static bool _windowWasFullScreen = false;

  /// Window changes run in order, so a quick on / off can't end inverted.
  static Future<void> _window = Future.value();
  static Future<void> get settled => _window;

  static void enter() {
    if (active.value) return;
    active.value = true;
    // Vommet issue 756: on phones (videos only) the system bars hide.
    if (LightboxSystemBars.supported()) {
      LightboxSystemBars.hide(LightboxFullScreen);
      return;
    }
    _window = _window.then((_) async {
      try {
        _windowWasFullScreen = await isWindowFullScreen();
        if (!_windowWasFullScreen) await setWindowFullScreen(true);
      } catch (e, s) {
        Log.onError(e, s, content: "Could not enter full screen");
      }
    });
  }

  static void exit() {
    if (!active.value) return;
    active.value = false;
    if (LightboxSystemBars.supported()) {
      LightboxSystemBars.show(LightboxFullScreen);
      return;
    }
    _window = _window.then((_) async {
      try {
        if (!_windowWasFullScreen) await setWindowFullScreen(false);
      } catch (e, s) {
        Log.onError(e, s, content: "Could not leave full screen");
      }
    });
  }

  /// ESC in the viewer: leaves full screen; false when it wasn't on.
  static bool exitIfActive() {
    if (!active.value) return false;
    exit();
    return true;
  }
}

/// Vommet issues 755 and 756: on phones the viewer hides the status and
/// navigation bars while a picture is zoomed in or a video is full screen,
/// and brings them back once nothing asks for that any more.
class LightboxSystemBars {
  /// Phones and tablets; swapped by tests.
  static bool Function() supported =
      () => PlatformUtils.isAndroid || PlatformUtils.isIOS;

  /// The system call (as the call stream view's full screen); swapped by
  /// tests.
  static Future<void> Function(bool hidden) setHidden = (hidden) =>
      SystemChrome.setEnabledSystemUIMode(
          hidden ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);

  static final Set<Object> _reasons = {};

  static bool get hidden => _reasons.isNotEmpty;

  static void hide(Object reason) => _update(() => _reasons.add(reason));

  static void show(Object reason) => _update(() => _reasons.remove(reason));

  /// Platform messages are handled in the order they are sent, so a quick
  /// hide / show can't end inverted.
  static void _update(void Function() change) {
    final before = hidden;
    change();
    final after = hidden;
    if (before == after || !supported()) return;
    unawaited(setHidden(after).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Could not change the system bars");
    }));
  }
}

/// Around a viewer route: ESC (or back on a phone) leaves full screen, and
/// the window is restored however the viewer closes.
class LightboxFullScreenScope extends StatefulWidget {
  const LightboxFullScreenScope({required this.child, super.key});

  final Widget child;

  @override
  State<LightboxFullScreenScope> createState() =>
      _LightboxFullScreenScopeState();
}

class _LightboxFullScreenScopeState extends State<LightboxFullScreenScope> {
  @override
  void dispose() {
    LightboxFullScreen.exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LightboxFullScreen.active,
      builder: (context, fullScreen, child) => PopScope(
        // Vommet issue 756: back leaves full screen first.
        canPop: !fullScreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) LightboxFullScreen.exit();
        },
        child: CallbackShortcuts(
          // Only while full screen, so ESC otherwise does what it did before.
          bindings: {
            if (fullScreen)
              const SingleActivator(LogicalKeyboardKey.escape):
                  LightboxFullScreen.exit,
          },
          child: child!,
        ),
      ),
      child: Focus(autofocus: true, child: widget.child),
    );
  }
}

/// The semi-transparent X in the corner of a full-screen video. It hides
/// after [hideAfter] without mouse movement and comes back when the mouse
/// moves.
class LightboxFullScreenExit extends StatefulWidget {
  const LightboxFullScreenExit({
    required this.child,
    this.hideAfter = const Duration(seconds: 3),
    super.key,
  });

  final Widget child;
  final Duration hideAfter;

  @override
  State<LightboxFullScreenExit> createState() => _LightboxFullScreenExitState();
}

class _LightboxFullScreenExitState extends State<LightboxFullScreenExit> {
  bool shown = true;
  Timer? hide;

  @override
  void initState() {
    super.initState();
    restartTimer();
  }

  @override
  void dispose() {
    hide?.cancel();
    super.dispose();
  }

  void restartTimer() {
    hide?.cancel();
    hide = Timer(widget.hideAfter, () {
      if (mounted) setState(() => shown = false);
    });
  }

  void onMove() {
    if (!shown) setState(() => shown = true);
    restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => onMove(),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            top: 16,
            right: 16,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !shown,
                child: Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    key: const ValueKey("lightbox_full_screen_exit"),
                    icon: const Icon(Icons.close),
                    color: Colors.white70,
                    onPressed: LightboxFullScreen.exit,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
