// Vommet: the settings search index (one entry per setting people may
// look for). The search also covers page names and the Experiments page by
// itself.
//
// This file is union-merged (.gitattributes), so topics that each add an
// entry don't conflict. Same rules as experiment_entries.dart:
// * add imports as separate lines below the existing ones;
// * add your entry directly above the closing `];` line, as one block whose
//   FIRST line is `// setting: <preference key or id>` and whose LAST line
//   is `), // <same id>`;
// * never change another topic's entry in the same commit.
//
// A setting whose preference exists on main passes `preference:` (the result
// row then gets a working switch). One that only exists in another topic
// passes its preference `key:` instead, so it still opens and flashes.
// unit_test/settings_search_test.dart fails when a settings page shows a
// preference that has no entry here.
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_navigation.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/config/room_encryption_default.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';

/// Searches the app settings shown in [categories].
List<SettingsSearchHit> searchAppSettings(
        String query, List<SettingsCategory> categories) =>
    SettingsSearch.search(query, categories, settingsSearchEntries(),
        experimentsTab: SettingsCategoryApp().labelSettingsAppExperiments);

/// Whether [categories] are the app settings (the only place with search).
bool isAppSettings(List<SettingsCategory> categories) =>
    categories.any((c) => c is SettingsCategoryApp);

