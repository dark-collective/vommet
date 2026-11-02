import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/widgets.dart';

class AppFocus {
  static StreamController _focusStateChanged = StreamController.broadcast();

  static Stream<void> get focusStateChanged => _focusStateChanged.stream;

  static AppLifecycleState? _state = AppLifecycleState.inactive;

  /// Vommet issue 501: on Android, "inactive" means the window is still on
  /// screen but another window has input focus: a chat bubble (shown as a
  /// floating pop-up on some phones), split screen, the notification shade.
  /// Animations froze there while still visible, so Android only counts the
  /// app as unfocused once it is no longer shown.
  static bool get focused =>
      _state == AppLifecycleState.resumed ||
      (PlatformUtils.isAndroid && _state == AppLifecycleState.inactive);

  static void init() {
    _state = WidgetsBinding.instance.lifecycleState;

    WidgetsBinding.instance.addObserver(AppFocusObserver((state) {
      Log.i("App lifecycle state changed: ${state}");

      _state = state;
      _focusStateChanged.add(null);
    }));

    // Vommet issue 501: lets paused animations restart as soon as the pause
    // setting is turned off.
    preferences.pauseAnimationsWhenNotFocused.onChanged
        .listen((_) => _focusStateChanged.add(null));
  }
}

/// Whether [node] belongs to a text field, so focus there must not be moved
/// elsewhere automatically.
bool focusIsOnTextField(FocusNode? node) {
  final context = node?.context;
  if (context == null) return false;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

class AppFocusObserver extends WidgetsBindingObserver {
  final Function(AppLifecycleState state) onStateChanged;

  AppFocusObserver(this.onStateChanged);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onStateChanged(state);
  }
}
