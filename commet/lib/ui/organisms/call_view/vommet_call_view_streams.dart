import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/own_stream_card.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:flutter/material.dart';

// Vommet: Discord-style stream watching in the call view (experiment
// `vommet_experiment_stream_watching`, see [VoipStreamWatching]). The call
// view asks these for a tile first and keeps its own when they return null.

bool _isRemoteShare(VoipStream stream) =>
    stream.type == VoipStreamType.screenshare &&
    stream.direction == VoipStreamDirection.incoming;

bool _isOwnShare(VoipStream stream) =>
    stream.type == VoipStreamType.screenshare &&
    stream.direction == VoipStreamDirection.outgoing;

/// The tile for [stream]: a Watch card while you don't watch someone's
/// screen share, the share with its controls while you do (when it's the
/// big one, [focused]), or null for the call view's usual tile. [focus]
/// makes a stream the big one (null: back to the grid).
Widget? vommetStreamTile(CallView view, VoipStream stream,
    {required bool focused,
    required BuildContext context,
    required void Function(VoipStream? stream) focus}) {
  final session = view.currentSession;
  final watching = VoipStreamWatching.of(session);
  // Your own share: its own dimmed tile with Stop streaming, as on Discord;
  // tapping it shows it big (the call view's usual tile).
  if (watching != null && _isOwnShare(stream) && !focused) {
    return OwnStreamCard(
        key: ValueKey("ownStreamCard_${stream.streamId}"),
        stream: stream,
        onStop: view.stopScreenshare);
  }
  if (watching == null || !_isRemoteShare(stream)) return null;

  if (!watching.isWatching(stream)) {
    return StreamWatchCard(
      key: ValueKey("streamWatchCard_${stream.streamId}"),
      stream: stream,
      session: session,
      watching: watching,
      onWatch: () async {
        await watching.setWatching(stream, true);
        focus(stream);
      },
    );
  }
  if (!focused) return null;

  return WatchedStreamControls(
    key: ValueKey("watchedStream_${stream.streamId}"),
    stream: stream,
    session: session,
    watching: watching,
    onStopWatching: () async {
      await watching.setWatching(stream, false);
      focus(null);
    },
    onFullscreen: () => vommetOpenFullscreen(view, stream, context),
    child: VoipStreamView(
      stream,
      session,
      canFullscreen: false,
      borderColor: Colors.white,
      fit: BoxFit.contain,
      key: ValueKey("callView_mainStreamView_${stream.streamId}"),
    ),
  );
}

/// Real fullscreen instead of the in-window lightbox, for calls that use
/// stream watching; false (do the usual) otherwise.
bool vommetOpenFullscreen(
    CallView view, VoipStream stream, BuildContext context) {
  if (VoipStreamWatching.of(view.currentSession) == null) return false;
  StreamFullscreenView.open(context,
      stream: stream,
      session: view.currentSession,
      actions: StreamCallActions(
        setMicrophoneMute: view.setMicrophoneMute,
        pickScreenshareSource: view.pickScreenshareSource,
        stopScreenshare: view.stopScreenshare,
        pickCamera: view.pickCamera,
        disableCamera: view.disableCamera,
        hangUp: view.hangUp,
      ));
  return true;
}

/// The screen share someone in the call is sharing (not yours), if any.
VoipStream? _shareOf(List<VoipStream> streams, String userId) {
  for (final s in streams) {
    if (_isRemoteShare(s) && s.streamUserId == userId) return s;
  }
  return null;
}

/// Whether [stream] (a person's voice tile) stays in the grid while that
/// person shares their screen: with stream watching, yes — their tile keeps
/// showing who talks and carries LIVE ([vommetWithLiveMark]) next to their
/// stream's own tile, as on Discord. Without it, the stream replaces them.
bool vommetKeepsVoiceTile(CallView view) =>
    VoipStreamWatching.of(view.currentSession) != null;

/// Wraps a person's voice tile with LIVE and a Watch chip while they share
/// their screen (stream watching only). The chip watches their stream and
/// makes it the big one; once you watch, it reads "watching" and focuses it.
Widget vommetWithLiveMark(CallView view, VoipStream stream,
    {required Widget child, required void Function(VoipStream? stream) focus}) {
  final session = view.currentSession;
  final watching = VoipStreamWatching.of(session);
  if (watching == null || stream.type != VoipStreamType.audio) return child;
  // Your own tile carries LIVE while you share (your stream has its own).
  if (stream.direction == VoipStreamDirection.outgoing) {
    if (!session.streams.any(_isOwnShare)) return child;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      const Positioned(left: 8, top: 8, child: StreamLivePill()),
    ]);
  }
  if (stream.direction != VoipStreamDirection.incoming) return child;
  final share = _shareOf(session.streams, stream.streamUserId);
  if (share == null) return child;
  final watched = watching.isWatching(share);
  return Stack(fit: StackFit.passthrough, children: [
    child,
    const Positioned(left: 8, top: 8, child: StreamLivePill()),
    Positioned(
      right: 8,
      top: watched ? null : 8,
      bottom: watched ? 8 : null,
      child: Tooltip(
        message: watched ? "Show their stream" : "Watch their stream",
        child: GestureDetector(
          onTap: () async {
            if (!watched) await watching.setWatching(share, true);
            focus(share);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: StreamOverlayTag(watched ? "watching" : "Watch",
                leading: watched ? Icons.visibility : Icons.play_arrow_rounded),
          ),
        ),
      ),
    ),
  ]);
}