List<SettingsSearchEntry> settingsSearchEntries() {
  final a = SettingsCategoryApp();
  final u = SettingsCategoryAccount();
  final app = a.title;
  final acc = u.title;
  return [
    // setting: tenorGifSearchEnabled
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Gif search",
      description:
          "Search for GIFs in the GIF picker. Requests go through a proxy",
      section: "Third party services",
      preference: preferences.tenorGifSearchEnabled,
      keywords: ["tenor", "gifs"],
    ), // tenorGifSearchEnabled
    // setting: urlPreviewInE2EEChat
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "URL Preview in Encrypted Chats",
      description:
          "This will expose any URLs sent in your encrypted chats to your homeserver in order to fetch the preview",
      section: "Third party services",
      preference: preferences.urlPreviewInE2EEChat,
      keywords: ["link preview", "links"],
    ), // urlPreviewInE2EEChat
    // setting: vommet_release_notice
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "New version notice",
      description:
          "Show a bar at the bottom of the app when a newer Vommet release is out",
      section: "Third party services",
      key: "vommet_release_notice",
      keywords: ["update", "release"],
    ), // vommet_release_notice
    // setting: askBeforeDeletingMessageEnabled
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Ask before deleting messages",
      description:
          "Enables the pop-up asking for confirmation when deleting a message.",
      section: "App Behavior",
      preference: preferences.askBeforeDeletingMessageEnabled,
      keywords: ["confirm", "delete", "redact"],
    ), // askBeforeDeletingMessageEnabled
    // setting: autoFocusMessageTextBox
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Autofocus Message Input",
      description:
          "Automatically focus on the message input text field when opening a chat",
      section: "App Behavior",
      preference: preferences.autoFocusMessageTextBox,
      keywords: ["keyboard", "composer"],
    ), // autoFocusMessageTextBox
    // setting: selectAutoCompleteSuggestion
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Select first auto-complete suggestion",
      description:
          "When typing a message, if there are any auto-complete suggestions, the first one will be highlighted by default",
      section: "App Behavior",
      preference: preferences.selectAutoCompleteSuggestion,
      keywords: ["autocomplete", "mention"],
    ), // selectAutoCompleteSuggestion
    // setting: automaticallyOpenSpace
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Always open space",
      description:
          "When navigating to a room from outside of a space, also open the space the room is in, if any",
      section: "App Behavior",
      preference: preferences.automaticallyOpenSpace,
    ), // automaticallyOpenSpace
    // setting: openRoomsAtLastReadMessage
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Open at last read message",
      description: "When opening a room, jump to the last message you read",
      section: "App Behavior",
      preference: preferences.openRoomsAtLastReadMessage,
      keywords: ["unread", "scroll"],
    ), // openRoomsAtLastReadMessage
    // setting: vommet_relative_date_dividers
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Relative dates in the chat",
      description:
          "The line between messages after a gap says Today, Yesterday or the weekday",
      section: "App Behavior",
      key: "vommet_relative_date_dividers",
      keywords: ["date", "day divider"],
    ), // vommet_relative_date_dividers
    // setting: pauseAnimationsWhenNotFocused
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Pause animations when unfocused",
      description:
          "When the app is in the background, pause animations to reduce CPU usage",
      section: "App Behavior",
      preference: preferences.pauseAnimationsWhenNotFocused,
      keywords: ["battery", "performance", "gif"],
    ), // pauseAnimationsWhenNotFocused
    // setting: messageEffectsEnabled
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Message Effects",
      description:
          "Messages can be sent with additional effects, such as confetti",
      section: "Message Effects",
      preference: preferences.messageEffectsEnabled,
      keywords: ["confetti", "fireworks"],
    ), // messageEffectsEnabled
    // setting: previewMediaInPrivateRooms
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Private Rooms",
      description:
          "Toggle previewing of images, videos, stickers and urls in private chats",
      section: "Media",
      preference: preferences.previewMediaInPrivateRooms,
      keywords: ["media preview", "images", "pictures"],
    ), // previewMediaInPrivateRooms
    // setting: previewMediaInPublicRooms
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Public Rooms",
      description:
          "Toggle previewing of images, videos, stickers and urls in public chat rooms",
      section: "Media",
      preference: preferences.previewMediaInPublicRooms,
      keywords: ["media preview", "images", "pictures"],
    ), // previewMediaInPublicRooms
    // setting: autoRotateImages
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Rotate Images",
      description:
          "When showing images in fullscreen, automatically rotate the image to best fill the screen",
      section: "Media",
      preference: preferences.autoRotateImages,
      keywords: ["fullscreen", "lightbox"],
    ), // autoRotateImages
    // setting: autoRotateVideos
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Rotate Videos",
      description:
          "When showing videos in fullscreen, automatically rotate the video to best fill the screen",
      section: "Media",
      preference: preferences.autoRotateVideos,
      keywords: ["fullscreen"],
    ), // autoRotateVideos
    // setting: allowed_remote_video_hosts
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Allowed Video Hosts",
      description: "Sites whose videos may play inside the chat",
      section: "Media",
      key: "allowed_remote_video_hosts",
      keywords: ["youtube", "embed", "video"],
    ), // allowed_remote_video_hosts
    // setting: appearance.theme
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Theme",
      description: "Pick the app's colors",
      keywords: ["dark mode", "light mode", "colors", "dracula"],
    ), // appearance.theme
    // setting: shouldFollowSystemTheme
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Theme mode",
      description: "Use one theme, or follow your device's light and dark mode",
      section: "Theme",
      preference: preferences.shouldFollowSystemTheme,
      inline: false,
      keywords: [
        "dark mode",
        "light mode",
        "follow system",
        "system brightness",
        "light theme",
        "dark theme"
      ],
    ), // shouldFollowSystemTheme
    // setting: shouldFollowSystemColors
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Follow System Colors",
      description: "Automatically follow system color scheme",
      section: "Theme",
      preference: preferences.shouldFollowSystemColors,
      inline: false,
      keywords: ["colors", "material you"],
    ), // shouldFollowSystemColors
    // setting: app_scale
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "App Scale",
      description: "Resizes the overall interface of the app",
      section: "Scaling",
      key: "app_scale",
      keywords: ["zoom", "size", "ui scale"],
    ), // app_scale
    // setting: text_scale
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Text Scale",
      description: "Multiply the size of text",
      section: "Scaling",
      key: "text_scale",
      keywords: ["font size", "bigger text"],
    ), // text_scale
    // setting: showRoomPreviewsInSpaceSidebar
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Show unjoined rooms in a space's room list",
      description:
          "List the rooms in a space that you haven't joined yet, next to the rooms you're in, so you can preview or join them",
      preference: preferences.showRoomPreviewsInSpaceSidebar,
    ), // showRoomPreviewsInSpaceSidebar
    // setting: showRoomsInSidebar
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Add a “Standalone rooms” button",
      description: "A # button for rooms that aren't part of a space",
      section: "Shortcuts under Home",
      preference: preferences.showRoomsInSidebar,
      keywords: ["standalone rooms", "rooms outside spaces", "sidebar"],
    ), // showRoomsInSidebar
    // setting: vommet_rail_unread_marks
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Show unread marks on spaces",
      description:
          "A small mark beside spaces with new messages. Mentions always show a red badge",
      key: "vommet_rail_unread_marks",
      keywords: ["unread", "badge", "dot"],
    ), // vommet_rail_unread_marks
    // setting: showRoomAvatars
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Use room avatars",
      description: "Show room avatar images instead of icons",
      preference: preferences.showRoomAvatars,
      keywords: ["icons", "pictures"],
    ), // showRoomAvatars
    // setting: usePlaceholderRoomAvatars
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Use placeholder avatars",
      description:
          "When a room does not have an avatar set, or using them is disabled, fallback to a generic color + first letter placeholder for the image",
      preference: preferences.usePlaceholderRoomAvatars,
    ), // usePlaceholderRoomAvatars
    // setting: org_mode_italics
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Org-mode style /italics/",
      description: "Send text between slashes, like /this/, in italics",
      key: "org_mode_italics",
      keywords: ["formatting", "markdown"],
    ), // org_mode_italics
    // setting: formatting_popup
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Formatting buttons",
      description:
          "Show a formatting bar when you select text in the message box",
      key: "formatting_popup",
      keywords: ["bold", "italic", "toolbar"],
    ), // formatting_popup
    // setting: showStateEvents
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Show state events",
      description:
          "Show changes to the room state, such as members joining and leaving, in the chat timeline",
      preference: preferences.showStateEvents,
      keywords: ["joins", "leaves", "membership"],
    ), // showStateEvents
    // setting: collapseStateEvents
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Collapse state events",
      description: "Group changes to room state in to a single timeline event",
      preference: preferences.collapseStateEvents,
    ), // collapseStateEvents
    // setting: group_consecutive_media
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Group pictures",
      description:
          "Show pictures and videos posted together by one person as a single mosaic",
      key: "group_consecutive_media",
      keywords: ["gallery", "mosaic", "images"],
    ), // group_consecutive_media
    // setting: vommet_layout_style_custom
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Layout",
      description:
          "Discord style, Telegram style or your own mix of the options",
      key: "vommet_layout_style_custom",
      keywords: ["discord", "telegram", "custom", "style", "look"],
    ), // vommet_layout_style_custom
    // setting: experiment_unified_chat_list
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Chats",
      description: "Spaces and Home, or one list of DMs, rooms and spaces",
      key: "experiment_unified_chat_list",
      keywords: [
        "telegram",
        "unified",
        "chat list",
        "one list",
        "spaces",
        "home"
      ],
    ), // experiment_unified_chat_list
    // setting: vommet_caption_below_media
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Captions",
      description: "Where the text sent with an image or video goes",
      key: "vommet_caption_below_media",
      keywords: ["caption", "image", "telegram", "under"],
    ), // vommet_caption_below_media
    // setting: vommet_limit_message_width
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Limit message width",
      description:
          "Long messages wrap at a comfortable reading width instead of filling the window",
      key: "vommet_limit_message_width",
      keywords: ["width", "wrap", "narrow", "compact"],
    ), // vommet_limit_message_width
    // setting: vommet_chat_bubble_layout
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Message bubbles",
      description: "Draw a rounded box around each message",
      key: "vommet_chat_bubble_layout",
      keywords: ["chat bubbles", "telegram", "whatsapp"],
    ), // vommet_chat_bubble_layout
    // setting: vommet_own_bubble_side
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Your messages",
      description:
          "Your messages on the right, or on the right only in narrow windows",
      key: "vommet_own_bubble_side",
      keywords: ["right", "side", "bubbles"],
    ), // vommet_own_bubble_side
    // setting: vommet_avatar_bottom_of_group
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      section: "Layout",
      title: "Avatar",
      description: "Where the sender's picture sits in a run of messages",
      key: "vommet_avatar_bottom_of_group",
      keywords: ["avatar", "picture", "bottom", "top"],
    ), // vommet_avatar_bottom_of_group
    // setting: vommet_banner_gradient
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Banners and panes",
      description: "The look of banners and side panes",
      key: "vommet_banner_gradient",
      keywords: ["gradient"],
    ), // vommet_banner_gradient
    // setting: vommet_thread_preview_mode
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Threads",
      description: "How threads are previewed in the chat",
      key: "vommet_thread_preview_mode",
      keywords: ["thread preview", "replies"],
    ), // vommet_thread_preview_mode
    // setting: vommet_reply_style
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Replies",
      description: "How a reply shows the message it answers",
      key: "vommet_reply_style",
      keywords: ["reply style", "quote", "element", "telegram"],
    ), // vommet_reply_style
    // setting: sounds.notification-sounds
    SettingsSearchEntry(
      category: app,
      tab: "Sounds",
      title: "Notification sounds",
      description:
          "Pick the sound for each kind of notification, or use your own file",
      keywords: ["ringtone", "custom sound", "volume"],
    ), // sounds.notification-sounds
    // setting: useFallbackTurnServer
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Use STUN Fallback",
      description:
          "Use a public server to help connect calls when your homeserver doesn't provide one",
      section: "Call Connection",
      preference: preferences.useFallbackTurnServer,
      keywords: ["turn", "connection"],
    ), // useFallbackTurnServer
    // setting: useVoipOverlay
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Enable Overlay",
      description:
          "When in a call, add an overlay on your screen to show the call participants",
      section: "Overlay",
      preference: preferences.useVoipOverlay,
      inline: false,
    ), // useVoipOverlay
    // setting: voip.default-audio-input
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Default Audio Input",
      description: "The microphone used in calls",
      section: "Devices",
      keywords: ["microphone", "mic", "input device"],
    ), // voip.default-audio-input
    // setting: voip.audio-output
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Audio Output",
      description: "The speakers or headphones used in calls",
      section: "Devices",
      keywords: ["speaker", "headphones", "headset", "output device"],
    ), // voip.audio-output
    // setting: stream_audio_kbps
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Audio Bitrate",
      description:
          "Adjust the bitrate of your outgoing audio. Higher is better",
      section: "Audio Settings",
      key: "stream_audio_kbps",
      keywords: ["quality", "microphone"],
    ), // stream_audio_kbps
    // setting: doSimulcast
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Use Simulcast",
      description:
          "Uploads your streams at multiple different levels of quality, so other users can decide which to use",
      section: "Stream Settings",
      preference: preferences.doSimulcast,
      keywords: ["screen share", "quality"],
    ), // doSimulcast
    // setting: screenshare_bitrate_mbps
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Stream Maximum Bitrate",
      description:
          "Determines the overall quality of your stream. Higher is better, but also uses more resources",
      section: "Stream Settings",
      key: "screenshare_bitrate_mbps",
      keywords: ["screen share", "quality"],
    ), // screenshare_bitrate_mbps
    // setting: screenshare_fps
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Stream Framerate",
      description: "Target frames per second for screen sharing",
      section: "Stream Settings",
      key: "screenshare_fps",
      keywords: ["fps", "screen share"],
    ), // screenshare_fps
    // setting: livekit_screenshare_codec
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Preferred Stream Codec",
      description: "The video codec used for screen sharing",
      section: "Stream Settings",
      key: "livekit_screenshare_codec",
      keywords: ["h264", "vp8", "vp9", "av1", "screen share"],
    ), // livekit_screenshare_codec
    // setting: livekit_screenshare_resolution
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Stream Resolution",
      description: "The resolution of your screen share",
      section: "Stream Settings",
      key: "livekit_screenshare_resolution",
      keywords: ["1080p", "720p", "screen share"],
    ), // livekit_screenshare_resolution
    // setting: shortcuts.keyboard-shortcuts
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsShortcuts,
      title: "Keyboard shortcuts",
      description: "Set keys for actions like mute and deafen",
      keywords: ["hotkey", "keybind", "push to talk"],
    ), // shortcuts.keyboard-shortcuts
    // setting: minimizeOnClose
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsWindowBehaviour,
      title: "Minimize on close",
      description:
          "When closing the window, the app will be minimized instead of exited",
      preference: preferences.minimizeOnClose,
      keywords: ["tray", "background", "exit"],
    ), // minimizeOnClose
    // setting: storage.storage-usage
    SettingsSearchEntry(
      category: app,
      tab: "Data and storage",
      title: "Storage usage",
      description: "See what takes space and clear the media cache",
      keywords: ["disk usage", "cache", "clear"],
    ), // storage.storage-usage
    // setting: media_cache_limit_mb
    SettingsSearchEntry(
      category: app,
      tab: "Data and storage",
      title: "Media cache limit",
      description: "The most space downloaded media may use",
      section: "Limits",
      key: "media_cache_limit_mb",
      keywords: ["cache", "size"],
    ), // media_cache_limit_mb
    // setting: media_cache_keep_days
    SettingsSearchEntry(
      category: app,
      tab: "Data and storage",
      title: "Remove media not opened for",
      description: "Clean out media you haven't looked at in a while",
      section: "Limits",
      key: "media_cache_keep_days",
      keywords: ["cache", "cleanup"],
    ), // media_cache_keep_days
    // setting: storage.automatic-media-download
    SettingsSearchEntry(
      category: app,
      tab: "Data and storage",
      title: "Automatic media download",
      description:
          "Choose what downloads by itself on Wi-Fi and on mobile data",
      keywords: ["auto-download", "wifi", "mobile data", "roaming"],
    ), // storage.automatic-media-download
    // setting: silenceNotifications
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Quiet notifications while I'm chatting on another device",
      description:
          "Notifications from a chat you just wrote in on another device come without sound",
      preference: preferences.silenceNotifications,
      keywords: ["silence", "mute", "sound"],
    ), // silenceNotifications
    // setting: enableNotifications
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Show notifications",
      description: "Enable or disable the display of notifications entirely",
      preference: preferences.enableNotifications,
    ), // enableNotifications
    // setting: suppressNotificationWhenRoomFocused
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Hide notifications for current room",
      description:
          "When receiving a message, if you have the chat selected and the app is in focus, dont show the notification",
      preference: preferences.suppressNotificationWhenRoomFocused,
    ), // suppressNotificationWhenRoomFocused
    // setting: in_app_notification_banners
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "In-app notification banners",
      description:
          "While Vommet is open, show new messages as a banner at the top of the app instead of a system notification",
      key: "in_app_notification_banners",
    ), // in_app_notification_banners
    // setting: showNotificationBadgesInTaskbar
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Notification Badges",
      description:
          "Show a badge with the number of unread messages in the system taskbar",
      preference: preferences.showNotificationBadgesInTaskbar,
      inline: false,
      keywords: ["unread count", "taskbar"],
    ), // showNotificationBadgesInTaskbar
    // setting: formatNotificationBody
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Message Body Formatting",
      description: "Apply user formatting in message notifications",
      preference: preferences.formatNotificationBody,
    ), // formatNotificationBody
    // setting: showMediaInNotifications
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Show Images",
      description: "Show images in notifications",
      preference: preferences.showMediaInNotifications,
      keywords: ["pictures", "media"],
    ), // showMediaInNotifications
    // setting: previewUrlInNotifications
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Preview Urls",
      description:
          "Fetch URL previews to show extra information about links in notifications",
      preference: preferences.previewUrlInNotifications,
      keywords: ["links"],
    ), // previewUrlInNotifications
    // setting: notifications_volume
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Notification volume",
      description: "Controls the volume of notifications and ringtones",
      key: "notifications_volume",
      keywords: ["sound", "loud"],
    ), // notifications_volume
    // setting: notif.push-notifications
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Push Notifications",
      description: "Set up push notifications for this device",
      keywords: ["unified push", "ntfy", "push"],
    ), // notif.push-notifications
    // setting: telemetry_consent
    SettingsSearchEntry(
      category: app,
      tab: "Privacy",
      title: "Send diagnostics",
      description:
          "Send anonymous crash and performance reports to help fix bugs",
      key: "telemetry_consent",
      keywords: ["telemetry", "crash reports", "analytics"],
    ), // telemetry_consent
    // setting: developerMode
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAdvanced,
      title: "Developer mode",
      description: "Shows extra information, useful for developers",
      preference: preferences.developerMode,
      inline: false,
      keywords: ["debug"],
    ), // developerMode
    // setting: vommet_show_hidden_events
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAdvanced,
      title: "Show hidden events",
      description:
          "Also show events the timeline normally hides, such as reactions and deletions, as plain rows",
      key: "vommet_show_hidden_events",
      keywords: ["debug", "raw events"],
    ), // vommet_show_hidden_events
    // setting: stickerCompatibilityMode
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAdvanced,
      title: "Sticker compatibility",
      description:
          "Send stickers as 'm.image' so they render in clients that can't show 'm.sticker'",
      preference: preferences.stickerCompatibilityMode,
      keywords: ["stickers"],
    ), // stickerCompatibilityMode
    // setting: advanced.override-layout
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAdvanced,
      title: "Override Layout",
      description: "Force the phone or desktop layout",
      keywords: ["mobile layout", "desktop layout"],
    ), // advanced.override-layout
    // setting: disableTextCursorManagement
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Disable Text Cursor Management",
      preference: preferences.disableTextCursorManagement,
      inline: false,
    ), // disableTextCursorManagement
    // setting: useSharedIsolateInBackgroundTasks
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Use shared database isolate in background",
      preference: preferences.useSharedIsolateInBackgroundTasks,
      inline: false,
    ), // useSharedIsolateInBackgroundTasks
    // setting: debugTranslations
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Debug Translations",
      preference: preferences.debugTranslations,
      inline: false,
    ), // debugTranslations
    // setting: widgetDeveloperMode
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Enable widget developer mode",
      preference: preferences.widgetDeveloperMode,
      inline: false,
    ), // widgetDeveloperMode
    // setting: showPerformanceOverlay
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Show performance overlay",
      preference: preferences.showPerformanceOverlay,
      inline: false,
    ), // showPerformanceOverlay
    // setting: custom_onscreen_keyboard_view_offset
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppDeveloperUtils,
      title: "Keyboard Offset",
      key: "custom_onscreen_keyboard_view_offset",
      keywords: ["onscreen keyboard"],
    ), // custom_onscreen_keyboard_view_offset
    // setting: profile.avatar
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Avatar",
      description: "Change your profile picture",
      keywords: ["profile picture", "photo"],
    ), // profile.avatar
    // setting: profile.display-name
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Display name",
      description: "The name others see",
      keywords: ["nickname", "username"],
    ), // profile.display-name
    // setting: profile.banner
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Banner",
      description: "The picture at the top of your profile",
    ), // profile.banner
    // setting: profile.status
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Status",
      description: "A short message shown next to your name",
      keywords: ["presence", "away"],
    ), // profile.status
    // setting: profile.bio
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Bio",
      description: "A few lines about yourself, shown on your profile",
      keywords: ["about me"],
    ), // profile.bio
    // setting: profile.timezone
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Timezone",
      description: "Show others your local time on your profile",
      keywords: ["time zone", "local time", "clock"],
    ), // profile.timezone
    // setting: profile.color-scheme
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabProfile,
      title: "Color Scheme",
      description: "The colors of your profile card",
      keywords: ["color", "theme"],
    ), // profile.color-scheme
    // setting: uprivacy.read-receipts
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabPrivacy,
      title: "Read receipts",
      description:
          "Let other members of a room know when you have read their messages.",
      section: "Chat Privacy",
      keywords: ["seen"],
    ), // uprivacy.read-receipts
    // setting: uprivacy.typing-indicator
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabPrivacy,
      title: "Typing indicator",
      description:
          "Let other members of a room know when you are typing a message.",
      section: "Chat Privacy",
      keywords: ["typing"],
    ), // uprivacy.typing-indicator
    // setting: uprivacy.allow-invitations
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabPrivacy,
      title: "Allow invitations",
      description: "Allow other users to invite you to rooms",
      section: "Chat Privacy",
      keywords: ["invites"],
    ), // uprivacy.allow-invitations
    // setting: security.sessions
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Sessions",
      description: "Your signed-in devices; verify or sign out of them",
      keywords: ["devices", "verify", "log out"],
    ), // security.sessions
    // setting: security.cross-signing
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Cross signing",
      description: "Set up to verify and keep track of all your sessions",
      keywords: ["verification", "verify"],
    ), // security.cross-signing
    // setting: security.message-backup
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Message backup",
      description:
          "Back up your encryption keys so you can read old messages on new devices",
      keywords: ["recovery key", "encryption", "restore"],
    ), // security.message-backup
    // setting: security.key-file
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Key file",
      description: "Export or import your room keys as a file",
      keywords: ["export keys", "import keys", "encryption"],
    ), // security.key-file
    // setting: security.blocked-users
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Blocked users",
      description: "People whose messages, invites and calls are hidden",
      keywords: ["block", "ignore"],
    ), // security.blocked-users
    // setting: emoji.favorite-packs
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabEmoticons,
      title: "Favorite Packs",
      description: "Emoji and sticker packs you use everywhere",
      keywords: ["stickers", "emoji", "emotes", "emoticons"],
    ), // emoji.favorite-packs
    // setting: accounts.accounts
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabManageAccounts,
      title: "Accounts",
      description: "Add another account or sign out",
      keywords: ["add account", "log out", "sign out", "login"],
    ), // accounts.accounts
    // setting: voip_microphone_volume
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Input Volume",
      description: "How loud your microphone is to everyone else",
      section: "Devices",
      key: "voip_microphone_volume",
      keywords: ["microphone", "mic", "gain", "loud"],
    ), // voip_microphone_volume
    // setting: voip_output_volume
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Output Volume",
      description:
          "Turns down everyone in your calls and the audio of streams you watch",
      section: "Devices",
      key: "voip_output_volume",
      keywords: ["speaker", "headphones", "loud", "quiet"],
    ), // voip_output_volume
    // setting: voip_push_to_talk
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Push to talk",
      description:
          "Your microphone only sends while you hold a key or the talk button",
      section: "Input Mode",
      key: "voip_push_to_talk",
      keywords: ["ptt", "voice activity", "input mode", "hotkey", "key"],
    ), // voip_push_to_talk
    // setting: voip_push_to_talk_release_delay
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Release delay",
      description: "Keeps sending a moment after you let go of push to talk",
      section: "Input Mode",
      key: "voip_push_to_talk_release_delay",
      keywords: ["ptt", "push to talk", "delay"],
    ), // voip_push_to_talk_release_delay
    // setting: voip_push_to_talk_sounds
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsCategoryVoiceAndVideo,
      title: "Talk sounds",
      description: "A soft click when push to talk starts and stops",
      section: "Input Mode",
      key: "voip_push_to_talk_sounds",
      keywords: ["ptt", "push to talk", "click", "sound"],
    ), // voip_push_to_talk_sounds
    // setting: vommet_member_list_subtitle
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Member list",
      description: "What shows under each member's name: homeserver or status",
      key: "vommet_member_list_subtitle",
      keywords: ["status", "homeserver", "server", "members"],
    ), // vommet_member_list_subtitle
    // setting: vommet_app_language
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Language",
      description: "The app language, or follow the device's language",
      section: "Language",
      key: "vommet_app_language",
      keywords: ["locale", "translation", "translate", "system language"],
    ), // vommet_app_language
    // setting: autoplay_gifs
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Autoplay GIFs",
      description:
          "Play GIFs, including GIFs bridged from Telegram, WhatsApp and Discord, by themselves. When off, tap a GIF to play it",
      section: "Media",
      key: "autoplay_gifs",
      keywords: ["gif", "animation", "animated", "loop", "motion", "telegram"],
    ), // autoplay_gifs
    // setting: rehide_media_spoilers
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Hide spoilers again",
      description:
          "Blur spoiler pictures and videos again when you switch to another room, like Telegram",
      section: "Media",
      key: "rehide_media_spoilers",
      keywords: ["spoiler", "blur", "reveal", "telegram", "image", "video"],
    ), // rehide_media_spoilers
    // setting: linkBareDomains
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Link bare web addresses",
      description:
          "Turns addresses like example.com into links, like Telegram does",
      section: "App Behavior",
      preference: preferences.linkBareDomains,
      keywords: ["links", "url", "autolink", "domain", "telegram"],
    ), // linkBareDomains
    // setting: vommet_show_tray_icon
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsWindowBehaviour,
      title: "Show tray icon",
      description:
          "Keep an icon in the system tray to show or hide the window and to quit. Needs a desktop or panel with a tray",
      key: "vommet_show_tray_icon",
      keywords: ["tray", "system tray", "appindicator", "background"],
    ), // vommet_show_tray_icon
    // setting: vommet_tray_unread_badge
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsWindowBehaviour,
      title: "Unread badge on tray icon",
      description:
          "Show how many unread messages notify you on the tray icon. Counts the same messages as the taskbar badge",
      key: "vommet_tray_unread_badge",
      keywords: ["tray", "badge", "unread", "count", "notification"],
    ), // vommet_tray_unread_badge
    // setting: vommet_close_to_tray
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsWindowBehaviour,
      title: "Close to tray",
      description:
          "When closing the window, hide it and keep the app running in the tray. Without a tray, closing works as usual",
      key: "vommet_close_to_tray",
      keywords: ["tray", "minimize", "background", "hide", "exit"],
    ), // vommet_close_to_tray
    // setting: telemetry_tag
    SettingsSearchEntry(
      category: app,
      tab: "Privacy",
      title: "Name tag",
      description:
          "An optional tag sent with your diagnostics, so the developers can find your reports",
      key: "telemetry_tag",
      keywords: ["telemetry", "diagnostics", "tag", "testing", "testers"],
    ), // telemetry_tag
    // setting: vommet_clock_format
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Clock",
      description: "How message times and other times in the app are shown",
      key: "vommet_clock_format",
      keywords: [
        "24-hour",
        "12-hour",
        "24 hour",
        "12 hour",
        "time format",
        "am pm"
      ],
    ), // vommet_clock_format
    // setting: vommet_sidebar_icon_size
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Sidebar icon size",
      description:
          "The size of the Home, direct message and space icons on the sidebar",
      key: "vommet_sidebar_icon_size",
      keywords: ["rail", "spaces", "icons", "compact", "smaller", "discord"],
    ), // vommet_sidebar_icon_size
    // setting: security.shared-history
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Let people who join later read my messages",
      description:
          "Whether people who join an encrypted room later can read your earlier messages",
      keywords: ["history", "shared history", "encryption", "invite"],
    ), // security.shared-history
    // setting: vommet_encrypt_new_rooms
    SettingsSearchEntry(
      category: app,
      tab: "Privacy",
      title: "Encrypt new rooms",
      description:
          "The encryption switch starts on when you make a room. You can still change it for each room",
      section: "Encryption",
      preference: encryptNewRoomsByDefault,
      keywords: ["e2ee", "encryption", "default", "create room"],
    ), // vommet_encrypt_new_rooms
    // setting: vommet_message_density
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Message spacing",
      description: "Cozy or compact: how tightly messages are packed in a room",
      key: "vommet_message_density",
      keywords: ["density", "compact", "cozy", "spacing", "padding"],
    ), // vommet_message_density
    // setting: vommet_onboarding_rerun
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppGeneral,
      title: "Run setup again",
      description:
          "Pick your language, layout, theme, message spacing and room encryption again, as on the first start",
      section: "First-run setup",
      key: "vommet_onboarding_rerun",
      keywords: ["onboarding", "welcome", "first run", "setup"],
    ), // vommet_onboarding_rerun
    // setting: security.recovery-checkins
    SettingsSearchEntry(
      category: acc,
      tab: u.labelSettingsTabSecurity,
      title: "Recovery key check-ins",
      description:
          "Now and then, Vommet asks for your recovery key to make sure you still have it",
      section: "Encryption & recovery",
      key: recoveryCheckInsSettingId,
      keywords: ["recovery key", "reminder", "check", "encryption", "backup"],
    ), // security.recovery-checkins
    // setting: notifyOnReactions
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppNotifications,
      title: "Notify me about reactions to my messages",
      description:
          "Get a notification when someone reacts to one of your messages",
      preference: preferences.notifyOnReactions,
      keywords: ["reaction", "emoji", "react"],
    ), // notifyOnReactions
    // setting: vommet_people_in_rail
    SettingsSearchEntry(
      category: app,
      tab: a.labelSettingsAppAppearance,
      title: "Add a People button",
      description:
          "Opens People: contacts, direct-message invites and blocked people. People is always in Home too",
      section: "Shortcuts under Home",
      preference: peopleInRail,
      keywords: ["people", "contacts", "friends", "invites", "sidebar"],
    ), // vommet_people_in_rail
  ];
}
