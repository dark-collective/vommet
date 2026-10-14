// Vommet: translations for the settings search index. The entries in
// settings_search_entries.dart stay plain English (that file is
// union-merged, so its blocks must not change); search looks each title,
// description and section up here by its English text and falls back to the
// entry's own text when there's no message for it (a new entry, or one whose
// wording changed since). The English text still matches too, so searching
// in English works in every language. To translate a new entry, add its
// strings below with the English text copied byte for byte.
// Developer Utils entries stay English, like that page.
import 'package:commet/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:intl/intl.dart';

/// [e] with its title, description, section and tab in the app's language.
/// Returns [e] itself when nothing is translated (English).
SettingsSearchEntry localizeSettingsSearchEntry(SettingsSearchEntry e) {
  final title = _titles[e.title]?.call() ?? e.title;
  final description = e.description == null
      ? null
      : _descriptions[e.description!]?.call() ?? e.description;
  final section =
      e.section == null ? null : _sections[e.section!]?.call() ?? e.section;
  final tab = _tabs[e.tab]?.call() ?? e.tab;
  if (title == e.title &&
      description == e.description &&
      section == e.section &&
      tab == e.tab) {
    return e;
  }
  return SettingsSearchEntry(
    category: e.category,
    tab: tab,
    title: title,
    description: description,
    section: section,
    // Keep the original target, so the page flashes the same control.
    key: e.targetId,
    preference: e.preference,
    inline: e.inline,
    keywords: [
      ...e.keywords,
      // The English words still find it.
      if (title != e.title) e.title,
      if (section != e.section) e.section!,
      if (description != e.description) e.description!,
    ],
  );
}

/// Tabs some entries name by their English label. The result must equal
/// the page's own (translated) label, or the entry is dropped.
final Map<String, String Function()> _tabs = {
  "Data and storage": () => SettingsCategoryApp().labelSettingsDataAndStorage,
  "Sounds": () => labelSettingsSounds,
  "Privacy": () => labelSettingsPrivacy,
};

final Map<String, String Function()> _titles = {
  "Gif search": () => settingsSearchTenorGifSearchEnabledTitle,
  "URL Preview in Encrypted Chats": () =>
      settingsSearchUrlPreviewInE2EEChatTitle,
  "New version notice": () => settingsSearchReleaseNoticeTitle,
  "Ask before deleting messages": () =>
      settingsSearchAskBeforeDeletingMessageEnabledTitle,
  "Autofocus Message Input": () => settingsSearchAutoFocusMessageTextBoxTitle,
  "Select first auto-complete suggestion": () =>
      settingsSearchSelectAutoCompleteSuggestionTitle,
  "Always open space": () => settingsSearchAutomaticallyOpenSpaceTitle,
  "Open at last read message": () =>
      settingsSearchOpenRoomsAtLastReadMessageTitle,
  "Relative dates in the chat": () => settingsSearchRelativeDateDividersTitle,
  "Pause animations when unfocused": () =>
      settingsSearchPauseAnimationsWhenNotFocusedTitle,
  "Message Effects": () => settingsSearchMessageEffectsEnabledTitle,
  "Private Rooms": () => settingsSearchPreviewMediaInPrivateRoomsTitle,
  "Public Rooms": () => settingsSearchPreviewMediaInPublicRoomsTitle,
  "Rotate Images": () => settingsSearchAutoRotateImagesTitle,
  "Rotate Videos": () => settingsSearchAutoRotateVideosTitle,
  "Allowed Video Hosts": () => settingsSearchAllowedRemoteVideoHostsTitle,
  "Theme": () => settingsSearchAppearanceThemeTitle,
  "Theme mode": () => settingsSearchShouldFollowSystemThemeTitle,
  "Follow System Colors": () => settingsSearchShouldFollowSystemColorsTitle,
  "App Scale": () => settingsSearchAppScaleTitle,
  "Text Scale": () => settingsSearchTextScaleTitle,
  "Show unjoined rooms in sidebar": () =>
      settingsSearchShowRoomPreviewsInSpaceSidebarTitle,
  "Show rooms in sidebar": () => settingsSearchShowRoomsInSidebarTitle,
  "Show unread marks on spaces": () => settingsSearchRailUnreadMarksTitle,
  "Use room avatars": () => settingsSearchShowRoomAvatarsTitle,
  "Use placeholder avatars": () => settingsSearchUsePlaceholderRoomAvatarsTitle,
  "Org-mode style /italics/": () => settingsSearchOrgModeItalicsTitle,
  "Formatting buttons": () => settingsSearchFormattingPopupTitle,
  "Show state events": () => settingsSearchShowStateEventsTitle,
  "Collapse state events": () => settingsSearchCollapseStateEventsTitle,
  "Group pictures": () => settingsSearchGroupConsecutiveMediaTitle,
  "Banners and panes": () => settingsSearchBannerGradientTitle,
  "Threads": () => settingsSearchThreadPreviewModeTitle,
  "Notification sounds": () => settingsSearchSoundsNotificationSoundsTitle,
  "Use STUN Fallback": () => settingsSearchUseFallbackTurnServerTitle,
  "Enable Overlay": () => settingsSearchUseVoipOverlayTitle,
  "Default Audio Input": () => settingsSearchVoipDefaultAudioInputTitle,
  "Audio Output": () => settingsSearchVoipAudioOutputTitle,
  "Audio Bitrate": () => settingsSearchStreamAudioKbpsTitle,
  "Use Simulcast": () => settingsSearchDoSimulcastTitle,
  "Stream Maximum Bitrate": () => settingsSearchScreenshareBitrateMbpsTitle,
  "Stream Framerate": () => settingsSearchScreenshareFpsTitle,
  "Preferred Stream Codec": () => settingsSearchLivekitScreenshareCodecTitle,
  "Stream Resolution": () => settingsSearchLivekitScreenshareResolutionTitle,
  "Keyboard shortcuts": () => settingsSearchShortcutsKeyboardShortcutsTitle,
  "Minimize on close": () => settingsSearchMinimizeOnCloseTitle,
  "Storage usage": () => settingsSearchStorageStorageUsageTitle,
  "Media cache limit": () => settingsSearchMediaCacheLimitMbTitle,
  "Remove media not opened for": () => settingsSearchMediaCacheKeepDaysTitle,
  "Automatic media download": () =>
      settingsSearchStorageAutomaticMediaDownloadTitle,
  "Quiet notifications while I'm chatting on another device": () =>
      settingsSearchSilenceNotificationsTitle,
  "Show notifications": () => settingsSearchEnableNotificationsTitle,
  "Hide notifications for current room": () =>
      settingsSearchSuppressNotificationWhenRoomFocusedTitle,
  "In-app notification banners": () =>
      settingsSearchInAppNotificationBannersTitle,
  "Notification Badges": () =>
      settingsSearchShowNotificationBadgesInTaskbarTitle,
  "Message Body Formatting": () => settingsSearchFormatNotificationBodyTitle,
  "Show Images": () => settingsSearchShowMediaInNotificationsTitle,
  "Preview Urls": () => settingsSearchPreviewUrlInNotificationsTitle,
  "Notification volume": () => settingsSearchNotificationsVolumeTitle,
  "Push Notifications": () => settingsSearchNotifPushNotificationsTitle,
  "Send diagnostics": () => settingsSearchTelemetryConsentTitle,
  "Developer mode": () => settingsSearchDeveloperModeTitle,
  "Show hidden events": () => settingsSearchShowHiddenEventsTitle,
  "Sticker compatibility": () => settingsSearchStickerCompatibilityModeTitle,
  "Override Layout": () => settingsSearchAdvancedOverrideLayoutTitle,
  "Avatar": () => settingsSearchProfileAvatarTitle,
  "Display name": () => settingsSearchProfileDisplayNameTitle,
  "Banner": () => settingsSearchProfileBannerTitle,
  "Status": () => settingsSearchProfileStatusTitle,
  "Bio": () => settingsSearchProfileBioTitle,
  "Timezone": () => settingsSearchProfileTimezoneTitle,
  "Color Scheme": () => settingsSearchProfileColorSchemeTitle,
  "Read receipts": () => settingsSearchUprivacyReadReceiptsTitle,
  "Typing indicator": () => settingsSearchUprivacyTypingIndicatorTitle,
  "Allow invitations": () => settingsSearchUprivacyAllowInvitationsTitle,
  "Sessions": () => settingsSearchSecuritySessionsTitle,
  "Cross signing": () => settingsSearchSecurityCrossSigningTitle,
  "Message backup": () => settingsSearchSecurityMessageBackupTitle,
  "Key file": () => settingsSearchSecurityKeyFileTitle,
  "Blocked users": () => settingsSearchSecurityBlockedUsersTitle,
  "Favorite Packs": () => settingsSearchEmojiFavoritePacksTitle,
  "Accounts": () => settingsSearchAccountsAccountsTitle,
  "Input Volume": () => settingsSearchVoipMicrophoneVolumeTitle,
  "Output Volume": () => settingsSearchVoipOutputVolumeTitle,
  "Push to talk": () => settingsSearchVoipPushToTalkTitle,
  "Release delay": () => settingsSearchVoipPushToTalkReleaseDelayTitle,
  "Talk sounds": () => settingsSearchVoipPushToTalkSoundsTitle,
  "Member list": () => settingsSearchMemberListSubtitleTitle,
};

