import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter/material.dart' as material;

import 'emoji_widget.dart';

class EmojiReaction extends StatelessWidget {
  const EmojiReaction(
      {required this.emoji,
      required this.numReactions,
      this.highlighted = false,
      this.onTapped,
      this.onLongPressed,
      this.onSecondaryTapped,
      this.tooltip,
      super.key});

  /// Who reacted, shown when the pointer hovers the reaction.
  final String? tooltip;

  /// Right click; falls back to [onLongPressed].
  final Function(Emoticon emote)? onSecondaryTapped;

  static String get reactorYou => Intl.message("You",
      desc: "Stands for the current user in the list of who reacted",
      name: "reactorYou");

  static String reactorsTwo(String user1, String user2) =>
      Intl.message("$user1 and $user2",
          desc: "Two people who reacted with the same emoji",
          name: "reactorsTwo",
          args: [user1, user2]);

  static String reactorsThree(String user1, String user2, String user3) =>
      Intl.message("$user1, $user2, and $user3",
          desc: "Three people who reacted with the same emoji",
          name: "reactorsThree",
          args: [user1, user2, user3]);

  static String reactorsMore(
          String user1, String user2, String user3, int others) =>
      Intl.plural(others,
          one: "$user1, $user2, $user3, and $others other",
          other: "$user1, $user2, $user3, and $others others",
          desc: "Three named people and a count of others who reacted",
          name: "reactorsMore",
          args: [user1, user2, user3, others]);

  static String reactedWith(String who, String emoji) =>
      Intl.message("$who reacted with $emoji",
          desc: "Tooltip on a reaction: who reacted, and with which emoji",
          name: "reactedWith",
          args: [who, emoji]);

  static String reactedPlain(String who) => Intl.message("$who reacted",
      desc: "Tooltip on a reaction whose emoji has no name to show",
      name: "reactedPlain",
      args: [who]);

  /// "Alice, Bob and 3 others": [names] are the first (up to three) people
  /// who reacted, [total] is how many reacted. Empty when nobody did.
  static String summarizeReactors(List<String> names, int total) {
    if (names.length < total && names.length < 3) total = names.length;
    if (total <= 0) return "";
    if (total == 1) return names[0];
    if (total == 2) return reactorsTwo(names[0], names[1]);
    if (total == 3) return reactorsThree(names[0], names[1], names[2]);
    return reactorsMore(names[0], names[1], names[2], total - 3);
  }

  final Function(Emoticon emote)? onTapped;
  final Function(Emoticon emote)? onLongPressed;
  final Emoticon emoji;
  final int numReactions;
  final bool highlighted;

  BorderRadius get borderRadius => BorderRadius.circular(8);

  @override
  Widget build(BuildContext context) {
    var bgColor = material.Theme.of(context).colorScheme.primary;

    if (!highlighted) {
      bgColor = material.Theme.of(context).colorScheme.surfaceContainerLow;
    }

    Widget result = material.InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () => onTapped?.call(emoji),
      onLongPress: () => onLongPressed?.call(emoji),
      onSecondaryTap: onSecondaryTapped != null || onLongPressed != null
          ? () => (onSecondaryTapped ?? onLongPressed)?.call(emoji)
          : null,
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: bgColor.withAlpha(70),
            border: Border.all(color: bgColor, width: 1),
            borderRadius: borderRadius),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmojiWidget(
                emoji,
                height: 17,
              ),
              const SizedBox(
                width: 5,
              ),
              tiamat.Text.label(numReactions.toString()),
              const SizedBox(
                width: 3,
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      result = tiamat.Tooltip(text: tooltip!, child: result);
    }

    return result;
  }
}
