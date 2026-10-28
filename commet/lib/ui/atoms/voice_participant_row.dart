import 'dart:async';

import 'package:commet/client/components/voip/voip_participants.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:intl/intl.dart';

/// Vommet: someone in a voice room's call, listed under the room in the
/// sidebar (experiment `experiment_sidebar_subspace_guides`). In a call
/// you're in ([call]), their avatar gets a green ring and their name lights
/// up while they talk, and a crossed-out mic shows when theirs is off. For
/// other calls we only know who is there.
///
/// Someone sharing their screen in your call gets LIVE, as on Discord:
/// clicking it (or Watch, when you point at the row) watches their stream
/// and opens the call with it big ([onOpenCall]).
class VoiceParticipantRow extends StatefulWidget {
  const VoiceParticipantRow(this.member,
      {this.call, this.onOpenCall, super.key});

  static String get voiceRowWatchButton => Intl.message("Watch",
      name: "voiceRowWatchButton",
      desc:
          "Sidebar, person in a voice call who shares their screen: button that watches their stream; keep very short");

  static String get voiceRowWatchTooltip => Intl.message("Watch their stream",
      name: "voiceRowWatchTooltip",
      desc:
          "Sidebar, person in a voice call: tooltip on LIVE, which starts watching their screen share");

  static String get voiceRowShowTooltip => Intl.message("Show their stream",
      name: "voiceRowShowTooltip",
      desc:
          "Sidebar, person in a voice call: tooltip on LIVE when you already watch their screen share; it opens it big");

  static String get voiceRowWatchingLabel => Intl.message("Watching",
      name: "voiceRowWatchingLabel",
      desc:
          "Sidebar, person in a voice call: screen reader label of the eye shown while you watch their screen share");

  final Member member;

  /// The call this person is in, when you're in it too and it can tell
  /// who's talking.
  final VoipParticipants? call;

  /// Opens the call (the room's own tap).
  final VoidCallback? onOpenCall;

  /// A talker stays lit this long after the server says they stopped, so
  /// the ring doesn't blink between words.
  static const hold = Duration(milliseconds: 400);

  /// The call in [room] you're in, if any (and if it can tell who's
  /// talking).
  static VoipParticipants? liveCallIn(Room room) {
    final sessions = clientManager?.callManager.currentSessions;
    if (sessions == null) return null;
    for (final session in sessions) {
      if (session.roomId == room.identifier &&
          session.client == room.client &&
          session.state != VoipState.ended &&
          session is VoipParticipants) {
        return session as VoipParticipants;
      }
    }
    return null;
  }

  @override
  State<VoiceParticipantRow> createState() => _VoiceParticipantRowState();
}

class _VoiceParticipantRowState extends State<VoiceParticipantRow> {
  StreamSubscription? sub;
  StreamSubscription? streamsSub;
  bool hovering = false;
  Timer? holdTimer;
  bool talking = false;
  bool micOff = false;

  @override
  void initState() {
    super.initState();
    listen();
  }

  @override
  void didUpdateWidget(VoiceParticipantRow old) {
    super.didUpdateWidget(old);
    if (old.call != widget.call ||
        old.member.identifier != widget.member.identifier) {
      listen();
    }
  }

  void listen() {
    sub?.cancel();
    streamsSub?.cancel();
    streamsSub = null;
    holdTimer?.cancel();
    final call = widget.call;
    talking = false;
    micOff = false;
    if (call == null) return;
    sub = call.onParticipantsChanged.listen((_) => update());
    // Shares starting and stopping, and watching them.
    streamsSub = session?.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    update(rebuild: false);
  }