final Map<String, String Function()> _descriptions = {
  "Search for GIFs in the GIF picker. Requests go through a proxy": () =>
      settingsSearchTenorGifSearchEnabledDescription,
  "This will expose any URLs sent in your encrypted chats to your homeserver in order to fetch the preview":
      () => settingsSearchUrlPreviewInE2EEChatDescription,
  "Show a bar at the bottom of the app when a newer Vommet release is out":
      () => settingsSearchReleaseNoticeDescription,
  "Enables the pop-up asking for confirmation when deleting a message.": () =>
      settingsSearchAskBeforeDeletingMessageEnabledDescription,
  "Automatically focus on the message input text field when opening a chat":
      () => settingsSearchAutoFocusMessageTextBoxDescription,
  "When typing a message, if there are any auto-complete suggestions, the first one will be highlighted by default":
      () => settingsSearchSelectAutoCompleteSuggestionDescription,
  "When navigating to a room from outside of a space, also open the space the room is in, if any":
      () => settingsSearchAutomaticallyOpenSpaceDescription,
  "When opening a room, jump to the last message you read": () =>
      settingsSearchOpenRoomsAtLastReadMessageDescription,
  "The line between messages after a gap says Today, Yesterday or the weekday":
      () => settingsSearchRelativeDateDividersDescription,
  "When the app is in the background, pause animations to reduce CPU usage":
      () => settingsSearchPauseAnimationsWhenNotFocusedDescription,
  "Messages can be sent with additional effects, such as confetti": () =>
      settingsSearchMessageEffectsEnabledDescription,
  "Toggle previewing of images, videos, stickers and urls in private chats":
      () => settingsSearchPreviewMediaInPrivateRoomsDescription,
  "Toggle previewing of images, videos, stickers and urls in public chat rooms":
      () => settingsSearchPreviewMediaInPublicRoomsDescription,
  "When showing images in fullscreen, automatically rotate the image to best fill the screen":
      () => settingsSearchAutoRotateImagesDescription,
  "When showing videos in fullscreen, automatically rotate the video to best fill the screen":
      () => settingsSearchAutoRotateVideosDescription,
  "Sites whose videos may play inside the chat": () =>
      settingsSearchAllowedRemoteVideoHostsDescription,
  "Pick the app's colours": () => settingsSearchAppearanceThemeDescription,
  "Use one theme, or follow your device's light and dark mode": () =>
      settingsSearchShouldFollowSystemThemeDescription,
  "Automatically follow system color scheme": () =>
      settingsSearchShouldFollowSystemColorsDescription,
  "Resizes the overall interface of the app": () =>
      settingsSearchAppScaleDescription,
  "Multiply the size of text": () => settingsSearchTextScaleDescription,
  "When there are rooms which you have not joined in a space, show them in the sidebar with the rest of the rooms in the space":
      () => settingsSearchShowRoomPreviewsInSpaceSidebarDescription,
  "Add an entry to the sidebar that shows all rooms which are not contained in a space":
      () => settingsSearchShowRoomsInSidebarDescription,
  "A small mark beside spaces with new messages. Mentions always show a red badge":
      () => settingsSearchRailUnreadMarksDescription,
  "Show room avatar images instead of icons": () =>
      settingsSearchShowRoomAvatarsDescription,
  "When a room does not have an avatar set, or using them is disabled, fallback to a generic color + first letter placeholder for the image":
      () => settingsSearchUsePlaceholderRoomAvatarsDescription,
  "Send text between slashes, like /this/, in italics": () =>
      settingsSearchOrgModeItalicsDescription,
  "Show a formatting bar when you select text in the message box": () =>
      settingsSearchFormattingPopupDescription,
  "Show changes to the room state, such as members joining and leaving, in the chat timeline":
      () => settingsSearchShowStateEventsDescription,
  "Group changes to room state in to a single timeline event": () =>
      settingsSearchCollapseStateEventsDescription,
  "Show pictures and videos posted together by one person as a single mosaic":
      () => settingsSearchGroupConsecutiveMediaDescription,
  "The look of banners and side panes": () =>
      settingsSearchBannerGradientDescription,
  "How threads are previewed in the chat": () =>
      settingsSearchThreadPreviewModeDescription,
  "Pick the sound for each kind of notification, or use your own file": () =>
      settingsSearchSoundsNotificationSoundsDescription,
  "Use a public server to help connect calls when your homeserver doesn't provide one":
      () => settingsSearchUseFallbackTurnServerDescription,
  "When in a call, add an overlay on your screen to show the call participants":
      () => settingsSearchUseVoipOverlayDescription,
  "The microphone used in calls": () =>
      settingsSearchVoipDefaultAudioInputDescription,
  "The speakers or headphones used in calls": () =>
      settingsSearchVoipAudioOutputDescription,
  "Adjust the bitrate of your outgoing audio. Higher is better": () =>
      settingsSearchStreamAudioKbpsDescription,
  "Uploads your streams at multiple different levels of quality, so other users can decide which to use":
      () => settingsSearchDoSimulcastDescription,
  "Determines the overall quality of your stream. Higher is better, but also uses more resources":
      () => settingsSearchScreenshareBitrateMbpsDescription,
  "Target frames per second for screen sharing": () =>
      settingsSearchScreenshareFpsDescription,
  "The video codec used for screen sharing": () =>
      settingsSearchLivekitScreenshareCodecDescription,
  "The resolution of your screen share": () =>
      settingsSearchLivekitScreenshareResolutionDescription,
  "Set keys for actions like mute and deafen": () =>
      settingsSearchShortcutsKeyboardShortcutsDescription,
  "When closing the window, the app will be minimized instead of exited": () =>
      settingsSearchMinimizeOnCloseDescription,
  "See what takes space and clear the media cache": () =>
      settingsSearchStorageStorageUsageDescription,
  "The most space downloaded media may use": () =>
      settingsSearchMediaCacheLimitMbDescription,
  "Clean out media you haven't looked at in a while": () =>
      settingsSearchMediaCacheKeepDaysDescription,
  "Choose what downloads by itself on Wi-Fi and on mobile data": () =>
      settingsSearchStorageAutomaticMediaDownloadDescription,
  "Notifications from a chat you just wrote in on another device come without sound":
      () => settingsSearchSilenceNotificationsDescription,
  "Enable or disable the display of notifications entirely": () =>
      settingsSearchEnableNotificationsDescription,
  "When receiving a message, if you have the chat selected and the app is in focus, dont show the notification":
      () => settingsSearchSuppressNotificationWhenRoomFocusedDescription,
  "While Vommet is open, show new messages as a banner at the top of the app instead of a system notification":
      () => settingsSearchInAppNotificationBannersDescription,
  "Show a badge with the number of unread messages in the system taskbar": () =>
      settingsSearchShowNotificationBadgesInTaskbarDescription,
  "Apply user formatting in message notifications": () =>
      settingsSearchFormatNotificationBodyDescription,
  "Show images in notifications": () =>
      settingsSearchShowMediaInNotificationsDescription,
  "Fetch URL previews to show extra information about links in notifications":
      () => settingsSearchPreviewUrlInNotificationsDescription,
  "Controls the volume of notifications and ringtones": () =>
      settingsSearchNotificationsVolumeDescription,
  "Set up push notifications for this device": () =>
      settingsSearchNotifPushNotificationsDescription,
  "Send anonymous crash and performance reports to help fix bugs": () =>
      settingsSearchTelemetryConsentDescription,
  "Shows extra information, useful for developers": () =>
      settingsSearchDeveloperModeDescription,
  "Also show events the timeline normally hides, such as reactions and deletions, as plain rows":
      () => settingsSearchShowHiddenEventsDescription,
  "Send stickers as 'm.image' so they render in clients that can't show 'm.sticker'":
      () => settingsSearchStickerCompatibilityModeDescription,
  "Force the phone or desktop layout": () =>
      settingsSearchAdvancedOverrideLayoutDescription,
  "Change your profile picture": () => settingsSearchProfileAvatarDescription,
  "The name others see": () => settingsSearchProfileDisplayNameDescription,
  "The picture at the top of your profile": () =>
      settingsSearchProfileBannerDescription,
  "A short message shown next to your name": () =>
      settingsSearchProfileStatusDescription,
  "A few lines about yourself, shown on your profile": () =>
      settingsSearchProfileBioDescription,
  "Show others your local time on your profile": () =>
      settingsSearchProfileTimezoneDescription,
  "The colours of your profile card": () =>
      settingsSearchProfileColorSchemeDescription,
  "Let other members of a room know when you have read their messages.": () =>
      settingsSearchUprivacyReadReceiptsDescription,
  "Let other members of a room know when you are typing a message.": () =>
      settingsSearchUprivacyTypingIndicatorDescription,
  "Allow other users to invite you to rooms": () =>
      settingsSearchUprivacyAllowInvitationsDescription,
  "Your signed-in devices; verify or sign out of them": () =>
      settingsSearchSecuritySessionsDescription,
  "Set up to verify and keep track of all your sessions": () =>
      settingsSearchSecurityCrossSigningDescription,
  "Back up your encryption keys so you can read old messages on new devices":
      () => settingsSearchSecurityMessageBackupDescription,
  "Export or import your room keys as a file": () =>
      settingsSearchSecurityKeyFileDescription,
  "People whose messages, invites and calls are hidden": () =>
      settingsSearchSecurityBlockedUsersDescription,
  "Emoji and sticker packs you use everywhere": () =>
      settingsSearchEmojiFavoritePacksDescription,
  "Add another account or sign out": () =>
      settingsSearchAccountsAccountsDescription,
  "How loud your microphone is to everyone else": () =>
      settingsSearchVoipMicrophoneVolumeDescription,
  "Turns down everyone in your calls and the audio of streams you watch": () =>
      settingsSearchVoipOutputVolumeDescription,
  "Your microphone only sends while you hold a key or the talk button": () =>
      settingsSearchVoipPushToTalkDescription,
  "Keeps sending a moment after you let go of push to talk": () =>
      settingsSearchVoipPushToTalkReleaseDelayDescription,
  "A soft click when push to talk starts and stops": () =>
      settingsSearchVoipPushToTalkSoundsDescription,
  "What shows under each member's name: homeserver or status": () =>
      settingsSearchMemberListSubtitleDescription,
};

