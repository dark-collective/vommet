import 'package:commet/config/encrypted_search_index_setting.dart';
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
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';

/// Vommet: the "Recovery key check-ins" switch's id for [SettingsHighlight].
const recoveryCheckInsSettingId = "security.recovery-checkins";

/// Vommet: the "Message history backup" row's id for [SettingsHighlight].
const messageBackupSettingId = "security.message-backup";

/// Vommet: opens app settings at one tab, for shortcuts such as the profile
/// card's "Edit Profile" and the voice menus' "Voice settings".
class SettingsNavigation {
  /// Tests only: stand-in categories for [categories].
  static List<SettingsCategory>? debugCategories;

  static List<SettingsCategory> get categories =>
      debugCategories ??
      [
        if (clientManager!.clients.isNotEmpty) SettingsCategoryAccount(),
        SettingsCategoryApp(),
        SettingsCategoryAbout(),
      ];

  /// The account category's title (Profile, Privacy, Security, ...).
  static String get accountCategory => SettingsCategoryAccount().title;

  /// The app category's title (Privacy, Voice and Video, ...).
  static String get appCategory => SettingsCategoryApp().title;

  /// The tab labelled [tab] in the category titled [category] (any category
  /// when null). Labels aren't unique: the account and the app category both
  /// have a "Privacy" tab.
  static SettingsTab? findTab(List<SettingsCategory> categories,
          {required String tab, String? category}) =>
      categories
          .where((c) => category == null || c.title == category)
          .expand((c) => c.tabs)
          .where((t) => t.label == tab)
          .firstOrNull;

  /// Opens settings at the tab labelled [tab] in the category titled
  /// [category]: selected in the sidebar on desktop, or as its own page on
  /// mobile. [highlight]: a setting on it to scroll to and flash (its
  /// SettingsSearchTarget id).
  static void open(BuildContext context,
      {required String tab, required String category, String? highlight}) {
    final match = findTab(categories, tab: tab, category: category);

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
            initialCategory: category,
            initialHighlight: highlight,
            settings: categories));
  }

  static void openProfile(BuildContext context) => open(context,
      tab: SettingsCategoryAccount().labelSettingsTabProfile,
      category: accountCategory);

  /// Settings › Security, at the "Recovery key check-ins" switch.
  static void openRecoveryCheckIns(BuildContext context) => open(context,
      tab: SettingsCategoryAccount().labelSettingsTabSecurity,
      category: accountCategory,
      highlight: recoveryCheckInsSettingId);

  /// Vommet Deep Search: Settings › Security, at the message (key) backup
  /// row, for the "can't be decrypted yet" line's Details.
  static void openMessageBackup(BuildContext context) => open(context,
      tab: SettingsCategoryAccount().labelSettingsTabSecurity,
      category: accountCategory,
      highlight: messageBackupSettingId);

  /// Vommet Deep Search: App Settings › Privacy (not the account's Privacy
  /// tab), at the search index setting, for the "Indexing is off" line's
  /// Turn on.
  static void openSearchIndex(BuildContext context) =>
      openAppPrivacy(context, highlight: encryptedIndexModePreference.key);

  /// App Settings › Privacy (not the account's Privacy tab); [highlight]: a
  /// setting on it to scroll to and flash.
  static void openAppPrivacy(BuildContext context, {String? highlight}) =>
      open(context,
          tab: labelSettingsPrivacy,
          category: appCategory,
          highlight: highlight);

  /// Settings › App › Language, where Translation lives (Vommet issue 819).
  static void openTranslation(BuildContext context) => open(context,
      tab: SettingsCategoryApp().labelSettingsAppLanguage,
      category: appCategory);

  static void openVoice(BuildContext context) => open(context,
      tab: SettingsCategoryApp().labelSettingsCategoryVoiceAndVideo,
      category: appCategory);
}
