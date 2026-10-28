import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet: the stream you watch, in a small floating player over the app,
/// as Discord's pop-out. It appears on its own when you leave the call view
/// while a stream is big there, or with Mini-player on the stream; Back to call
/// (or opening the call view again) docks it back.
class StreamMiniPlayer extends ChangeNotifier {
  StreamMiniPlayer._();

  static final StreamMiniPlayer instance = StreamMiniPlayer._();

  static String get miniPlayerBackToCall => Intl.message("Back to call",
      name: "miniPlayerBackToCall",
      desc:
          "Floating mini-player of a screen share you watch: button that goes back to the call and shows the stream there");

  static String get miniPlayerPopOut => Intl.message("Mini-player",
      name: "miniPlayerPopOut",
      desc:
          "Controls over a screen share you're watching: button that moves the stream into a small floating player");

  VoipSession? _session;
  VoipStream? _stream;
  bool _poppedOut = false;
  bool _fullscreen = false;
  StreamSubscription? _sub;
  final Map<VoipSession, int> _callViews = {};

  VoipSession? get session => _session;
  VoipStream? get stream => _stream;

  /// Whether the player is on screen (not while its stream is fullscreen).
  bool get showing => _session != null && _stream != null && !_fullscreen;

  /// Shows [stream] in the player. [poppedOut]: asked for with Mini-player (or a stream tile), so
  /// it stays when the call view opens again (Back to call docks it).
  void show(VoipSession session, VoipStream stream, {bool poppedOut = false}) {
    if (_session != session) {
      _sub?.cancel();
      _sub = session.onStateChanged.listen((_) => _follow());
    }
    _session = session;
    _stream = stream;
    _poppedOut = poppedOut;
    _fullscreen = false;
    notifyListeners();
  }

  void hide() {
    if (_session == null) return;
    _sub?.cancel();
    _sub = null;
    _session = null;
    _stream = null;
    _poppedOut = false;
    _fullscreen = false;
    notifyListeners();
  }

  /// Follows the sharer to a new stream when they switch what they share;
  /// goes away when they stop, you stop watching, or the call ends.
  void _follow() {
    final session = _session;
    final stream = _stream;
    if (session == null || stream == null) return;
    final watching = VoipStreamWatching.of(session);
    if (session.state == VoipState.ended || watching == null) {
      hide();
      return;
    }
    var current = stream;
    if (!session.streams.contains(stream)) {
      final next = session.streams.firstWhereOrNull((s) =>
          s.participantId == stream.participantId && s.type == stream.type);
      if (next == null) {
        hide();
        return;
      }
      current = next;
    }
    if (!watching.isWatching(current)) {
      hide();
      return;
    }
    if (current != stream) {
      _stream = current;
    }
    notifyListeners();
  }

  /// A call view of [session] opened: the stream goes back into it, unless
  /// it was popped out on purpose.
  void callViewOpened(VoipSession session) {
    _callViews.update(session, (n) => n + 1, ifAbsent: () => 1);
    if (_session == session && !_poppedOut) dockBack();
  }

  /// A call view of [session] closed while [focused] was big in it: a
  /// stream you watch goes on in the player.
  void callViewClosed(VoipSession session, VoipStream? focused) {
    final left = (_callViews[session] ?? 1) - 1;
    if (left > 0) {
      _callViews[session] = left;
      return;
    }
    _callViews.remove(session);
    if (focused == null || showing) return;
    final watching = VoipStreamWatching.of(session);
    if (watching == null ||
        session.state == VoipState.ended ||
        focused.type != VoipStreamType.screenshare ||
        focused.direction != VoipStreamDirection.incoming ||
        !session.streams.contains(focused) ||
        !watching.isWatching(focused)) {
      return;
    }
    show(session, focused);
  }