final Map<String, String Function()> _sections = {
  "Third party services": () => settingsSearchSectionThirdPartyServices,
  "App Behaviour": () => settingsSearchSectionAppBehaviour,
  "Message Effects": () => settingsSearchSectionMessageEffects,
  "Media": () => settingsSearchSectionMedia,
  "Theme": () => settingsSearchSectionTheme,
  "Scaling": () => settingsSearchSectionScaling,
  "Call Connection": () => settingsSearchSectionCallConnection,
  "Overlay": () => settingsSearchSectionOverlay,
  "Devices": () => settingsSearchSectionDevices,
  "Audio Settings": () => settingsSearchSectionAudioSettings,
  "Stream Settings": () => settingsSearchSectionStreamSettings,
  "Limits": () => settingsSearchSectionLimits,
  "Chat Privacy": () => settingsSearchSectionChatPrivacy,
  "Input Mode": () => settingsSearchSectionInputMode,
};

String get settingsSearchTenorGifSearchEnabledTitle => Intl.message(
    "Gif search",
    name: "settingsSearchTenorGifSearchEnabledTitle",
    desc:
        "Settings search result title for the \"Gif search\" setting; use the same wording as that setting's label on its page");

String get settingsSearchTenorGifSearchEnabledDescription => Intl.message(
    "Search for GIFs in the GIF picker. Requests go through a proxy",
    name: "settingsSearchTenorGifSearchEnabledDescription",
    desc:
        "Settings search result: one-line explanation of the \"Gif search\" setting, shown under its title");

String get settingsSearchSectionThirdPartyServices => Intl.message(
    "Third party services",
    name: "settingsSearchSectionThirdPartyServices",
    desc:
        "Settings search result: name of the \"Third party services\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchUrlPreviewInE2EEChatTitle => Intl.message(
    "URL Preview in Encrypted Chats",
    name: "settingsSearchUrlPreviewInE2EEChatTitle",
    desc:
        "Settings search result title for the \"URL Preview in Encrypted Chats\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUrlPreviewInE2EEChatDescription => Intl.message(
    "This will expose any URLs sent in your encrypted chats to your homeserver in order to fetch the preview",
    name: "settingsSearchUrlPreviewInE2EEChatDescription",
    desc:
        "Settings search result: one-line explanation of the \"URL Preview in Encrypted Chats\" setting, shown under its title");

String get settingsSearchReleaseNoticeTitle => Intl.message(
    "New version notice",
    name: "settingsSearchReleaseNoticeTitle",
    desc:
        "Settings search result title for the \"New version notice\" setting; use the same wording as that setting's label on its page");

String get settingsSearchReleaseNoticeDescription => Intl.message(
    "Show a bar at the bottom of the app when a newer Vommet release is out",
    name: "settingsSearchReleaseNoticeDescription",
    desc:
        "Settings search result: one-line explanation of the \"New version notice\" setting, shown under its title");

String get settingsSearchAskBeforeDeletingMessageEnabledTitle => Intl.message(
    "Ask before deleting messages",
    name: "settingsSearchAskBeforeDeletingMessageEnabledTitle",
    desc:
        "Settings search result title for the \"Ask before deleting messages\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAskBeforeDeletingMessageEnabledDescription => Intl.message(
    "Enables the pop-up asking for confirmation when deleting a message.",
    name: "settingsSearchAskBeforeDeletingMessageEnabledDescription",
    desc:
        "Settings search result: one-line explanation of the \"Ask before deleting messages\" setting, shown under its title");

String get settingsSearchSectionAppBehaviour => Intl.message("App Behaviour",
    name: "settingsSearchSectionAppBehaviour",
    desc:
        "Settings search result: name of the \"App Behaviour\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchAutoFocusMessageTextBoxTitle => Intl.message(
    "Autofocus Message Input",
    name: "settingsSearchAutoFocusMessageTextBoxTitle",
    desc:
        "Settings search result title for the \"Autofocus Message Input\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAutoFocusMessageTextBoxDescription => Intl.message(
    "Automatically focus on the message input text field when opening a chat",
    name: "settingsSearchAutoFocusMessageTextBoxDescription",
    desc:
        "Settings search result: one-line explanation of the \"Autofocus Message Input\" setting, shown under its title");

String get settingsSearchSelectAutoCompleteSuggestionTitle => Intl.message(
    "Select first auto-complete suggestion",
    name: "settingsSearchSelectAutoCompleteSuggestionTitle",
    desc:
        "Settings search result title for the \"Select first auto-complete suggestion\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSelectAutoCompleteSuggestionDescription => Intl.message(
    "When typing a message, if there are any auto-complete suggestions, the first one will be highlighted by default",
    name: "settingsSearchSelectAutoCompleteSuggestionDescription",
    desc:
        "Settings search result: one-line explanation of the \"Select first auto-complete suggestion\" setting, shown under its title");

String get settingsSearchAutomaticallyOpenSpaceTitle => Intl.message(
    "Always open space",
    name: "settingsSearchAutomaticallyOpenSpaceTitle",
    desc:
        "Settings search result title for the \"Always open space\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAutomaticallyOpenSpaceDescription => Intl.message(
    "When navigating to a room from outside of a space, also open the space the room is in, if any",
    name: "settingsSearchAutomaticallyOpenSpaceDescription",
    desc:
        "Settings search result: one-line explanation of the \"Always open space\" setting, shown under its title");

String get settingsSearchOpenRoomsAtLastReadMessageTitle => Intl.message(
    "Open at last read message",
    name: "settingsSearchOpenRoomsAtLastReadMessageTitle",
    desc:
        "Settings search result title for the \"Open at last read message\" setting; use the same wording as that setting's label on its page");