  void update({bool rebuild = true}) {
    final call = widget.call;
    if (call == null) return;
    final id = widget.member.identifier;
    final off = call.micOffUserIds.contains(id);
    final speaking = !off && call.speakingUserIds.contains(id);
    var nextTalking = talking;
    if (speaking) {
      holdTimer?.cancel();
      holdTimer = null;
      nextTalking = true;
    } else if (talking && holdTimer == null) {
      if (off) {
        nextTalking = false;
      } else {
        holdTimer = Timer(VoiceParticipantRow.hold, () {
          holdTimer = null;
          if (mounted) setState(() => talking = false);
        });
      }
    }
    if (nextTalking == talking && off == micOff) return;
    if (!rebuild) {
      talking = nextTalking;
      micOff = off;
      return;
    }
    setState(() {
      talking = nextTalking;
      micOff = off;
    });
  }

  VoipSession? get session {
    final call = widget.call;
    return call is VoipSession ? call as VoipSession : null;
  }

  /// Their screen share in your call, if they share (stream watching only).
  VoipStream? get share {
    final session = this.session;
    if (session == null || VoipStreamWatching.of(session) == null) return null;
    for (final stream in session.streams) {
      if (stream.type == VoipStreamType.screenshare &&
          stream.direction == VoipStreamDirection.incoming &&
          stream.streamUserId == widget.member.identifier) {
        return stream;
      }
    }
    return null;
  }

  Future<void> watch(VoipStream share) async {
    final watching = VoipStreamWatching.of(session!);
    if (watching == null) return;
    if (!watching.isWatching(share)) await watching.setWatching(share, true);
    watching.requestFocus(share);
    widget.onOpenCall?.call();
  }

  @override
  void dispose() {
    sub?.cancel();
    streamsSub?.cancel();
    holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Vommet issue 475: redacted mode.
    final name = RedactionScope.of(context)
        .name(widget.member.displayName, widget.member.identifier);
    final share = this.share;
    final watched = share != null &&
        VoipStreamWatching.of(session!)?.isWatching(share) == true;
    final row = SizedBox(
      // Vommet: the size these rows had before the experiment (a 24 px
      // picture in a 37 px row, like the room rows above them).
      height: 37,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(4),
            // Like Discord, the ring lies over the picture's outer edge
            // (painted on top, same corners as tiamat's rounded square:
            // radius / 1.25) rather than standing off it with a gap, with a
            // 1 px line of the sidebar's colour inside it.
            child: Container(
              foregroundDecoration: talking
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12 / 1.25),
                      border: Border.all(
                        color: VoiceRoomOccupancy.greenFor(context),
                        width: 2,
                      ),
                    )
                  : null,
              child: Container(
                foregroundDecoration: talking
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(12 / 1.25),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          width: 3,
                        ),
                      )
                    : null,
                child: tiamat.Avatar(
                  radius: 12,
                  image: widget.member.avatar,
                  placeholderColor: widget.member.defaultColor,
                  placeholderText: widget.member.displayName,
                  redactionKey: widget.member.identifier,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    color: talking ? scheme.onSurface : scheme.secondary,
                    fontWeight: talking ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ),
          if (share != null && watched)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.visibility,
                  size: 14,
                  semanticLabel: VoiceParticipantRow.voiceRowWatchingLabel,
                  color: scheme.secondary),
            ),
          if (share != null && !watched && hovering)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _RowWatchButton(() => watch(share)),
            ),
          if (share != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: watched
                    ? VoiceParticipantRow.voiceRowShowTooltip
                    : VoiceParticipantRow.voiceRowWatchTooltip,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => watch(share),
                    child: const StreamLivePill(size: 8),
                  ),
                ),
              ),
            ),
          if (micOff)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Icon(
                Icons.mic_off,
                size: 14,
                semanticLabel: "Microphone off",
                color: scheme.error.withValues(alpha: 0.85),
              ),
            )
          else if (share != null)
            const SizedBox(width: 8),
        ],
      ),
    );
    if (share == null) return row;
    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: row,
    );
  }
}

/// Vommet: the small Watch button on a sharer's row in the sidebar.
class _RowWatchButton extends StatelessWidget {
  const _RowWatchButton(this.onPressed);
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_arrow_rounded, size: 13, color: scheme.onSurface),
            const SizedBox(width: 2),
            Text(VoiceParticipantRow.voiceRowWatchButton,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
          ]),
        ),
      ),
    );
  }
}
