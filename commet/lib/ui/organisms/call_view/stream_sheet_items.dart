import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/stream_viewers.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: the screen-share items of a person's long-press menu (phones)
/// and right-click menu (desktop), on their tile or their stream's tile,
/// with stream watching on: Mute stream and Stop watching while you watch
/// their stream, Watch stream while you don't. They follow the big tile
/// and fullscreen (and the other way round) through
/// [VoipStreamWatching.onChanged].
class StreamSheetItems {
  static String get streamSheetJustForYou => Intl.message("Just for you",
      name: "streamSheetJustForYou",
      desc:
          "Long-press menu of someone sharing their screen in a call: under Mute stream, says only you stop hearing it");

  /// The screen share [userId] is sharing to you, with stream watching on.
  static VoipStream? shareOf(VoipSession session, String userId) {
    if (VoipStreamWatching.of(session) == null) return null;
    return session.streams.firstWhereOrNull((s) =>
        s.type == VoipStreamType.screenshare &&
        s.direction == VoipStreamDirection.incoming &&
        s.streamUserId == userId);
  }

  /// The items for [share] (from [shareOf]).
  static List<tiamat.ContextMenuItem> items(
      VoipSession session, VoipStream share) {
    final watching = VoipStreamWatching.of(session);
    if (watching == null) return [];
    if (!watching.isWatching(share)) {
      final viewers = watching.viewersOf(share).length;
      return [
        tiamat.ContextMenuItem(
          text: StreamWatchCard.streamWatchButton,
          customBuilder: (context, onClicked, {closeMenu}) => _tile(
            key: const ValueKey("streamSheetWatch"),
            icon: Icons.play_arrow_rounded,
            title: StreamWatchCard.streamWatchButton,
            subtitle:
                viewers > 0 ? StreamViewers.streamViewersCount(viewers) : null,
            onTap: () async {
              (closeMenu ?? onClicked)();
              await watching.setWatching(share, true);
              watching.requestFocus(share);
            },
          ),
        ),
      ];
    }
    final audio = session.streams.firstWhereOrNull((s) =>
        s.participantId == share.participantId &&
        s.type == VoipStreamType.screenshareAudio);
    return [
      if (audio != null)
        tiamat.ContextMenuItem(
          text: WatchedStreamControlsStrings.watchedStreamMute,
          customBuilder: (context, onClicked, {closeMenu}) =>
              _MuteStreamSwitch(watching: watching, share: share),
        ),
      tiamat.ContextMenuItem(
        text: WatchedStreamControlsStrings.watchedStreamStopWatching,
        customBuilder: (context, onClicked, {closeMenu}) => _tile(
          key: const ValueKey("streamSheetStopWatching"),
          icon: Icons.close_rounded,
          title: WatchedStreamControlsStrings.watchedStreamStopWatching,
          color: streamLiveRed,
          onTap: () {
            (closeMenu ?? onClicked)();
            watching.setWatching(share, false);
          },
        ),
      ),
    ];
  }

  static Widget _tile(
          {required Key key,
          required IconData icon,
          required String title,
          String? subtitle,
          Color? color,
          required VoidCallback onTap}) =>
      Builder(builder: (context) {
        final c = color ?? Theme.of(context).colorScheme.onSurface;
        return ListTile(
          key: key,
          dense: true,
          minTileHeight: 48,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: Icon(icon, color: c, size: 22),
          title: Text(title,
              style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: onTap,
        );
      });
}

/// "Mute stream / Just for you", in step with the tile and fullscreen.
class _MuteStreamSwitch extends StatefulWidget {
  const _MuteStreamSwitch({required this.watching, required this.share});
  final VoipStreamWatching watching;
  final VoipStream share;

  @override
  State<_MuteStreamSwitch> createState() => _MuteStreamSwitchState();
}

class _MuteStreamSwitchState extends State<_MuteStreamSwitch> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.watching.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = widget.watching.isStreamAudioMuted(widget.share);
    return SwitchListTile(
      key: const ValueKey("streamSheetMute"),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      secondary: Icon(muted ? Icons.volume_off : Icons.volume_up,
          color: muted ? streamLiveRed : null, size: 22),
      title: Text(WatchedStreamControlsStrings.watchedStreamMute,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(StreamSheetItems.streamSheetJustForYou),
      value: muted,
      onChanged: (v) => widget.watching.setStreamAudioMuted(widget.share, v),
    );
  }
}