String get settingsSearchOpenRoomsAtLastReadMessageDescription => Intl.message(
    "When opening a room, jump to the last message you read",
    name: "settingsSearchOpenRoomsAtLastReadMessageDescription",
    desc:
        "Settings search result: one-line explanation of the \"Open at last read message\" setting, shown under its title");

String get settingsSearchRelativeDateDividersTitle => Intl.message(
    "Relative dates in the chat",
    name: "settingsSearchRelativeDateDividersTitle",
    desc:
        "Settings search result title for the \"Relative dates in the chat\" setting; use the same wording as that setting's label on its page");

String get settingsSearchRelativeDateDividersDescription => Intl.message(
    "The line between messages after a gap says Today, Yesterday or the weekday",
    name: "settingsSearchRelativeDateDividersDescription",
    desc:
        "Settings search result: one-line explanation of the \"Relative dates in the chat\" setting, shown under its title");

String get settingsSearchPauseAnimationsWhenNotFocusedTitle => Intl.message(
    "Pause animations when unfocused",
    name: "settingsSearchPauseAnimationsWhenNotFocusedTitle",
    desc:
        "Settings search result title for the \"Pause animations when unfocused\" setting; use the same wording as that setting's label on its page");

String get settingsSearchPauseAnimationsWhenNotFocusedDescription => Intl.message(
    "When the app is in the background, pause animations to reduce CPU usage",
    name: "settingsSearchPauseAnimationsWhenNotFocusedDescription",
    desc:
        "Settings search result: one-line explanation of the \"Pause animations when unfocused\" setting, shown under its title");

String get settingsSearchMessageEffectsEnabledTitle => Intl.message(
    "Message Effects",
    name: "settingsSearchMessageEffectsEnabledTitle",
    desc:
        "Settings search result title for the \"Message Effects\" setting; use the same wording as that setting's label on its page");

String get settingsSearchMessageEffectsEnabledDescription => Intl.message(
    "Messages can be sent with additional effects, such as confetti",
    name: "settingsSearchMessageEffectsEnabledDescription",
    desc:
        "Settings search result: one-line explanation of the \"Message Effects\" setting, shown under its title");

String get settingsSearchSectionMessageEffects => Intl.message(
    "Message Effects",
    name: "settingsSearchSectionMessageEffects",
    desc:
        "Settings search result: name of the \"Message Effects\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchPreviewMediaInPrivateRoomsTitle => Intl.message(
    "Private Rooms",
    name: "settingsSearchPreviewMediaInPrivateRoomsTitle",
    desc:
        "Settings search result title for the \"Private Rooms\" setting; use the same wording as that setting's label on its page");

String get settingsSearchPreviewMediaInPrivateRoomsDescription => Intl.message(
    "Toggle previewing of images, videos, stickers and urls in private chats",
    name: "settingsSearchPreviewMediaInPrivateRoomsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Private Rooms\" setting, shown under its title");

String get settingsSearchSectionMedia => Intl.message("Media",
    name: "settingsSearchSectionMedia",
    desc:
        "Settings search result: name of the \"Media\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchPreviewMediaInPublicRoomsTitle => Intl.message(
    "Public Rooms",
    name: "settingsSearchPreviewMediaInPublicRoomsTitle",
    desc:
        "Settings search result title for the \"Public Rooms\" setting; use the same wording as that setting's label on its page");

String get settingsSearchPreviewMediaInPublicRoomsDescription => Intl.message(
    "Toggle previewing of images, videos, stickers and urls in public chat rooms",
    name: "settingsSearchPreviewMediaInPublicRoomsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Public Rooms\" setting, shown under its title");

String get settingsSearchAutoRotateImagesTitle => Intl.message("Rotate Images",
    name: "settingsSearchAutoRotateImagesTitle",
    desc:
        "Settings search result title for the \"Rotate Images\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAutoRotateImagesDescription => Intl.message(
    "When showing images in fullscreen, automatically rotate the image to best fill the screen",
    name: "settingsSearchAutoRotateImagesDescription",
    desc:
        "Settings search result: one-line explanation of the \"Rotate Images\" setting, shown under its title");

String get settingsSearchAutoRotateVideosTitle => Intl.message("Rotate Videos",
    name: "settingsSearchAutoRotateVideosTitle",
    desc:
        "Settings search result title for the \"Rotate Videos\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAutoRotateVideosDescription => Intl.message(
    "When showing videos in fullscreen, automatically rotate the video to best fill the screen",
    name: "settingsSearchAutoRotateVideosDescription",
    desc:
        "Settings search result: one-line explanation of the \"Rotate Videos\" setting, shown under its title");

String get settingsSearchAllowedRemoteVideoHostsTitle => Intl.message(
    "Allowed Video Hosts",
    name: "settingsSearchAllowedRemoteVideoHostsTitle",
    desc:
        "Settings search result title for the \"Allowed Video Hosts\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAllowedRemoteVideoHostsDescription => Intl.message(
    "Sites whose videos may play inside the chat",
    name: "settingsSearchAllowedRemoteVideoHostsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Allowed Video Hosts\" setting, shown under its title");

String get settingsSearchAppearanceThemeTitle => Intl.message("Theme",
    name: "settingsSearchAppearanceThemeTitle",
    desc:
        "Settings search result title for the \"Theme\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAppearanceThemeDescription => Intl.message(
    "Pick the app's colours",
    name: "settingsSearchAppearanceThemeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Theme\" setting, shown under its title");

String get settingsSearchShouldFollowSystemThemeTitle => Intl.message(
    "Theme mode",
    name: "settingsSearchShouldFollowSystemThemeTitle",
    desc:
        "Settings search result title for the \"Theme mode\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShouldFollowSystemThemeDescription => Intl.message(
    "Use one theme, or follow your device's light and dark mode",
    name: "settingsSearchShouldFollowSystemThemeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Theme mode\" setting, shown under its title");

String get settingsSearchSectionTheme => Intl.message("Theme",
    name: "settingsSearchSectionTheme",
    desc:
        "Settings search result: name of the \"Theme\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchShouldFollowSystemColorsTitle => Intl.message(
    "Follow System Colors",
    name: "settingsSearchShouldFollowSystemColorsTitle",
    desc:
        "Settings search result title for the \"Follow System Colors\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShouldFollowSystemColorsDescription => Intl.message(
    "Automatically follow system color scheme",
    name: "settingsSearchShouldFollowSystemColorsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Follow System Colors\" setting, shown under its title");

String get settingsSearchAppScaleTitle => Intl.message("App Scale",
    name: "settingsSearchAppScaleTitle",
    desc:
        "Settings search result title for the \"App Scale\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAppScaleDescription => Intl.message(
    "Resizes the overall interface of the app",
    name: "settingsSearchAppScaleDescription",
    desc:
        "Settings search result: one-line explanation of the \"App Scale\" setting, shown under its title");

String get settingsSearchSectionScaling => Intl.message("Scaling",
    name: "settingsSearchSectionScaling",
    desc:
        "Settings search result: name of the \"Scaling\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchTextScaleTitle => Intl.message("Text Scale",
    name: "settingsSearchTextScaleTitle",
    desc:
        "Settings search result title for the \"Text Scale\" setting; use the same wording as that setting's label on its page");

String get settingsSearchTextScaleDescription => Intl.message(
    "Multiply the size of text",
    name: "settingsSearchTextScaleDescription",
    desc:
        "Settings search result: one-line explanation of the \"Text Scale\" setting, shown under its title");

String get settingsSearchShowRoomPreviewsInSpaceSidebarTitle => Intl.message(
    "Show unjoined rooms in sidebar",
    name: "settingsSearchShowRoomPreviewsInSpaceSidebarTitle",
    desc:
        "Settings search result title for the \"Show unjoined rooms in sidebar\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowRoomPreviewsInSpaceSidebarDescription => Intl.message(
    "When there are rooms which you have not joined in a space, show them in the sidebar with the rest of the rooms in the space",
    name: "settingsSearchShowRoomPreviewsInSpaceSidebarDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show unjoined rooms in sidebar\" setting, shown under its title");

String get settingsSearchShowRoomsInSidebarTitle => Intl.message(
    "Show rooms in sidebar",
    name: "settingsSearchShowRoomsInSidebarTitle",
    desc:
        "Settings search result title for the \"Show rooms in sidebar\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowRoomsInSidebarDescription => Intl.message(
    "Add an entry to the sidebar that shows all rooms which are not contained in a space.",
    name: "settingsSearchShowRoomsInSidebarDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show rooms in sidebar\" setting, shown under its title");

