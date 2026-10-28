import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:commet/ui/atoms/emoji_reaction.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/utils/redaction/redaction_policy.dart';
import 'package:flutter/material.dart';

import 'package:flutter/material.dart' as material;

class TimelineEventViewReactions extends StatefulWidget {
  const TimelineEventViewReactions(
      {required this.initialIndex, required this.timeline, super.key});

  final int initialIndex;
  final Timeline timeline;

  /// "You, Alice and 2 others reacted with :fire:". Only the names that are
  /// spelled out get looked up, so a reaction from hundreds stays cheap.
  static String reactorsTooltip(
      Timeline timeline, Emoticon emote, Set<String> userIds,
      {RedactionPolicy? redaction}) {
    final room = timeline.room;
    final currentUserIdentifier = timeline.client.self?.identifier;
    final ordered = [
      if (userIds.contains(currentUserIdentifier)) currentUserIdentifier!,
      ...userIds.where((id) => id != currentUserIdentifier),
    ];
    final names = ordered
        .take(3)
        .map((id) => id == currentUserIdentifier
            ? EmojiReaction.reactorYou
            // Vommet issue 475: names follow redacted mode.
            : (redaction ?? RedactionPolicy.off)
                .name(room.getMemberOrFallback(id).displayName, id))
        .toList();
    final who = EmojiReaction.summarizeReactors(names, ordered.length);

    final shortcode = emote.shortcode;
    if (shortcode != null && shortcode.isNotEmpty) {
      return EmojiReaction.reactedWith(who, ":$shortcode:");
    }
    // A custom emoji without a shortcode has only its mxc:// URL as a key.
    if (emote is UnicodeEmoticon) {
      return EmojiReaction.reactedWith(who, emote.key);
    }
    return EmojiReaction.reactedPlain(who);
  }

  /// Who reacted with [emote], in a dialog.
  static void showReactors(BuildContext context, Timeline timeline,
      Emoticon emote, Set<String> userIds) {
    AdaptiveDialog.show(
      context,
      scrollable: false,
      builder: (context) => SizedBox(
        height: 400,
        width: 400,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: EmojiWidget(
                emote,
                height: 40,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: userIds.length,
                itemBuilder: (context, index) {
                  final id = userIds.elementAt(index % userIds.length);
                  return UserPanel(
                      userId: id,
                      contextRoom: timeline.room,
                      client: timeline.client);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  State<TimelineEventViewReactions> createState() =>
      _TimelineEventViewReactionsState();
}

class _TimelineEventViewReactionsState extends State<TimelineEventViewReactions>
    implements TimelineEventViewWidget {
  Map<Emoticon, Set<String>>? reactions;

  late final String? currentUserIdentifier;
  late final TimelineEvent event;

  @override
  void initState() {
    event = widget.timeline.events[widget.initialIndex];
    currentUserIdentifier = widget.timeline.client.self?.identifier;
    setStateFromIndex(widget.initialIndex);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (reactions == null) {
      return Container();
    }

    return Wrap(
        spacing: 3,
        runSpacing: 3,
        direction: material.Axis.horizontal,
        children: reactions!.keys.map((key) {
          var value = reactions![key]!;

          return EmojiReaction(
              emoji: key,
              tooltip: TimelineEventViewReactions.reactorsTooltip(
                  widget.timeline, key, value,
                  redaction: RedactionScope.of(context)),
              onTapped: onReactionTapped,
              onLongPressed: (emote) => TimelineEventViewReactions.showReactors(
                  context, widget.timeline, key, value),
              numReactions: value.length,
              highlighted: value.contains(currentUserIdentifier));
        }).toList());
  }

  void onReactionTapped(Emoticon emote) {
    if (reactions == null) {
      return;
    }

    if (reactions![emote]?.contains(currentUserIdentifier) == true) {
      widget.timeline.room.removeReaction(event, emote);
    } else {
      widget.timeline.room.addReaction(event, emote);
    }
  }

  @override
  void update(int newIndex) {
    setStateFromIndex(newIndex);
  }

  void setStateFromIndex(int index) {
    setState(() {
      final event = widget.timeline.events[index];
      if (event is TimelineEventFeatureReactions) {
        reactions = (event as TimelineEventFeatureReactions)
            .getReactions(widget.timeline);
      }
    });
  }
}
