import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/push_notification_component.dart';
import 'package:commet/client/sounds/app_sounds.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/account_notification_defaults.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notifier_debug_view.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/quiet_status.dart';
import 'package:commet/ui/pages/setup/menus/unified_push_setup.dart';
import 'package:commet/ui/pages/settings/categories/app/sound_settings/sound_settings_page.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  Notifier? notifier;
  GlobalKey pushGatewayKey = GlobalKey();
  bool isPushGatewayLoading = false;

  String get notificationSettingsNotSupported =>
      Intl.message("Push notifications are not supported on this system",
          name: "notificationSettingsNotSupported",
          desc: "Message to display when push notifications are not supported");

  @override
  void initState() {
    super.initState();
    notifier = NotificationManager.notifier;
  }

  bool get canConfigureNotifications =>
      PlatformUtils.isAndroid || PlatformUtils.isLinux;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Vommet: the account-wide defaults rooms follow.
        Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: notifySettingsDefaultHeader,
          child: AccountNotificationDefaults(),
        ),
        const SizedBox(height: 10),
        if (canConfigureNotifications)
          Column(
            children: [
              Panel(
                mode: tiamat.TileType.surfaceContainerLow,
                header: "Push Notifications",
                child: buildNotificationSettings(),
              ),
              if (notifier is UnifiedPushNotifier)
                Column(
                  children: [
                    const SizedBox(
                      height: 10,
                    ),
                    Panel(
                        mode: tiamat.TileType.surfaceContainerLow,
                        header: "Unified Push",
                        child: Column(
                          children: [
                            UnifiedPushSetupView(
                              onToggled: (_) => setState(() {}),
                            ),
                            if (preferences.unifiedPushEnabled.value == true)
                              pushGatewaySelector(),
                          ],
                        )),
                    const SizedBox(
                      height: 10,
                    ),
                  ],
                ),
            ],
          ),
        // Vommet: shown to everyone, to spot and remove stale registrations
        // (raw details stay behind developer mode).
        Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: notifySettingsPushRegistrationsHeader,
          child: NotifierDebugView(),
        ),
      ],
    );
  }

  Widget buildNotificationSettings() {
    return Column(
      children: [
        if (PlatformUtils.isAndroid)
          BooleanPreferenceToggle(
            preference: preferences.silenceNotifications,
            title: notifySettingsQuietTitle,
            description: notifySettingsQuietDescription,
          ),
        // Vommet: what that means right now.
        if (PlatformUtils.isAndroid) const QuietNotificationsStatus(),
        if (PlatformUtils.isLinux || PlatformUtils.isWindows)
          Column(
            children: [
              BooleanPreferenceToggle(
                preference: preferences.enableNotifications,
                title: "Show notifications",
                description:
                    "Enable or disable the display of notifications entirely",
              ),
              BooleanPreferenceToggle(
                preference: preferences.suppressNotificationWhenRoomFocused,
                title: "Hide notifications for current room",
                description:
                    "When receiving a message, if you have the chat selected and the app is in focus, dont show the notification",
              ),
              BooleanPreferenceToggle(
                preference: preferences.inAppNotificationBanners,
                title: notifySettingsInAppBannersTitle,
                description: notifySettingsInAppBannersDescription,
              ),
              if (PlatformUtils.isLinux)
                Column(
                  children: [
                    SizedBox(
                      height: 20,
                    ),
                    BooleanPreferenceToggle(
                      preference: preferences.showNotificationBadgesInTaskbar,
                      title: "Notification Badges",
                      description:
                          "Show a badge with the number of unread messages in the system taskbar",
                      onChanged: (enabled) {
                        if (enabled) {
                          NotificationManager.notifier?.enableBadges();
                        } else {
                          NotificationManager.notifier?.disableBadges();
                        }
                      },
                    ),
                    BooleanPreferenceToggle(
                      preference: preferences.formatNotificationBody,
                      title: "Message Body Formatting",
                      description:
                          "Apply user formatting in message notifications",
                    ),
                    AnimatedOpacity(
                      opacity:
                          preferences.formatNotificationBody.value ? 1 : 0.3,
                      duration: Durations.short4,
                      child: IgnorePointer(
                        ignoring:
                            preferences.formatNotificationBody.value == false,
                        child: Column(
                          children: [
                            BooleanPreferenceToggle(
                              preference: preferences.showMediaInNotifications,
                              title: "Show Images",
                              description:
                                  "Show images in notifications, if allowed by 'General > Media Preview' settings",
                            ),
                            BooleanPreferenceToggle(
                              preference: preferences.previewUrlInNotifications,
                              title: "Preview Urls",
                              description:
                                  "Fetch URL previews to show extra information about links in notifications",
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              SizedBox(
                height: 20,
              ),
              DoublePreferenceSlider(
                preference: preferences.notificationsVolume,
                min: 0,
                max: 150,
                numDecimals: 0,
                units: "%",
                title: "Notification volume",
                description:
                    "Controls the volume of notifications and ringtones",
                onChanged: (p0) {
                  Player p = NotificationManager.getSoundPlayer();
                  p.setVolume(p0);
                  final sound = AppSounds.media(SoundEvent.message);
                  if (sound != null) p.open(sound);
                },
              ),
              // Vommet: the two sounds most people change; the rest are on
              // the Sounds page.
              const SoundRow(event: SoundEvent.message),
              const SoundRow(event: SoundEvent.ringIncoming),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(Icons.tune,
                    color: Theme.of(context).colorScheme.primary),
                title: tiamat.Text(notifySettingsAllSounds,
                    type: tiamat.TextType.label,
                    color: Theme.of(context).colorScheme.primary),
                subtitle:
                    tiamat.Text.labelLow(notifySettingsAllSoundsDescription),
                trailing: Icon(Icons.chevron_right,
                    color: Theme.of(context).colorScheme.primary),
                onTap: () => SoundSettingsPage.open(context),
              ),
            ],
          ),
      ],
    );
  }

  Widget pushGatewaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        tiamat.DropdownTextField(
            key: pushGatewayKey,
            initialValue: preferences.pushGateway,
            textEditorPlaceholder: "push.example.com",
            editableEntryPlaceholder: "Custom push gateway",
            items: [
              // Vommet: upstream's push.commet.chat serves Commet's Firebase
              // project, which this fork does not ship. Only UnifiedPush.
              if (notifier is UnifiedPushNotifier)
                "matrix.gateway.unifiedpush.org"
            ]),
        tiamat.Button(
          text: CommonStrings.promptApply,
          isLoading: isPushGatewayLoading,
          onTap: onPushGatewaySelected,
        )
      ],
    );
  }

  Future<void> onPushGatewaySelected() async {
    var value = (pushGatewayKey.currentState as DropdownTextFieldState).value;
    preferences.setPushGateway(value);

    setState(() {
      isPushGatewayLoading = true;
    });

    await PushNotificationComponent.updateAllPushers();

    setState(() {
      isPushGatewayLoading = false;
    });
  }
}

String get notifySettingsDefaultHeader => Intl.message("Default notifications",
    name: "notifySettingsDefaultHeader",
    desc: "Header of the account notification defaults panel");

String get notifySettingsPushRegistrationsHeader =>
    Intl.message("Push registrations",
        name: "notifySettingsPushRegistrationsHeader",
        desc: "Header of the panel listing push registrations");

String get notifySettingsQuietTitle => Intl.message(
    "Quiet notifications while I'm chatting on another device",
    name: "notifySettingsQuietTitle",
    desc:
        "Title of the Android setting that silences notifications while active on another device");

String get notifySettingsQuietDescription => Intl.message(
    "On: if you wrote in a chat from another device in the last 5 minutes and that device is still online, this phone shows that chat's new messages without sound. Everything else notifies normally. Off: every notification makes its normal sound.",
    name: "notifySettingsQuietDescription",
    desc: "Description of the quiet-notifications setting");

String get notifySettingsInAppBannersTitle =>
    Intl.message("In-app notification banners",
        name: "notifySettingsInAppBannersTitle",
        desc: "Title of the in-app notification banners setting");

String get notifySettingsInAppBannersDescription => Intl.message(
    "While Vommet is open, show new messages as a banner at the top of the app instead of a system notification.",
    name: "notifySettingsInAppBannersDescription",
    desc: "Description of the in-app notification banners setting");

String get notifySettingsAllSounds => Intl.message("All sounds",
    name: "notifySettingsAllSounds",
    desc: "Row that opens the full sound settings");

String get notifySettingsAllSoundsDescription =>
    Intl.message("Calls, mute and deafen, screen share, and more",
        name: "notifySettingsAllSoundsDescription",
        desc: "Subtitle of the All sounds row");