String get settingsSearchRailUnreadMarksTitle => Intl.message(
    "Show unread marks on spaces",
    name: "settingsSearchRailUnreadMarksTitle",
    desc:
        "Settings search result title for the \"Show unread marks on spaces\" setting; use the same wording as that setting's label on its page");

String get settingsSearchRailUnreadMarksDescription => Intl.message(
    "A small mark beside spaces with new messages. Mentions always show a red badge.",
    name: "settingsSearchRailUnreadMarksDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show unread marks on spaces\" setting, shown under its title");

String get settingsSearchShowRoomAvatarsTitle => Intl.message(
    "Use room avatars",
    name: "settingsSearchShowRoomAvatarsTitle",
    desc:
        "Settings search result title for the \"Use room avatars\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowRoomAvatarsDescription => Intl.message(
    "Show room avatar images instead of icons",
    name: "settingsSearchShowRoomAvatarsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Use room avatars\" setting, shown under its title");

String get settingsSearchUsePlaceholderRoomAvatarsTitle => Intl.message(
    "Use placeholder avatars",
    name: "settingsSearchUsePlaceholderRoomAvatarsTitle",
    desc:
        "Settings search result title for the \"Use placeholder avatars\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUsePlaceholderRoomAvatarsDescription => Intl.message(
    "When a room does not have an avatar set, or using them is disabled, fallback to a generic color + first letter placeholder for the image",
    name: "settingsSearchUsePlaceholderRoomAvatarsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Use placeholder avatars\" setting, shown under its title");

String get settingsSearchOrgModeItalicsTitle => Intl.message(
    "Org-mode style /italics/",
    name: "settingsSearchOrgModeItalicsTitle",
    desc:
        "Settings search result title for the \"Org-mode style /italics/\" setting; use the same wording as that setting's label on its page");

String get settingsSearchOrgModeItalicsDescription => Intl.message(
    "Send text between slashes, like /this/, in italics",
    name: "settingsSearchOrgModeItalicsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Org-mode style /italics/\" setting, shown under its title");

String get settingsSearchFormattingPopupTitle => Intl.message(
    "Formatting buttons",
    name: "settingsSearchFormattingPopupTitle",
    desc:
        "Settings search result title for the \"Formatting buttons\" setting; use the same wording as that setting's label on its page");

String get settingsSearchFormattingPopupDescription => Intl.message(
    "Show a formatting bar when you select text in the message box",
    name: "settingsSearchFormattingPopupDescription",
    desc:
        "Settings search result: one-line explanation of the \"Formatting buttons\" setting, shown under its title");

String get settingsSearchShowStateEventsTitle => Intl.message(
    "Show state events",
    name: "settingsSearchShowStateEventsTitle",
    desc:
        "Settings search result title for the \"Show state events\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowStateEventsDescription => Intl.message(
    "Show changes to the room state, such as members joining and leaving, in the chat timeline.",
    name: "settingsSearchShowStateEventsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show state events\" setting, shown under its title");

String get settingsSearchCollapseStateEventsTitle => Intl.message(
    "Collapse state events",
    name: "settingsSearchCollapseStateEventsTitle",
    desc:
        "Settings search result title for the \"Collapse state events\" setting; use the same wording as that setting's label on its page");

String get settingsSearchCollapseStateEventsDescription => Intl.message(
    "Group changes to room state in to a single timeline event.",
    name: "settingsSearchCollapseStateEventsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Collapse state events\" setting, shown under its title");

String get settingsSearchGroupConsecutiveMediaTitle => Intl.message(
    "Group pictures",
    name: "settingsSearchGroupConsecutiveMediaTitle",
    desc:
        "Settings search result title for the \"Group pictures\" setting; use the same wording as that setting's label on its page");

String get settingsSearchGroupConsecutiveMediaDescription => Intl.message(
    "Show pictures and videos posted together by one person as a single mosaic.",
    name: "settingsSearchGroupConsecutiveMediaDescription",
    desc:
        "Settings search result: one-line explanation of the \"Group pictures\" setting, shown under its title");

String get settingsSearchBannerGradientTitle => Intl.message(
    "Banners and panes",
    name: "settingsSearchBannerGradientTitle",
    desc:
        "Settings search result title for the \"Banners and panes\" setting; use the same wording as that setting's label on its page");

String get settingsSearchBannerGradientDescription => Intl.message(
    "The look of banners and side panes",
    name: "settingsSearchBannerGradientDescription",
    desc:
        "Settings search result: one-line explanation of the \"Banners and panes\" setting, shown under its title");

String get settingsSearchThreadPreviewModeTitle => Intl.message("Threads",
    name: "settingsSearchThreadPreviewModeTitle",
    desc:
        "Settings search result title for the \"Threads\" setting; use the same wording as that setting's label on its page");

String get settingsSearchThreadPreviewModeDescription => Intl.message(
    "How threads are previewed in the chat",
    name: "settingsSearchThreadPreviewModeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Threads\" setting, shown under its title");

String get settingsSearchSoundsNotificationSoundsTitle => Intl.message(
    "Notification sounds",
    name: "settingsSearchSoundsNotificationSoundsTitle",
    desc:
        "Settings search result title for the \"Notification sounds\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSoundsNotificationSoundsDescription => Intl.message(
    "Pick the sound for each kind of notification, or use your own file",
    name: "settingsSearchSoundsNotificationSoundsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Notification sounds\" setting, shown under its title");

String get settingsSearchUseFallbackTurnServerTitle => Intl.message(
    "Use STUN Fallback",
    name: "settingsSearchUseFallbackTurnServerTitle",
    desc:
        "Settings search result title for the \"Use STUN Fallback\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUseFallbackTurnServerDescription => Intl.message(
    "Use a public server to help connect calls when your homeserver doesn't provide one",
    name: "settingsSearchUseFallbackTurnServerDescription",
    desc:
        "Settings search result: one-line explanation of the \"Use STUN Fallback\" setting, shown under its title");

String get settingsSearchSectionCallConnection => Intl.message(
    "Call Connection",
    name: "settingsSearchSectionCallConnection",
    desc:
        "Settings search result: name of the \"Call Connection\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchUseVoipOverlayTitle => Intl.message("Enable Overlay",
    name: "settingsSearchUseVoipOverlayTitle",
    desc:
        "Settings search result title for the \"Enable Overlay\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUseVoipOverlayDescription => Intl.message(
    "When in a call, add an overlay on your screen to show the call participants",
    name: "settingsSearchUseVoipOverlayDescription",
    desc:
        "Settings search result: one-line explanation of the \"Enable Overlay\" setting, shown under its title");

String get settingsSearchSectionOverlay => Intl.message("Overlay",
    name: "settingsSearchSectionOverlay",
    desc:
        "Settings search result: name of the \"Overlay\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchVoipDefaultAudioInputTitle => Intl.message(
    "Default Audio Input",
    name: "settingsSearchVoipDefaultAudioInputTitle",
    desc:
        "Settings search result title for the \"Default Audio Input\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipDefaultAudioInputDescription => Intl.message(
    "The microphone used in calls",
    name: "settingsSearchVoipDefaultAudioInputDescription",
    desc:
        "Settings search result: one-line explanation of the \"Default Audio Input\" setting, shown under its title");

String get settingsSearchSectionDevices => Intl.message("Devices",
    name: "settingsSearchSectionDevices",
    desc:
        "Settings search result: name of the \"Devices\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchVoipAudioOutputTitle => Intl.message("Audio Output",
    name: "settingsSearchVoipAudioOutputTitle",
    desc:
        "Settings search result title for the \"Audio Output\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipAudioOutputDescription => Intl.message(
    "The speakers or headphones used in calls",
    name: "settingsSearchVoipAudioOutputDescription",
    desc:
        "Settings search result: one-line explanation of the \"Audio Output\" setting, shown under its title");

String get settingsSearchStreamAudioKbpsTitle => Intl.message("Audio bitrate",
    name: "settingsSearchStreamAudioKbpsTitle",
    desc:
        "Settings search result title for the \"Audio Bitrate\" setting; use the same wording as that setting's label on its page");

String get settingsSearchStreamAudioKbpsDescription => Intl.message(
    "Adjust the bitrate of your outgoing audio. Higher is better.",
    name: "settingsSearchStreamAudioKbpsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Audio Bitrate\" setting, shown under its title");

