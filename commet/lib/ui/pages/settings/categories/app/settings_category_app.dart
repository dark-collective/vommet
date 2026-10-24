import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/experiments.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/advanced_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/appearance_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/data_storage_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/experiments_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/general_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/privacy_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/shortcut_settings/shortcut_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/voip_settings/voip_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notification_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/sound_settings/sound_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/app/window_settings.dart';
import 'package:commet/ui/pages/settings/categories/developer/developer_settings_page.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_settings.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:commet/ui/pages/settings/categories/app/redaction_settings_page.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';

class SettingsCategoryApp implements SettingsCategory {
  String get labelSettingsAppGeneral => Intl.message("General",
      name: "labelSettingsAppGeneral",
      desc: "Label for the App General settings page");

  String get labelSettingsAppAppearance => Intl.message("Appearance",
      name: "labelSettingsAppAppearance",
      desc: "Label for the App Appearance settings page");

  String get labelSettingsWindowBehaviour => Intl.message("Window Behavior",
      name: "labelSettingsWindowBehaviour",
      desc: "Label for the Window Behaviour settings page");

  String get labelSettingsAppAdvanced => Intl.message("Advanced",
      name: "labelSettingsAppAdvanced",
      desc: "Label for the App Advanced settings page");

  String get labelSettingsAppExperiments => Intl.message("Experiments",
      name: "labelSettingsAppExperiments",
      desc: "Label for the App Experiments settings page");

  String get labelSettingsAppNotifications => Intl.message("Notifications",
      name: "labelSettingsAppNotifications",
      desc: "Label for the App notifications settings page");

  String get labelSettingsDataAndStorage => Intl.message("Data and storage",
      name: "labelSettingsDataAndStorage",
      desc: "Label for the data and storage settings");

  String get labelSettingsShortcuts => Intl.message("Shortcuts",
      name: "labelSettingsShortcuts",
      desc: "Label for the Keyboard shortcuts settings page");

  String get labelSettingsAppDeveloperUtils => Intl.message("Developer Utils",
      name: "labelSettingsAppDeveloperUtils",
      desc:
          "Label for the developer utils settings page, usually hidden unless developer mode is turned on");

  String get labelSettingsCategoryApp => Intl.message("App Settings",
      name: "labelSettingsCategoryApp",
      desc: "Label for the settings category of the overall App settings/");

  String get labelSettingsCategoryVoiceAndVideo => Intl.message(
      "Voice and Video",
      name: "labelSettingsCategoryVoiceAndVideo",
      desc: "Label for the settings category related to voice and video calls");

  @override
  String get title => labelSettingsCategoryApp;

  @override
  List<SettingsTab> get tabs => List.from([
        SettingsTab(
            label: labelSettingsAppGeneral,
            icon: m.Icons.settings,
            pageBuilder: (context) {
              return const GeneralSettingsPage();
            }),
        SettingsTab(
            label: labelSettingsAppAppearance,
            icon: m.Icons.style,
            pageBuilder: (context) {
              return const AppearanceSettingsPage();
            }),
        // Vommet: every sound the app plays.
        SettingsTab(
            label: labelSettingsSounds,
            icon: m.Icons.volume_up,
            pageBuilder: (context) {
              return const SoundSettingsPage();
            }),
        if (clientManager?.clients
                .any((e) => e.getComponent<VoipComponent>() != null) ==
            true)
          SettingsTab(
              label: labelSettingsCategoryVoiceAndVideo,
              icon: m.Icons.call,
              pageBuilder: (context) {
                return const VoipSettingsPage();
              }),
        // Vommet: hidden where there are no shortcuts to set (was a
        // placeholder box on GNOME and other Wayland desktops).
        if ((PlatformUtils.isLinux || PlatformUtils.isWindows) &&
            ShortcutSettingsPage.hasShortcuts)
          SettingsTab(
              label: labelSettingsShortcuts,
              icon: m.Icons.keyboard_alt_outlined,
              pageBuilder: (context) {
                return const ShortcutSettingsPage();
              }),
        if (BuildConfig.DESKTOP)
          SettingsTab(
              label: labelSettingsWindowBehaviour,
              icon: m.Icons.window,
              pageBuilder: (context) {
                return const WindowSettingsPage();
              }),
        // Vommet: media cache usage and limits; no file cache on web.
        if (fileCache != null)
          SettingsTab(
              label: labelSettingsDataAndStorage,
              icon: m.Icons.data_usage,
              pageBuilder: (context) {
                return const DataStorageSettingsPage();
              }),
        // Vommet: on every platform, since the page also holds the account
        // notification defaults (was Linux and Android only, for unified push).
        SettingsTab(
            label: labelSettingsAppNotifications,
            icon: m.Icons.notifications,
            pageBuilder: (context) {
              return const NotificationSettingsPage();
            }),
        SettingsTab(
            label: labelSettingsPrivacy,
            icon: m.Icons.privacy_tip,
            pageBuilder: (context) {
              return const PrivacySettingsPage();
            }),
        // Vommet: redacted mode (Vommet issue 400), while its experiment is on.
        if (preferences.experimentRedactedMode.value)
          SettingsTab(
              label: labelSettingsRedactedMode,
              icon: m.Icons.visibility_off,
              pageBuilder: (context) {
                return const RedactionSettingsPage();
              }),
        SettingsTab(
            label: labelSettingsAppAdvanced,
            icon: m.Icons.code,
            pageBuilder: (context) {
              return const AdvancedSettingsPage();
            }),
        if (Experiments.hasExperiments)
          SettingsTab(
              label: labelSettingsAppExperiments,
              icon: m.Icons.science,
              pageBuilder: (context) {
                return const ExperimentsSettingsPage();
              }),
        // Vommet: folders and the archive of the Telegram-style chat list
        // (Vommet issue 291), while its experiment is on.
        if (unifiedChatListEnabled)
          SettingsTab(
              label: "Chat folders",
              icon: m.Icons.folder_copy_outlined,
              pageBuilder: (context) {
                return const ChatFoldersSettingsPage();
              }),
        if (preferences.developerMode.value)
          SettingsTab(
            label: labelSettingsAppDeveloperUtils,
            icon: m.Icons.bug_report,
            pageBuilder: (context) {
              return const DeveloperSettingsPage();
            },
          ),
      ]);
}

String get labelSettingsSounds => Intl.message("Sounds",
    name: "labelSettingsSounds", desc: "Label of the Sounds settings tab");

String get labelSettingsPrivacy => Intl.message("Privacy",
    name: "labelSettingsPrivacy", desc: "Label of the Privacy settings tab");
