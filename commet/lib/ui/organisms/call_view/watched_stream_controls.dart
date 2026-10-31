import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/rtc_screen_share_annotation/rtc_screen_share_annotation_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/molecules/call_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:window_manager/window_manager.dart';
import 'package:intl/intl.dart';

/// Vommet: your own call buttons, for the fullscreen stream view.
class StreamCallActions {
  const StreamCallActions({
    this.setMicrophoneMute,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
  });

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
}

/// Vommet: a stream you're watching, with Discord-style controls that stay
/// out of the way: they show when you start watching, then fade after a
/// few seconds. Moving the mouse brings them back (and they stay while the
/// pointer is over them); a click or tap brings them back (or hides them);
/// a double-click toggles fullscreen.
class WatchedStreamControls extends StatefulWidget {
  const WatchedStreamControls({
    required this.stream,
    required this.session,
    required this.child,
    this.watching,
    this.onStopWatching,
    this.onFullscreen,
    this.fullscreen = false,
    this.actions,
    super.key,
  });

  final VoipStream stream;
  final VoipSession session;
  final VoipStreamWatching? watching;
  final Widget child;
  final VoidCallback? onStopWatching;

  /// Enters fullscreen, or leaves it when [fullscreen].
  final VoidCallback? onFullscreen;
  final bool fullscreen;

  /// Your own call buttons, shown in fullscreen.
  final StreamCallActions? actions;

  static const Duration hideAfter = Duration(seconds: 3);

  @override
  State<WatchedStreamControls> createState() => _WatchedStreamControlsState();
}

class _WatchedStreamControlsState extends State<WatchedStreamControls> {
  String get watchedStreamExitHintTouch => Intl.message(
      "Double-tap to exit fullscreen",
      name: "watchedStreamExitHintTouch",
      desc:
          "Controls over a screen share you're watching: hint shown when entering fullscreen on a phone");

  String get watchedStreamExitHintDesktop => Intl.message(
      "Press Esc or double-click to exit fullscreen",
      name: "watchedStreamExitHintDesktop",
      desc:
          "Controls over a screen share you're watching: hint shown when entering fullscreen on a computer");

  String get watchedStreamMute => Intl.message("Mute stream",
      name: "watchedStreamMute",
      desc:
          "Controls over a screen share you're watching: tooltip on the button that mutes the stream's audio");

  String get watchedStreamUnmute => Intl.message("Unmute stream",
      name: "watchedStreamUnmute",
      desc:
          "Controls over a screen share you're watching: tooltip on the button that unmutes the stream's audio");

  String get watchedStreamFullscreen => Intl.message("Fullscreen",
      name: "watchedStreamFullscreen",
      desc:
          "Controls over a screen share you're watching: tooltip on the fullscreen button");

  String get watchedStreamExitFullscreen => Intl.message("Exit fullscreen",
      name: "watchedStreamExitFullscreen",
      desc:
          "Controls over a screen share you're watching: tooltip on the fullscreen button while fullscreen");

  String get watchedStreamStopWatching => Intl.message("Stop watching",
      name: "watchedStreamStopWatching",
      desc:
          "Controls over a screen share you're watching: button and tooltip that stops watching the stream");

  String get watchedStreamShowCursor => Intl.message(
      "Show your cursor to the sharer",
      name: "watchedStreamShowCursor",
      desc:
          "Controls over a screen share you're watching: tooltip on the button that shows your mouse pointer on the sharer's screen");

  String get watchedStreamStopSharing => Intl.message("Stop sharing",
      name: "watchedStreamStopSharing",
      desc:
          "Controls over a screen share you're watching: tooltip on the button that stops your own screen share");

  bool _visible = true;
  bool _hint = false;

  /// The mouse is over one of the control bars: don't hide them under it.
  bool _overControls = false;
  Timer? _hideTimer;
  Timer? _hintTimer;
  StreamSubscription? _sub;
  StreamSubscription? _levels;

