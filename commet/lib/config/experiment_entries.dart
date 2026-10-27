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
// Experiments are on by default (opt-out); add `optIn: true` only when one is
// too risky to switch on for everyone.
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/main.dart';
import 'package:commet/client/matrix/nicknames/nickname_experiment.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/pages/guides/guides.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/ui/atoms/reaction_burst.dart';
import 'package:commet/client/components/voip/camera_background_blur.dart';

List<Experiment> experimentEntries() => [
      // experiment: vommet_experiment_forward_messages
      Experiment(
        preference: preferences.experimentForwardMessages,
        title: "Forward messages",
        description:
            "Adds Forward to the message menu, like Telegram: pick a room, then the message waits above the message box until you send it. The sender's name is left out unless you tap it and choose to show it (your last choice is kept); there you can also hide a caption or pick another room. Forwards name the original sender (MSC4553, unstable); other apps see a \"Forwarded from\" line. Forwards from others show who wrote them. No restart needed",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_forward_messages
      // experiment: experiment_quick_profile_controls
      Experiment(
        preference: preferences.experimentQuickProfileControls,
        title: "Profile and audio quick controls",
        description:
            "Click your name in the bottom-left corner for a profile card: status message, Online / Idle / Invisible, and changing your avatar and banner (each only where your homeserver supports it)",
        category: ExperimentCategory.calls,
      ), // experiment_quick_profile_controls
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
            "Join Element Call and Element X calls in ordinary rooms and DMs, not just voice rooms, encrypted or not",
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
      // experiment: vommet_experiment_thread_read_state
      Experiment(
        preference: preferences.experimentThreadReadState,
        title: "Read state per thread",
        description:
            "Reading a room no longer marks its threads read: each thread keeps its own read position (threaded read receipts), and the Threads list marks threads with new replies. A room stays unread until you've read its threads too. Takes effect as you read",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_thread_read_state
      // experiment: vommet_experiment_space_nicknames
      Experiment(
        preference: experimentSpaceNicknames,
        title: "Nickname per space and room",
        description:
            "Adds \"Your nickname\" to space and room settings: others see that name in the space and every room in it, or just in one room. Vommet writes it as your name in each room (slowly, for big spaces), gives new rooms in the space the same name, and puts it back after you change your global name here. Turning this off stops all of that; names already set stay",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_space_nicknames
      // experiment: vommet_experiment_select_messages
      Experiment(
        preference: preferences.experimentSelectMessages,
        title: "Select several messages",
        description:
            "Adds Select to the message menu, like Telegram: tick several messages, then delete, copy or forward them in one go. Tap or click a message to tick it, drag along the circles to tick many, or Shift+click to tick a range. On a computer, dragging from one message into another selects the messages passed. On a phone, long-press a message to select it and tap a message for its menu. Esc, back or Cancel stops selecting. No restart needed",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_select_messages
      // experiment: vommet_experiment_docked_widgets
      Experiment(
        preference: WidgetDock.experiment,
        title: "Docked widgets",
        description: "Widgets open inside Vommet's window instead of a "
            "window of their own. Pop one out into its own window and dock "
            "it back without it reloading.",
        category: ExperimentCategory.layout,
        available: WidgetDock.available,
        // On for everyone by default (operator, 10-25); a stored "off" from
        // before was cleared once (Preferences.dockedWidgetsDefaultOnOnce).
      ), // vommet_experiment_docked_widgets
      // experiment: vommet_experiment_new_home
      Experiment(
        preference: experimentNewHome,
        title: "New Home",
        description:
            "Home's column gets Overview, People and Rooms above your direct messages, like Discord. Overview shows cards (Recent activity, Favorites, Standalone rooms) that you can reorder, hide and set up from their ⋯ menu; the layout is private account data, shared by your devices. People has your contacts (with Active Now), direct-message invites and blocked people. Rooms lists standalone rooms and your spaces, with a search and filters",
        category: ExperimentCategory.layout,
        // On for everyone by default (operator, 10-25); a stored "off" from
        // before was cleared once (Preferences.newHomeDefaultOnOnce).
        onChanged: onNewHomeToggled,
      ), // vommet_experiment_new_home
      // experiment: vommet_experiment_redacted_mode
      Experiment(
        preference: preferences.experimentRedactedMode,
        title: "Redacted mode",
        description: "Hide names, profile pictures, message text, room names "
            "and pictures on screen, like streamer mode, for screenshots and "
            "screen sharing. Turn it on and pick a level in Settings › "
            "Redacted mode.",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_redacted_mode
      // experiment: vommet_experiment_guides
      Experiment(
        preference: experimentGuides,
        title: "Help on right-click",
        description:
            "Right-click a part of the app (press and hold on a phone; on an empty spot, with two fingers) for a short guide about it, and a Getting started walkthrough after your first sign-in. All guides are in Settings › Help and guides either way",
        category: ExperimentCategory.layout,
      ), // vommet_experiment_guides
      // experiment: vommet_experiment_chat_wallpapers
      Experiment(
        preference: experimentChatWallpapers,
        title: "Chat wallpapers",
        description:
            "Give a 1:1 chat its own wallpaper, like Telegram: either of you picks a picture, darkens or lightens and blurs it, and you both see it in that chat. In encrypted chats the picture is encrypted too. Room menu › Chat wallpaper, or the chat's Appearance settings, where you can also hide it for yourself",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_chat_wallpapers
      // experiment: vommet_experiment_room_info_page
      Experiment(
        preference: experimentRoomInfoPage,
        title: "New room info page",
        description:
            "Tapping a room's name opens a Room info page for everyone, like Telegram or Signal: the room's picture, topic and members, quick Mute, Search, Invite and Call buttons, its shared media, files, links, pins and threads, then your own settings for the room and the room's settings for everyone (read-only where you can't change them). On a computer it opens as a window with About, Members, Shared and Settings tabs. Direct chats follow who is in them: one that gains a third person becomes a group, and turns back when they leave",
        category: ExperimentCategory.layout,
      ), // vommet_experiment_room_info_page
      // experiment: vommet_experiment_reaction_bursts
      Experiment(
        preference: experimentReactionBursts,
        title: "Reaction bursts",
        description:
            "When you react, or a reaction arrives while you're in the room, its emoji bursts out of the reaction for a moment. Only on this device; follows Message Effects and your system's reduce-motion setting",
        category: ExperimentCategory.messages,
      ), // vommet_experiment_reaction_bursts
      // experiment: experiment_camera_background_blur
      Experiment(
        preference: preferences.experimentCameraBackgroundBlur,
        title: "Camera background blur",
        description: "Adds \"Blur background\" to Settings, Voice and "
            "video, to blur what's behind you on camera. Web app, Android, "
            "iOS, macOS, Linux and Windows.",
        category: ExperimentCategory.calls,
        available: () => CameraBackgroundBlur.supported,
        onChanged: (_) => CameraBackgroundBlur.notifyChanged(),
      ), // experiment_camera_background_blur
    ];
