import 'package:commet/client/attachment.dart';
import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline_events/timeline_event_feature_forwarded.dart';
import 'package:commet/client/timeline_events/timeline_event_message.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// What a pending forward is, for the bar and its options.
class _ForwardSummary {
  _ForwardSummary(PendingForward forward) {
    final event = forward.event;
    final timeline = forward.timeline;

    String senderId = event.senderId;
    if (event is TimelineEventFeatureForwarded) {
      senderId =
          (event as TimelineEventFeatureForwarded).forwardedFrom?.senderId ??
              senderId;
    }
    final room = timeline?.room;
    senderName = room != null
        ? room.getMemberOrFallback(senderId).displayName
        : senderId;

    canShowSender = MatrixForwarding.canShowSender(event);
    hasCaption = MatrixForwarding.hasCaption(event, timeline);

    if (event is TimelineEventSticker) {
      kind = ForwardBar.labelForwardSticker;
    } else if (event case TimelineEventMessage m) {
      final attachment = m.attachments?.firstOrNull;
      switch (attachment) {
        case ImageAttachment a:
          kind = ForwardBar.labelForwardPhoto;
          thumbnail = a.image;
        case VideoAttachment v:
          kind = ForwardBar.labelForwardVideo;
          thumbnail = v.thumbnail;
        case FileAttachment _:
          kind = ForwardBar.labelForwardFile;
        default:
          kind = ForwardBar.labelForwardMessage;
      }

      if (attachment == null || hasCaption) {
        text = timeline != null ? m.getPlaintextBody(timeline) : m.body;
      }
    } else {
      kind = ForwardBar.labelForwardMessage;
    }
  }

  late final String senderName;
  late final String kind;
  late final bool canShowSender;
  late final bool hasCaption;
  ImageProvider? thumbnail;
  String? text;
}

/// Sits above the message box while a message waits to be forwarded, like
/// Telegram's: tap it for options, × to cancel.
class ForwardBar extends StatelessWidget {
  const ForwardBar({required this.room, required this.forward, super.key});

  final Room room;
  final PendingForward forward;

  static String get labelForwardMessage => Intl.message("Forward message",
      desc: "Title of the bar above the message box for a pending forward",
      name: "labelForwardMessage");

  static String get labelForwardPhoto => Intl.message("Forward photo",
      desc: "Title of the forward bar when the message is an image",
      name: "labelForwardPhoto");

  static String get labelForwardVideo => Intl.message("Forward video",
      desc: "Title of the forward bar when the message is a video",
      name: "labelForwardVideo");

  static String get labelForwardFile => Intl.message("Forward file",
      desc: "Title of the forward bar when the message is a file",
      name: "labelForwardFile");

  static String get labelForwardSticker => Intl.message("Forward sticker",
      desc: "Title of the forward bar when the message is a sticker",
      name: "labelForwardSticker");

  static String labelForwardFrom(String name) => Intl.message("From $name",
      desc: "Who a pending forward is from, shown under the forward bar title",
      args: [name],
      name: "labelForwardFrom");

  static String get labelSenderHidden => Intl.message("Sender name hidden",
      desc: "Forward bar subtitle when the forward won't name the sender",
      name: "labelSenderHidden");

  static String get labelCaptionHidden => Intl.message("caption hidden",
      desc: "Added to the forward bar subtitle when the caption is dropped",
      name: "labelCaptionHidden");

  static String get promptCancelForward => Intl.message("Cancel forward",
      desc: "Tooltip of the × on the forward bar", name: "promptCancelForward");

