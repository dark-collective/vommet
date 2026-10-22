// Vommet: translations for the Experiments page entries. The entries in
// experiment_entries.dart stay plain English (that file is union-merged, so
// its blocks must not change); the page and settings search look each
// title/description up here by its English text and fall back to the
// entry's own text when there's no message for it (a new experiment, or one
// whose wording changed since). To translate a new experiment, add its
// title and description below with the English text copied byte for byte.
import 'package:commet/config/experiment_registry.dart';
import 'package:intl/intl.dart';

/// The experiment's title in the app's language.
String experimentTitle(Experiment e) => experimentTitleL10n(e.title) ?? e.title;

/// The experiment's description in the app's language.
String experimentDescription(Experiment e) =>
    experimentDescriptionL10n(e.description) ?? e.description;

/// The category heading in the app's language.
String experimentCategoryLabel(ExperimentCategory c) => switch (c) {
      ExperimentCategory.messages => experimentCategoryMessagesLabel,
      ExperimentCategory.calls => experimentCategoryCallsLabel,
      ExperimentCategory.layout => experimentCategoryLayoutLabel,
      ExperimentCategory.sync => experimentCategorySyncLabel,
    };

/// Translated title for an experiment whose English title is [english], or
/// null when there is no message for it.
String? experimentTitleL10n(String english) => _titles[english]?.call();

/// Translated description for an experiment whose English description is
/// [english], or null when there is no message for it.
String? experimentDescriptionL10n(String english) =>
    _descriptions[english]?.call();

final Map<String, String Function()> _titles = {
  "Encrypted Element Call": () => experimentE2eeElementCallTitle,
  "Forward messages": () => experimentForwardMessagesTitle,
  "Keep drafts": () => experimentMessageDraftsTitle,
  "Discord-style layout": () => experimentBannerLayoutTitle,
  "Sliding sync": () => experimentSlidingSyncTitle,
  "Noise suppression": () => experimentNoiseSuppressionTitle,
  "Automatic gain control": () => experimentAutoGainControlTitle,
  "Profile and audio quick controls": () => experimentQuickProfileControlsTitle,
  "Timestamps": () => experimentMessageTimestampsTitle,
  "Send while offline": () => experimentOfflineSendingTitle,
  "Calls in text rooms": () => experimentRoomCallsTitle,
  "Calls across homeservers (multi-SFU)": () => experimentMultiSfuTitle,
  "Drag spaces with the mouse": () => experimentSidebarDesktopDragTitle,
  "Pin rooms to the sidebar": () => experimentSidebarPinnedRoomsTitle,
  "Newest unread DMs first": () => experimentSidebarNewestUnreadDmsTitle,
  "Clearer subspaces and voice rooms": () =>
      experimentSidebarSubspaceGuidesTitle,
  "Manage a space's rooms": () => experimentManageSpaceRoomsTitle,
  "Picture gallery": () => experimentLightboxGalleryTitle,
  "Encryption markers": () => experimentEncryptionMarkersTitle,
  "Trust warnings in direct messages": () => experimentDmTrustWarningsTitle,
  "Open a voice room's chat": () => experimentVoiceRoomChatTitle,
  "Secure messaging setup": () => experimentSecureSetupTitle,
  "Read state per thread": () => experimentThreadReadStateTitle,
  "Block users": () => experimentBlockUsersTitle,
  "Call cards and per-call mute": () => experimentCallCardsTitle,
  "Nickname per space and room": () => experimentSpaceNicknamesTitle,
  "Reopen the last room in a space": () => experimentLastRoomPerSpaceTitle,
  "Select several messages": () => experimentSelectMessagesTitle,
  "Watch streams like Discord": () => experimentStreamWatchingTitle,
};

