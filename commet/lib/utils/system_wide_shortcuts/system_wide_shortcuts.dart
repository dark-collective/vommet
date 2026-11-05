import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/system_wide_shortcuts/key_release.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts_linux.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intl/intl.dart';

class SystemWideShortcuts {
  static void init() async {
    if (PlatformUtils.isLinux) {
      SystemWideShortcutsLinux.init();
    }

    // Vommet: push to talk also works while Vommet is focused, where
    // system wide shortcuts don't (Wayland, Flatpak).
    HardwareKeyboard.instance.addHandler(_handleInAppPushToTalk);

    // Vommet: every saved key is read before any is registered. Upstream
    // set them one by one, and each set saved all of them, so the ones not
    // read yet were saved as none: only the first shortcut survived a
    // restart. A key that can't be registered system wide is still kept
    // (the in-app push to talk key uses it).
    for (var shortcut in shortcuts.entries) {
      shortcut.value.hotkey = preferences.getSystemHotkey(shortcut.key);
    }
    for (var shortcut in shortcuts.entries) {
      final hotkey = shortcut.value.hotkey;
      if (hotkey == null) continue;
      try {
        await shortcut.value._register(hotkey);
      } catch (e) {
        Log.w("Could not register the ${shortcut.key} shortcut: $e");
      }
    }
  }

  /// Vommet: whether the push to talk key works while you're in another app
  /// (it needs the key's release, see [KeyRelease]).
  static bool get pushToTalkWorksEverywhere =>
      isSupported &&
      !BuildConfig.IS_FLATPAK &&
      (PlatformUtils.isWindows ||
          (PlatformUtils.isDisplayServer(DisplayServer.X11) &&
              KeyRelease.isSupported));

  static bool _inAppPushToTalkHeld = false;

  static bool _handleInAppPushToTalk(KeyEvent event) {
    final hotkey = shortcuts["push_to_talk"]?.hotkey;
    final pushToTalk = clientManager?.callManager.pushToTalk;
    if (hotkey == null || pushToTalk == null) return false;
    if (event.physicalKey != hotkey.physicalKey) return false;

    if (event is KeyUpEvent) {
      if (!_inAppPushToTalkHeld) return false;
      _inAppPushToTalkHeld = false;
      pushToTalk.release(_inApp);
      return true;
    }
    if (!pushToTalk.isOn) return false;
    if (event is KeyRepeatEvent) return _inAppPushToTalkHeld;
    final modifiers = hotkey.modifiers ?? const [];
    final pressed = HotKeyModifier.values.where((m) => m.isModifierPressed);
    if (pressed.length != modifiers.length ||
        !pressed.every(modifiers.contains)) {
      return false;
    }
    _inAppPushToTalkHeld = true;
    pushToTalk.press(_inApp);
    return true;
  }

  static const _inApp = "push_to_talk_in_app";

  static bool get isSupported {
    if (PlatformUtils.isWindows) return true;

    if (PlatformUtils.isDisplayServer(DisplayServer.X11)) {
      return true;
    }

    if (PlatformUtils.isDesktopEnvironment(DesktopEnvironment.KDEPlasma)) {
      return true;
    }

    return false;
  }

  static String get shortcutNameMute => Intl.message("Mute",
      name: "shortcutNameMute",
      desc: "name for the system wide shortcut to activate microphone mute");

  static String get shortcutNameUnmute => Intl.message("Unmute",
      name: "shortcutNameUnmute",
      desc: "name for the system wide shortcut to disable microphone mute");

  static String get shortcutNamePushToTalk => Intl.message("Push to talk",
      name: "shortcutNamePushToTalk",
      desc: "name for the shortcut that sends the microphone while it's held");

  static String get shortcutNameToggleMute => Intl.message("Toggle Mute",
      name: "shortcutNameToggleMute",
      desc:
          "name for the system wide shortcut to toggle the microphone mute status");

  static Map<String, AppShortcut> shortcuts = {
    "mute": AppShortcut(
        getDisplayName: () => shortcutNameMute,
        callback: () => clientManager?.callManager.mute()),
    "unmute": AppShortcut(
        getDisplayName: () => shortcutNameUnmute,
        callback: () => clientManager?.callManager.unmute()),
    "toggle_mute": AppShortcut(
        getDisplayName: () => shortcutNameToggleMute,
        callback: () => clientManager?.callManager.toggleMute()),
    // Vommet: held, not pressed (see PushToTalk).
    "push_to_talk": AppShortcut(
        getDisplayName: () => shortcutNamePushToTalk,
        callback: () =>
            clientManager?.callManager.pushToTalk.press(_systemWide),
        release: () =>
            clientManager?.callManager.pushToTalk.release(_systemWide)),
  };

  static const _systemWide = "push_to_talk_system_wide";

  static Future<void> storeHotkeys() async {
    for (var i in shortcuts.entries) {
      await preferences.setSystemHotkey(i.key, i.value.hotkey);
    }
  }
}

class AppShortcut {
  void Function() callback;

  /// Vommet: for a shortcut that's held (push to talk), called when its key
  /// is let go.
  void Function()? release;

  String Function() getDisplayName;

  HotKey? hotkey;

  /// Vommet: a press is being followed until the key is let go.
  bool _watchingRelease = false;

  AppShortcut({
    required this.getDisplayName,
    required this.callback,
    this.release,
  });

  Future<void> setHotkey(HotKey newHotkey) async {
    if (hotkey != null) {
      await _unregister(hotkey!);
    }

    for (var key in SystemWideShortcuts.shortcuts.values) {
      if (key.hotkey == newHotkey) {
        await key.clearHotkey();
      }
    }

    // Vommet: saved even where it can't be registered system wide
    // (Wayland), for the in-app push to talk key.
    try {
      await _register(newHotkey);
    } catch (e) {
      Log.w("Could not register a system wide shortcut: $e");
    }

    hotkey = newHotkey;

    await SystemWideShortcuts.storeHotkeys();
  }

  /// Vommet: a key that never registered (Wayland) can't fail the change.
  Future<void> _unregister(HotKey old) async {
    try {
      await hotKeyManager.unregister(old);
    } catch (e) {
      Log.w("Could not unregister a system wide shortcut: $e");
    }
  }

  Future<void> _register(HotKey newHotkey) async {
    await hotKeyManager.register(
      newHotkey,
      keyDownHandler: (hotKey) {
        callback();
        // Vommet: Windows and Linux report no release; watch for it. Held
        // keys repeat their press, so only one watch at a time.
        final onRelease = release;
        if (onRelease != null && !_watchingRelease) {
          _watchingRelease = KeyRelease.watch(hotKey, () {
            _watchingRelease = false;
            onRelease();
          });
        }
      },
      // macOS reports the release itself.
      keyUpHandler: release == null ? null : (hotKey) => release?.call(),
    );
  }

  Future<void> clearHotkey() async {
    if (hotkey != null) {
      await _unregister(hotkey!);
      hotkey = null;
    }

    await SystemWideShortcuts.storeHotkeys();
  }
}
