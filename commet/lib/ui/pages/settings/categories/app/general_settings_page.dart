import 'package:commet/ui/pages/settings/categories/app/widget_settings_panel.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/app/release_updates_setting.dart';
import 'package:commet/ui/pages/settings/categories/app/string_list_preference_editor.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/categories/app/language_settings_panel.dart';
import 'package:commet/ui/pages/setup/menus/check_for_updates.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_rerun_panel.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/pages/settings/categories/app/voice_transcription_settings.dart';
import 'package:commet/utils/voice_transcription.dart';
import 'package:commet/ui/pages/settings/categories/app/spellcheck_settings_panel.dart';
import 'package:commet/utils/spellcheck/spellcheck.dart';

import 'package:tiamat/tiamat.dart';

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => GeneralSettingsPageState();
}

class GeneralSettingsPageState extends State<GeneralSettingsPage> {
  String get labelThirdPartyServicesTitle =>
      Intl.message("Third party services",
          desc: "Header for the third party services section in settings",
          name: "labelThirdPartyServicesTitle");

  String get labelGifSearchToggle => Intl.message("Gif search",
      desc: "Label for the toggle for enabling and disabling gif search",
      name: "labelGifSearchToggle");

  String labelGifSearchDescriptionGeneric(proxyUrl, serviceName) => Intl.message(
      "Enable use of $serviceName GIF search. Requests will be proxied via $proxyUrl.",
      desc: "Explains that gifs will be fetched via proxy",
      args: [proxyUrl, serviceName],
      name: "labelGifSearchDescriptionGeneric");

  String get labelReleaseNoticeTitle => Intl.message("New releases",
      desc: "Label for the setting for what happens when a newer release is "
          "out",
      name: "labelReleaseNoticeTitle");

  String get labelReleaseNoticeDescription => Intl.message(
      "Vommet checks its release list on nether.codes once per launch. When a newer release is out, a bar at the bottom of the app can get the right file for this install and check its signature. Installing always takes a tap.",
      desc: "Description of the setting for what happens when a newer "
          "release is out",
      name: "labelReleaseNoticeDescription");

  String get labelUrlPreviewInEncryptedChatTitle => Intl.message(
      "URL Preview in Encrypted Chats",
      desc:
          "Label for the toggle for enabling and disabling use of url previews in encrypted chats",
      name: "labelUrlPreviewInEncryptedChatTitle");

  String get labelUrlPreviewInEncryptedChatDescription => Intl.message(
      "This will expose any URLs sent in your encrypted chats to your homeserver in order to fetch the preview",
      desc:
          "description for the toggle for enabling and disabling use of url previews in encrypted chats",
      name: "labelUrlPreviewInEncryptedChatDescription");

  String get labelAppBehaviourTitle => Intl.message("App Behavior",
      desc: "Header for the app behaviour section in settings",
      name: "labelAppBehaviourTitle");

  String get labelAskBeforeDeletingMessageToggle => Intl.message(
      "Ask before deleting messages",
      desc:
          "Label for the toggle for enabling and disabling message deletion confirmation",
      name: "labelAskBeforeDeletingMessageToggle");

  String get labelAskBeforeDeletingMessageDescription => Intl.message(
      "Enables the pop-up asking for confirmation when deleting a message.",
      desc:
          "Label describing what 'asking before deleting messages' even means",
      name: "labelAskBeforeDeletingMessageDescription");

  // Vommet: Link bare web addresses.
  String get labelLinkBareDomainsToggle => Intl.message(
      "Link bare web addresses",
      desc:
          "Title of the toggle that turns addresses like example.com in messages into links",
      name: "labelLinkBareDomainsToggle");

  String get labelLinkBareDomainsToggleDescription => Intl.message(
      "Turns addresses like example.com into links, like Telegram does",
      desc:
          "Description of the toggle that turns addresses like example.com in messages into links",
      name: "labelLinkBareDomainsToggleDescription");

  String get labelMessageEffectsTitle => Intl.message("Message Effects",
      desc:
          "Header for the settings tile for message effects, such as confetti",
      name: "labelMessageEffectsTitle");

  String get labelMessageEffectsDescription => Intl.message(
      "Messages can be sent with additional effects, such as confetti",
      desc: "Label describing what message effects are",
      name: "labelMessageEffectsDescription");

