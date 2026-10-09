import 'package:commet/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/push_notification/notifier.dart';
import 'package:commet/client/components/push_notification/push_notification_component.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/notifier_debug_view.dart';
import 'package:commet/ui/pages/settings/categories/app/notification_settings/quiet_status.dart';
import 'package:commet/ui/pages/setup/menus/unified_push_setup.dart';
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
        const Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: "Push registrations",
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
            title: "Quiet notifications while I'm chatting on another device",
            description:
                "On: if you wrote in a chat from another device in the last 5 minutes and that device is still online, this phone shows that chat's new messages without sound. Everything else notifies normally. Off: every notification makes its normal sound",
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
                  p.open(Media("asset:///assets/sound/message.ogg"));
                },
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
