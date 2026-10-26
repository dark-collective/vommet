import 'package:commet/ui/atoms/selected_segment_style.dart';
import 'package:commet/config/layout_style.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/room_layout_options.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';
import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/setup/onboarding/choice_cards.dart';
import 'package:commet/ui/pages/setup/onboarding/layout_preview.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:tiamat/tiamat.dart' show Panel, TileType;

/// Vommet: Settings › Appearance › Layout. Discord style, Telegram style or
/// your own mix of the options under them. The options sit under a
/// Customize expander, so picking a style is one tap; it opens by itself
/// while Custom is picked.
class LayoutSettings extends StatefulWidget {
  const LayoutSettings({super.key});

  @override
  State<LayoutSettings> createState() => _LayoutSettingsState();
}

class _LayoutSettingsState extends State<LayoutSettings> {
  /// Bumped when a style sets every option, so the controls show the new
  /// values.
  int generation = 0;

  /// Whether the Customize options are showing.
  late bool customizeOpen = currentLayoutStyle == LayoutStyle.custom;

  Future<void> pick(LayoutStyle style) async {
    await pickLayoutStyle(style);
    if (mounted) {
      setState(() {
        generation++;
        if (style == LayoutStyle.custom) customizeOpen = true;
      });
    }
  }

  /// A Rooms and spaces option: not part of a style, so the layout stays as
  /// it is.
  Future<void> set(Future<void> Function() save) async {
    await save();
    if (mounted) setState(() {});
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
                    badge: layoutStyleBeta,
                  ),
                  ChoiceCardOption(
                    value: LayoutStyle.custom,
                    title: layoutStyleCustom,
                    description: layoutStyleCustomDescription,
                    preview: const LayoutPreview.custom(),
                  ),
                ],
              ),
              tiamat.Text.labelLow(
                style == LayoutStyle.custom
                    ? layoutSettingsCustomHelp
                    : layoutSettingsHelp,
              ),
              _CustomizeHeader(
                open: customizeOpen,
                onTap: () => setState(() => customizeOpen = !customizeOpen),
              ),
              if (customizeOpen) ..._options(bubbles, oneList),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _options(bool bubbles, bool oneList) => [
        _section(layoutSectionChatList),
        _Choice<bool>(
          key: ValueKey("layout-chats-$generation"),
          searchId: experimentUnifiedChatList.key,
          title: layoutChats,
          description: oneList ? layoutChatsOneListHelp : layoutChatsSpacesHelp,
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
          description: bubbles ? layoutOwnRightDescription : layoutNeedsBubbles,
          enabled: bubbles,
          values: [
            (false, layoutOwnRightWhenNarrow),
            (true, layoutOwnRightAlways),
          ],
          selected: OwnBubbleSide.current == OwnBubbleSide.right,
          onSelected: (v) => changed(
            () => ownBubbleSide.set(
              (v ? OwnBubbleSide.right : OwnBubbleSide.rightWhenNarrow).name,
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
        // Vommet: was the one "Discord-style layout" switch (10-25).
        // Not part of a style: picking a style leaves these alone and
        // changing one doesn't make the layout Custom.
        _section(layoutSectionRoomsAndSpaces,
            help: layoutSectionRoomsAndSpacesHelp),
        _toggle(
          shrinkBannersOnScroll,
          layoutShrinkBanners,
          layoutShrinkBannersDescription,
          makesCustom: false,
        ),
        _Choice<bool>(
          key: ValueKey("layout-${memberListOnlineSections.key}-$generation"),
          searchId: memberListOnlineSections.key,
          title: layoutMemberList,
          description: layoutMemberListDescription,
          values: [
            (true, layoutMemberListOnline),
            (false, layoutMemberListByRole),
          ],
          selected: memberListOnlineSections.value,
          onSelected: (v) => set(() => memberListOnlineSections.set(v)),
        ),
        _toggle(
          memberListCallActivity,
          layoutCallActivity,
          layoutCallActivityDescription,
          makesCustom: false,
        ),
        _toggle(
          memberPanelTabs,
          layoutMemberPanelTabs,
          layoutMemberPanelTabsDescription,
          makesCustom: false,
        ),
        _toggle(
          resizablePanels,
          layoutResizePanels,
          layoutResizePanelsDescription,
          makesCustom: false,
        ),
        _Choice<bool>(
          key: ValueKey("layout-${spaceHomeLikeRoomList.key}-$generation"),
          searchId: spaceHomeLikeRoomList.key,
          title: layoutSpaceHome,
          description: layoutSpaceHomeDescription,
          values: [
            (true, layoutSpaceHomeRoomList),
            (false, layoutSpaceHomeCards),
          ],
          selected: spaceHomeLikeRoomList.value,
          onSelected: (v) => set(() => spaceHomeLikeRoomList.set(v)),
        ),
        _toggle(
          homeBadgeCountsDms,
          layoutHomeBadgeDms,
          layoutHomeBadgeDmsDescription,
          makesCustom: false,
        ),
      ];

  Widget _section(String title, {String? help}) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.labelEmphasised(title),
            if (help != null) tiamat.Text.labelLow(help),
          ],
        ),
      );

  Widget _toggle(BoolPreference preference, String title, String description,
          {bool makesCustom = true}) =>
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
                  onChanged: (v) => makesCustom
                      ? changed(() => preference.set(v))
                      : set(() => preference.set(v)),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The row that shows or hides the layout options.
