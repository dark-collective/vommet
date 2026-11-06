import 'dart:async';

import 'package:commet/client/attachment.dart';
import 'package:commet/client/room.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/share_intake.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issues 795, 807: sends a share to several rooms at once. Each file
/// goes through the attachment dialog once (remove hidden info, send
/// smaller), the same result goes to every room, and the last room picked
/// opens. Rooms that fail are named in one snackbar with Retry.
class ShareToRooms {
  static String labelShareFailedRooms(int count, String rooms) =>
      Intl.plural(count,
          one: "Couldn't share to $rooms",
          other: "Couldn't share to $count rooms: $rooms",
          args: [count, rooms],
          desc: "Snackbar when sharing to several rooms failed in some of them",
          name: "labelShareFailedRooms");

  static String get promptShareRetry => Intl.message("Retry",
      desc:
          "Button on the snackbar of a failed multi-room share that sends to the failed rooms again",
      name: "promptShareRetry");

  static Future<void> send(
      BuildContext context, List<Room> rooms, SharePayload payload) async {
    if (rooms.isEmpty) return;

    final files = <PendingFileAttachment>[];
    for (final file in payload.files) {
      if (!context.mounted) return;
      final (size, data) = await file.read();
      if (!context.mounted) return;

      final processed =
          await AdaptiveDialog.show<PendingFileAttachment>(context,
              scrollable: false,
              builder: (context) => AttachmentProcessor(
                    attachment: PendingFileAttachment(
                        name: file.name,
                        path: file.path,
                        size: size,
                        data: data,
                        mimeType: file.mimeType),
                  ));
      if (processed != null) files.add(processed);
    }

    final text = payload.text?.trim();
    final message = text == null || text.isEmpty ? null : text;
    // Every file dismissed and no text: nothing to send.
    if (files.isEmpty && message == null) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final redaction = RedactionScope.of(context);
    final last = rooms.last;
    EventBus.doOpenRoom(last.identifier, clientId: last.client.identifier);

    // In the background, so the next share can be picked meanwhile.
    unawaited(sendAll(rooms, files, message, messenger,
        name: (room) => redaction.roomDisplayName(room)));
  }

  static Future<void> sendAll(
      List<Room> rooms,
      List<PendingFileAttachment> files,
      String? message,
      ScaffoldMessengerState? messenger,
      {required String Function(Room room) name}) async {
    final failed = <Room>[];
    for (final room in rooms) {
      try {
        await room.sendMessage(
            message: message,
            processedAttachments: await room.processAttachments(files));
      } catch (error, trace) {
        Log.onError(error, trace, content: "Failed to send shared content");
        failed.add(room);
      }
    }
    if (failed.isEmpty || messenger == null || !messenger.mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text(
          labelShareFailedRooms(failed.length, failed.map(name).join(", "))),
      action: SnackBarAction(
          label: promptShareRetry,
          onPressed: () =>
              sendAll(failed, files, message, messenger, name: name)),
    ));
  }
}