  @override
  void initState() {
    super.initState();
    _sub = widget.session.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    // Who's talking, for the fullscreen view's row of people.
    if (widget.fullscreen) {
      _levels = widget.session.onUpdateVolumeVisualizers.listen((_) {
        if (mounted && _visible) setState(() {});
      });
    }
    _scheduleHide();
    if (widget.fullscreen) {
      _hint = true;
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _hint = false);
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _sub?.cancel();
    _levels?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_overControls) return;
    _hideTimer = Timer(WatchedStreamControls.hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggle() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// Any use of a control keeps them up a while longer.
  void _poke() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  /// Keeps the controls up while the mouse is over [child].
  Widget _holdWhileHovered(Widget child) => MouseRegion(
        onEnter: (_) {
          _overControls = true;
          _hideTimer?.cancel();
        },
        onExit: (_) {
          _overControls = false;
          _scheduleHide();
        },
        child: child,
      );

  VoipStream? get _audio => widget.session.streams.firstWhereOrNull((s) =>
      s.participantId == widget.stream.participantId &&
      s.type == VoipStreamType.screenshareAudio);

  @override
  Widget build(BuildContext context) {
    final room = widget.session.client.getRoom(widget.session.roomId);
    final member = room?.getMemberOrFallback(widget.stream.streamUserId);
    final name = member?.displayName ?? widget.stream.streamUserId;
    final audio = _audio;
    final muted = audio != null &&
        (widget.watching?.isStreamAudioMuted(widget.stream) ?? false);
    final isShare = widget.stream.type == VoipStreamType.screenshare;

    Widget overlay(Widget child) => IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: child),
        );