final Map<String, String Function()> _descriptions = {
  "Join calls in encrypted rooms (end-to-end encrypted "
      "Element Call media).": () => experimentE2eeElementCallDescription,
  "Adds Forward to the message menu, like Telegram: pick a room, then the message waits above the message box until you send it. Tap it to hide the sender's name or a caption, or to pick another room. Forwards name the original sender (MSC4553, unstable); other apps see a \"Forwarded from\" line. Forwards from others show who wrote them. No restart needed":
      () => experimentForwardMessagesDescription,
  "Text you haven't sent stays in the message box when you switch to another room or DM and back, with the message you were replying to. Kept until the app closes, never saved to disk. Takes effect when you next open a room":
      () => experimentMessageDraftsDescription,
  "Banners shrink to their name bar as you scroll, the member list is split into Online and Offline, and you can drag the room list and member list edges to resize them (double-click an edge to reset). Takes effect when you next open a room":
      () => experimentBannerLayoutDescription,
  "Sync faster with sliding sync, when your homeserver supports it. Falls back to regular sync otherwise.":
      () => experimentSlidingSyncDescription,
  "Remove keyboard, fan and other background noise from your microphone in calls (RNNoise or DeepFilterNet3). Choose the strength in Voice settings":
      () => experimentNoiseSuppressionDescription,
  "Level your microphone in calls, so you're as loud as people on Element Call or Discord. Takes effect on your next call":
      () => experimentAutoGainControlDescription,
  "Click your name in the bottom-left corner for a profile card: status message, Online / Idle / Invisible, and changing your avatar and banner (each only where your homeserver supports it)":
      () => experimentQuickProfileControlsDescription,
  "Write <t:1700000000> (Discord, with :t :T :d :D :f :F :R styles) or \$[1700000000] (Sable) to send a time everyone sees in their own time zone (MSC3160), and show other people's timestamps that way. No restart needed":
      () => experimentMessageTimestampsDescription,
  "Messages you send without a connection wait and go out by themselves when you're back online, like Telegram, even if Vommet was closed in between (for up to a week). Files sent offline still need a retry after restarting.":
      () => experimentOfflineSendingDescription,
  "Join Element Call and Element X calls in ordinary rooms and DMs, not just voice rooms. Encrypted rooms also need Encrypted Element Call":
      () => experimentRoomCallsDescription,
  "Hear and be heard by people on other homeservers who use Element Call 0.21 or newer: listen on every call server people publish on, and follow the call when its main server changes. Applies to calls you join after turning it on":
      () => experimentMultiSfuDescription,
  "On desktop, drag spaces and folders in the sidebar straight away, like Discord, instead of pressing and holding first":
      () => experimentSidebarDesktopDragDescription,
  "Right-click any room or DM and choose Pin to Sidebar to give it its own icon next to your spaces. Drag it to reorder; your pins sync to your other devices":
      () => experimentSidebarPinnedRoomsDescription,
  "Show the most recently active unread direct message at the top of the sidebar, like Discord":
      () => experimentSidebarNewestUnreadDmsDescription,
  "Subspace names in a space's room list are small capitals with a faint line down the side, so you can see where each subspace ends, and long room names wrap to two lines. Voice rooms get a headphones mark (a ring around the room's picture) that turns green, with a count, while people are in the call, and green text when you're in it. In a call you're in, people light up while they talk and show when their mic is off. Spaces on the left show headphones while a call is on in them, or LIVE while someone shares their screen in your call there. On phones the next panel's strip is narrower. No restart needed":
      () => experimentSidebarSubspaceGuidesDescription,
  "Adds \"Manage rooms\" to the space menu for people allowed to edit the space: reorder its rooms and subspaces with drag handles, move a room into another subspace, or remove it from the space (the room isn't deleted). Nothing changes until you save. On phones, long-pressing a room on the space's home page then only opens its menu. No restart needed":
      () => experimentManageSpaceRoomsDescription,
  "When you open a picture or video in a room, use the left and right arrow keys (or swipe on a phone) to go through the room's other pictures and videos. Esc closes the viewer":
      () => experimentLightboxGalleryDescription,
  "A small icon after a room's name when it isn't "
          "encrypted (or, in a direct message, when you verified the "
          "person), the topic on its own line, and \"Send an "
          "unencrypted message\" in rooms that aren't encrypted.":
      () => experimentEncryptionMarkersDescription,
  "Warn when someone's identity changed (or they never "
          "set up secure messaging), check new direct messages before "
          "they start, and stop you from sending your own recovery key.":
      () => experimentDmTrustWarningsDescription,
  "Like Discord: hover a voice room in the room list for a chat button (desktop), or long-press it for \"Open Chat\" at the top of the menu (mobile). A voice room's header gets a chat button, and the chat's header a headphones button back to the call. No restart needed":
      () => experimentVoiceRoomChatDescription,
  "On for everyone. Right after sign-in, sets up your recovery key (or confirms this device) before any room opens, then checks now and then that you still have the key. Only turn it off to rule it out when something goes wrong; the setup is still in Settings › Security":
      () => experimentSecureSetupDescription,
  "Reading a room no longer marks its threads read: each thread keeps its own read position (threaded read receipts), and the Threads list marks threads with new replies. A room stays unread until you've read its threads too. Takes effect as you read":
      () => experimentThreadReadStateDescription,
  "Block and Unblock in people's profile menus, and a Blocked users list in Settings › Security. Blocking hides their messages, invites and calls on all your devices (your account's Matrix ignore list); they aren't told":
      () => experimentBlockUsersDescription,
  "Each call you're in is a card showing its room, its space and, with several accounts, which account you're in it with. Mute and deafen are per call: the open card has its own microphone and headphones buttons, a folded card shows a red mark when you're muted or deafened there, and a new call starts the way you left the last one. The buttons by your name act on the open call. No restart needed":
      () => experimentCallCardsDescription,
  "Adds \"Your nickname\" to space and room settings: others see that name in the space and every room in it, or just in one room. Vommet writes it as your name in each room (slowly, for big spaces), gives new rooms in the space the same name, and puts it back after you change your global name here. Turning this off stops all of that; names already set stay":
      () => experimentSpaceNicknamesDescription,
  "Clicking a space takes you back to the room you were in when you left it, like Discord. Click the space again for its main page. Remembered on this device for each account. No restart needed":
      () => experimentLastRoomPerSpaceDescription,
  "Adds Select to the message menu, like Telegram: tick several messages, then delete, copy or forward them in one go. Tap or click a message to tick it, drag along the circles to tick many, or Shift+click to tick a range. Esc, back or Cancel stops selecting. No restart needed":
      () => experimentSelectMessagesDescription,
  "Other people's screen shares wait for you to press Watch stream, so you only download the ones you look at. Each shows a small live preview when the sharer's app sends one, otherwise their picture. While you watch, the controls fade after a few seconds: click the stream to bring them back. They let you mute or turn down the stream's sound, stop watching, or go fullscreen (also a double-click), which now fills your whole screen with your call buttons at the bottom. Takes effect from your next call":
      () => experimentStreamWatchingDescription,
};

