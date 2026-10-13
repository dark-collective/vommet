import 'package:commet/client/components/polls/poll_component.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/molecules/read_indicator.dart';
import 'package:commet/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:commet/ui/molecules/user_panel.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/error_utils.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventViewPoll extends StatefulWidget {
  const TimelineEventViewPoll(
      {required this.initialIndex, required this.timeline, super.key});

  final int initialIndex;
  final Timeline timeline;
  @override
  State<TimelineEventViewPoll> createState() => _TimelineEventViewPollState();
}

class _TimelineEventViewPollState extends State<TimelineEventViewPoll>
    implements TimelineEventViewWidget {
  PollComponent? polls;
  String? body;

  ImageProvider? senderAvatar;
  String senderName = "";
  String senderId = "";
  Color senderColor = Colors.grey;

  /// Vommet: the poll couldn't be read (malformed content, or the index
  /// pointed at another event while the timeline shifted); show a line
  /// instead of throwing, which drew Flutter's grey error box.
  bool unreadable = false;
  int maxSelections = 0;
  bool showResults = false;
  bool isFinished = false;
  List<PollAnswer> allowedAnswers = [];
  Map<String, Set<String>> pollResponses = {};
  TimelineEvent? event;

  @override
  void initState() {
    polls = widget.timeline.client.getComponent<PollComponent>();
    setStateFromIndex(widget.initialIndex);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    int totalVotes = 0;

    for (var answer in allowedAnswers) {
      var r = pollResponses[answer.id];
      if (r != null) {
        var len = r.length;
        totalVotes += len;
      }
    }

    return TimelineEventLayoutMessage(
      senderName: senderName,
      senderColor: senderColor,
      senderAvatar: senderAvatar,
      showSender: true,
      formattedContent: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).desktop ? 500 : double.infinity),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            if (unreadable) tiamat.Text.labelLow("Couldn't display this poll"),
            if (body != null) tiamat.Text.label(body!),
            for (var answer in allowedAnswers)
              buildAnswer(answer, totalVotes: totalVotes),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                tiamat.Text.labelLow("$totalVotes votes"),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!showResults)
                      tiamat.Text.labelLow(
                          "Results will be visible once the poll has ended"),
                    if (isFinished) tiamat.Text.labelLow("This poll has ended")
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  void update(int newIndex) {
    setStateFromIndex(newIndex);
  }

  void setStateFromIndex(int index) {
    // Vommet: indexes shift while history, reactions and poll responses
    // load, so the index can point at a different event; keep showing the
    // poll we have rather than parsing that one as a poll.
    if (index < 0 || index >= widget.timeline.events.length) return;
    final e = widget.timeline.events[index];
    if (event != null && e.eventId != event!.eventId) return;
    final p = polls;
    if (p == null) return;

    final sender = widget.timeline.room.getMemberOrFallback(e.senderId);
    try {
      final newMax = p.getMaxSelections(e);
      final newShow = p.shouldShowResults(e, widget.timeline);
      final newBody = p.getPollQuestion(e);
      final newFinished = p.isFinished(e, widget.timeline);
      final newAnswers = p.getAllowedPollAnswers(e);
      final newResponses = p.getPollResponses(widget.timeline, e);
      void apply() {
        senderId = sender.identifier;
        senderName = sender.displayName;
        senderAvatar = sender.avatar;
        senderColor = sender.defaultColor;
        maxSelections = newMax;
        showResults = newShow;
        body = newBody;
        isFinished = newFinished;
        allowedAnswers = newAnswers;
        pollResponses = newResponses;
        event = e;
        unreadable = false;
      }

      mounted ? setState(apply) : apply();
    } catch (error, stack) {
      Log.onError(error, stack, content: "Couldn't read poll ${e.eventId}");
      void broken() {
        senderId = sender.identifier;
        senderName = sender.displayName;
        senderAvatar = sender.avatar;
        senderColor = sender.defaultColor;
        event ??= e;
        unreadable = event!.eventId == e.eventId;
      }

      mounted ? setState(broken) : broken();
    }
  }

  Widget buildAnswer(PollAnswer answer, {int totalVotes = 1}) {
    var responses = pollResponses[answer.id];

    var isOurResponse =
        responses?.contains(widget.timeline.client.self!.identifier) == true;

    return Material(
      clipBehavior: Clip.antiAlias,
      color: ColorScheme.of(context).surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onLongPress: !showResults
            ? null
            : () {
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
                          child: tiamat.Text.largeTitle(answer.answer),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: responses?.length ?? 0,
                            itemBuilder: (context, index) {
                              final id = responses!.elementAt(index);
                              return UserPanel(
                                  userId: id,
                                  contextRoom: widget.timeline.room,
                                  client: widget.timeline.client);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
        onTap: isFinished
            ? null
            : () {
                List<PollAnswer> selectedAnswer;

                if (maxSelections > 1) {
                  selectedAnswer = allowedAnswers
                      .where((i) =>
                          pollResponses[i.id]?.contains(
                              widget.timeline.client.self!.identifier) ==
                          true)
                      .toList(growable: true);

                  if (isOurResponse) {
                    selectedAnswer.remove(answer);
                  } else {
                    selectedAnswer.add(answer);
                  }
                } else {
                  selectedAnswer = [answer];
                }

                ErrorUtils.tryRun(context, () async {
                  await polls?.setAnswer(
                    event!,
                    widget.timeline.room,
                    selectedAnswer,
                  );
                });
              },
        child: Container(
          decoration: BoxDecoration(
              border: BoxBorder.all(
                  color: isOurResponse
                      ? ColorScheme.of(context).onSurface.withAlpha(150)
                      : Colors.transparent,
                  strokeAlign: BorderSide.strokeAlignInside,
                  width: 1.5),
              borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              spacing: 4,
              children: [
                Row(
                  spacing: 8,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    tiamat.Text(
                      answer.answer,
                    ),
                    if (showResults)
                      Row(
                        spacing: 8,
                        children: [
                          SizedBox(
                            width: 50,
                            child: ReadIndicator(
                                spacing: 10,
                                room: widget.timeline.room,
                                users: responses ?? {}),
                          ),
                          tiamat.Text(
                            (responses?.length ?? 0).toString(),
                          )
                        ],
                      )
                  ],
                ),
                if (showResults)
                  LinearProgressIndicator(
                    value: totalVotes == 0
                        ? 0
                        : (responses?.length ?? 0) / totalVotes,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
