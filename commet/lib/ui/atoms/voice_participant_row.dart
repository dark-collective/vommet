import 'dart:async';

import 'package:commet/client/components/voip/voip_participants.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:commet/client/member.dart';
import 'package:commet/ui/atoms/voice_room_occupancy.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/atoms/redaction_scope.dart';

/// Vommet: someone in a voice room's call, listed under the room in the
/// sidebar (experiment `experiment_sidebar_subspace_guides`). In a call
/// you're in ([call]), their avatar gets a green ring and their name lights
/// up while they talk, and a crossed-out mic shows when theirs is off. For
/// other calls we only know who is there.
class VoiceParticipantRow extends StatefulWidget {
  const VoiceParticipantRow(this.member, {this.call, super.key});

  final Member member;

  /// The call this person is in, when you're in it too and it can tell
  /// who's talking.
  final VoipParticipants? call;

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
    holdTimer?.cancel();
    final call = widget.call;
    talking = false;
    micOff = false;
    if (call == null) return;
    sub = call.onParticipantsChanged.listen((_) => update());
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

  @override
  void dispose() {
    sub?.cancel();
    holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Vommet issue 475: redacted mode.
    final name = RedactionScope.of(context)
        .name(widget.member.displayName, widget.member.identifier);
    return SizedBox(
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
          if (micOff)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Icon(
                Icons.mic_off,
                size: 14,
                semanticLabel: "Microphone off",
                color: scheme.error.withValues(alpha: 0.85),
              ),
            ),
        ],
      ),
    );
  }
}
