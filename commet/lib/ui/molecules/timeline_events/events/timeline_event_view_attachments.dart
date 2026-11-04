import 'package:commet/ui/molecules/my_gifs_from_viewer.dart';
import 'package:commet/client/attachment.dart';
import 'package:commet/ui/atoms/message_attachment.dart';
import 'package:flutter/material.dart';

class TimelineEventViewAttachments extends StatelessWidget {
  const TimelineEventViewAttachments(
      {required this.attachments,
      this.previewMedia = false,
      this.roomId,
      this.clientId,
      this.eventId,
      this.myGifsMenuEntry,
      super.key});
  final List<Attachment> attachments;
  final bool previewMedia;

  /// Vommet: the message, for picture-in-picture's Back to message.
  final String? roomId;
  final String? clientId;
  final String? eventId;
  final MyGifsMenuEntryBuilder? myGifsMenuEntry;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: attachments
          .map((e) => Padding(
                padding: const EdgeInsets.fromLTRB(0, 2, 2, 2),
                child: RepaintBoundary(
                  child: MessageAttachment(
                    e,
                    previewMedia: previewMedia,
                    roomId: roomId,
                    clientId: clientId,
                    eventId: eventId,
                    myGifsMenuEntry: myGifsMenuEntry,
                  ),
                ),
              ))
          .toList(),
    );
  }
}
