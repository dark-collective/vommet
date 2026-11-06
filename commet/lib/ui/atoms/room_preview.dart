import 'package:commet/client/client.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomPreviewView extends StatelessWidget {
  const RoomPreviewView({required this.previewData, super.key});
  final RoomPreview previewData;
  @override
  Widget build(BuildContext context) {
    // Vommet issue 475: name and topic follow redacted mode.
    final redaction = RedactionScope.of(context);
    final name =
        redaction.roomName(previewData.displayName, previewData.roomId);
    final topic = redaction.roomTopic(previewData.topic);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (previewData.avatar != null)
          ImageButton(
            size: 90,
            image: redaction.hidesAvatars ? null : previewData.avatar!,
            placeholderColor: redaction.hidesAvatars
                ? redaction.identityColor(previewData.roomId)
                : previewData.color,
            placeholderText: redaction.hidesAvatars
                ? (redaction.avatarLetter(previewData.roomId).isEmpty
                    ? " "
                    : redaction.avatarLetter(previewData.roomId))
                : name,
            semanticsLabel: name,
          ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.Text.largeTitle(name),
                Row(
                  spacing: 8,
                  children: [
                    if (previewData.type != null)
                      tiamat.Tooltip(
                          text: previewData.type!.string,
                          child: Icon(size: 15, previewData.type!.icon)),
                    if (previewData.numMembers != null)
                      Row(
                        children: [
                          Icon(size: 15, Icons.people),
                          tiamat.Text.labelLow("${previewData.numMembers}")
                        ],
                      ),
                    Icon(
                        size: 15,
                        switch (previewData.visibility) {
                          null => Icons.lock,
                          final RoomVisibilityPublic _ => Icons.public,
                          final RoomVisibilityPrivate _ => Icons.lock,
                          final RoomVisibilityRestricted _ => Icons.shield,
                          final RoomVisibilityKnock _ => Icons.how_to_reg,
                          _ => Icons.question_mark,
                        })
                  ],
                ),
                if (topic != null)
                  Flexible(
                      child: tiamat.Text.labelLow(
                    topic,
                  ))
              ],
            ),
          ),
        )
      ],
    );
  }
}
