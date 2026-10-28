import 'dart:async';

import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/live_person_tile.dart';
import 'package:commet/ui/organisms/call_view/multi_stream_focus.dart';
import 'package:commet/ui/organisms/call_view/own_stream_card.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
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
/// makes a stream the big one (null: back to the grid). With several
/// streams big ([MultiStreamFocus]), [unfocus] takes just this one out,
/// [onShowBig] pins it big and [onSideBySide] goes back to them all alike.
Widget? vommetStreamTile(CallView view, VoipStream stream,
    {required bool focused,
    required BuildContext context,
    required void Function(VoipStream? stream) focus,
    VoidCallback? unfocus,
    VoidCallback? onShowBig,
    VoidCallback? onSideBySide}) {
  final remove = unfocus ?? () => focus(null);
  final session = view.currentSession;
  final watching = VoipStreamWatching.of(session);
  // Your own share: its own dimmed tile with Stop streaming, as on Discord;
  // tapping it shows it big (the call view's usual tile).
  if (watching != null && _isOwnShare(stream) && !focused) {
    return OwnStreamCard(
        key: ValueKey("ownStreamCard_${stream.streamId}"),
        stream: stream,
        session: session,
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
      remove();
    },
    onFullscreen: () => vommetOpenFullscreen(view, stream, context),
    onPopOut: () {
      StreamMiniPlayer.instance.show(session, stream, poppedOut: true);
      remove();
    },
    onShowBig: onShowBig,
    onSideBySide: onSideBySide,
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

/// Wraps a person's voice tile while they share their screen (stream
/// watching only): LIVE, and a click anywhere on the tile watches their
/// stream and makes it the big one, as on Discord ([LivePersonTile]).
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
  return LivePersonTile(
    watched: watched,
    onOpen: () async {
      if (!watched) await watching.setWatching(share, true);
      focus(share);
    },
    child: child,
  );
}

/// Whether the tile of someone's screen share is left out of the grid
/// (stream watching only): while you don't watch it and their own tile is
/// in the grid ([shown]), that tile is the way in, as on Discord. A share
/// with no tile of its sharer next to it (a stream from a bot or a bridge)
/// keeps its card.
bool vommetHidesStreamTile(
    CallView view, VoipStream stream, Iterable<VoipStream> shown) {
  final watching = VoipStreamWatching.of(view.currentSession);
  if (watching == null || !_isRemoteShare(stream)) return false;
  if (watching.isWatching(stream)) return false;
  return shown.any((s) =>
      s.type == VoipStreamType.audio &&
      s.direction == VoipStreamDirection.incoming &&
      s.streamUserId == stream.streamUserId);
}

/// Shows big the streams asked for from outside the call view (the
/// sidebar's Watch, [VoipStreamWatching.requestFocus]): one asked for
/// before the call view opened at once, later ones as they come. Cancel
/// the subscription when the call view goes.
StreamSubscription? vommetFollowFocusRequests(
    CallView view, void Function(VoipStream stream) focus) {
  final watching = VoipStreamWatching.of(view.currentSession);
  if (watching == null) return null;
  void take() {
    final stream = watching.takeFocusRequest();
    if (stream != null && view.currentSession.streams.contains(stream)) {
      focus(stream);
    }
  }

  // After initState (the caller can't setState in it).
  scheduleMicrotask(take);
  return watching.onFocusRequest.listen((_) => take());
}

/// A call view opened: a stream in the mini-player docks back into it
/// (stream watching only). Call before [vommetFollowFocusRequests].
void vommetCallViewOpened(CallView view) {
  if (VoipStreamWatching.of(view.currentSession) == null) return;
  StreamMiniPlayer.instance.callViewOpened(view.currentSession);
}

/// A call view closed with [focused] big in it: a stream you watch goes on
/// in the mini-player, as on Discord.
void vommetCallViewClosed(CallView view, VoipStream? focused) {
  if (VoipStreamWatching.of(view.currentSession) == null) return;
  StreamMiniPlayer.instance.callViewClosed(view.currentSession, focused);
}

/// The streams shown big when you watch several at once ([multi]), or null
/// when [main] is the only one. [update] changes the call view's main
/// stream (in its setState).
Widget? vommetMultiStreams(
    CallView view, MultiStreamFocus multi, VoipStream main,
    {required BuildContext context,
    required void Function(VoipStream? stream) focus,
    required void Function(VoipStream? Function(VoipStream? main)) update}) {
  if (!multi.isMulti) return null;
  void showBig(VoipStream s) => update((m) => multi.showBig(m, s));
  return MultiStreamLayout(
    focus: multi,
    main: main,
    session: view.currentSession,
    onShowBig: showBig,
    tile: (s) {
      final big = multi.pinned && s == main;
      return vommetStreamTile(view, s,
              focused: true,
              context: context,
              focus: focus,
              unfocus: () => update((m) => multi.remove(m, s)),
              onShowBig: big ? null : () => showBig(s),
              onSideBySide: big
                  ? () => update((m) {
                        multi.pinned = false;
                        return m;
                      })
                  : null) ??
          VoipStreamView(s, view.currentSession,
              canFullscreen: false, fit: BoxFit.contain);
    },
  );
}