String get settingsSearchSectionAudioSettings => Intl.message("Audio settings",
    name: "settingsSearchSectionAudioSettings",
    desc:
        "Settings search result: name of the \"Audio Settings\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchDoSimulcastTitle => Intl.message("Use Simulcast",
    name: "settingsSearchDoSimulcastTitle",
    desc:
        "Settings search result title for the \"Use Simulcast\" setting; use the same wording as that setting's label on its page");

String get settingsSearchDoSimulcastDescription => Intl.message(
    "Uploads your streams at multiple different levels of quality, so other users can decide which to use",
    name: "settingsSearchDoSimulcastDescription",
    desc:
        "Settings search result: one-line explanation of the \"Use Simulcast\" setting, shown under its title");

String get settingsSearchSectionStreamSettings => Intl.message(
    "Stream Settings",
    name: "settingsSearchSectionStreamSettings",
    desc:
        "Settings search result: name of the \"Stream Settings\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchScreenshareBitrateMbpsTitle => Intl.message(
    "Stream Maximum Bitrate",
    name: "settingsSearchScreenshareBitrateMbpsTitle",
    desc:
        "Settings search result title for the \"Stream Maximum Bitrate\" setting; use the same wording as that setting's label on its page");

String get settingsSearchScreenshareBitrateMbpsDescription => Intl.message(
    "Determines the overall quality of your stream. Higher is better, but also uses more resources",
    name: "settingsSearchScreenshareBitrateMbpsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Stream Maximum Bitrate\" setting, shown under its title");

String get settingsSearchScreenshareFpsTitle => Intl.message("Stream Framerate",
    name: "settingsSearchScreenshareFpsTitle",
    desc:
        "Settings search result title for the \"Stream Framerate\" setting; use the same wording as that setting's label on its page");

String get settingsSearchScreenshareFpsDescription => Intl.message(
    "Target frames per second for screen sharing",
    name: "settingsSearchScreenshareFpsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Stream Framerate\" setting, shown under its title");

String get settingsSearchLivekitScreenshareCodecTitle => Intl.message(
    "Preferred Stream Codec",
    name: "settingsSearchLivekitScreenshareCodecTitle",
    desc:
        "Settings search result title for the \"Preferred Stream Codec\" setting; use the same wording as that setting's label on its page");

String get settingsSearchLivekitScreenshareCodecDescription => Intl.message(
    "The video codec used for screen sharing",
    name: "settingsSearchLivekitScreenshareCodecDescription",
    desc:
        "Settings search result: one-line explanation of the \"Preferred Stream Codec\" setting, shown under its title");

String get settingsSearchLivekitScreenshareResolutionTitle => Intl.message(
    "Stream Resolution",
    name: "settingsSearchLivekitScreenshareResolutionTitle",
    desc:
        "Settings search result title for the \"Stream Resolution\" setting; use the same wording as that setting's label on its page");

String get settingsSearchLivekitScreenshareResolutionDescription => Intl.message(
    "The resolution of your screen share",
    name: "settingsSearchLivekitScreenshareResolutionDescription",
    desc:
        "Settings search result: one-line explanation of the \"Stream Resolution\" setting, shown under its title");

String get settingsSearchShortcutsKeyboardShortcutsTitle => Intl.message(
    "Keyboard shortcuts",
    name: "settingsSearchShortcutsKeyboardShortcutsTitle",
    desc:
        "Settings search result title for the \"Keyboard shortcuts\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShortcutsKeyboardShortcutsDescription => Intl.message(
    "Set keys for actions like mute and deafen",
    name: "settingsSearchShortcutsKeyboardShortcutsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Keyboard shortcuts\" setting, shown under its title");

String get settingsSearchMinimizeOnCloseTitle => Intl.message(
    "Minimize on close",
    name: "settingsSearchMinimizeOnCloseTitle",
    desc:
        "Settings search result title for the \"Minimize on close\" setting; use the same wording as that setting's label on its page");

String get settingsSearchMinimizeOnCloseDescription => Intl.message(
    "When closing the window, the app will be minimized instead of exited",
    name: "settingsSearchMinimizeOnCloseDescription",
    desc:
        "Settings search result: one-line explanation of the \"Minimize on close\" setting, shown under its title");

String get settingsSearchStorageStorageUsageTitle => Intl.message(
    "Storage usage",
    name: "settingsSearchStorageStorageUsageTitle",
    desc:
        "Settings search result title for the \"Storage usage\" setting; use the same wording as that setting's label on its page");

String get settingsSearchStorageStorageUsageDescription => Intl.message(
    "See what takes space and clear the media cache",
    name: "settingsSearchStorageStorageUsageDescription",
    desc:
        "Settings search result: one-line explanation of the \"Storage usage\" setting, shown under its title");

String get settingsSearchMediaCacheLimitMbTitle => Intl.message(
    "Media cache limit",
    name: "settingsSearchMediaCacheLimitMbTitle",
    desc:
        "Settings search result title for the \"Media cache limit\" setting; use the same wording as that setting's label on its page");

String get settingsSearchMediaCacheLimitMbDescription => Intl.message(
    "The most space downloaded media may use",
    name: "settingsSearchMediaCacheLimitMbDescription",
    desc:
        "Settings search result: one-line explanation of the \"Media cache limit\" setting, shown under its title");

String get settingsSearchSectionLimits => Intl.message("Limits",
    name: "settingsSearchSectionLimits",
    desc:
        "Settings search result: name of the \"Limits\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchMediaCacheKeepDaysTitle => Intl.message(
    "Remove media not opened for",
    name: "settingsSearchMediaCacheKeepDaysTitle",
    desc:
        "Settings search result title for the \"Remove media not opened for\" setting; use the same wording as that setting's label on its page");

String get settingsSearchMediaCacheKeepDaysDescription => Intl.message(
    "Clean out media you haven't looked at in a while",
    name: "settingsSearchMediaCacheKeepDaysDescription",
    desc:
        "Settings search result: one-line explanation of the \"Remove media not opened for\" setting, shown under its title");

String get settingsSearchStorageAutomaticMediaDownloadTitle => Intl.message(
    "Automatic media download",
    name: "settingsSearchStorageAutomaticMediaDownloadTitle",
    desc:
        "Settings search result title for the \"Automatic media download\" setting; use the same wording as that setting's label on its page");

String get settingsSearchStorageAutomaticMediaDownloadDescription => Intl.message(
    "Choose what downloads by itself on Wi-Fi and on mobile data",
    name: "settingsSearchStorageAutomaticMediaDownloadDescription",
    desc:
        "Settings search result: one-line explanation of the \"Automatic media download\" setting, shown under its title");

String get settingsSearchSilenceNotificationsTitle => Intl.message(
    "Quiet notifications while I'm chatting on another device",
    name: "settingsSearchSilenceNotificationsTitle",
    desc:
        "Settings search result title for the \"Quiet notifications while I'm chatting on another device\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSilenceNotificationsDescription => Intl.message(
    "Notifications from a chat you just wrote in on another device come without sound",
    name: "settingsSearchSilenceNotificationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Quiet notifications while I'm chatting on another device\" setting, shown under its title");

String get settingsSearchEnableNotificationsTitle => Intl.message(
    "Show notifications",
    name: "settingsSearchEnableNotificationsTitle",
    desc:
        "Settings search result title for the \"Show notifications\" setting; use the same wording as that setting's label on its page");

String get settingsSearchEnableNotificationsDescription => Intl.message(
    "Enable or disable the display of notifications entirely",
    name: "settingsSearchEnableNotificationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show notifications\" setting, shown under its title");

String get settingsSearchSuppressNotificationWhenRoomFocusedTitle => Intl.message(
    "Hide notifications for current room",
    name: "settingsSearchSuppressNotificationWhenRoomFocusedTitle",
    desc:
        "Settings search result title for the \"Hide notifications for current room\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSuppressNotificationWhenRoomFocusedDescription => Intl.message(
    "When receiving a message, if you have the chat selected and the app is in focus, dont show the notification",
    name: "settingsSearchSuppressNotificationWhenRoomFocusedDescription",
    desc:
        "Settings search result: one-line explanation of the \"Hide notifications for current room\" setting, shown under its title");

String get settingsSearchInAppNotificationBannersTitle => Intl.message(
    "In-app notification banners",
    name: "settingsSearchInAppNotificationBannersTitle",
    desc:
        "Settings search result title for the \"In-app notification banners\" setting; use the same wording as that setting's label on its page");