  String get labelMediaPreviewSettingsTitle => Intl.message("Media Preview",
      desc: "Header for the settings tile for for media preview toggles",
      name: "labelMediaPreviewSettingsTitle");

  String get labelMediaSettings => Intl.message("Media",
      desc: "Header for the settings tile for for media",
      name: "labelMediaSettings");

  String get labelMediaPreviewPrivateRoomsToggle => Intl.message(
        "Private Rooms",
        desc:
            "Short label for the private rooms toggle in media previews section",
        name: "labelMediaPreviewPrivateRoomsToggle",
      );

  String get labelMediaPreviewPrivateRoomsToggleDescription => Intl.message(
      "Toggle previewing of images, videos, stickers and urls in private chats",
      desc: "Label describing toggle of media previews for private rooms",
      name: "labelMediaPreviewPrivateRoomsToggleDescription");

  String get labelMediaPreviewPublicRoomsToggle => Intl.message(
        "Public Rooms",
        desc:
            "Short label for the private rooms toggle in media previews section",
        name: "labelMediaPreviewPublicRoomsToggle",
      );

  String get labelMediaPreviewPublicRoomsToggleDescription => Intl.message(
      "Toggle previewing of images, videos, stickers and urls in public chat rooms",
      desc: "Label describing toggle of media previews for public rooms",
      name: "labelMediaPreviewPublicRoomsToggleDescription");

  // Vommet: Autoplay GIFs.
  String get labelAutoplayGifsToggle => Intl.message("Autoplay GIFs",
      desc: "Title of the toggle that plays GIFs by themselves in the timeline",
      name: "labelAutoplayGifsToggle");

  String get labelAutoplayGifsToggleDescription => Intl.message(
      "Play GIFs, including GIFs bridged from Telegram, WhatsApp and Discord, by themselves. When off, tap a GIF to play it",
      desc: "Description of the toggle that plays GIFs by themselves",
      name: "labelAutoplayGifsToggleDescription");

  String get labelRehideMediaSpoilersToggle => Intl.message(
      "Hide spoilers again",
      desc:
          "Title of the toggle that blurs revealed spoiler pictures and videos again after leaving the room",
      name: "labelRehideMediaSpoilersToggle");

