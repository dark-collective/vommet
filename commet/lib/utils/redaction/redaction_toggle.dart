// Vommet: switching redacted mode on and off in one step (Vommet issue 474):
// from the account menu, the Ctrl+K switcher, the "Redacted" pill, or
// Ctrl+Shift+H anywhere in the app.

import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/redaction_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

String get redactedModeShortcutLabel => "Ctrl+Shift+H";

String get redactedModeIndicator => Intl.message("Redacted",
    name: "redactedModeIndicator",
    desc: "The pill shown while redacted mode is on");

String get redactedModeIndicatorTooltip => Intl.message(
    "Redacted mode is on. Tap to turn it off; right-click or long-press for its settings.",
    name: "redactedModeIndicatorTooltip",
    desc: "Tooltip of the pill shown while redacted mode is on");

String get redactedModeTurnedOn => Intl.message("Redacted mode on",
    name: "redactedModeTurnedOn",
    desc: "Short message after redacted mode was switched on");

String get redactedModeTurnedOff => Intl.message("Redacted mode off",
    name: "redactedModeTurnedOff",
    desc: "Short message after redacted mode was switched off");

String redactedModeShortcutHint(String shortcut) => Intl.message(
    "$shortcut to turn it off",
    args: [shortcut],
    name: "redactedModeShortcutHint",
    desc:
        "After redacted mode was switched on: the keyboard shortcut that turns it off again");

String get redactedModeTurnOn => Intl.message("Turn redacted mode on",
    name: "redactedModeTurnOn",
    desc: "Ctrl+K switcher action that switches redacted mode on");

String get redactedModeTurnOff => Intl.message("Turn redacted mode off",
    name: "redactedModeTurnOff",
    desc: "Ctrl+K switcher action that switches redacted mode off");

String get redactedModeSettings => Intl.message("Redacted mode settings",
    name: "redactedModeSettings",
    desc: "Ctrl+K switcher action that opens Settings › Redacted mode");

/// The quick toggle shows only while redacted mode's experiment is on.
bool get redactedModeAvailable => preferences.experimentRedactedMode.value;

/// Ctrl+Shift+H.
bool isRedactedModeShortcut(KeyEvent event) {
  final keyboard = HardwareKeyboard.instance;
  return event is KeyDownEvent &&
      event.logicalKey == LogicalKeyboardKey.keyH &&
      keyboard.isControlPressed &&
      keyboard.isShiftPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isMetaPressed;
}

/// Switches redacted mode on or off with the levels picked in settings and
/// says so in a short message under [context]. Does nothing while the
/// experiment is off.
Future<void> toggleRedactedMode(BuildContext? context) =>
    setRedactedMode(context, !preferences.redactionEnabled.value);

Future<void> setRedactedMode(BuildContext? context, bool on) async {
  if (!redactedModeAvailable) return;
  final messenger = context != null && context.mounted
      ? ScaffoldMessenger.maybeOf(context)
      : null;
  await preferences.redactionEnabled.set(on);
  if (messenger == null) return;
  final touchOnly = PlatformUtils.isAndroid || PlatformUtils.isIOS;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 3),
    content: Text(on && !touchOnly
        ? "$redactedModeTurnedOn · "
            "${redactedModeShortcutHint(redactedModeShortcutLabel)}"
        : on
            ? redactedModeTurnedOn
            : redactedModeTurnedOff),
  ));
}

void openRedactedModeSettings(BuildContext context) =>
    SettingsNavigation.open(context, tab: labelSettingsRedactedMode);