String get experimentE2eeElementCallTitle => Intl.message(
    "Encrypted Element Call",
    name: "experimentE2eeElementCallTitle",
    desc:
        "Name of the \"Encrypted Element Call\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentE2eeElementCallDescription => Intl.message(
    "Join calls in encrypted rooms (end-to-end encrypted "
    "Element Call media).",
    name: "experimentE2eeElementCallDescription",
    desc:
        "Explanation under the \"Encrypted Element Call\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentForwardMessagesTitle => Intl.message("Forward messages",
    name: "experimentForwardMessagesTitle",
    desc:
        "Name of the \"Forward messages\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentForwardMessagesDescription => Intl.message(
    "Adds Forward to the message menu, like Telegram: pick a room, then the message waits above the message box until you send it. Tap it to hide the sender's name or a caption, or to pick another room. Forwards name the original sender (MSC4553, unstable); other apps see a \"Forwarded from\" line. Forwards from others show who wrote them. No restart needed.",
    name: "experimentForwardMessagesDescription",
    desc:
        "Explanation under the \"Forward messages\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentMessageDraftsTitle => Intl.message("Keep drafts",
    name: "experimentMessageDraftsTitle",
    desc:
        "Name of the \"Keep drafts\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentMessageDraftsDescription => Intl.message(
    "Text you haven't sent stays in the message box when you switch to another room or DM and back, with the message you were replying to. Kept until the app closes, never saved to disk. Takes effect when you next open a room.",
    name: "experimentMessageDraftsDescription",
    desc:
        "Explanation under the \"Keep drafts\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentBannerLayoutTitle => Intl.message("Discord-style layout",
    name: "experimentBannerLayoutTitle",
    desc:
        "Name of the \"Discord-style layout\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentBannerLayoutDescription => Intl.message(
    "Banners shrink to their name bar as you scroll, the member list is split into Online and Offline, and you can drag the room list and member list edges to resize them (double-click an edge to reset). Takes effect when you next open a room.",
    name: "experimentBannerLayoutDescription",
    desc:
        "Explanation under the \"Discord-style layout\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSlidingSyncTitle => Intl.message("Sliding sync",
    name: "experimentSlidingSyncTitle",
    desc:
        "Name of the \"Sliding sync\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSlidingSyncDescription => Intl.message(
    "Sync faster with sliding sync, when your homeserver supports it. Falls back to regular sync otherwise.",
    name: "experimentSlidingSyncDescription",
    desc:
        "Explanation under the \"Sliding sync\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentNoiseSuppressionTitle => Intl.message("Noise suppression",
    name: "experimentNoiseSuppressionTitle",
    desc:
        "Name of the \"Noise suppression\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentNoiseSuppressionDescription => Intl.message(
    "Remove keyboard, fan, and other background noise from your microphone in calls (RNNoise or DeepFilterNet3). Choose the strength in Voice settings.",
    name: "experimentNoiseSuppressionDescription",
    desc:
        "Explanation under the \"Noise suppression\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentAutoGainControlTitle => Intl.message(
    "Automatic gain control",
    name: "experimentAutoGainControlTitle",
    desc:
        "Name of the \"Automatic gain control\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentAutoGainControlDescription => Intl.message(
    "Level your microphone in calls, so you're as loud as people on Element Call or Discord. Takes effect on your next call.",
    name: "experimentAutoGainControlDescription",
    desc:
        "Explanation under the \"Automatic gain control\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentQuickProfileControlsTitle => Intl.message(
    "Profile and audio quick controls",
    name: "experimentQuickProfileControlsTitle",
    desc:
        "Name of the \"Profile and audio quick controls\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentQuickProfileControlsDescription => Intl.message(
    "Click your name in the bottom-left corner for a profile card: status message, Online / Idle / Invisible, and changing your avatar and banner (each only where your homeserver supports it).",
    name: "experimentQuickProfileControlsDescription",
    desc:
        "Explanation under the \"Profile and audio quick controls\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentMessageTimestampsTitle => Intl.message("Timestamps",
    name: "experimentMessageTimestampsTitle",
    desc:
        "Name of the \"Timestamps\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentMessageTimestampsDescription => Intl.message(
    "Write <t:1700000000> (Discord, with :t :T :d :D :f :F :R styles) or \$[1700000000] (Sable) to send a time everyone sees in their own time zone (MSC3160), and show other people's timestamps that way. No restart needed.",
    name: "experimentMessageTimestampsDescription",
    desc:
        "Explanation under the \"Timestamps\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentOfflineSendingTitle => Intl.message("Send while offline",
    name: "experimentOfflineSendingTitle",
    desc:
        "Name of the \"Send while offline\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentOfflineSendingDescription => Intl.message(
    "Messages you send without a connection wait and go out by themselves when you're back online, like Telegram, even if Vommet was closed in between (for up to a week). Files sent offline still need a retry after restarting.",
    name: "experimentOfflineSendingDescription",
    desc:
        "Explanation under the \"Send while offline\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentRoomCallsTitle => Intl.message("Calls in text rooms",
    name: "experimentRoomCallsTitle",
    desc:
        "Name of the \"Calls in text rooms\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentRoomCallsDescription => Intl.message(
    "Join Element Call and Element X calls in ordinary rooms and DMs, not just voice rooms. Encrypted rooms also need Encrypted Element Call.",
    name: "experimentRoomCallsDescription",
    desc:
        "Explanation under the \"Calls in text rooms\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentMultiSfuTitle => Intl.message(
    "Calls across homeservers (multi-SFU)",
    name: "experimentMultiSfuTitle",
    desc:
        "Name of the \"Calls across homeservers (multi-SFU)\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentMultiSfuDescription => Intl.message(
    "Hear and be heard by people on other homeservers who use Element Call 0.21 or newer: listen on every call server people publish on, and follow the call when its main server changes. Applies to calls you join after turning it on.",
    name: "experimentMultiSfuDescription",
    desc:
        "Explanation under the \"Calls across homeservers (multi-SFU)\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSidebarDesktopDragTitle => Intl.message(
    "Drag spaces with the mouse",
    name: "experimentSidebarDesktopDragTitle",
    desc:
        "Name of the \"Drag spaces with the mouse\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSidebarDesktopDragDescription => Intl.message(
    "On desktop, drag spaces and folders in the sidebar straight away, like Discord, instead of pressing and holding first.",
    name: "experimentSidebarDesktopDragDescription",
    desc:
        "Explanation under the \"Drag spaces with the mouse\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSidebarPinnedRoomsTitle => Intl.message(
    "Pin rooms to the sidebar",
    name: "experimentSidebarPinnedRoomsTitle",
    desc:
        "Name of the \"Pin rooms to the sidebar\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSidebarPinnedRoomsDescription => Intl.message(
    "Right-click any room or DM and choose Pin to sidebar to give it its own icon next to your spaces. Drag it to reorder; your pins sync to your other devices.",
    name: "experimentSidebarPinnedRoomsDescription",
    desc:
        "Explanation under the \"Pin rooms to the sidebar\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSidebarNewestUnreadDmsTitle => Intl.message(
    "Newest unread DMs first",
    name: "experimentSidebarNewestUnreadDmsTitle",
    desc:
        "Name of the \"Newest unread DMs first\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSidebarNewestUnreadDmsDescription => Intl.message(
    "Show the most recently active unread direct message at the top of the sidebar, like Discord.",
    name: "experimentSidebarNewestUnreadDmsDescription",
    desc:
        "Explanation under the \"Newest unread DMs first\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSidebarSubspaceGuidesTitle => Intl.message(
    "Clearer subspaces and voice rooms",
    name: "experimentSidebarSubspaceGuidesTitle",
    desc:
        "Name of the \"Clearer subspaces and voice rooms\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSidebarSubspaceGuidesDescription => Intl.message(
    "Subspace names in a space's room list are small capitals with a faint line down the side, so you can see where each subspace ends. Voice rooms get a headphones mark beside their picture that turns green while people are in the call, a green pill at the end of the row with the number of people in it, and a faint green highlight on the row while you're in the call. In a call you're in, people light up while they talk and show when their mic is off. Spaces on the left show green headphones while a call is on in them, or a red screen-share mark while someone shares their screen in your call there. On phones, less of the next panel shows at the edge, leaving more room for room names. No restart needed.",
    name: "experimentSidebarSubspaceGuidesDescription",
    desc:
        "Explanation under the \"Clearer subspaces and voice rooms\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentManageSpaceRoomsTitle => Intl.message(
    "Manage a space's rooms",
    name: "experimentManageSpaceRoomsTitle",
    desc:
        "Name of the \"Manage a space's rooms\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentManageSpaceRoomsDescription => Intl.message(
    "Adds \"Manage rooms\" to the space menu for people allowed to edit the space: reorder its rooms and subspaces with drag handles, move a room into another subspace, or remove it from the space (the room isn't deleted). Nothing changes until you save. On phones, long-pressing a room on the space's home page then only opens its menu. No restart needed.",
    name: "experimentManageSpaceRoomsDescription",
    desc:
        "Explanation under the \"Manage a space's rooms\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentLightboxGalleryTitle => Intl.message("Picture gallery",
    name: "experimentLightboxGalleryTitle",
    desc:
        "Name of the \"Picture gallery\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentLightboxGalleryDescription => Intl.message(
    "When you open a picture or video in a room, use the left and right arrow keys (or swipe on a phone) to go through the room's other pictures and videos. Esc closes the viewer.",
    name: "experimentLightboxGalleryDescription",
    desc:
        "Explanation under the \"Picture gallery\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentEncryptionMarkersTitle => Intl.message(
    "Encryption markers",
    name: "experimentEncryptionMarkersTitle",
    desc:
        "Name of the \"Encryption markers\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentEncryptionMarkersDescription => Intl.message(
    "A small icon after a room's name when the room isn't encrypted (or, in a direct message, when you verified the person), and \"Send an unencrypted message\" in the message box of rooms that aren't encrypted. In every room, encrypted or not, the topic also moves to its own line under the name.",
    name: "experimentEncryptionMarkersDescription",
    desc:
        "Explanation under the \"Encryption markers\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentDmTrustWarningsTitle => Intl.message(
    "Trust warnings in direct messages",
    name: "experimentDmTrustWarningsTitle",
    desc:
        "Name of the \"Trust warnings in direct messages\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentDmTrustWarningsDescription => Intl.message(
    "Warn when someone's identity changed (or they never "
    "set up secure messaging), check new direct messages before "
    "they start, and stop you from sending your own recovery key.",
    name: "experimentDmTrustWarningsDescription",
    desc:
        "Explanation under the \"Trust warnings in direct messages\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentVoiceRoomChatTitle => Intl.message(
    "Open a voice room's chat",
    name: "experimentVoiceRoomChatTitle",
    desc:
        "Name of the \"Open a voice room's chat\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentVoiceRoomChatDescription => Intl.message(
    "Like Discord: hover a voice room in the room list for a chat button (desktop), or long-press it for \"Open chat\" at the top of the menu (mobile). A voice room's header gets a chat button, and the chat's header a headphones button back to the call. No restart needed.",
    name: "experimentVoiceRoomChatDescription",
    desc:
        "Explanation under the \"Open a voice room's chat\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSecureSetupTitle => Intl.message("Secure messaging setup",
    name: "experimentSecureSetupTitle",
    desc:
        "Name of the \"Secure messaging setup\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSecureSetupDescription => Intl.message(
    "On for everyone. Right after sign-in, sets up your recovery key (or confirms this device) before any room opens, then checks now and then that you still have the key. Only turn it off to rule it out when something goes wrong; the setup is still in Settings › Security.",
    name: "experimentSecureSetupDescription",
    desc:
        "Explanation under the \"Secure messaging setup\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentThreadReadStateTitle => Intl.message(
    "Read state per thread",
    name: "experimentThreadReadStateTitle",
    desc:
        "Name of the \"Read state per thread\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentThreadReadStateDescription => Intl.message(
    "Reading a room no longer marks its threads read: each thread keeps its own read position (threaded read receipts), and the Threads list marks threads with new replies. A room stays unread until you've read its threads too. Takes effect as you read.",
    name: "experimentThreadReadStateDescription",
    desc:
        "Explanation under the \"Read state per thread\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentBlockUsersTitle => Intl.message("Block users",
    name: "experimentBlockUsersTitle",
    desc:
        "Name of the \"Block users\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentBlockUsersDescription => Intl.message(
    "Block and Unblock in people's profile menus, and a Blocked users list in Settings › Security. Blocking hides their messages, invites, and calls on all your devices (your account's Matrix ignore list); they aren't told.",
    name: "experimentBlockUsersDescription",
    desc:
        "Explanation under the \"Block users\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentCallCardsTitle => Intl.message(
    "Call cards and per-call mute",
    name: "experimentCallCardsTitle",
    desc:
        "Name of the \"Call cards and per-call mute\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentCallCardsDescription => Intl.message(
    "Each call you're in is a card showing its room, its space, and, with several accounts, which account you're in it with. Mute and deafen are per call: the open card has its own microphone and headphones buttons, a folded card shows a red mark when you're muted or deafened there, and a new call starts the way you left the last one. The buttons by your name act on the open call. No restart needed.",
    name: "experimentCallCardsDescription",
    desc:
        "Explanation under the \"Call cards and per-call mute\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSpaceNicknamesTitle => Intl.message(
    "Nickname per space and room",
    name: "experimentSpaceNicknamesTitle",
    desc:
        "Name of the \"Nickname per space and room\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSpaceNicknamesDescription => Intl.message(
    "Adds \"Your nickname\" to space and room settings: others see that name in the space and every room in it, or just in one room. Vommet writes it as your name in each room (slowly, for big spaces), gives new rooms in the space the same name, and puts it back after you change your global name here. Turning this off stops all of that; names already set stay.",
    name: "experimentSpaceNicknamesDescription",
    desc:
        "Explanation under the \"Nickname per space and room\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentLastRoomPerSpaceTitle => Intl.message(
    "Reopen the last room in a space",
    name: "experimentLastRoomPerSpaceTitle",
    desc:
        "Name of the \"Reopen the last room in a space\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentLastRoomPerSpaceDescription => Intl.message(
    "Clicking a space takes you back to the room you were in when you left it, like Discord. Click the space again for its main page. Remembered on this device for each account. No restart needed.",
    name: "experimentLastRoomPerSpaceDescription",
    desc:
        "Explanation under the \"Reopen the last room in a space\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentSelectMessagesTitle => Intl.message(
    "Select several messages",
    name: "experimentSelectMessagesTitle",
    desc:
        "Name of the \"Select several messages\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentSelectMessagesDescription => Intl.message(
    "Adds Select to the message menu, like Telegram: tick several messages, then delete, copy, or forward them in one go. Tap or click a message to tick it, drag along the circles to tick many, or Shift+click to tick a range. Esc, back, or Cancel stops selecting. No restart needed.",
    name: "experimentSelectMessagesDescription",
    desc:
        "Explanation under the \"Select several messages\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentStreamWatchingTitle => Intl.message(
    "Watch streams like Discord",
    name: "experimentStreamWatchingTitle",
    desc:
        "Name of the \"Watch streams like Discord\" experiment, shown as a toggle title on the Experiments settings page and in settings search");

