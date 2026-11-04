import 'package:commet/client/matrix/forwarding/matrix_forwarding.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/forward_message/forward_message_dialog.dart';
import 'package:commet/ui/organisms/forward_message/pending_forward.dart';
import 'package:flutter/widgets.dart';

/// Vommet issue 802: Forward in the media viewer's ⋮ menu. Null when
/// [event] can't be forwarded. The viewer closes first (whoever opened it
/// does that); the room picker then opens over the app, and the forward
/// waits in the chosen room's message box like any other forward.
VoidCallback? forwardFromViewer(Room room, TimelineEvent? event,
    {Timeline? timeline}) {
  if (event == null || !MatrixForwarding.canForward(event)) return null;
  return () async {
    final context = navigator.currentContext;
    if (context == null) return;
    final targets = await ForwardMessageDialog.pickRooms(context, room.client);
    if (targets == null) return;
    PendingForwards.startInAll(targets,
        PendingForward(event: event, timeline: timeline ?? room.timeline));
  };
}
