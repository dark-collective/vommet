import 'dart:async';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/member.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/live_person_tile.dart';
import 'package:commet/ui/organisms/call_view/multi_stream_focus.dart';
import 'package:commet/ui/organisms/call_view/own_stream_card.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:commet/ui/organisms/call_view/stream_viewers.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

// Vommet: Discord-style stream watching in the call view (experiment
// `vommet_experiment_stream_watching`, see [VoipStreamWatching]). The call
// view asks these for a tile first and keeps its own when they return null.

bool _isRemoteShare(VoipStream stream) =>
    stream.type == VoipStreamType.screenshare &&
    stream.direction == VoipStreamDirection.incoming;

bool _isOwnShare(VoipStream stream) =>
    stream.type == VoipStreamType.screenshare &&
    stream.direction == VoipStreamDirection.outgoing;

/// The tile for [stream]: in the grid, someone's screen share gets its own
/// stream tile ([StreamTile], as on Discord); big ([focused]), the share
/// with its controls while you watch it (a Watch card otherwise); null for
/// the call view's usual tile. [focus] makes a stream big alongside the
/// ones already big (null: back to the grid), [replace] makes it the only
/// big one ("Watch stream"). [othersBig]: another stream you watch is big
/// (the tile's small icon then watches side by side); [shownBig]: this one
/// is. With several streams big ([MultiStreamFocus]), [unfocus] takes just
/// this one out, [onShowBig] pins it big and [onSideBySide] goes back to
/// them all alike.
Widget? vommetStreamTile(CallView view, VoipStream stream,
    {required bool focused,
    required BuildContext context,
    required void Function(VoipStream? stream) focus,
    void Function(VoipStream stream)? replace,
    bool othersBig = false,
    bool shownBig = false,
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

  if (!focused) {
    return _VommetStreamTile(
        key: ValueKey("streamTile_${stream.streamId}"),
        session: session,
        stream: stream,
        watching: watching,
        othersBig: othersBig,
        shownBig: shownBig,
        focus: focus,
        replace: replace ?? focus);
  }

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
/// watching only) in LIVE, as on Discord ([LivePersonTile]). Their stream
/// has its own tile right after it ([vommetOrderStreamTiles]); a click on
/// the person shows the person big.
Widget vommetWithLiveMark(CallView view, VoipStream stream,
    {required Widget child}) {
  final session = view.currentSession;
  final watching = VoipStreamWatching.of(session);
  if (watching == null || stream.type != VoipStreamType.audio) return child;
  // Your own tile carries LIVE while you share (your stream has its own).
  if (stream.direction == VoipStreamDirection.outgoing) {
    if (!session.streams.any(_isOwnShare)) return child;
    return LivePersonTile(child: child);
  }
  if (stream.direction != VoipStreamDirection.incoming) return child;
  if (_shareOf(session.streams, stream.streamUserId) == null) return child;
  return LivePersonTile(child: child);
}

/// The grid's tiles in order (stream watching only): every screen share
/// right after its sharer's own tile, as on Discord. A share with no tile
/// of its sharer (a stream from a bot or a bridge) stays where it was.
List<VoipStream> vommetOrderStreamTiles(CallView view, List<VoipStream> shown) {
  if (VoipStreamWatching.of(view.currentSession) == null) return shown;
  bool isShare(VoipStream s) => s.type == VoipStreamType.screenshare;
  bool hasPerson(VoipStream share) =>
      shown.any((s) => !isShare(s) && s.streamUserId == share.streamUserId);
  final ordered = <VoipStream>[];
  for (var i = 0; i < shown.length; i++) {
    final s = shown[i];
    if (isShare(s) && hasPerson(s)) continue;
    ordered.add(s);
    if (isShare(s)) continue;
    // After this person's last tile (a camera and their voice tile).
    if (shown
        .skip(i + 1)
        .any((o) => !isShare(o) && o.streamUserId == s.streamUserId)) {
      continue;
    }
    ordered.addAll(
        shown.where((o) => isShare(o) && o.streamUserId == s.streamUserId));
  }
  return ordered;
}

/// "Watch stream" on a stream tile replaced the streams that were big
/// ([replaced]) with [kept]: stop watching those, as on Discord (one stream
/// at a time unless you add one side by side). One in the mini-player
/// keeps playing there.
void vommetStopWatchingReplaced(
    CallView view, Iterable<VoipStream> replaced, VoipStream kept) {
  final watching = VoipStreamWatching.of(view.currentSession);
  if (watching == null) return;
  final player = StreamMiniPlayer.instance;
  for (final s in replaced) {
    if (s == kept || !_isRemoteShare(s) || !watching.isWatching(s)) continue;
    if (player.showing && player.stream == s) continue;
    // Nor one in its own window.
    if (StreamPopoutWindow.maybeInstance?.isShowing(view.currentSession, s) ??
        false) {
      continue;
    }
    unawaited(watching.setWatching(s, false));
  }
}

/// Whether [stream] is a screen share you watch (another one then joins
/// it side by side).
bool vommetIsWatchedShare(CallView view, VoipStream? stream) {
  if (stream == null || !_isRemoteShare(stream)) return false;
  return VoipStreamWatching.of(view.currentSession)?.isWatching(stream) ??
      false;
}

/// Vommet issue 864: [child] (the stream tile of [stream]) with its sharer's
/// menu on a right-click, as on their own tile: their mic and stream volume
/// and the watch controls. Without it the right-click fell through to the
/// room's voice guide.
Widget vommetWithStreamMenu(
    VoipSession session, VoipStream stream, Member sharer,
    {required Widget child}) {
  List<tiamat.ContextMenuItem> items() => VoipStreamView.contextMenuItems(
      stream.participantId, sharer, session.streams,
      session: session);
  return AdaptiveContextMenu(items: items(), itemsBuilder: items, child: child);
}

/// Vommet: someone's screen share's own tile in the grid ([StreamTile]),
/// built from the call: their name and picture, a preview while there is
/// one (the stream itself once you watch it), who's watching, and whether
/// it plays in the mini-player.
class _VommetStreamTile extends StatelessWidget {
  const _VommetStreamTile(
      {required this.session,
      required this.stream,
      required this.watching,
      required this.othersBig,
      required this.shownBig,
      required this.focus,
      required this.replace,
      super.key});

  final VoipSession session;
  final VoipStream stream;
  final VoipStreamWatching watching;
  final bool othersBig;
  final bool shownBig;
  final void Function(VoipStream? stream) focus;
  final void Function(VoipStream stream) replace;

  Future<void> _small(StreamTileSmallAction action) async {
    await watching.setWatching(stream, true);
    final player = StreamMiniPlayer.instance;
    switch (action) {
      case StreamTileSmallAction.sideBySide:
        if (player.showing && player.stream == stream) player.hide();
        focus(stream);
      case StreamTileSmallAction.miniPlayer:
        await StreamPopoutWindow.maybeInstance?.closeIfShowing(stream);
        player.show(session, stream, poppedOut: true);
      case StreamTileSmallAction.popOutWindow:
        // The seam for the stream's own window; the mini-player until then.
        final open = StreamTile.popOutWindow;
        if (open != null) {
          await open(session, stream);
        } else {
          player.show(session, stream, poppedOut: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = StreamMiniPlayer.instance;
    final popout = StreamPopoutWindow.maybeInstance;
    return ListenableBuilder(
      listenable: Listenable.merge([player, popout]),
      builder: (context, _) {
        final inMini = player.showing &&
            player.session == session &&
            player.stream == stream;
        // Vommet: playing in its own window (StreamPopoutWindow).
        final inWindow = popout?.isShowing(session, stream) ?? false;
        final room = session.client.getRoom(session.roomId);
        final member = room?.getMemberOrFallback(stream.streamUserId);
        // Vommet issue 475: redacted mode.
        final redaction = RedactionScope.of(context);
        final name = redaction.name(
            member?.displayName ?? stream.streamUserId, stream.streamUserId);
        final color = redaction.nameColor(
            member?.defaultColor ?? Colors.blueGrey, stream.streamUserId);
        Widget avatar(double radius) => tiamat.Avatar(
            radius: radius,
            image: member?.avatar,
            placeholderColor: color,
            placeholderText: name,
            redactionKey: stream.streamUserId);
        final watched = watching.isWatching(stream);
        // The thumbnail: the stream itself once you watch it, else its
        // low-quality preview layer while the sharer sends one. Not while
        // it plays in the mini-player or big (one renderer at a time).
        final Widget? video = inMini || inWindow || shownBig
            ? null
            : watched
                ? stream.buildVideoRenderer(BoxFit.cover,
                    ValueKey("streamTileVideo_${stream.streamId}"))
                : watching.hasPreview(stream)
                    ? stream.buildVideoRenderer(BoxFit.cover,
                        ValueKey("streamTilePreview_${stream.streamId}"))
                    : null;
        final media = MediaQuery.of(context);
        final phone = media.mobile;
        final small =
            StreamTile.smallActionFor(othersBig: othersBig, phone: phone);
        final tile = StreamTile(
          name: name,
          avatar: avatar(9),
          background:
              video ?? StreamTilePlaceholder(color: color, avatar: avatar(28)),
          softenBackground: video != null && !watched,
          viewers: StreamViewers(session: session, stream: stream),
          state: shownBig
              ? StreamTileState.shownBig
              : inWindow
                  ? StreamTileState.inOwnWindow
                  : inMini
                      ? StreamTileState.inMiniPlayer
                      : StreamTileState.idle,
          small: small,
          alwaysShowButtons: phone || media.foldLayoutRules,
          onWatch: () async {
            await watching.setWatching(stream, true);
            if (player.showing && player.stream == stream) player.hide();
            await popout?.closeIfShowing(stream);
            replace(stream);
          },
          onSmall: () => _small(small),
          onShowHere: inWindow ? popout!.dockBack : player.dockBack,
        );
        // Phones keep the tile's long-press sheet.
        if (member == null || !media.desktop) return tile;
        return vommetWithStreamMenu(session, stream, member, child: tile);
      },
    );
  }
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
      // Shown big here now, not in its own window too.
      unawaited(StreamPopoutWindow.maybeInstance?.closeIfShowing(stream));
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

/// Stopping watching from outside the big tile (the long-press menu,
/// fullscreen) takes that stream out of the big view too. [update] changes
/// the call view's main stream (in its setState). Cancel the subscription
/// when the call view goes.
StreamSubscription? vommetFollowWatching(CallView view, MultiStreamFocus multi,
    void Function(VoipStream? Function(VoipStream? main)) update) {
  final watching = VoipStreamWatching.of(view.currentSession);
  if (watching == null) return null;
  return watching.onChanged.listen((_) => update((main) {
        final shown = [if (main != null) main, ...multi.others];
        for (final s in shown) {
          if (_isRemoteShare(s) && !watching.isWatching(s)) {
            main = multi.remove(main, s);
          }
        }
        return main;
      }));
}