String get experimentStreamWatchingDescription => Intl.message(
    "Other people's screen shares wait for you to press Watch stream, so you only download the ones you look at. Each shows a small live preview when the sharer's app sends one, otherwise their picture. While you watch, the controls fade after a few seconds: click the stream to bring them back. They let you mute or turn down the stream's sound, stop watching, or go fullscreen (also a double-click), which now fills your whole screen with your call buttons at the bottom. Takes effect from your next call.",
    name: "experimentStreamWatchingDescription",
    desc:
        "Explanation under the \"Watch streams like Discord\" experiment toggle on the Experiments settings page (also shown in settings search)");

String get experimentCategoryMessagesLabel => Intl.message("Chat and messages",
    name: "experimentCategoryMessagesLabel",
    desc:
        "Heading of the \"Chat and messages\" group on the Experiments settings page");

String get experimentCategoryCallsLabel => Intl.message("Calls and voice",
    name: "experimentCategoryCallsLabel",
    desc:
        "Heading of the \"Calls and voice\" group on the Experiments settings page");

String get experimentCategoryLayoutLabel => Intl.message("Layout and sidebar",
    name: "experimentCategoryLayoutLabel",
    desc:
        "Heading of the \"Layout and sidebar\" group on the Experiments settings page");

String get experimentCategorySyncLabel => Intl.message("Sync and performance",
    name: "experimentCategorySyncLabel",
    desc:
        "Heading of the \"Sync and performance\" group on the Experiments settings page");
