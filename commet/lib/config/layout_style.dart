// Vommet: Settings › Appearance › Layout. Discord style and Telegram style
// each set a group of options at once (the chat list and how messages look);
// changing any option yourself makes the layout Custom. The options live
// here, beside the styles, so this change doesn't touch preferences.dart.
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_preference.dart';

enum LayoutStyle { discord, telegram, custom }

/// Where your own bubbles sit.
enum OwnBubbleSide {
  left,
  right,

  /// On the right, but on the left in wide windows (Vommet issue 507).
  rightWhenNarrow;

  static OwnBubbleSide get current => values.firstWhere(
        (s) => s.name == ownBubbleSide.value,
        orElse: () => rightWhenNarrow,
      );
}

/// The text sent with a picture or video goes under it instead of above.
final BoolPreference captionBelowMedia = BoolPreference(
  "vommet_caption_below_media",
  defaultValue: false,
);

/// Messages wrap at [LayoutOptions.maxMessageWidth] instead of filling the
/// timeline.
final BoolPreference limitMessageWidth = BoolPreference(
  "vommet_limit_message_width",
  defaultValue: false,
);

/// An [OwnBubbleSide] name.
final StringPreference ownBubbleSide = StringPreference(
  "vommet_own_bubble_side",
  defaultValue: OwnBubbleSide.rightWhenNarrow.name,
);

/// The sender's picture sits beside the last message of a run instead of
/// the first.
final BoolPreference avatarAtBottomOfGroup = BoolPreference(
  "vommet_avatar_bottom_of_group",
  defaultValue: false,
);

/// Set when Custom was picked by hand, so it stays picked even while the
/// options happen to match a style.
final BoolPreference layoutStyleCustomPicked = BoolPreference(
  "vommet_layout_style_custom",
  defaultValue: false,
);

/// One full set of layout options.
class LayoutOptions {
  const LayoutOptions({
    required this.oneChatList,
    required this.captionBelow,
    required this.limitWidth,
    required this.bubbles,
    required this.ownSide,
    required this.avatarAtBottom,
  });

  /// The widest a message gets while [limitWidth] is on.
  static const double maxMessageWidth = 640;

  final bool oneChatList;
  final bool captionBelow;
  final bool limitWidth;
  final bool bubbles;
  final OwnBubbleSide ownSide;
  final bool avatarAtBottom;

  static const discord = LayoutOptions(
    oneChatList: false,
    captionBelow: false,
    limitWidth: false,
    bubbles: false,
    ownSide: OwnBubbleSide.rightWhenNarrow,
    avatarAtBottom: false,
  );

  static const telegram = LayoutOptions(
    oneChatList: true,
    captionBelow: true,
    limitWidth: true,
    bubbles: true,
    ownSide: OwnBubbleSide.right,
    avatarAtBottom: true,
  );

  static LayoutOptions get current => LayoutOptions(
        oneChatList: experimentUnifiedChatList.value,
        captionBelow: captionBelowMedia.value,
        limitWidth: limitMessageWidth.value,
        bubbles: preferences.chatBubbleLayout.value,
        ownSide: OwnBubbleSide.current,
        avatarAtBottom: avatarAtBottomOfGroup.value,
      );

  /// The same layout on screen: which side your bubbles take only matters
  /// with bubbles on.
  bool looksLike(LayoutOptions o) =>
      oneChatList == o.oneChatList &&
      captionBelow == o.captionBelow &&
      limitWidth == o.limitWidth &&
      bubbles == o.bubbles &&
      (!bubbles || ownSide == o.ownSide) &&
      avatarAtBottom == o.avatarAtBottom;

  /// The style these options make, ignoring a hand-picked Custom.
  LayoutStyle get style {
    if (looksLike(discord)) return LayoutStyle.discord;
    if (looksLike(telegram)) return LayoutStyle.telegram;
    return LayoutStyle.custom;
  }

  Future<void> save() async {
    await experimentUnifiedChatList.set(oneChatList);
    await captionBelowMedia.set(captionBelow);
    await limitMessageWidth.set(limitWidth);
    await preferences.chatBubbleLayout.set(bubbles);
    await ownBubbleSide.set(ownSide.name);
    await avatarAtBottomOfGroup.set(avatarAtBottom);
  }
}

/// The style shown as picked on the Layout settings.
LayoutStyle get currentLayoutStyle => layoutStyleCustomPicked.value
    ? LayoutStyle.custom
    : LayoutOptions.current.style;

/// Picks [style]: Discord and Telegram set every option, Custom keeps them.
Future<void> pickLayoutStyle(LayoutStyle style) async {
  final before = experimentUnifiedChatList.value;
  switch (style) {
    case LayoutStyle.discord:
      await LayoutOptions.discord.save();
    case LayoutStyle.telegram:
      await LayoutOptions.telegram.save();
    case LayoutStyle.custom:
      break;
  }
  await layoutStyleCustomPicked.set(style == LayoutStyle.custom);
  if (experimentUnifiedChatList.value != before) {
    onUnifiedChatListToggled(experimentUnifiedChatList.value);
  }
}