    return MouseRegion(
      // In fullscreen the pointer hides with the controls.
      cursor: widget.fullscreen && !_visible
          ? SystemMouseCursors.none
          : MouseCursor.defer,
      // Moving the mouse brings the controls (and the pointer) back, as
      // in Discord; before, only a click did. Touches don't hover.
      onHover: (_) => _poke(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onDoubleTap: widget.onFullscreen,
        child: Stack(fit: StackFit.expand, children: [
          widget.child,
          if (widget.fullscreen)
            overlay(const IgnorePointer(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [
                    0,
                    .14,
                    .8,
                    1
                  ],
                          colors: [
                    Color(0x8c000000),
                    Colors.transparent,
                    Colors.transparent,
                    Color(0x99000000),
                  ]))),
            )),
          Positioned(
            left: 10,
            top: 10,
            right: widget.fullscreen ? 220 : 10,
            child: overlay(Row(children: [
              if (isShare) ...[
                const StreamLivePill(),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: StreamOverlayTag(name,
                    leading: isShare ? Icons.screen_share : Icons.videocam,
                    trailing: muted ? Icons.volume_off : null),
              ),
            ])),
          ),
          if (widget.fullscreen)
            Positioned(right: 16, top: 12, child: overlay(_callPeople())),
          if (widget.fullscreen && widget.actions != null)
            Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child:
                    overlay(Center(child: _holdWhileHovered(_ownCallBar())))),
          Positioned(
            right: 10,
            bottom: widget.fullscreen ? 16 : 10,
            child: overlay(_holdWhileHovered(Listener(
              onPointerDown: (_) => _poke(),
              child: _streamBar(audio, muted),
            ))),
          ),
          if (_hint)
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                        PlatformUtils.isAndroid
                            ? watchedStreamExitHintTouch
                            : watchedStreamExitHintDesktop,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _bar(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .75),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _button(IconData icon, String tooltip, VoidCallback? onPressed,
          {Color? tint}) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: tint?.withValues(alpha: .25) ?? Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed == null
                ? null
                : () {
                    _poke();
                    onPressed();
                  },
            child: SizedBox(
                width: 34,
                height: 32,
                child: Icon(icon, size: 19, color: tint ?? Colors.white)),
          ),
        ),
      );

  Widget _streamBar(VoipStream? audio, bool muted) {
    final watching = widget.watching;
    return LayoutBuilder(builder: (context, _) {
      final wide = MediaQuery.of(context).size.width > 700;
      return _bar([
        if (audio != null && watching != null)
          _button(muted ? Icons.volume_off : Icons.volume_up,
              muted ? watchedStreamUnmute : watchedStreamMute, () async {
            await watching.setStreamAudioMuted(widget.stream, !muted);
            if (mounted) setState(() {});
          }, tint: muted ? streamLiveRed : null),
        if (audio != null && !muted && wide)
          SizedBox(
            width: 110,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                  trackHeight: 3),
              child: Slider(
                min: 0,
                max: 2.5,
                value: audio.volume.clamp(0.0, 2.5).toDouble(),
                onChanged: (v) {
                  _poke();
                  setState(() => audio.setVolume(v));
                },
              ),
            ),
          ),
        if (widget.fullscreen) _annotationButton(),
        _button(
            widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
            widget.fullscreen
                ? watchedStreamExitFullscreen
                : watchedStreamFullscreen,
            widget.onFullscreen),
        if (widget.onStopWatching != null) ...[
          Container(
              width: 1,
              height: 20,
              color: Colors.white24,
              margin: const EdgeInsets.symmetric(horizontal: 4)),
          Tooltip(
            message: watchedStreamStopWatching,
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onStopWatching,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.close, size: 18, color: Colors.white),
                  if (wide) ...[
                    const SizedBox(width: 4),
                    Text(watchedStreamStopWatching,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  ],
                ]),
              ),
            ),
          ),
        ],
      ]);
    });
  }

  /// Upstream's shared-cursor button from the old fullscreen view.
  Widget _annotationButton() {
    final component =
        widget.session.client.getComponent<RTCScreenShareAnnotationComponent>();
    if (component == null) return const SizedBox.shrink();
    return _button(Icons.mouse, watchedStreamShowCursor, () async {
      await component.getOrCreateSession(widget.session);
    });
  }

  /// Who's in the call, lit up while they talk.
  Widget _callPeople() {
    final room = widget.session.client.getRoom(widget.session.roomId);
    final audio = <String, VoipStream>{
      for (final s in widget.session.streams)
        if (s.type == VoipStreamType.audio) s.streamUserId: s
    };
    final users = audio.keys.take(8);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final id in users)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Builder(builder: (context) {
            final m = room?.getMemberOrFallback(id);
            final talking = (audio[id]?.audiolevel ?? 0) > 0;
            return Tooltip(
              message: m?.displayName ?? id,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: talking ? const Color(0xff23a55a) : Colors.black54),
                child: tiamat.Avatar(
                    radius: 13,
                    image: m?.avatar,
                    placeholderColor: m?.defaultColor,
                    placeholderText: m?.displayName ?? id),
              ),
            );
          }),
        ),
    ]);
  }

  Widget _ownCallBar() {
    final a = widget.actions!;
    final session = widget.session;
    final calls = clientManager?.callManager;
    final micOff = session.isMicrophoneMuted;
    final deafened = calls?.isDeafenedIn(session) ?? false;
    return Listener(
      onPointerDown: (_) => _poke(),
      child: _bar([
        _button(
            micOff ? Icons.mic_off : Icons.mic,
            micOff
                ? CallControlStrings.callControlUnmute
                : CallControlStrings.callControlMute, () async {
          await a.setMicrophoneMute?.call(!micOff);
          if (mounted) setState(() {});
        }, tint: micOff ? streamLiveRed : null),
        if (calls != null)
          _button(
              deafened ? Icons.headset_off : Icons.headset,
              deafened
                  ? CallControlStrings.callControlUndeafen
                  : CallControlStrings.callControlDeafen, () {
            calls.toggleDeafenIn(session);
            setState(() {});
          }, tint: deafened ? streamLiveRed : null),
        _button(
            session.isCameraEnabled
                ? Icons.no_photography
                : Icons.camera_alt_outlined,
            session.isCameraEnabled
                ? CallControlStrings.callControlTurnOffCamera
                : CallControlStrings.callControlTurnOnCamera,
            session.isCameraEnabled ? a.disableCamera : a.pickCamera),
        _button(
            session.isSharingScreen
                ? Icons.stop_screen_share
                : Icons.screen_share_outlined,
            session.isSharingScreen
                ? watchedStreamStopSharing
                : CallControlStrings.callControlShareScreen,
            session.isSharingScreen
                ? a.stopScreenshare
                : a.pickScreenshareSource),
        const SizedBox(width: 4),
        Tooltip(
          message: CallControlStrings.callControlLeaveCall,
          child: Material(
            color: const Color(0xff8c1d18),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                Navigator.of(context).maybePop();
                await a.hangUp?.call();
              },
              child: const SizedBox(
                  width: 40,
                  height: 30,
                  child: Icon(Icons.call_end, size: 18, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Vommet: a stream in real fullscreen. On desktop the window goes
/// fullscreen (and back to how it was afterwards); on phones the system
/// bars hide. Esc or a double-click leaves.
class StreamFullscreenView extends StatefulWidget {
  const StreamFullscreenView(
      {required this.stream, required this.session, this.actions, super.key});

  final VoipStream stream;
  final VoipSession session;
  final StreamCallActions? actions;

  static bool get _desktopWindow =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  static Future<void> open(BuildContext context,
      {required VoipStream stream,
      required VoipSession session,
      StreamCallActions? actions}) async {
    bool wasFullscreen = false;
    try {
      if (_desktopWindow) {
        wasFullscreen = await windowManager.isFullScreen();
        if (!wasFullscreen) await windowManager.setFullScreen(true);
      } else if (PlatformUtils.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not enter fullscreen");
    }
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (_, __, ___) => StreamFullscreenView(
          stream: stream, session: session, actions: actions),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
    try {
      if (_desktopWindow) {
        if (!wasFullscreen) await windowManager.setFullScreen(false);
      } else if (PlatformUtils.isAndroid) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not leave fullscreen");
    }
  }

  @override
  State<StreamFullscreenView> createState() => _StreamFullscreenViewState();
}

class _StreamFullscreenViewState extends State<StreamFullscreenView> {
  late VoipStream stream = widget.stream;
  StreamSubscription? _sub;
  RTCScreenShareAnnotationSession? _annotation;

  /// The shared cursor, once it was switched on with its button.
  RTCScreenShareAnnotationSession? get _cursor =>
      _annotation ??= widget.session.client
          .getComponent<RTCScreenShareAnnotationComponent>()
          ?.getExistingSession(widget.session);

  @override
  void initState() {
    super.initState();
    _sub = widget.session.onStateChanged.listen((_) => _follow());
  }

  /// Follows the sharer to a new stream when they switch what they share;
  /// closes when they stop, or when the call ends.
  void _follow() {
    if (!mounted) return;
    final streams = widget.session.streams;
    if (widget.session.state == VoipState.ended) {
      Navigator.of(context).maybePop();
      return;
    }
    if (streams.contains(stream)) return;
    final next = streams.firstWhereOrNull((s) =>
        s.participantId == stream.participantId && s.type == stream.type);
    if (next == null) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => stream = next);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watching = VoipStreamWatching.of(widget.session);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.black,
          child: LayoutBuilder(builder: (context, box) {
            return MouseRegion(
              onHover: (event) => _cursor?.setCursorPosition(
                  streamId: stream.streamId,
                  x: event.localPosition.dx / box.maxWidth,
                  y: event.localPosition.dy / box.maxHeight),
              child: WatchedStreamControls(
                key: ValueKey("fullscreen_${stream.streamId}"),
                stream: stream,
                session: widget.session,
                watching: watching,
                fullscreen: true,
                actions: widget.actions,
                onFullscreen: () => Navigator.of(context).maybePop(),
                child: Center(
                    child: stream.buildVideoRenderer(
                            BoxFit.contain,
                            ValueKey(
                                "fullscreenRenderer_${stream.streamId}")) ??
                        const CircularProgressIndicator()),
              ),
            );
          }),
        ),
      ),
    );
  }
}