  /// Hides the player and asks the call view to show its stream big.
  void dockBack() {
    final session = _session;
    final stream = _stream;
    hide();
    if (session == null || stream == null) return;
    VoipStreamWatching.of(session)?.requestFocus(stream);
  }

  /// Opens the call's room with the stream big there.
  void backToCall() {
    final session = _session;
    if (session == null) return;
    _poppedOut = false;
    dockBack();
    EventBus.doOpenRoom(session.roomId, clientId: session.client.identifier);
  }

  Future<void> stopWatching() async {
    final session = _session;
    final stream = _stream;
    hide();
    if (session == null || stream == null) return;
    await VoipStreamWatching.of(session)?.setWatching(stream, false);
  }

  Future<void> openFullscreen() async {
    final session = _session;
    final stream = _stream;
    final context = navigator.currentContext;
    if (session == null || stream == null || context == null) return;
    _fullscreen = true;
    notifyListeners();
    await StreamFullscreenView.open(context, stream: stream, session: session);
    if (_session == session && _fullscreen) {
      _fullscreen = false;
      notifyListeners();
    }
  }
}

/// Vommet: draws the [StreamMiniPlayer] over the app.
class StreamMiniPlayerHost extends StatelessWidget {
  const StreamMiniPlayerHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final player = StreamMiniPlayer.instance;
    return Stack(children: [
      child,
      // Its own Overlay: the host sits above the Navigator's, and the
      // buttons' tooltips need one. Where the player isn't, touches go
      // through to the app.
      Positioned.fill(
        child: Overlay(initialEntries: [
          OverlayEntry(
            builder: (context) => ListenableBuilder(
              listenable: player,
              builder: (context, _) => player.showing
                  ? _FloatingStreamPlayer(
                      key: ValueKey("miniPlayer_${player.session.hashCode}"),
                      session: player.session!,
                      stream: player.stream!)
                  : const SizedBox.shrink(),
            ),
          ),
        ]),
      ),
    ]);
  }
}

class _FloatingStreamPlayer extends StatefulWidget {
  const _FloatingStreamPlayer(
      {required this.session, required this.stream, super.key});

  final VoipSession session;
  final VoipStream stream;

  @override
  State<_FloatingStreamPlayer> createState() => _FloatingStreamPlayerState();
}

class _FloatingStreamPlayerState extends State<_FloatingStreamPlayer> {
  /// Which corner it sits in (it snaps to the nearest after a drag).
  Alignment corner = Alignment.bottomRight;

  /// While dragging: the top-left corner, in the overlay.
  Offset? dragAt;
  bool controls = false;
  Timer? hideTimer;

  static const margin = 16.0;

  /// Clear of the message box at the bottom.
  static const bottomMargin = 84.0;

  @override
  void dispose() {
    hideTimer?.cancel();
    super.dispose();
  }

  void showControls() {
    hideTimer?.cancel();
    if (!controls) setState(() => controls = true);
  }

  void hideControlsSoon() {
    hideTimer?.cancel();
    hideTimer = Timer(WatchedStreamControls.hideAfter, () {
      if (mounted) setState(() => controls = false);
    });
  }

  /// [value] within [low]..[high]; [low] when the range is empty (a tiny
  /// window), where clamp would throw.
  static double fit(double value, double low, double high) =>
      high < low ? low : value.clamp(low, high).toDouble();

