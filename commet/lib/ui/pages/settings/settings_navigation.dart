import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/settings/categories/about/settings_category_about.dart';
import 'package:commet/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/mobile_settings_page.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_page.dart';
import 'package:flutter/material.dart';

/// Vommet: the "Recovery key check-ins" switch's id for [SettingsHighlight].
const recoveryCheckInsSettingId = "security.recovery-checkins";

/// Vommet: opens app settings at one tab, for shortcuts such as the profile
/// card's "Edit Profile" and the voice menus' "Voice settings".
class SettingsNavigation {
  static List<SettingsCategory> get categories => [
        if (clientManager!.clients.isNotEmpty) SettingsCategoryAccount(),
        SettingsCategoryApp(),
        SettingsCategoryAbout(),
      ];

  /// Opens settings at the tab labelled [tab]: selected in the sidebar on
  /// desktop, or as its own page on mobile. [highlight]: a setting on it to
  /// scroll to and flash (its SettingsSearchTarget id).
  static void open(BuildContext context,
      {required String tab, String? highlight}) {
    final match = categories
        .expand((c) => c.tabs)
        .where((t) => t.label == tab)
        .firstOrNull;

    if (match != null && !MediaQuery.of(context).desktop) {
      NavigationUtils.navigateTo(
          context,
          SettingsHighlight(
            targetId: highlight,
            serial: 1,
            child: SettingsSubPage(
                builder: match.pageBuilder,
                makeScrollable: match.makeScrollable),
          ));
      return;
    }

    NavigationUtils.navigateTo(
        context,
        SettingsPage(
            initialTab: tab,
            initialHighlight: highlight,
            settings: categories));
  }

  static void openProfile(BuildContext context) =>
      open(context, tab: SettingsCategoryAccount().labelSettingsTabProfile);

  /// Settings › Security, at the "Recovery key check-ins" switch.
  static void openRecoveryCheckIns(BuildContext context) => open(context,
      tab: SettingsCategoryAccount().labelSettingsTabSecurity,
      highlight: recoveryCheckInsSettingId);

  static void openVoice(BuildContext context) => open(context,
      tab: SettingsCategoryApp().labelSettingsCategoryVoiceAndVideo);
}
