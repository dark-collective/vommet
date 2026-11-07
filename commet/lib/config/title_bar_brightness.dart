import 'dart:async';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/config/style/theme_changer.dart';

/// Vommet: the Linux title bar follows the app theme (Vommet issue 384).
///
/// The window has no header bar, so GTK draws a plain client-side title bar
/// with its own theme, which in the Flatpak is always light Adwaita. This
/// tells the runner (linux/window_theme.h) whether the bar should be dark:
/// the app theme's brightness, unless the user forced light or dark in
/// Settings › Appearance › Theme › Title bar, which works for any theme.
class TitleBarBrightness {
  static const channel = MethodChannel("im.nether.vommet/window");

  /// Values of the `linux_title_bar` preference.
  static const followTheme = "theme";
  static const light = "light";
  static const dark = "dark";
  static const options = [followTheme, light, dark];

  /// Whether the runner has the channel. Only the Linux runner does.
  static bool Function() isSupported = () => PlatformUtils.isLinux;

  static Brightness? _theme;
  static Brightness? _override;
  static Brightness? _sent;
  static final List<StreamSubscription> _subscriptions = [];

  /// The forced brightness for a preference value; null follows the theme.
  static Brightness? overrideFor(String value) => switch (value) {
        light => Brightness.light,
        dark => Brightness.dark,
        _ => null,
      };

  /// Starts following the theme and the saved setting.
  static void init(ThemeData initialTheme) => follow(
        initialTheme: initialTheme.brightness,
        themes: ThemeChanger.onThemeChanged.stream,
        setting: preferences.linuxTitleBar.value,
        settingChanges: preferences.linuxTitleBar.onChanged,
      );

  /// [init] without the app's globals, for tests.
  static void follow({
    required Brightness initialTheme,
    required Stream<ThemeData> themes,
    required String setting,
    required Stream<String> settingChanges,
  }) {
    _theme = initialTheme;
    _override = overrideFor(setting);
    _subscriptions
      ..add(themes.listen((theme) {
        _theme = theme.brightness;
        _send();
      }))
      ..add(settingChanges.listen((value) {
        _override = overrideFor(value);
        _send();
      }));
    _send();
  }

  /// Sends the wanted brightness to the runner, once per change.
  static Future<void> _send() async {
    var wanted = _override ?? _theme;
    if (wanted == null || wanted == _sent || !isSupported()) return;
    _sent = wanted;
    try {
      await channel.invokeMethod<void>(
          "setDarkTheme", wanted == Brightness.dark);
    } on MissingPluginException {
      // A runner without the channel: nothing to follow.
    } on PlatformException catch (e) {
      debugPrint("Could not set the window theme: $e");
    }
  }

  /// Stops following and forgets what was sent (for tests).
  static Future<void> reset() async {
    for (var s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    _theme = null;
    _override = null;
    _sent = null;
  }
}