String get settingsSearchInAppNotificationBannersDescription => Intl.message(
    "While Vommet is open, show new messages as a banner at the top of the app instead of a system notification.",
    name: "settingsSearchInAppNotificationBannersDescription",
    desc:
        "Settings search result: one-line explanation of the \"In-app notification banners\" setting, shown under its title");

String get settingsSearchShowNotificationBadgesInTaskbarTitle => Intl.message(
    "Notification Badges",
    name: "settingsSearchShowNotificationBadgesInTaskbarTitle",
    desc:
        "Settings search result title for the \"Notification Badges\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowNotificationBadgesInTaskbarDescription => Intl.message(
    "Show a badge with the number of unread messages in the system taskbar",
    name: "settingsSearchShowNotificationBadgesInTaskbarDescription",
    desc:
        "Settings search result: one-line explanation of the \"Notification Badges\" setting, shown under its title");

String get settingsSearchFormatNotificationBodyTitle => Intl.message(
    "Message Body Formatting",
    name: "settingsSearchFormatNotificationBodyTitle",
    desc:
        "Settings search result title for the \"Message Body Formatting\" setting; use the same wording as that setting's label on its page");

String get settingsSearchFormatNotificationBodyDescription => Intl.message(
    "Apply user formatting in message notifications",
    name: "settingsSearchFormatNotificationBodyDescription",
    desc:
        "Settings search result: one-line explanation of the \"Message Body Formatting\" setting, shown under its title");

String get settingsSearchShowMediaInNotificationsTitle => Intl.message(
    "Show Images",
    name: "settingsSearchShowMediaInNotificationsTitle",
    desc:
        "Settings search result title for the \"Show Images\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowMediaInNotificationsDescription => Intl.message(
    "Show images in notifications",
    name: "settingsSearchShowMediaInNotificationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show Images\" setting, shown under its title");

String get settingsSearchPreviewUrlInNotificationsTitle => Intl.message(
    "Preview Urls",
    name: "settingsSearchPreviewUrlInNotificationsTitle",
    desc:
        "Settings search result title for the \"Preview Urls\" setting; use the same wording as that setting's label on its page");

String get settingsSearchPreviewUrlInNotificationsDescription => Intl.message(
    "Fetch URL previews to show extra information about links in notifications",
    name: "settingsSearchPreviewUrlInNotificationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Preview Urls\" setting, shown under its title");

String get settingsSearchNotificationsVolumeTitle => Intl.message(
    "Notification volume",
    name: "settingsSearchNotificationsVolumeTitle",
    desc:
        "Settings search result title for the \"Notification volume\" setting; use the same wording as that setting's label on its page");

String get settingsSearchNotificationsVolumeDescription => Intl.message(
    "Controls the volume of notifications and ringtones",
    name: "settingsSearchNotificationsVolumeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Notification volume\" setting, shown under its title");

String get settingsSearchNotifPushNotificationsTitle => Intl.message(
    "Push Notifications",
    name: "settingsSearchNotifPushNotificationsTitle",
    desc:
        "Settings search result title for the \"Push Notifications\" setting; use the same wording as that setting's label on its page");

String get settingsSearchNotifPushNotificationsDescription => Intl.message(
    "Set up push notifications for this device",
    name: "settingsSearchNotifPushNotificationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Push Notifications\" setting, shown under its title");

String get settingsSearchTelemetryConsentTitle => Intl.message(
    "Send diagnostics",
    name: "settingsSearchTelemetryConsentTitle",
    desc:
        "Settings search result title for the \"Send diagnostics\" setting; use the same wording as that setting's label on its page");

String get settingsSearchTelemetryConsentDescription => Intl.message(
    "Send anonymous crash and performance reports to help fix bugs",
    name: "settingsSearchTelemetryConsentDescription",
    desc:
        "Settings search result: one-line explanation of the \"Send diagnostics\" setting, shown under its title");

String get settingsSearchDeveloperModeTitle => Intl.message("Developer mode",
    name: "settingsSearchDeveloperModeTitle",
    desc:
        "Settings search result title for the \"Developer mode\" setting; use the same wording as that setting's label on its page");

String get settingsSearchDeveloperModeDescription => Intl.message(
    "Shows extra information, useful for developers",
    name: "settingsSearchDeveloperModeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Developer mode\" setting, shown under its title");

String get settingsSearchShowHiddenEventsTitle => Intl.message(
    "Show hidden events",
    name: "settingsSearchShowHiddenEventsTitle",
    desc:
        "Settings search result title for the \"Show hidden events\" setting; use the same wording as that setting's label on its page");

String get settingsSearchShowHiddenEventsDescription => Intl.message(
    "Also show events the timeline normally hides, such as reactions and deletions, as plain rows.",
    name: "settingsSearchShowHiddenEventsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Show hidden events\" setting, shown under its title");

String get settingsSearchStickerCompatibilityModeTitle => Intl.message(
    "Sticker compatibility",
    name: "settingsSearchStickerCompatibilityModeTitle",
    desc:
        "Settings search result title for the \"Sticker compatibility\" setting; use the same wording as that setting's label on its page");

String get settingsSearchStickerCompatibilityModeDescription => Intl.message(
    "Send stickers as 'm.image' so they render in clients that can't show 'm.sticker'",
    name: "settingsSearchStickerCompatibilityModeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Sticker compatibility\" setting, shown under its title");

String get settingsSearchAdvancedOverrideLayoutTitle => Intl.message(
    "Override Layout",
    name: "settingsSearchAdvancedOverrideLayoutTitle",
    desc:
        "Settings search result title for the \"Override Layout\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAdvancedOverrideLayoutDescription => Intl.message(
    "Force the phone or desktop layout",
    name: "settingsSearchAdvancedOverrideLayoutDescription",
    desc:
        "Settings search result: one-line explanation of the \"Override Layout\" setting, shown under its title");

String get settingsSearchProfileAvatarTitle => Intl.message("Avatar",
    name: "settingsSearchProfileAvatarTitle",
    desc:
        "Settings search result title for the \"Avatar\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileAvatarDescription => Intl.message(
    "Change your profile picture",
    name: "settingsSearchProfileAvatarDescription",
    desc:
        "Settings search result: one-line explanation of the \"Avatar\" setting, shown under its title");

String get settingsSearchProfileDisplayNameTitle => Intl.message("Display name",
    name: "settingsSearchProfileDisplayNameTitle",
    desc:
        "Settings search result title for the \"Display name\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileDisplayNameDescription => Intl.message(
    "The name others see",
    name: "settingsSearchProfileDisplayNameDescription",
    desc:
        "Settings search result: one-line explanation of the \"Display name\" setting, shown under its title");

String get settingsSearchProfileBannerTitle => Intl.message("Banner",
    name: "settingsSearchProfileBannerTitle",
    desc:
        "Settings search result title for the \"Banner\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileBannerDescription => Intl.message(
    "The picture at the top of your profile",
    name: "settingsSearchProfileBannerDescription",
    desc:
        "Settings search result: one-line explanation of the \"Banner\" setting, shown under its title");

String get settingsSearchProfileStatusTitle => Intl.message("Status",
    name: "settingsSearchProfileStatusTitle",
    desc:
        "Settings search result title for the \"Status\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileStatusDescription => Intl.message(
    "A short message shown next to your name",
    name: "settingsSearchProfileStatusDescription",
    desc:
        "Settings search result: one-line explanation of the \"Status\" setting, shown under its title");

String get settingsSearchProfileBioTitle => Intl.message("Bio",
    name: "settingsSearchProfileBioTitle",
    desc:
        "Settings search result title for the \"Bio\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileBioDescription => Intl.message(
    "A few lines about yourself, shown on your profile",
    name: "settingsSearchProfileBioDescription",
    desc:
        "Settings search result: one-line explanation of the \"Bio\" setting, shown under its title");

String get settingsSearchProfileTimezoneTitle => Intl.message("Timezone",
    name: "settingsSearchProfileTimezoneTitle",
    desc:
        "Settings search result title for the \"Timezone\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileTimezoneDescription => Intl.message(
    "Show others your local time on your profile",
    name: "settingsSearchProfileTimezoneDescription",
    desc:
        "Settings search result: one-line explanation of the \"Timezone\" setting, shown under its title");

String get settingsSearchProfileColorSchemeTitle => Intl.message("Color Scheme",
    name: "settingsSearchProfileColorSchemeTitle",
    desc:
        "Settings search result title for the \"Color Scheme\" setting; use the same wording as that setting's label on its page");