  Offset cornerOffset(Size area, Size size, Alignment corner) {
    final left = corner.x < 0 ? margin : area.width - size.width - margin;
    final top =
        corner.y < 0 ? margin : area.height - size.height - bottomMargin;
    return Offset(fit(left, 0, area.width - size.width),
        fit(top, 0, area.height - size.height));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final area = Size(box.maxWidth, box.maxHeight);
      final narrow = area.width < 600;
      final width = fit(narrow ? area.width * .55 : 340.0, 160, 340);
      final size = Size(width, width * 9 / 16);
      final at = dragAt ?? cornerOffset(area, size, corner);
      return Stack(children: [
        Positioned(
          left: at.dx,
          top: at.dy,
          width: size.width,
          height: size.height,
          child: GestureDetector(
            onPanStart: (_) => setState(() => dragAt = at),
            onPanUpdate: (d) => setState(() => dragAt = Offset(
                fit(dragAt!.dx + d.delta.dx, 0, area.width - size.width),
                fit(dragAt!.dy + d.delta.dy, 0, area.height - size.height))),
            onPanEnd: (_) {
              final centre = dragAt! + Offset(size.width / 2, size.height / 2);
              setState(() {
                corner = Alignment(centre.dx < area.width / 2 ? -1 : 1,
                    centre.dy < area.height / 2 ? -1 : 1);
                dragAt = null;
              });
            },
            onTap: () {
              if (controls) {
                setState(() => controls = false);
              } else {
                showControls();
                hideControlsSoon();
              }
            },
            onDoubleTap: StreamMiniPlayer.instance.openFullscreen,
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              onEnter: (_) => showControls(),
              onHover: (_) => showControls(),
              onExit: (_) => hideControlsSoon(),
              child: _player(context),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _player(BuildContext context) {
    final session = widget.session;
    final stream = widget.stream;
    final watching = VoipStreamWatching.of(session);
    final room = session.client.getRoom(session.roomId);
    final member = room?.getMemberOrFallback(stream.streamUserId);
    final redaction = RedactionScope.of(context);
    final name = redaction.name(
        member?.displayName ?? stream.streamUserId, stream.streamUserId);
    final roomName = room?.displayName;
    final muted = watching?.isStreamAudioMuted(stream) ?? false;
    final player = StreamMiniPlayer.instance;

    Widget button(IconData icon, String tooltip, VoidCallback onPressed,
            {Color? tint}) =>
        Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.black.withValues(alpha: .6),
            shape: const CircleBorder(),
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(icon, size: 18, color: tint ?? Colors.white)),
            ),
          ),
        );

    return Material(
      color: Colors.black,
      elevation: 10,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        Center(
            child: stream.buildVideoRenderer(BoxFit.contain,
                    ValueKey("miniPlayerRenderer_${stream.streamId}")) ??
                const CircularProgressIndicator()),
        IgnorePointer(
          ignoring: !controls,
          child: AnimatedOpacity(
            opacity: controls ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [
                    0,
                    .3,
                    .65,
                    1
                  ],
                      colors: [
                    Color(0xa0000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xa0000000),
                  ])),
              child: Stack(children: [
                Positioned(
                  left: 8,
                  top: 8,
                  right: 48,
                  child: Row(children: [
                    const StreamLivePill(size: 9),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(roomName == null ? name : "$name · $roomName",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ]),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: button(
                      Icons.close,
                      WatchedStreamControlsStrings.watchedStreamStopWatching,
                      player.stopWatching),
                ),
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Row(children: [
                    button(
                        Icons.login_rounded,
                        StreamMiniPlayer.miniPlayerBackToCall,
                        player.backToCall),
                    if (watching != null) ...[
                      const SizedBox(width: 6),
                      button(
                          muted ? Icons.volume_off : Icons.volume_up,
                          muted
                              ? WatchedStreamControlsStrings.watchedStreamUnmute
                              : WatchedStreamControlsStrings.watchedStreamMute,
                          () async {
                        await watching.setStreamAudioMuted(stream, !muted);
                        if (mounted) setState(() {});
                      }, tint: muted ? streamLiveRed : null),
                    ],
                  ]),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: button(
                      Icons.fullscreen,
                      WatchedStreamControlsStrings.watchedStreamFullscreen,
                      player.openFullscreen),
                ),
              ]),
            ),
          ),
        ),
        if (!controls && muted)
          const Positioned(
              right: 8,
              bottom: 8,
              child: Icon(Icons.volume_off, size: 16, color: Colors.white)),
      ]),
    );
  }
}
