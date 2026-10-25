import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/categories/app/boolean_preference_toggle.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/ui/pages/setup/onboarding/layout_preview.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' show Panel, TileType;

/// Vommet: Settings › Appearance › Layout. Discord style, Telegram style or
/// your own mix of the options under them.
class LayoutSettings extends StatefulWidget {
  const LayoutSettings({super.key});

  @override
  State<LayoutSettings> createState() => _LayoutSettingsState();
}

class _LayoutSettingsState extends State<LayoutSettings> {
  /// Bumped when a style sets every option, so the controls show the new
  /// values.
  int generation = 0;

  Future<void> pick(LayoutStyle style) async {
    await pickLayoutStyle(style);
    if (mounted) setState(() => generation++);
  }

  /// Changing one option yourself makes the layout Custom.
  Future<void> changed(Future<void> Function() save) async {
    await save();
    await layoutStyleCustomPicked.set(true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = currentLayoutStyle;
    final bubbles = preferences.chatBubbleLayout.value;
    final oneList = experimentUnifiedChatList.value;
    return SettingsSearchTarget(
      ids: [layoutSettingsTitle, layoutStyleCustomPicked.key],
      child: Panel(
        header: layoutSettingsTitle,
        mode: TileType.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              ChoiceCards<LayoutStyle>(
                selected: style,
                onSelected: pick,
                options: [
                  ChoiceCardOption(
                    value: LayoutStyle.discord,
                    title: layoutStyleDiscord,
                    description: layoutStyleDiscordDescription,
                    preview: const LayoutPreview(unified: false),
                  ),
                  ChoiceCardOption(
                    value: LayoutStyle.telegram,
                    title: layoutStyleTelegram,
                    description: layoutStyleTelegramDescription,
                    preview: const LayoutPreview(unified: true, bubbles: true),
                  ),
                  ChoiceCardOption(
                    value: LayoutStyle.custom,
                    title: layoutStyleCustom,
                    description: layoutStyleCustomDescription,
                    icon: Icons.tune,
                  ),
                ],
              ),
              tiamat.Text.labelLow(
                style == LayoutStyle.custom
                    ? layoutSettingsCustomHelp
                    : layoutSettingsHelp,
              ),
              _section(layoutSectionChatList),
              _Choice<bool>(
                key: ValueKey("layout-chats-$generation"),
                searchId: experimentUnifiedChatList.key,
                title: layoutChats,
                description:
                    oneList ? layoutChatsOneListHelp : layoutChatsSpacesHelp,
                values: [
                  (false, layoutChatsSpaces),
                  (true, layoutChatsOneList),
                ],
                selected: oneList,
                onSelected: (v) => changed(() async {
                  await experimentUnifiedChatList.set(v);
                  onUnifiedChatListToggled(v);
                }),
              ),
              _section(layoutSectionMessages),
              _Choice<bool>(
                key: ValueKey("layout-captions-$generation"),
                searchId: captionBelowMedia.key,
                title: layoutCaptions,
                description: layoutCaptionsDescription,
                values: [
                  (false, layoutCaptionsAbove),
                  (true, layoutCaptionsBelow),
                ],
                selected: captionBelowMedia.value,
                onSelected: (v) => changed(() => captionBelowMedia.set(v)),
              ),
              _toggle(
                limitMessageWidth,
                layoutLimitWidth,
                layoutLimitWidthDescription,
              ),
              _toggle(
                preferences.chatBubbleLayout,
                layoutBubbles,
                layoutBubblesDescription,
              ),
              _Choice<bool>(
                key: ValueKey("layout-own-side-$generation-$bubbles"),
                searchId: ownBubbleSide.key,
                title: layoutOwnRight,
                description:
                    bubbles ? layoutOwnRightDescription : layoutNeedsBubbles,
                enabled: bubbles,
                values: [
                  (false, layoutOwnRightWhenNarrow),
                  (true, layoutOwnRightAlways),
                ],
                selected: OwnBubbleSide.current == OwnBubbleSide.right,
                onSelected: (v) => changed(
                  () => ownBubbleSide.set(
                    (v ? OwnBubbleSide.right : OwnBubbleSide.rightWhenNarrow)
                        .name,
                  ),
                ),
              ),
              _Choice<bool>(
                key: ValueKey("layout-avatar-$generation"),
                searchId: avatarAtBottomOfGroup.key,
                title: layoutAvatar,
                description: layoutAvatarDescription,
                values: [(false, layoutAvatarTop), (true, layoutAvatarBottom)],
                selected: avatarAtBottomOfGroup.value,
                onSelected: (v) => changed(() => avatarAtBottomOfGroup.set(v)),
              ),
              // Vommet: was the "Discord-style layout" experiment (10-25).
              // Not part of a style, so changing it doesn't make the layout
              // Custom.
              _section(layoutSectionRooms),
              BooleanPreferenceToggle(
                preference: preferences.experimentBannerLayout,
                title: layoutBannerLayout,
                description: layoutBannerLayoutDescription,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: tiamat.Text.labelEmphasised(title),
      );

  Widget _toggle(BoolPreference preference, String title, String description) =>
      SettingsSearchTarget(
        ids: [preference.key, title],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.labelEmphasised(title),
                    tiamat.Text.labelLow(description),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                child: tiamat.Switch(
                  key: ValueKey("layout-${preference.key}-$generation"),
                  state: preference.value,
                  onChanged: (v) => changed(() => preference.set(v)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// A titled row with a segmented button, wrapping under the text when narrow.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.searchId,
    required this.title,
    required this.description,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String searchId;
  final String title;
  final String description;
  final List<(T, String)> values;
  final T selected;
  final void Function(T value) onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsSearchTarget(
      ids: [searchId, title],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(title),
                  tiamat.Text.labelLow(description),
                ],
              ),
            ),
            SegmentedButton<T>(
              showSelectedIcon: false,
              style: selectedSegmentStyle(Theme.of(context).colorScheme),
              segments: [
                for (final (value, label) in values)
                  ButtonSegment(
                    value: value,
                    label: Text(label),
                    enabled: enabled,
                  ),
              ],
              selected: {selected},
              onSelectionChanged: enabled
                  ? (v) {
                      if (v.first != selected) onSelected(v.first);
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

String get layoutSettingsTitle => Intl.message(
      "Layout",
      name: "layoutSettingsTitle",
      desc: "Header of the layout section in Settings › Appearance",
    );

String get layoutStyleDiscord => Intl.message(
      "Discord style",
      name: "layoutStyleDiscord",
      desc: "Layout style with spaces down the side and flat messages",
    );

String get layoutStyleDiscordDescription => Intl.message(
      "Spaces down the side, a room list and flat messages",
      name: "layoutStyleDiscordDescription",
      desc: "Description of the Discord style layout",
    );

String get layoutStyleTelegram => Intl.message(
      "Telegram style",
      name: "layoutStyleTelegram",
      desc: "Layout style with one chat list and message bubbles",
    );

String get layoutStyleTelegramDescription => Intl.message(
      "One chat list and message bubbles, yours on the right",
      name: "layoutStyleTelegramDescription",
      desc: "Description of the Telegram style layout",
    );

String get layoutStyleCustom => Intl.message(
      "Custom",
      name: "layoutStyleCustom",
      desc: "Layout style made from the user's own choice of options",
    );

String get layoutStyleCustomDescription => Intl.message(
      "Your own mix of the options below",
      name: "layoutStyleCustomDescription",
      desc: "Description of the custom layout style",
    );

String get layoutSettingsHelp => Intl.message(
      "A style sets how the whole app looks: the chat list and the messages. Change any option below to make your own mix.",
      name: "layoutSettingsHelp",
      desc: "Explains the layout styles in Settings › Appearance",
    );

String get layoutSettingsCustomHelp => Intl.message(
      "You changed an option, so this is now your own layout. Pick a style above to reset everything to it.",
      name: "layoutSettingsCustomHelp",
      desc: "Shown under the layout styles while Custom is picked",
    );

String get layoutSectionChatList => Intl.message(
      "Chat list",
      name: "layoutSectionChatList",
      desc: "Heading of the chat list options in the layout settings",
    );

String get layoutSectionMessages => Intl.message(
      "Messages",
      name: "layoutSectionMessages",
      desc: "Heading of the message options in the layout settings",
    );

String get layoutChats => Intl.message(
      "Chats",
      name: "layoutChats",
      desc: "Layout option: how the chat list is arranged",
    );

String get layoutChatsSpaces => Intl.message(
      "Spaces and Home",
      name: "layoutChatsSpaces",
      desc: "Chat list option: the space sidebar with Home",
    );

String get layoutChatsOneList => Intl.message(
      "One list",
      name: "layoutChatsOneList",
      desc: "Chat list option: one unified list of every chat",
    );

String get layoutChatsSpacesHelp => Intl.message(
      "Spaces down the side, with Home for DMs and standalone rooms",
      name: "layoutChatsSpacesHelp",
      desc: "Description of the Spaces and Home chat list option",
    );

String get layoutChatsOneListHelp => Intl.message(
      "One list of DMs, rooms and spaces, newest first, pinned chats on top",
      name: "layoutChatsOneListHelp",
      desc: "Description of the One list chat list option",
    );

String get layoutCaptions => Intl.message(
      "Captions",
      name: "layoutCaptions",
      desc: "Layout option: where the text sent with an image goes",
    );

String get layoutCaptionsDescription => Intl.message(
      "Where the text sent with an image or video goes",
      name: "layoutCaptionsDescription",
      desc: "Description of the captions layout option",
    );

String get layoutCaptionsAbove => Intl.message(
      "Above image",
      name: "layoutCaptionsAbove",
      desc: "Captions option: text above the image",
    );

String get layoutCaptionsBelow => Intl.message(
      "Under image",
      name: "layoutCaptionsBelow",
      desc: "Captions option: text under the image",
    );

String get layoutLimitWidth => Intl.message(
      "Limit message width",
      name: "layoutLimitWidth",
      desc: "Layout option: messages wrap at a reading width",
    );

String get layoutLimitWidthDescription => Intl.message(
      "Long messages wrap at a comfortable reading width instead of filling the window",
      name: "layoutLimitWidthDescription",
      desc: "Description of the limit message width option",
    );

String get layoutBubbles => Intl.message(
      "Message bubbles",
      name: "layoutBubbles",
      desc: "Layout option: draw a bubble around each message",
    );

String get layoutBubblesDescription => Intl.message(
      "Draw a rounded box around each message",
      name: "layoutBubblesDescription",
      desc: "Description of the message bubbles option",
    );

String get layoutOwnRight => Intl.message(
      "Your messages",
      name: "layoutOwnRight",
      desc: "Layout option: which side your own bubbles sit on",
    );

String get layoutOwnRightDescription => Intl.message(
      "On the right, or on the right only in narrow windows so wide windows keep every message on the left",
      name: "layoutOwnRightDescription",
      desc: "Description of the your messages layout option",
    );

String get layoutOwnRightWhenNarrow => Intl.message(
      "Right when narrow",
      name: "layoutOwnRightWhenNarrow",
      desc: "Your messages option: on the right only in narrow windows",
    );

String get layoutOwnRightAlways => Intl.message(
      "Always right",
      name: "layoutOwnRightAlways",
      desc: "Your messages option: always on the right",
    );

String get layoutNeedsBubbles => Intl.message(
      "Needs message bubbles",
      name: "layoutNeedsBubbles",
      desc: "Shown on layout options that only work with message bubbles",
    );

String get layoutAvatar => Intl.message(
      "Avatar",
      name: "layoutAvatar",
      desc: "Layout option: where the sender's picture sits in a run",
    );

String get layoutAvatarDescription => Intl.message(
      "Where the sender's picture sits in a run of messages",
      name: "layoutAvatarDescription",
      desc: "Description of the avatar layout option",
    );

String get layoutAvatarTop => Intl.message(
      "Top of group",
      name: "layoutAvatarTop",
      desc: "Avatar option: beside the first message",
    );

String get layoutAvatarBottom => Intl.message(
      "Bottom of group",
      name: "layoutAvatarBottom",
      desc: "Avatar option: beside the last message",
    );

String get layoutSectionRooms => Intl.message(
      "Rooms",
      name: "layoutSectionRooms",
      desc:
          "Heading of the room options (banners, member list, panes) in the layout settings",
    );

String get layoutBannerLayout => Intl.message(
      "Discord-style layout",
      name: "layoutBannerLayout",
      desc:
          "Layout setting: collapsing banners, online and offline member sections, resizable panes",
    );

String get layoutBannerLayoutDescription => Intl.message(
      "Banners shrink to their name bar as you scroll, the member list is split into Online and Offline, and you can drag the room list and member list edges to resize them (double-click an edge to reset). Takes effect when you next open a room.",
      name: "layoutBannerLayoutDescription",
      desc: "Description of the Discord-style layout setting",
    );