  @override
  Widget build(BuildContext context) {
    final summary = _ForwardSummary(forward);
    final colors = Theme.of(context).colorScheme;

    var subtitle = forward.showSender && summary.canShowSender
        ? labelForwardFrom(summary.senderName)
        : labelSenderHidden;
    if (forward.hideCaption && summary.hasCaption) {
      subtitle = "$subtitle · $labelCaptionHidden";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ForwardOptions.show(context, room, forward),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
            child: Row(
              children: [
                Icon(Icons.shortcut, color: colors.primary),
                const SizedBox(width: 8),
                if (summary.thumbnail != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image(
                          image: summary.thumbnail!,
                          width: 36,
                          height: 36,
                          fit: BoxFit.cover),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tiamat.Text.labelEmphasised(summary.kind,
                          color: colors.primary,
                          overflow: TextOverflow.ellipsis),
                      tiamat.Text.labelLow(subtitle,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: promptCancelForward,
                  icon: const Icon(Icons.close),
                  onPressed: () => PendingForwards.clear(room),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram-style options for a pending forward: a preview of what will be
/// sent, sender and caption toggles, another recipient, or no forward.
class ForwardOptions extends StatefulWidget {
  const ForwardOptions({required this.room, required this.forward, super.key});

  final Room room;
  final PendingForward forward;

  static String get titleForwardOptions => Intl.message("Forward message",
      desc: "Title of the options sheet for a pending forward",
      name: "titleForwardOptions");

  static String get labelRecipientsSeeForward =>
      Intl.message("Recipients will see that it was forwarded",
          desc: "Explains the forward options sheet when the sender is shown",
          name: "labelRecipientsSeeForward");

  static String get labelRecipientsSeePlain =>
      Intl.message("Recipients will see it as your own message",
          desc: "Explains the forward options sheet when the sender is hidden",
          name: "labelRecipientsSeePlain");

  static String get labelForwardPreviewFrom => Intl.message("Forwarded from",
      desc: "Header of the forward preview, before the original sender",
      name: "labelForwardPreviewFrom");

  static String get promptHideSenderName => Intl.message("Hide sender name",
      desc: "Forward option: send the message without naming its sender",
      name: "promptHideSenderName");

  static String get promptShowSenderName => Intl.message("Show sender name",
      desc: "Forward option: name the original sender",
      name: "promptShowSenderName");

  static String get promptHideCaption => Intl.message("Hide caption",
      desc: "Forward option: send media without its caption",
      name: "promptHideCaption");

  static String get promptShowCaption => Intl.message("Show caption",
      desc: "Forward option: keep the media's caption",
      name: "promptShowCaption");

  static String get promptChangeRecipient => Intl.message("Change recipient",
      desc: "Forward option: pick another room for the pending forward",
      name: "promptChangeRecipient");

  static String get promptApplyChanges => Intl.message("Apply changes",
      desc: "Forward option: keep the chosen options",
      name: "promptApplyChanges");

  static String get promptDoNotForward => Intl.message("Do not forward",
      desc: "Forward option: cancel the pending forward",
      name: "promptDoNotForward");

  static Future<void> show(
      BuildContext context, Room room, PendingForward forward) {
    return AdaptiveDialog.show(
      context,
      title: titleForwardOptions,
      builder: (_) => ForwardOptions(room: room, forward: forward),
    );
  }

  @override
  State<ForwardOptions> createState() => _ForwardOptionsState();
}

class _ForwardOptionsState extends State<ForwardOptions> {
  late PendingForward forward = widget.forward;
  late final _ForwardSummary summary = _ForwardSummary(widget.forward);

  bool get showsSender => forward.showSender && summary.canShowSender;
  bool get showsCaption => !(forward.hideCaption && summary.hasCaption);

  void close() => Navigator.of(context).pop();

  Future<void> changeRecipient() async {
    final client = widget.room.client;
    final applied = forward;
    final navigator = Navigator.of(context);
    final room = await ForwardMessageDialog.pick(context, client);
    if (room == null) return;

    if (room.identifier != widget.room.identifier) {
      PendingForwards.clear(widget.room);
    }
    PendingForwards.startIn(room, applied);
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: tiamat.Text.labelLow(showsSender
                ? ForwardOptions.labelRecipientsSeeForward
                : ForwardOptions.labelRecipientsSeePlain),
          ),
          preview(context),
          const SizedBox(height: 8),
          if (summary.canShowSender)
            option(
              icon: showsSender ? Icons.person_off_outlined : Icons.person,
              label: showsSender
                  ? ForwardOptions.promptHideSenderName
                  : ForwardOptions.promptShowSenderName,
              onTap: () => setState(() =>
                  forward = forward.copyWith(showSender: !forward.showSender)),
            ),
          if (summary.hasCaption)
            option(
              icon: showsCaption
                  ? Icons.subtitles_off_outlined
                  : Icons.subtitles_outlined,
              label: showsCaption
                  ? ForwardOptions.promptHideCaption
                  : ForwardOptions.promptShowCaption,
              onTap: () => setState(() => forward =
                  forward.copyWith(hideCaption: !forward.hideCaption)),
            ),
          option(
            icon: Icons.swap_horiz,
            label: ForwardOptions.promptChangeRecipient,
            onTap: changeRecipient,
          ),
          const Divider(),
          option(
            icon: Icons.check_circle_outline,
            label: ForwardOptions.promptApplyChanges,
            onTap: () {
              PendingForwards.set(widget.room, forward);
              close();
            },
          ),
          option(
            icon: Icons.delete_outline,
            label: ForwardOptions.promptDoNotForward,
            color: Theme.of(context).colorScheme.error,
            onTap: () {
              PendingForwards.clear(widget.room);
              close();
            },
          ),
        ],
      ),
    );
  }

  Widget preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = showsCaption ? summary.text : null;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showsSender)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Row(
                children: [
                  Icon(Icons.shortcut, size: 16, color: colors.primary),
                  const SizedBox(width: 4),
                  tiamat.Text.labelLow(ForwardOptions.labelForwardPreviewFrom),
                  const SizedBox(width: 4),
                  Flexible(
                    child: tiamat.Text.labelEmphasised(summary.senderName,
                        color: colors.primary, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          if (summary.thumbnail != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Image(
                  image: summary.thumbnail!,
                  width: double.infinity,
                  fit: BoxFit.cover),
            ),
          if (summary.thumbnail == null && text == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: tiamat.Text.label(summary.kind),
            ),
          if (text != null && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: tiamat.Text.body(text,
                  maxLines: 6, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }

  Widget option(
      {required IconData icon,
      required String label,
      required void Function() onTap,
      Color? color}) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 16),
              Expanded(child: tiamat.Text(label, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
