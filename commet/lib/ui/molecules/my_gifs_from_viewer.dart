import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/room.dart';
import 'package:commet/client/timeline.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/molecules/my_gifs.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';

/// Read when the menu opens, after gallery navigation or favorite sync.
typedef MyGifsMenuEntryBuilder = TimelineEventMenuEntry? Function();

final _pending = Expando<Set<String>>();

/// The displayed event's account owns My GIFs, regardless of which account
/// is selected elsewhere. Without a source event, no collection action.
TimelineEventMenuEntry? myGifsFromViewer(Room? room, TimelineEvent? event) {
  if (room == null ||
      event == null ||
      event.status != TimelineEventStatus.synced ||
      !room.client.isLoggedIn()) {
    return null;
  }
  if (event is MatrixTimelineEvent && !identical(event.client, room.client)) {
    return null;
  }
  final gifs = room.client.getComponent<GifComponent>();
  if (gifs == null || !gifs.isGif(event)) return null;
  final pending = _pending[gifs] ??= <String>{};
  if (pending.contains(event.eventId)) return null;
  final entry = MyGifs.menuEntry(gifs, event, saved: gifs.isFavoriteGif(event));
  return TimelineEventMenuEntry(
    name: entry.name,
    icon: entry.icon,
    action: (context) async {
      if (!pending.add(event.eventId)) return;
      try {
        await entry.action?.call(context);
      } finally {
        pending.remove(event.eventId);
      }
    },
  );
}