class _CustomizeHeader extends StatelessWidget {
  const _CustomizeHeader({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      expanded: open,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          key: const ValueKey("layout-customize"),
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              spacing: 10,
              children: [
                Icon(Icons.tune, size: 20, color: scheme.onSurfaceVariant),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(layoutCustomize),
                      tiamat.Text.labelLow(layoutCustomizeDescription),
                    ],
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
      "A style sets the chat list and how messages look. Change any of them under Customize to make your own mix.",
      name: "layoutSettingsHelp",
      desc: "Explains the layout styles in Settings › Appearance",
    );

String get layoutSettingsCustomHelp => Intl.message(
      "You changed an option, so this is now your own layout. Pick a style above to reset the chat list and messages to it.",
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

String get layoutStyleBeta => Intl.message(
      "Beta",
      name: "layoutStyleBeta",
      desc: "Small tag on the Telegram style card: still being worked on",
    );

String get layoutCustomize => Intl.message(
      "Customize",
      name: "layoutCustomize",
      desc:
          "Layout settings: the expander that shows the single layout options",
    );

String get layoutCustomizeDescription => Intl.message(
      "Chat list, messages, rooms and spaces",
      name: "layoutCustomizeDescription",
      desc: "Under Customize in the layout settings: what it holds",
    );

String get layoutSectionRoomsAndSpaces => Intl.message(
      "Rooms and spaces",
      name: "layoutSectionRoomsAndSpaces",
      desc:
          "Heading of the room and space options (banners, member list, panels) in the layout settings",
    );

String get layoutSectionRoomsAndSpacesHelp => Intl.message(
      "These stay as you set them, whichever style you pick above.",
      name: "layoutSectionRoomsAndSpacesHelp",
      desc:
          "Under the Rooms and spaces heading: picking a layout style doesn't change these options",
    );

String get layoutShrinkBanners => Intl.message(
      "Shrink banners as you scroll",
      name: "layoutShrinkBanners",
      desc: "Layout setting: room and space banners collapse when scrolling",
    );

String get layoutShrinkBannersDescription => Intl.message(
      "A room or space banner folds into its name bar when you scroll down",
      name: "layoutShrinkBannersDescription",
      desc: "Description of the Shrink banners as you scroll setting",
    );

String get layoutMemberList => Intl.message(
      "Member list",
      name: "layoutMemberList",
      desc: "Layout setting: how the member list groups people",
    );

String get layoutMemberListDescription => Intl.message(
      "Group people by whether they're online, or only by role",
      name: "layoutMemberListDescription",
      desc: "Description of the Member list setting",
    );

String get layoutMemberListOnline => Intl.message(
      "Online · Offline",
      name: "layoutMemberListOnline",
      desc: "Member list option: Online and Offline sections",
    );

String get layoutMemberListByRole => Intl.message(
      "By role",
      name: "layoutMemberListByRole",
      desc: "Member list option: sections by role only",
    );

String get layoutCallActivity => Intl.message(
      "Show who's in the call",
      name: "layoutCallActivity",
      desc:
          "Layout setting: In voice and Sharing their screen under names in the member list",
    );

String get layoutCallActivityDescription => Intl.message(
      "“In voice” and “Sharing their screen” under names in the member list",
      name: "layoutCallActivityDescription",
      desc: "Description of the Show who's in the call setting",
    );

String get layoutMemberPanelTabs => Intl.message(
      "Member panel tabs",
      name: "layoutMemberPanelTabs",
      desc:
          "Layout setting: tabs in the member panel and a slimmer room header",
    );

String get layoutMemberPanelTabsDescription => Intl.message(
      "Members, Media, Files, Pins… as tabs; the header keeps Invite, Call, Search",
      name: "layoutMemberPanelTabsDescription",
      desc: "Description of the Member panel tabs setting",
    );

String get layoutResizePanels => Intl.message(
      "Resize panels",
      name: "layoutResizePanels",
      desc: "Layout setting: drag the room list and member list edges",
    );

String get layoutResizePanelsDescription => Intl.message(
      "Drag the room list or member list edge; double-click an edge to reset it",
      name: "layoutResizePanelsDescription",
      desc: "Description of the Resize panels setting",
    );

String get layoutSpaceHome => Intl.message(
      "Space home page",
      name: "layoutSpaceHome",
      desc: "Layout setting: how a space's home page lists its rooms",
    );

String get layoutSpaceHomeDescription => Intl.message(
      "How a space lists its rooms on its home page",
      name: "layoutSpaceHomeDescription",
      desc: "Description of the Space home page setting",
    );

String get layoutSpaceHomeRoomList => Intl.message(
      "Like the room list",
      name: "layoutSpaceHomeRoomList",
      desc: "Space home page option: rooms listed like the room list",
    );

String get layoutSpaceHomeCards => Intl.message(
      "Cards",
      name: "layoutSpaceHomeCards",
      desc: "Space home page option: a card per room",
    );

String get layoutHomeBadgeDms => Intl.message(
      "Unread DMs on the Home button",
      name: "layoutHomeBadgeDms",
      desc: "Layout setting: the Home button badge counts unread DMs",
    );

String get layoutHomeBadgeDmsDescription => Intl.message(
      "The Home button badge also counts unread direct messages",
      name: "layoutHomeBadgeDmsDescription",
      desc: "Description of the Unread DMs on the Home button setting",
    );