String get settingsSearchProfileColorSchemeDescription => Intl.message(
    "The colours of your profile card",
    name: "settingsSearchProfileColorSchemeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Color Scheme\" setting, shown under its title");

String get settingsSearchUprivacyReadReceiptsTitle => Intl.message(
    "Read receipts",
    name: "settingsSearchUprivacyReadReceiptsTitle",
    desc:
        "Settings search result title for the \"Read receipts\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUprivacyReadReceiptsDescription => Intl.message(
    "Let other members of a room know when you have read their messages.",
    name: "settingsSearchUprivacyReadReceiptsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Read receipts\" setting, shown under its title");

String get settingsSearchSectionChatPrivacy => Intl.message("Chat Privacy",
    name: "settingsSearchSectionChatPrivacy",
    desc:
        "Settings search result: name of the \"Chat Privacy\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchUprivacyTypingIndicatorTitle => Intl.message(
    "Typing indicator",
    name: "settingsSearchUprivacyTypingIndicatorTitle",
    desc:
        "Settings search result title for the \"Typing indicator\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUprivacyTypingIndicatorDescription => Intl.message(
    "Let other members of a room know when you are typing a message.",
    name: "settingsSearchUprivacyTypingIndicatorDescription",
    desc:
        "Settings search result: one-line explanation of the \"Typing indicator\" setting, shown under its title");

String get settingsSearchUprivacyAllowInvitationsTitle => Intl.message(
    "Allow invitations",
    name: "settingsSearchUprivacyAllowInvitationsTitle",
    desc:
        "Settings search result title for the \"Allow invitations\" setting; use the same wording as that setting's label on its page");

String get settingsSearchUprivacyAllowInvitationsDescription => Intl.message(
    "Allow other users to invite you to rooms.",
    name: "settingsSearchUprivacyAllowInvitationsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Allow invitations\" setting, shown under its title");

String get settingsSearchSecuritySessionsTitle => Intl.message("Sessions",
    name: "settingsSearchSecuritySessionsTitle",
    desc:
        "Settings search result title for the \"Sessions\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSecuritySessionsDescription => Intl.message(
    "Your signed-in devices; verify or sign out of them",
    name: "settingsSearchSecuritySessionsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Sessions\" setting, shown under its title");

String get settingsSearchSecurityCrossSigningTitle => Intl.message(
    "Cross signing",
    name: "settingsSearchSecurityCrossSigningTitle",
    desc:
        "Settings search result title for the \"Cross signing\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSecurityCrossSigningDescription => Intl.message(
    "Set up to verify and keep track of all your sessions",
    name: "settingsSearchSecurityCrossSigningDescription",
    desc:
        "Settings search result: one-line explanation of the \"Cross signing\" setting, shown under its title");

String get settingsSearchSecurityMessageBackupTitle => Intl.message(
    "Message backup",
    name: "settingsSearchSecurityMessageBackupTitle",
    desc:
        "Settings search result title for the \"Message backup\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSecurityMessageBackupDescription => Intl.message(
    "Back up your encryption keys so you can read old messages on new devices",
    name: "settingsSearchSecurityMessageBackupDescription",
    desc:
        "Settings search result: one-line explanation of the \"Message backup\" setting, shown under its title");

String get settingsSearchSecurityKeyFileTitle => Intl.message("Key file",
    name: "settingsSearchSecurityKeyFileTitle",
    desc:
        "Settings search result title for the \"Key file\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSecurityKeyFileDescription => Intl.message(
    "Export or import your room keys as a file",
    name: "settingsSearchSecurityKeyFileDescription",
    desc:
        "Settings search result: one-line explanation of the \"Key file\" setting, shown under its title");

String get settingsSearchSecurityBlockedUsersTitle => Intl.message(
    "Blocked users",
    name: "settingsSearchSecurityBlockedUsersTitle",
    desc:
        "Settings search result title for the \"Blocked users\" setting; use the same wording as that setting's label on its page");

String get settingsSearchSecurityBlockedUsersDescription => Intl.message(
    "People whose messages, invites and calls are hidden",
    name: "settingsSearchSecurityBlockedUsersDescription",
    desc:
        "Settings search result: one-line explanation of the \"Blocked users\" setting, shown under its title");

String get settingsSearchEmojiFavoritePacksTitle => Intl.message(
    "Favorite Packs",
    name: "settingsSearchEmojiFavoritePacksTitle",
    desc:
        "Settings search result title for the \"Favorite Packs\" setting; use the same wording as that setting's label on its page");

String get settingsSearchEmojiFavoritePacksDescription => Intl.message(
    "Emoji and sticker packs you use everywhere",
    name: "settingsSearchEmojiFavoritePacksDescription",
    desc:
        "Settings search result: one-line explanation of the \"Favorite Packs\" setting, shown under its title");

String get settingsSearchAccountsAccountsTitle => Intl.message("Accounts",
    name: "settingsSearchAccountsAccountsTitle",
    desc:
        "Settings search result title for the \"Accounts\" setting; use the same wording as that setting's label on its page");

String get settingsSearchAccountsAccountsDescription => Intl.message(
    "Add another account or sign out",
    name: "settingsSearchAccountsAccountsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Accounts\" setting, shown under its title");

String get settingsSearchVoipMicrophoneVolumeTitle => Intl.message(
    "Input volume",
    name: "settingsSearchVoipMicrophoneVolumeTitle",
    desc:
        "Settings search result title for the \"Input Volume\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipMicrophoneVolumeDescription => Intl.message(
    "How loud your microphone is to everyone else",
    name: "settingsSearchVoipMicrophoneVolumeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Input Volume\" setting, shown under its title");

String get settingsSearchVoipOutputVolumeTitle => Intl.message("Output volume",
    name: "settingsSearchVoipOutputVolumeTitle",
    desc:
        "Settings search result title for the \"Output Volume\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipOutputVolumeDescription => Intl.message(
    "Turns down everyone in your calls and the audio of streams you watch",
    name: "settingsSearchVoipOutputVolumeDescription",
    desc:
        "Settings search result: one-line explanation of the \"Output Volume\" setting, shown under its title");

String get settingsSearchVoipPushToTalkTitle => Intl.message("Push to talk",
    name: "settingsSearchVoipPushToTalkTitle",
    desc:
        "Settings search result title for the \"Push to talk\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipPushToTalkDescription => Intl.message(
    "Your microphone only sends while you hold a key or the talk button.",
    name: "settingsSearchVoipPushToTalkDescription",
    desc:
        "Settings search result: one-line explanation of the \"Push to talk\" setting, shown under its title");

String get settingsSearchSectionInputMode => Intl.message("Input mode",
    name: "settingsSearchSectionInputMode",
    desc:
        "Settings search result: name of the \"Input Mode\" section of a settings page, shown in the result's breadcrumb; use the same wording as the section heading on that page");

String get settingsSearchVoipPushToTalkReleaseDelayTitle => Intl.message(
    "Release delay",
    name: "settingsSearchVoipPushToTalkReleaseDelayTitle",
    desc:
        "Settings search result title for the \"Release delay\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipPushToTalkReleaseDelayDescription => Intl.message(
    "Keeps sending a moment after you let go of push to talk",
    name: "settingsSearchVoipPushToTalkReleaseDelayDescription",
    desc:
        "Settings search result: one-line explanation of the \"Release delay\" setting, shown under its title");

String get settingsSearchVoipPushToTalkSoundsTitle => Intl.message(
    "Talk sounds",
    name: "settingsSearchVoipPushToTalkSoundsTitle",
    desc:
        "Settings search result title for the \"Talk sounds\" setting; use the same wording as that setting's label on its page");

String get settingsSearchVoipPushToTalkSoundsDescription => Intl.message(
    "A soft click when push to talk starts and stops",
    name: "settingsSearchVoipPushToTalkSoundsDescription",
    desc:
        "Settings search result: one-line explanation of the \"Talk sounds\" setting, shown under its title");

String get settingsSearchMemberListSubtitleTitle => Intl.message("Member list",
    name: "settingsSearchMemberListSubtitleTitle",
    desc:
        "Settings search result title for the \"Member list\" setting; use the same wording as that setting's label on its page");

String get settingsSearchMemberListSubtitleDescription => Intl.message(
    "What shows under each member's name: homeserver or status",
    name: "settingsSearchMemberListSubtitleDescription",
    desc:
        "Settings search result: one-line explanation of the \"Member list\" setting, shown under its title");