  String get labelRehideMediaSpoilersToggleDescription => Intl.message(
      "Blur spoiler pictures and videos again when you switch to another room, like Telegram. When off, they stay revealed until you restart Vommet",
      desc:
          "Description of the toggle that blurs revealed spoiler pictures and videos again after leaving the room",
      name: "labelRehideMediaSpoilersToggleDescription");

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Vommet: app language.
        const LanguageSettingsPanel(),
        const SizedBox(
          height: 10,
        ),
        // Vommet: the first-run onboarding pages again (Vommet issue 524).
        const OnboardingRerunPanel(),
        const SizedBox(
          height: 10,
        ),
        Panel(
          header: labelThirdPartyServicesTitle,
          mode: TileType.surfaceContainerLow,
          child: Column(children: [
            BooleanPreferenceToggle(
              preference: preferences.tenorGifSearchEnabled,
              title: labelGifSearchToggle,
              description: labelGifSearchDescriptionGeneric(
                  preferences.proxyUrl.value, "KLIPY"),
            ),
            const SizedBox(
              height: 10,
            ),
            BooleanPreferenceToggle(
              preference: preferences.urlPreviewInE2EEChat,
              title: labelUrlPreviewInEncryptedChatTitle,
              description: labelUrlPreviewInEncryptedChatDescription,
            ),
            // Vommet: the new-version bar.
            ReleaseUpdatesSetting(
              title: labelReleaseNoticeTitle,
              description: labelReleaseNoticeDescription,
            ),
            if (UpdateChecker.shouldCheckForUpdates)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: CheckForUpdatesSettingWidget(),
              ),
          ]),
        ),
        const SizedBox(
          height: 10,
        ),
        Panel(
          header: labelAppBehaviourTitle,
          mode: TileType.surfaceContainerLow,
          child: Column(children: [
            BooleanPreferenceToggle(
              preference: preferences.askBeforeDeletingMessageEnabled,
              title: labelAskBeforeDeletingMessageToggle,
              description: labelAskBeforeDeletingMessageDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.autoFocusMessageTextBox,
              title: "Autofocus Message Input",
              description:
                  "Automatically focus on the message input text field when opening a chat",
            ),
            BooleanPreferenceToggle(
              preference: preferences.selectAutoCompleteSuggestion,
              title: "Select first auto-complete suggestion",
              description:
                  "When typing a message, if there are any auto-complete suggestions, the first one will be highlighted by default",
            ),
            BooleanPreferenceToggle(
              preference: preferences.linkBareDomains,
              title: labelLinkBareDomainsToggle,
              description: labelLinkBareDomainsToggleDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.automaticallyOpenSpace,
              title: "Always open space",
              description:
                  "When navigating to a room from outside of a space, also open the space the room is in, if any",
            ),
            BooleanPreferenceToggle(
              preference: preferences.openRoomsAtLastReadMessage,
              title: "Open at last read message",
              description:
                  "When opening a room, jump to the last message you read",
            ),
            // Vommet
            BooleanPreferenceToggle(
              preference: preferences.relativeDateDividers,
              title: labelRelativeDateDividersTitle,
              description: labelRelativeDateDividersDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.pauseAnimationsWhenNotFocused,
              title: "Pause animations when unfocused",
              description:
                  "When the app is in the background, pause animations to reduce CPU usage",
            )
          ]),
        ),
        const SizedBox(
          height: 10,
        ),
        Panel(
          header: labelMessageEffectsTitle,
          mode: TileType.surfaceContainerLow,
          child: BooleanPreferenceToggle(
            preference: preferences.messageEffectsEnabled,
            title: labelMessageEffectsTitle,
            description: labelMessageEffectsDescription,
          ),
        ),
        // Vommet: where widgets open (Linux).
        if (PlatformUtils.isLinux) ...[
          const SizedBox(
            height: 10,
          ),
          const WidgetSettingsPanel(),
        ],
        const SizedBox(
          height: 10,
        ),
        Panel(
          header: labelMediaSettings,
          mode: TileType.surfaceContainerLow,
          child: Column(children: [
            BooleanPreferenceToggle(
              preference: preferences.previewMediaInPrivateRooms,
              title: labelMediaPreviewPrivateRoomsToggle,
              description: labelMediaPreviewPrivateRoomsToggleDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.previewMediaInPublicRooms,
              title: labelMediaPreviewPublicRoomsToggle,
              description: labelMediaPreviewPublicRoomsToggleDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.autoplayGifs,
              title: labelAutoplayGifsToggle,
              description: labelAutoplayGifsToggleDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.rehideMediaSpoilers,
              title: labelRehideMediaSpoilersToggle,
              description: labelRehideMediaSpoilersToggleDescription,
            ),
            if (MediaQuery.of(context).mobile) ...[
              Seperator(),
              BooleanPreferenceToggle(
                preference: preferences.autoRotateImages,
                title: "Rotate Images",
                description:
                    "When showing images in fullscreen, automatically rotate the image to best fill the screen",
              ),
              BooleanPreferenceToggle(
                preference: preferences.autoRotateVideos,
                title: "Rotate Videos",
                description:
                    "When showing videos in fullscreen, automatically rotate the video to best fill the screen",
              ),
            ],
            Seperator(),
            StringListPreferenceEditor(
              preference: preferences.allowedRemoteVideoHosts,
              title: "Allowed Video Hosts",
              description:
                  "Allowed web hosts for displaying external videos, such as in URL Previews. Your IP address will be revealed to these servers when accessing the video",
            )
          ]),
        ),
        // Vommet: voice message transcription (#70)
        if (VoiceTranscription.supported) ...[
          const SizedBox(height: 10),
          const VoiceTranscriptionSettings(),
        ],
        // Vommet: message box spellcheck (desktop)
        if (Spellcheck.supported) ...[
          const SizedBox(height: 10),
          const SpellcheckSettingsPanel(),
        ],
      ],
    );
  }
}

String get labelRelativeDateDividersTitle => Intl.message(
    "Relative dates in the chat",
    name: "labelRelativeDateDividersTitle",
    desc: "Title of the setting for relative date dividers in the timeline");

String get labelRelativeDateDividersDescription => Intl.message(
    "The line between messages after a gap says \"Today,\" \"Yesterday,\" or the weekday. Off: always the date, e.g. Thu, Oct 9.",
    name: "labelRelativeDateDividersDescription",
    desc:
        "Description of the relative date dividers setting; the example date format may be localized");
