// Vommet: every experiment on the Experiments page, one entry per feature.
//
// This file is union-merged (.gitattributes), so topics that each add an
// entry don't conflict. To keep the merged file valid Dart:
// * add your imports as separate lines below the existing ones;
// * add your entry directly above the closing `];` line, as one block whose
//   FIRST line is `// experiment: <preference key>` and whose LAST line is
//   `), // <preference key>`. Unique first and last lines stop git from
//   sliding two topics' blocks into each other when it unions them;
// * never change another topic's entry or import in the same commit.
// The page groups entries by category; order within a category is file order.
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/client/components/voip/voice_filter.dart';

List<Experiment> experimentEntries() => [
      // experiment: experiment_enabled_e2ee_element_call
      Experiment(
        preference: preferences.experimentEnableE2eeElementCall,
        title: "Encrypted Element Call",
        description: "Join calls in encrypted rooms (end-to-end encrypted "
            "Element Call media).",
        category: ExperimentCategory.calls,
      ), // experiment_enabled_e2ee_element_call
      // experiment: vommet_experiment_forward_messages
      Experiment(
        preference: preferences.experimentForwardMessages,
        title: "Forward messages",
        description:
            "Adds Forward to the message menu, like Telegram: pick a room, then the message waits above the message box until you send it. Tap it to hide the sender's name or a caption, or to pick another room. Forwards name the original sender (MSC4553, unstable); other apps see a \"Forwarded from\" line. Forwards from others show who wrote them. No restart needed",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_forward_messages
      // experiment: vommet_experiment_message_drafts
      Experiment(
        preference: preferences.experimentMessageDrafts,
        title: "Keep drafts",
        description:
            "Text you haven't sent stays in the message box when you switch to another room or DM and back, with the message you were replying to. Kept until the app closes, never saved to disk. Takes effect when you next open a room",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_message_drafts
      // experiment: vommet_experiment_banner_layout
      Experiment(
        preference: preferences.experimentBannerLayout,
        title: "Discord-style layout",
        description:
            "Banners shrink to their name bar as you scroll, the member list is split into Online and Offline, and you can drag the room list and member list edges to resize them (double-click an edge to reset). Takes effect when you next open a room",
        category: ExperimentCategory.layout,
      ), // vommet_experiment_banner_layout
      // experiment: experiment_sliding_sync
      Experiment(
        preference: preferences.experimentSlidingSync,
        title: "Sliding sync",
        description:
            "Sync faster with sliding sync, when your homeserver supports it. Falls back to regular sync otherwise.",
        category: ExperimentCategory.sync,
        needsRestart: true,
      ), // experiment_sliding_sync
      // experiment: experiment_noise_suppression
      Experiment(
        preference: preferences.experimentNoiseSuppression,
        title: "Noise suppression",
        description:
            "Remove keyboard, fan and other background noise from your microphone in calls (RNNoise or DeepFilterNet3). Choose the strength in Voice settings",
        category: ExperimentCategory.calls,
        onChanged: (_) => Future.microtask(VoiceFilter.apply),
      ), // experiment_noise_suppression
      // experiment: experiment_auto_gain_control
      Experiment(
        preference: preferences.experimentAutoGainControl,
        title: "Automatic gain control",
        description:
            "Level your microphone in calls, so you're as loud as people on Element Call or Discord. Takes effect on your next call",
        category: ExperimentCategory.calls,
      ), // experiment_auto_gain_control
      // experiment: experiment_quick_profile_controls
      Experiment(
        preference: preferences.experimentQuickProfileControls,
        title: "Profile and audio quick controls",
        description:
            "Click your name in the bottom-left corner for a profile card: status message, Online / Idle / Invisible, and changing your avatar and banner (each only where your homeserver supports it). Adds input and output volume sliders to the microphone and headphone menus",
        category: ExperimentCategory.calls,
        // The mic volume goes to the voice filter; the output volume is
        // re-applied so a call in progress follows the toggle.
        onChanged: (_) {
          VoiceFilter.apply();
          clientManager?.callManager.refreshPlaybackVolumes();
        },
      ), // experiment_quick_profile_controls
      // experiment: experiment_message_timestamps
      Experiment(
        preference: preferences.experimentMessageTimestamps,
        title: "Timestamps",
        description:
            "Write <t:1700000000> (Discord, with :t :T :d :D :f :F :R styles) or \$[1700000000] (Sable) to send a time everyone sees in their own time zone (MSC3160), and show other people's timestamps that way. No restart needed",
        category: ExperimentCategory.messages,
      ), // experiment_message_timestamps
      // experiment: experiment_offline_sending
      Experiment(
        preference: preferences.experimentOfflineSending,
        title: "Send while offline",
        description:
            "Messages you send without a connection wait and go out by themselves when you're back online, like Telegram, even if Vommet was closed in between (for up to a week). Files sent offline still need a retry after restarting.",
        category: ExperimentCategory.messages,
        needsRestart: true,
      ), // experiment_offline_sending
      // experiment: experiment_room_calls
      Experiment(
        preference: preferences.experimentRoomCalls,
        title: "Calls in text rooms",
        description:
            "Join Element Call and Element X calls in ordinary rooms and DMs, not just voice rooms. Encrypted rooms also need Encrypted Element Call",
        category: ExperimentCategory.calls,
      ), // experiment_room_calls
      // experiment: experiment_multi_sfu
      Experiment(
        preference: preferences.experimentMultiSfu,
        title: "Calls across homeservers (multi-SFU)",
        description:
            "Hear and be heard by people on other homeservers who use Element Call 0.21 or newer: listen on every call server people publish on, and follow the call when its main server changes. Applies to calls you join after turning it on",
        category: ExperimentCategory.calls,
      ), // experiment_multi_sfu
      // experiment: experiment_sidebar_desktop_drag
      Experiment(
        preference: preferences.experimentSidebarDesktopDrag,
        title: "Drag spaces with the mouse",
        description:
            "On desktop, drag spaces and folders in the sidebar straight away, like Discord, instead of pressing and holding first",
        category: ExperimentCategory.layout,
      ), // experiment_sidebar_desktop_drag
      // experiment: experiment_sidebar_pinned_rooms
      Experiment(
        preference: preferences.experimentSidebarPinnedRooms,
        title: "Pin rooms to the sidebar",
        description:
            "Right-click any room or DM and choose Pin to Sidebar to give it its own icon next to your spaces. Drag it to reorder; your pins sync to your other devices",
        category: ExperimentCategory.layout,
      ), // experiment_sidebar_pinned_rooms
      // experiment: experiment_sidebar_newest_unread_dms
      Experiment(
        preference: preferences.experimentSidebarNewestUnreadDms,
        title: "Newest unread DMs first",
        description:
            "Show the most recently active unread direct message at the top of the sidebar, like Discord",
        category: ExperimentCategory.layout,
      ), // experiment_sidebar_newest_unread_dms
      // experiment: experiment_sidebar_subspace_guides
      Experiment(
        preference: preferences.experimentSidebarSubspaceGuides,
        title: "Clearer subspaces and voice rooms",
        description:
            "Subspace names in a space's room list are small capitals with a faint line down the side, so you can see where each subspace ends. Voice rooms get a headphones mark that turns green, with a count, while people are in the call, and green text when you're in it. No restart needed",
        category: ExperimentCategory.layout,
      ), // experiment_sidebar_subspace_guides
      // experiment: experiment_manage_space_rooms
      Experiment(
        preference: preferences.experimentManageSpaceRooms,
        title: "Manage a space's rooms",
        description:
            "Adds \"Manage rooms\" to the space menu for people allowed to edit the space: reorder its rooms and subspaces with drag handles, move a room into another subspace, or remove it from the space (the room isn't deleted). Nothing changes until you save. On phones, long-pressing a room on the space's home page then only opens its menu. No restart needed",
        category: ExperimentCategory.layout,
      ), // experiment_manage_space_rooms
      // experiment: vommet_experiment_lightbox_gallery
      Experiment(
        preference: preferences.experimentLightboxGallery,
        title: "Picture gallery",
        description:
            "When you open a picture or video in a room, use the left and right arrow keys (or swipe on a phone) to go through the room's other pictures and videos. Esc closes the viewer",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_lightbox_gallery
      // experiment: experiment_encryption_markers
      Experiment(
        preference: preferences.experimentEncryptionMarkers,
        title: "Encryption markers",
        description: "A small icon after a room's name when it isn't "
            "encrypted (or, in a direct message, when you verified the "
            "person), the topic on its own line, and \"Send an "
            "unencrypted message\" in rooms that aren't encrypted.",
        category: ExperimentCategory.messages,
      ), // experiment_encryption_markers
      // experiment: experiment_dm_trust_warnings
      Experiment(
        preference: preferences.experimentDmTrustWarnings,
        title: "Trust warnings in direct messages",
        description: "Warn when someone's identity changed (or they never "
            "set up secure messaging), check new direct messages before "
            "they start, and stop you from sending your own recovery key.",
        category: ExperimentCategory.messages,
      ), // experiment_dm_trust_warnings
      // experiment: experiment_voice_room_chat
      Experiment(
        preference: preferences.experimentVoiceRoomChat,
        title: "Open a voice room's chat",
        description:
            "Like Discord: hover a voice room in the room list for a chat button (desktop), or long-press it for \"Open Chat\" at the top of the menu (mobile). A voice room's header gets a chat button, and the chat's header a headphones button back to the call. No restart needed",
        category: ExperimentCategory.calls,
      ), // experiment_voice_room_chat
    ];
