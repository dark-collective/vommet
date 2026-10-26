import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:commet/ui/pages/settings/categories/app/pinned_bar_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/layout_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/sidebar_icon_size_settings.dart';

import 'package:commet/config/preferences.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/banner_and_pane_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/thread_preview_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/reply_style_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/message_density_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/timeline_image_size_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/app_icon_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/clock_format_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/app_font_settings.dart';
import 'package:commet/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:commet/ui/pages/settings/categories/app/theme_settings/theme_settings_widget.dart';
import 'package:commet/ui/pages/settings/categories/app/member_list_settings.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:commet/ui/pages/settings/categories/app/message_hover_bar_settings.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:commet/ui/pages/settings/categories/app/title_bar_settings.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/ui/molecules/timeline_events/deleted_message_placeholder.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/ui/organisms/chat_wallpaper/chat_wallpaper_settings.dart';
import 'package:commet/ui/molecules/timeline_events/double_tap_action.dart';
import 'package:commet/ui/pages/settings/categories/app/double_tap_settings.dart';

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  String get labelSettingsAppTheme => Intl.message("Theme",
      name: "labelSettingsAppTheme",
      desc: "Label for theme section of app appearance");

  String get labelStickerSize => Intl.message("Sticker size",
      desc: "Title of the setting for how big stickers appear in the timeline",
      name: "labelStickerSize");

  String get labelStickerSizeDescription => Intl.message(
      "How big stickers appear in the timeline. GIFs keep their size.",
      desc: "Description of the sticker size setting",
      name: "labelStickerSizeDescription");

  String get labelAppScale => Intl.message("App Scale",
      name: 'labelAppScale',
      desc:
          "Label for the setting which controls the UI scale of the overall app");

  String get labelUseRoomAvatars => Intl.message("Use room avatars",
      name: "labelUseRoomAvatars",
      desc: "Label for enabling using room avatars instead of icons");

  String get labelEnableRoomIconsDescription =>
      Intl.message("Show room avatar images instead of icons",
          name: "labelEnableRoomIconsDescription",
          desc: "Description for the enable room icons setting");

  String get labelUseRoomAvatarPlaceholders =>
      Intl.message("Use placeholder avatars",
          name: "labelUseRoomAvatarPlaceholders",
          desc: "Label for enabling generic icons in the appearance settings");

  String get labelUseRoomAvatarPlaceholdersDescription => Intl.message(
      "When a room does not have an avatar set, or using them is disabled, fallback to a generic color + first letter placeholder for the image",
      name: "labelUseRoomAvatarPlaceholdersDescription",
      desc: "Description for the enable generic icons setting");

  String get labelShowRoomPreviewsInSpaceSidebar => Intl.message(
      "Show unjoined rooms in a space's room list",
      name: "labelShowRoomPreviewsInSpaceSidebar",
      desc: "Label for enabling using the preview list in the space sidebar");

  String get labelShowRoomPreviewsInSpaceSidebarDescription => Intl.message(
      "List the rooms in a space that you haven't joined yet, next to the rooms you're in, so you can preview or join them",
      name: "labelShowRoomPreviewsInSpaceSidebarDescription",
      desc:
          "Description for enabling using the preview list in the space sidebar");

  String get labelOrgModeItalics => Intl.message("Org-mode style /italics/",
      name: "labelOrgModeItalics",
      desc: "Label for the setting that sends text between slashes as italics");

  String get labelOrgModeItalicsDescription => Intl.message(
      "Send text between slashes, like /this/, in italics. Type \\/ for a plain slash.",
      name: "labelOrgModeItalicsDescription",
      desc: "Description for the org-mode italics setting");

  String get labelFormattingPopup => Intl.message("Formatting buttons",
      name: "labelFormattingPopup",
      desc: "Label for the setting that shows the composer formatting buttons");

  String get labelFormattingPopupDescription => Intl.message(
      "Show formatting buttons when you select text in the message box.",
      name: "labelFormattingPopupDescription",
      desc: "Description for the formatting buttons setting");

  String get labelChatBubbleLayout => Intl.message("Chat bubbles",
      name: "labelChatBubbleLayout",
      desc:
          "Label for the setting that shows chat messages as bubbles, your own on the right");

  String get labelChatBubbleLayoutDescription => Intl.message(
      "Show messages as bubbles: yours on the right, everyone else's on the left (all on the left in wide windows).",
      name: "labelChatBubbleLayoutDescription",
      desc: "Description for the chat bubble layout setting");

  String get labelShowRoomStateEvents => Intl.message("Show state events",
      name: "labelShowRoomStateEvents",
      desc:
          "Label for enabling visibility of state events in the room timeline");

  String get labelShowRoomStateEventsDescription => Intl.message(
      "Show changes to the room state, such as members joining and leaving, in the chat timeline.",
      name: "labelShowRoomStateEventsDescription",
      desc:
          "Description for enabling using visibility of room state events in the timeline");

  String get labelCollapseStateEvents => Intl.message("Collapse state events",
      name: "labelCollapseStateEvents",
      desc:
          "Label for enabling collapsing of state events in the room timeline");

  String get labelCollapseStateEventsDescription => Intl.message(
      "Group changes to room state in to a single timeline event.",
      name: "labelCollapseStateEventsDescription",
      desc:
          "Description for enabling using collapsing of room state events in the timeline");

  String get labelGroupConsecutiveMedia => Intl.message("Group pictures",
      name: "labelGroupConsecutiveMedia",
      desc:
          "Label for the setting that shows consecutive pictures as a mosaic");

  String get labelGroupConsecutiveMediaDescription => Intl.message(
      "Show pictures and videos posted together by one person as a single mosaic.",
      name: "labelGroupConsecutiveMediaDescription",
      desc:
          "Description for the setting that shows consecutive pictures as a mosaic");

  // Vommet: the "Standalone rooms" button's strings moved to
  // new_home_shortcuts.dart, with its toggle (HomeShortcutsSettings).

  String get labelRailUnreadMarks => Intl.message("Show unread marks on spaces",
      name: "labelRailUnreadMarks",
      desc:
          "Label for the setting that shows a mark beside sidebar spaces with unread messages");

  String get labelRailUnreadMarksDescription => Intl.message(
      "A small mark beside spaces with new messages. Mentions always show a red badge.",
      name: "labelRailUnreadMarksDescription",
      desc:
          "Description for the setting that shows a mark beside sidebar spaces with unread messages");

  String get labelNewestUnreadDmsFirst => Intl.message(
      "Newest unread DMs first",
      name: "labelNewestUnreadDmsFirst",
      desc:
          "Label for the setting that puts the most recently active unread direct message at the top of the sidebar");

  String get labelNewestUnreadDmsFirstDescription => Intl.message(
      "Show the most recently active unread direct message at the top of the sidebar, like Discord.",
      name: "labelNewestUnreadDmsFirstDescription",
      desc: "Description for the newest unread DMs first setting");

  String get labelShowDeletedMessages => Intl.message("Show deleted messages",
      name: "labelShowDeletedMessages",
      desc:
          "Label for the setting that leaves a line in the timeline where a message was deleted");

  String get labelShowDeletedMessagesDescription => Intl.message(
      "A deleted message leaves a muted \"Message deleted\" line in its place (with who deleted it if it wasn't the sender, and their reason), so replies and notifications for it still make sense. Turn off to hide deleted messages completely. Takes effect when you next open a room.",
      name: "labelShowDeletedMessagesDescription",
      desc: "Description for the show deleted messages setting");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        themeSettings(context),
        const SizedBox(
          height: 10,
        ),
        // Vommet: the window, tray and splash icon (Vommet issue 591).
        const AppIconSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: Discord style, Telegram style or a custom mix.
        const LayoutSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: the bar over a message you point at.
        const MessageHoverBarSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet (experiment): what double-tapping a message does.
        if (experimentDoubleTapAction.value) ...[
          const DoubleTapSettings(),
          const SizedBox(
            height: 10,
          ),
        ],
        Panel(
          // Vommet: the app font, above the scale sliders.
          header: AppFontSettings.header,
          mode: TileType.surfaceContainerLow,
          child: Column(
            spacing: 12,
            children: [
              const AppFontSettings(),
              DoublePreferenceSlider(
                min: 0.2,
                max: 2,
                requiresConfirmationButton: true,
                preference: preferences.appScale,
                onChanged: (p0) {
                  ScaledWidgetsFlutterBinding.instance.scaleFactor =
                      (deviceSize) {
                    return p0;
                  };
                },
                title: labelAppScale,
                description: "Resizes the overall interface of the app",
              ),
              DoublePreferenceSlider(
                min: 0.2,
                max: 3,
                requiresConfirmationButton: true,
                preference: preferences.textScale,
                title: "Text Scale",
                description: "Multiply the size of text",
              ),
              // Vommet issue 620.
              DoublePreferenceSlider(
                min: Preferences.stickerSizeMin,
                max: Preferences.stickerSizeMax,
                numDecimals: 0,
                units: " px",
                preference: preferences.stickerSize,
                title: labelStickerSize,
                description: labelStickerSizeDescription,
              )
            ],
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        // Vommet: banner gradient and resizable panes.
        const BannerAndPaneSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: what thread cards preview.
        const ThreadPreviewSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: how replies quote the message they answer.
        const ReplyStyleSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: cozy or compact messages (Vommet issue 524).
        const MessageDensitySettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: Default or Large pictures in the timeline (Vommet issue 721).
        const TimelineImageSizeSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: the 12-hour or 24-hour clock.
        const ClockFormatSettings(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: the People and # buttons under Home in the sidebar.
        const HomeShortcutsSettings(),
        const SizedBox(
          height: 10,
        ),
        Panel(
          header: "Other Options",
          mode: TileType.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Column(
              children: [
                BooleanPreferenceToggle(
                  preference: preferences.showRoomPreviewsInSpaceSidebar,
                  title: labelShowRoomPreviewsInSpaceSidebar,
                  description: labelShowRoomPreviewsInSpaceSidebarDescription,
                ),
                const Seperator(),
                // Vommet: the rail's unread pill
                BooleanPreferenceToggle(
                  preference: preferences.railUnreadMarks,
                  title: labelRailUnreadMarks,
                  description: labelRailUnreadMarksDescription,
                ),
                const Seperator(),
                // Vommet: was the "Newest unread DMs first" experiment
                // (10-25).
                BooleanPreferenceToggle(
                  preference: preferences.experimentSidebarNewestUnreadDms,
                  title: labelNewestUnreadDmsFirst,
                  description: labelNewestUnreadDmsFirstDescription,
                ),
                const Seperator(),
                // Vommet: the rail's icon size (Vommet issue 506).
                const SidebarIconSizeSetting(),
                const Seperator(),
                BooleanPreferenceToggle(
                  preference: preferences.showRoomAvatars,
                  title: labelUseRoomAvatars,
                  description: labelEnableRoomIconsDescription,
                ),
                const Seperator(),
                BooleanPreferenceToggle(
                  preference: preferences.usePlaceholderRoomAvatars,
                  title: labelUseRoomAvatarPlaceholders,
                  description: labelUseRoomAvatarPlaceholdersDescription,
                ),
                const Seperator(),
                // Vommet: the pinned message bar above the chat.
                const PinnedBarSettings(),
                const Seperator(),
                // Vommet issue 746: chat wallpapers.
                if (experimentChatWallpapers.value) ...[
                  BooleanPreferenceToggle(
                    preference: showChatWallpapers,
                    title: labelShowChatWallpapers,
                    description: labelShowChatWallpapersDescription,
                  ),
                  const Seperator(),
                ],
                BooleanPreferenceToggle(
                  preference: preferences.orgModeItalics,
                  title: labelOrgModeItalics,
                  description: labelOrgModeItalicsDescription,
                ),
                const Seperator(),
                BooleanPreferenceToggle(
                  preference: preferences.formattingPopup,
                  title: labelFormattingPopup,
                  description: labelFormattingPopupDescription,
                ),
                const Seperator(),
                BooleanPreferenceToggle(
                  preference: preferences.showStateEvents,
                  title: labelShowRoomStateEvents,
                  description: labelShowRoomStateEventsDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.collapseStateEvents,
                  title: labelCollapseStateEvents,
                  description: labelCollapseStateEventsDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.groupConsecutiveMedia,
                  title: labelGroupConsecutiveMedia,
                  description: labelGroupConsecutiveMediaDescription,
                ),
                // Vommet: was the "Show deleted messages" experiment (10-25).
                BooleanPreferenceToggle(
                  preference: experimentDeletedMessagePlaceholders,
                  title: labelShowDeletedMessages,
                  description: labelShowDeletedMessagesDescription,
                )
              ],
            ),
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        // Vommet: what shows under a member's name.
        const MemberListSettings(),
      ],
    );
  }

  String get labelFollowColorsOffForTheme => Intl.message(
      "This theme has its own colors, so this is off while it is in use.",
      name: "labelFollowColorsOffForTheme",
      desc:
          "Shown under the Follow System Colors toggle when a gradient or imported theme is in use, which ignores it");

  String get labelThemeMode => Intl.message("Theme mode",
      name: "labelThemeMode",
      desc:
          "Theme settings: choose between one theme and following the system's light/dark mode");

  String get labelThemeModeOne => Intl.message("One theme",
      name: "labelThemeModeOne",
      desc: "Theme mode choice: always use the one picked theme");

  String get labelThemeModeFollow => Intl.message("Follow system",
      name: "labelThemeModeFollow",
      desc:
          "Theme mode choice: use one theme when the system is light and another when it is dark");

  String get labelThemeModeDescription => Intl.message(
      "Follow system switches between a light and a dark theme with your device's light/dark mode.",
      name: "labelThemeModeDescription",
      desc: "Description under the Theme mode switch");

  // Vommet: any change that can move the theme on screen.
  Stream<void> get themeChanges => Stream.multi((controller) {
        var subs = [
          preferences.theme.onChanged,
          preferences.themeLight.onChanged,
          preferences.themeDark.onChanged,
          preferences.shouldFollowSystemTheme.onChanged,
        ].map((s) => s.listen((_) => controller.add(null))).toList();
        controller.onCancel = () {
          for (var sub in subs) {
            sub.cancel();
          }
        };
      });

  Future<void> applyTheme(BuildContext context) async {
    var theme = await preferences.resolveTheme();
    if (context.mounted) ThemeChanger.setTheme(context, theme);
  }

  // Vommet: "Theme mode" replaces the Follow System Brightness toggle (same
  // preference). With "Follow system", the theme list shows a light and a dark
  // slot, and any theme can fill either. Follow System Colors still only acts
  // on the built-in themes.
  Widget followSystemToggles(BuildContext context) {
    return StreamBuilder(
      stream: themeChanges,
      builder: (context, _) {
        var following = preferences.shouldFollowSystemTheme.value;
        var mode = SettingsSearchTarget(
            ids: [preferences.shouldFollowSystemTheme.key],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tiamat.Text.labelEmphasised(labelThemeMode),
                        tiamat.Text.labelLow(labelThemeModeDescription),
                      ],
                    ),
                  ),
                  m.SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style:
                        selectedSegmentStyle(m.Theme.of(context).colorScheme),
                    segments: [
                      m.ButtonSegment(
                          value: false, label: m.Text(labelThemeModeOne)),
                      m.ButtonSegment(
                          value: true, label: m.Text(labelThemeModeFollow)),
                    ],
                    selected: {following},
                    onSelectionChanged: (value) async {
                      await preferences.shouldFollowSystemTheme
                          .set(value.first);
                      preferences.themeSlot.value =
                          preferences.systemBrightness;
                      if (context.mounted) await applyTheme(context);
                    },
                  ),
                ],
              ),
            ));

        var colorsToggle = Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
            child: BooleanPreferenceToggle(
              preference: preferences.shouldFollowSystemColors,
              title: "Follow System Colors",
              description: "Automatically follow system color scheme",
              onChanged: (_) => applyTheme(context),
            ));

        if (preferences.themeFollowsSystem) {
          return Column(children: [mode, colorsToggle]);
        }

        var colors = m.Theme.of(context).colorScheme;
        return Column(children: [
          mode,
          IgnorePointer(child: Opacity(opacity: 0.45, child: colorsToggle)),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 8, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Icon(m.Icons.info_outline, size: 16, color: colors.secondary),
              const SizedBox(width: 8),
              Expanded(
                  child: tiamat.Text.labelLow(labelFollowColorsOffForTheme)),
            ]),
          ),
        ]);
      },
    );
  }

  Widget themeSettings(BuildContext context) {
    return Column(
      children: [
        Panel(
          header: labelSettingsAppTheme,
          mode: TileType.surfaceContainerLow,
          child: Column(children: [
            followSystemToggles(context),
            // Vommet: the Linux title bar (Vommet issue 384).
            const TitleBarSettings(),
            const Seperator(),
            const ThemeListWidget(),
          ]),
        ),
      ],
    );
  }
}

class UIScaleSelector extends StatefulWidget {
  const UIScaleSelector({super.key});

  @override
  State<UIScaleSelector> createState() => _UIScaleSelectorState();
}

class _UIScaleSelectorState extends State<UIScaleSelector> {
  double value = 1;

  @override
  void initState() {
    value = preferences.appScale.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return m.Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      child: Row(
        children: [
          SizedBox(width: 30, child: tiamat.Text(value.toStringAsPrecision(2))),
          Expanded(
              child: Slider(
            min: 0.5,
            max: preferences.developerMode.value ? 3 : 2,
            value: value,
            divisions: preferences.developerMode.value ? 25 : 15,
            onChanged: (value) {
              setState(() {
                this.value = value;
              });
            },
          )),
          Button.secondary(
            text: CommonStrings.promptApply,
            onTap: () {
              double newValue = value;
              preferences.appScale.set(newValue);
              ScaledWidgetsFlutterBinding.instance.scaleFactor = (deviceSize) {
                return newValue;
              };
            },
          )
        ],
      ),
    );
  }
}
