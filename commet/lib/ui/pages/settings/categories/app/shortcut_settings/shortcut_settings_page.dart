import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/hover_reply_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/keyboard_hook_shortcuts_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/outsource_shortcut_settings_page.dart';
import 'package:commet/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:flutter/material.dart';

class ShortcutSettingsPage extends StatelessWidget {
  const ShortcutSettingsPage({super.key});

  static bool get _showOutsourceMenu =>
      PlatformUtils.isDisplayServer(DisplayServer.Wayland) &&
      PlatformUtils.isDesktopEnvironment(DesktopEnvironment.KDEPlasma);

  static bool get _showHooksMenu {
    if (BuildConfig.IS_FLATPAK) return false;
    return !_showOutsourceMenu || preferences.developerMode.value;
  }

  /// Vommet: whether this page has anything to show. Upstream showed a
  /// placeholder box (GNOME and other Wayland desktops) or an empty page
  /// (Flatpak outside KDE); the Shortcuts tab is now hidden there instead.
  /// The push to talk key is set in Voice and Video either way.
  /// Vommet issue 1069: the local row now keeps this page available.
  static bool get hasShortcuts =>
      true; // Vommet issue 1069: local shortcuts work without global hooks.

  @override
  Widget build(BuildContext context) {
    if (!hasShortcuts) return const SizedBox.shrink();

    final showOutsourceMenu =
        SystemWideShortcuts.isSupported && _showOutsourceMenu;
    final showHooksMenu = SystemWideShortcuts.isSupported && _showHooksMenu;

    return Column(
      spacing: 8,
      children: [
        // Vommet issue 1069: available on Wayland and Flatpak too.
        const HoverReplySettings(),
        if (showOutsourceMenu) OutsourceShortcutSettingsPage(),
        if (showHooksMenu) KeyboardHookShortcutsSettingsPage()
      ],
    );
  }
}
