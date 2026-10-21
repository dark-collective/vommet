import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/call_encryption_strip.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/room_call_bar.dart';
import 'package:commet/ui/organisms/calendar_view/calendar_room_view.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/ui/organisms/chat/chat.dart';
import 'package:commet/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:commet/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:commet/ui/organisms/docked_widget/docked_widget_panel.dart';
import 'package:flutter/material.dart';

class RoomPrimaryView extends StatelessWidget {
  const RoomPrimaryView(this.room,
      {super.key, this.bypassSpecialRoomTypes = false});
  final Room room;
  final bool bypassSpecialRoomTypes;

  // Vommet: a widget docked in this room shows beside (or, in a voice
  // room's call, above) the room's view.
  @override
  Widget build(BuildContext context) =>
      DockedWidgetArea(room: room, child: buildPrimary(context));

  Widget buildPrimary(BuildContext context) {
    if (!bypassSpecialRoomTypes) {
      var photos = room.getComponent<PhotoAlbumRoom>();
      var voip = room.getComponent<VoipRoomComponent>();
      var calendar = room.getComponent<CalendarRoom>();

      var key = ValueKey("room-primary-view-${room.localId}");

      if (voip != null) {
        return ScaledSafeArea(
          bottom: true,
          top: false,
          child: VoipRoomView(
            voip,
            key: key,
          ),
        );
      }

      if (photos != null) {
        return PhotoAlbumView(
          photos,
          key: key,
        );
      }

      if (calendar?.isCalendarRoom == true) {
        return CalendarRoomView(
          calendar!,
          key: key,
        );
      }
    }

    final call = clientManager?.callManager.getCallInRoom(
      room.client,
      room.identifier,
    );

    // Vommet: on a phone with the keyboard open, a slim call bar instead of
    // the call view, so the chat keeps the space above the keyboard.
    if (call != null && MediaQuery.of(context).mobile) {
      final session = call;
      return KeyboardOpenBuilder(
        builder: (context, keyboardOpen) => StreamBuilder<void>(
          stream: session.onStateChanged,
          builder: (context, _) {
            // The call view only draws streams (video, screen share, audio
            // tiles). A call in a text room often has none, which left a big
            // empty grey box above the chat, so the slim strip stands in.
            final full = !keyboardOpen && _hasStreamsToShow(session);
            return Column(
              children: [
                // Vommet: "This call isn't encrypted" (Vommet issue 131).
                CallEncryptionStrip(room),
                if (!full) CompactCallStrip(session),
                if (full) Flexible(child: CallWidget(session)),
                Flexible(
                  child: Chat(room, key: key),
                ),
              ],
            );
          },
        ),
      );
    }

    // Vommet: on a foldable standing half open like a laptop, the call fills
    // the part above the fold and the chat the part below it.
    return HorizontalFoldBuilder(
      builder: (context, foldY) => Column(
        children: [
          // One Flexible either way (flex 0 = sized by the fold), so the
          // call keeps its state when the posture changes.
          // Vommet: "This call isn't encrypted" (Vommet issue 131), above the
          // call; below it when the call is sized to the fold.
          if (call != null && foldY == null) CallEncryptionStrip(room),
          if (call != null)
            Flexible(
              flex: foldY == null ? 1 : 0,
              child: SizedBox(height: foldY, child: CallWidget(call)),
            ),
          if (call != null && foldY != null) CallEncryptionStrip(room),
          // Vommet: join an Element Call / Element X call in this room.
          if (call == null) RoomCallBar(room),
          Flexible(
            child: Chat(room, key: key),
          ),
        ],
      ),
    );
  }

  static bool _hasStreamsToShow(VoipSession session) =>
      session.streams.any((s) => s.type != VoipStreamType.screenshareAudio);
}
