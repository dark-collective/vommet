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
            "Adds Forward to the message menu: send a copy of a message, image or sticker to other rooms and DMs. No restart needed",
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
            "Sync faster with sliding sync, when your homeserver supports it. Falls back to regular sync otherwise. Unread counts don't work yet on Synapse servers (e.g. matrix.org)",
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
    ];
