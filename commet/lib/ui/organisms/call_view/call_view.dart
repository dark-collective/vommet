import 'dart:async';
import 'package:commet/ui/atoms/clickable_gesture_detector.dart';
import 'package:commet/client/components/voip/camera_background_blur.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/fold_layout.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/layout/bento.dart';
import 'package:commet/ui/molecules/talk_button.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/call_view/voip_fullscreen_stream_view.dart';
import 'package:commet/ui/organisms/call_view/voip_stream_view.dart';
import 'package:commet/ui/organisms/call_view/multi_stream_focus.dart';
import 'package:commet/ui/organisms/call_view/vommet_call_view_streams.dart';
import 'package:commet/utils/animation/ring_shaker.dart';
import 'package:commet/utils/animation/ripple.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallView extends StatefulWidget {
  const CallView(
    this.currentSession, {
    this.setMicrophoneMute,
    this.pickScreenshareSource,
    this.stopScreenshare,
    this.pickCamera,
    this.disableCamera,
    this.hangUp,
    this.declineCall,
    this.acceptCall,
    super.key,
  });
  final VoipSession currentSession;

  static const Duration volumeAnimationDuration = Duration(milliseconds: 500);

  final Future<void> Function(bool)? setMicrophoneMute;
  final Future<void> Function()? pickScreenshareSource;
  final Future<void> Function()? stopScreenshare;
  final Future<void> Function()? pickCamera;
  final Future<void> Function()? disableCamera;
  final Future<void> Function()? hangUp;
  final Future<void> Function()? declineCall;
  final Future<void> Function()? acceptCall;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  final _streamsKey = GlobalKey();
  bool _muteBusy = false;

  Timer? statTimer;
  StreamSubscription? sub;
  StreamSubscription<void>? _blurSub;
  StreamSubscription? focusSub;
  StreamSubscription? _vommetWatchSub;
  bool isMouseHovering = false;
  VoipStream? mainStream;
  late Room room;

  // Vommet: who and what the focused stream was, kept while it is gone, so
  // focus follows a replacement (the sharer switched source: the old stream
  // is removed, a new one arrives). The view used to keep showing the
  // removed stream, which rendered nothing.
  String? _followUserId;
  VoipStreamType? _followType;

  // Vommet: the other streams you watch shown big with the main one.
  final MultiStreamFocus vommetMulti = MultiStreamFocus();

  void _vommetFocus(VoipStream? stream) {
    if (!mounted) return;
    setState(() => _setMainStream(stream));
  }

  void _vommetUpdate(VoipStream? Function(VoipStream? main) f) {
    setState(() => mainStream = f(mainStream));
  }

  void _followMainStream() {
    // Vommet: several streams big follow together.
    if (vommetMulti.isMulti) {
      mainStream = vommetMulti.follow(widget.currentSession, mainStream);
      return;
    }
    final streams = widget.currentSession.streams;
    final main = mainStream;
    if (main != null) {
      if (streams.contains(main)) return;
      _followUserId = main.streamUserId;
      _followType = main.type;
      mainStream = null;
    }
    if (_followUserId == null) return;
    for (final s in streams) {
      if (s.streamUserId == _followUserId && s.type == _followType) {
        mainStream = s;
        _followUserId = null;
        _followType = null;
        return;
      }
    }
    mainStream = vommetMulti.follow(widget.currentSession, mainStream);
  }

  // Vommet: "Watch stream" on a stream tile: it replaces the streams that
  // were big, as on Discord.
  void _vommetReplace(VoipStream stream) {
    if (!mounted) return;
    final replaced = [
      if (mainStream != null) mainStream!,
      ...vommetMulti.others
    ];
    setState(() {
      vommetMulti.clear();
      mainStream = stream;
      _followUserId = null;
      _followType = null;
    });
    vommetStopWatchingReplaced(widget, replaced, stream);
  }

  void _setMainStream(VoipStream? stream) {
    // Vommet: a stream you watch joins the ones already big.
    mainStream = vommetMulti.add(widget.currentSession, mainStream, stream);
    _followUserId = null;
    _followType = null;
  }

  @override
  void initState() {
    super.initState();
    sub = widget.currentSession.onStateChanged.listen((event) {
      setState(_followMainStream);
    });
    _blurSub = CameraBackgroundBlur.onChanged.listen((_) {
      if (mounted) setState(() {});
    });

    room = widget.currentSession.client.getRoom(widget.currentSession.roomId)!;
    vommetCallViewOpened(widget);
    focusSub = vommetFollowFocusRequests(widget, _vommetFocus);
    _vommetWatchSub = vommetFollowWatching(widget, vommetMulti, (f) {
      if (mounted) _vommetUpdate(f);
    });
    statTimer = Timer.periodic(const Duration(milliseconds: 200), timer);
  }

  @override
  void dispose() {
    statTimer?.cancel();
    sub?.cancel();
    _blurSub?.cancel();
    focusSub?.cancel();
    _vommetWatchSub?.cancel();
    vommetCallViewClosed(widget, mainStream);
    super.dispose();
  }

  void timer(Timer timer) async {
    await widget.currentSession.updateStats();
  }

  @override
  Widget build(BuildContext context) {
    return tiamat.Tile.lowest(
      child: switch (widget.currentSession.state) {
        VoipState.connected => callConnectedView(),
        VoipState.outgoing => callOutgoingView(),
        VoipState.connecting => callOutgoingView(),
        VoipState.ended => callEndedView(),
        VoipState.incoming => callIncomingView(),
        _ => const Placeholder()
      },
    );
  }

  Widget callOutgoingView() {
    return callButtons(
      canHangUp: true,
      child: Center(
        child: RippleAnimation(
          ripplesCount: 3,
          scale: 1,
          color: Theme.of(context).colorScheme.primary,
          repeat: true,
          child: Avatar.large(
              image: room.avatar,
              placeholderColor: room.defaultColor,
              placeholderText: room.displayName,
              redactionKey: RedactionScope.of(context).roomAvatarKey(room)),
        ),
      ),
    );
  }

  Widget callButtons(
      {bool canMute = false,
      bool canTalk = false,
      bool canScreenshare = false,
      bool canHangUp = false,
      bool canToggleCamera = false,
      required Widget child}) {
    Widget buttons(double buttonRadius) => callButtonRow(
        buttonRadius: buttonRadius,
        canMute: canMute,
        canTalk: canTalk,
        canScreenshare: canScreenshare,
        canHangUp: canHangUp,
        canToggleCamera: canToggleCamera);

    // Keeps the streams (and their renderers) alive when the layout below
    // changes with the device's posture.
    final streams = KeyedSubtree(key: _streamsKey, child: child);

    // Vommet: on a foldable standing half open like a laptop, the streams
    // fill the part above the fold and the buttons sit, larger and always
    // shown, on the part below it.
    return HorizontalFoldBuilder(builder: (context, foldY) {
      if (foldY != null) {
        return Column(
          children: [
            SizedBox(height: foldY, child: streams),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: buttons(32),
                ),
              ),
            ),
          ],
        );
      }

      final buttonRadius = MediaQuery.of(context).mobile ? 24.0 : 18.0;
      return MouseRegion(
        onEnter: (event) {
          setState(() {
            isMouseHovering = true;
          });
        },
        onExit: (event) {
          setState(() {
            isMouseHovering = false;
          });
        },
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            streams,
            AnimatedOpacity(
              // Vommet: an iPad or an unfolded foldable in the desktop layout
              // never hovers, so the buttons stay shown there.
              opacity: MediaQuery.of(context).mobile ||
                      MediaQuery.of(context).foldLayoutRules ||
                      isMouseHovering
                  ? 1
                  : 0,
              duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: buttons(buttonRadius),
              ),
            )
          ],
        ),
      );
    });
  }

  Widget callButtonRow(
      {required double buttonRadius,
      required bool canMute,
      required bool canTalk,
      required bool canScreenshare,
      required bool canHangUp,
      required bool canToggleCamera}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        if (canScreenshare)
          tiamat.CircleButton(
              radius: buttonRadius,
              icon: Icons.screen_share_outlined,
              onPressed: widget.pickScreenshareSource),
        if (widget.currentSession.isSharingScreen && canScreenshare)
          tiamat.CircleButton(
            radius: buttonRadius,
            icon: Icons.stop_screen_share,
            onPressed: widget.stopScreenshare,
          ),
        // Vommet: push to talk's hold-to-talk pill, in place of
        // the mic button.
        if (canTalk)
          TalkButton(widget.currentSession, height: buttonRadius * 2),
        if (canMute)
          // Vommet: red while muted (the two icons looked alike in
          // the same grey), and taps are ignored until a toggle has
          // gone through, since the first unmute publishes the
          // microphone and a second tap used to undo it.
          Tooltip(
            message:
                widget.currentSession.isMicrophoneMuted ? "Unmute" : "Mute",
            child: tiamat.CircleButton(
              radius: buttonRadius,
              icon: widget.currentSession.isMicrophoneMuted
                  ? Icons.mic_off
                  : Icons.mic,
              color: widget.currentSession.isMicrophoneMuted
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconColor: widget.currentSession.isMicrophoneMuted
                  ? Theme.of(context).colorScheme.onError
                  : null,
              onPressed: _muteBusy
                  ? null
                  : () async {
                      setState(() => _muteBusy = true);
                      try {
                        await widget.setMicrophoneMute
                            ?.call(!widget.currentSession.isMicrophoneMuted);
                      } finally {
                        if (mounted) {
                          setState(() => _muteBusy = false);
                        }
                      }
                    },
            ),
          ),
        if (canToggleCamera)
          tiamat.CircleButton(
            radius: buttonRadius,
            icon: widget.currentSession.isCameraEnabled
                ? Icons.no_photography
                : Icons.camera_alt_outlined,
            onPressed: widget.currentSession.isCameraEnabled
                ? widget.disableCamera
                : widget.pickCamera,
          ),
        // Vommet: background blur on and off while the camera is on (web,
        // with the Camera background blur experiment). The session restarts
        // the camera with or without it.
        if (canToggleCamera &&
            widget.currentSession.isCameraEnabled &&
            CameraBackgroundBlur.available)
          Tooltip(
            message: preferences.cameraBackgroundBlur.value
                ? "Stop blurring background"
                : "Blur background",
            child: tiamat.CircleButton(
              radius: buttonRadius,
              icon: preferences.cameraBackgroundBlur.value
                  ? Icons.blur_off
                  : Icons.blur_on,
              onPressed: () async {
                await preferences.cameraBackgroundBlur
                    .set(!preferences.cameraBackgroundBlur.value);
                CameraBackgroundBlur.turnedOffForSpeed = false;
                CameraBackgroundBlur.notifyChanged();
              },
            ),
          ),
        if (canHangUp)
          // Vommet: the icon used the grey secondary colour on the red
          // container, so the button looked disabled, and the theme's faint
          // hover tint didn't show on red (Vommet issue 579). Use the
          // container's own foreground for the icon and a visible hover and
          // press tint in that colour.
          Theme(
            data: Theme.of(context).copyWith(
              hoverColor: Theme.of(context)
                  .colorScheme
                  .onErrorContainer
                  .withValues(alpha: 0.12),
              highlightColor: Theme.of(context)
                  .colorScheme
                  .onErrorContainer
                  .withValues(alpha: 0.16),
            ),
            child: tiamat.CircleButton(
              color: Theme.of(context).colorScheme.errorContainer,
              iconColor: Theme.of(context).colorScheme.onErrorContainer,
              radius: buttonRadius,
              icon: Icons.call_end,
              onPressed: () async {
                await widget.hangUp?.call();
                setState(() {});
              },
            ),
          )
      ],
    );
  }

  Widget callConnectedView() {
    // Vommet: with push to talk the talk pill replaces the mic button.
    final pushToTalk = preferences.voipPushToTalk.value;
    return callButtons(
        canMute: !pushToTalk,
        canTalk: pushToTalk,
        canHangUp: true,
        canScreenshare: true,
        canToggleCamera: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            var ratio = constraints.maxWidth / constraints.maxHeight;

            if (ratio > 1 && mainStream == null) {
              return Row(children: generateLayout());
            } else {
              return Column(children: generateLayout());
            }
          },
        ));
  }

  Iterable<VoipStream> get visibleStreams {
    final shown = widget.currentSession.streams
        .where((i) => shouldShowAudioStream(i, widget.currentSession.streams))
        .where((element) => element.type != VoipStreamType.screenshareAudio)
        .toList();
    // Vommet: every share has its own tile, right after its sharer's tile
    // (which carries LIVE), as on Discord.
    return vommetOrderStreamTiles(widget, shown);
  }

  bool _shownBig(VoipStream stream) =>
      stream == mainStream || vommetMulti.others.contains(stream);

  List<Widget> generateLayout() {
    return [
      // Vommet: several streams you watch, big together.
      if (mainStream != null && vommetMulti.isMulti)
        Flexible(
          flex: 100,
          fit: FlexFit.tight,
          child: vommetMultiStreams(widget, vommetMulti, mainStream!,
                  context: context,
                  focus: _vommetFocus,
                  update: _vommetUpdate) ??
              const SizedBox(),
        ),
      if (mainStream != null && !vommetMulti.isMulti)
        Flexible(
          flex: 100,
          fit: FlexFit.tight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(2.0),
              child: ClickableGestureDetector(
                onTap: () {
                  setState(() {
                    _setMainStream(null);
                  });
                },
                child: vommetStreamTile(widget, mainStream!,
                        focused: true, context: context, focus: _vommetFocus) ??
                    VoipStreamView(
                      mainStream!,
                      widget.currentSession,
                      borderColor: Colors.white,
                      onFullscreen: () {
                        if (vommetOpenFullscreen(
                            widget, mainStream!, context)) {
                          return;
                        }
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    Scaffold(
                              backgroundColor: Colors.black,
                              body: VoipFullscreenStreamView(
                                session: widget.currentSession,
                                stream: mainStream!,
                              ),
                            ),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            fullscreenDialog: true,
                          ),
                        );
                      },
                      fit: BoxFit.contain,
                      key: ValueKey(
                          "callView_mainStreamView_${mainStream!.streamId}"),
                    ),
              ),
            ),
          ),
        ),
      if (visibleStreams.any((i) => !_shownBig(i)))
        Flexible(
          fit: FlexFit.tight,
          flex: mainStream == null ? 75 : 50,
          child: Center(
            child: BentoLayout(visibleStreams
                .where((element) => !_shownBig(element))
                .map((e) => ClickableGestureDetector(
                    onTap: () {
                      setState(() {
                        _setMainStream(e);
                      });
                    },
                    child: vommetStreamTile(widget, e,
                            focused: false,
                            context: context,
                            focus: _vommetFocus,
                            replace: _vommetReplace,
                            othersBig: vommetIsWatchedShare(widget, mainStream),
                            shownBig: _shownBig(e)) ??
                        vommetWithLiveMark(widget, e,
                            child: VoipStreamView(
                              key: ValueKey("callView__${e.streamId}"),
                              e,
                              fit: e.type == VoipStreamType.screenshare
                                  ? BoxFit.contain
                                  : BoxFit.cover,
                              widget.currentSession,
                              onFullscreen: () {
                                if (vommetOpenFullscreen(widget, e, context))
                                  return;
                                NavigationUtils.navigateTo(
                                  context,
                                  Scaffold(
                                    backgroundColor: Colors.black,
                                    body: VoipFullscreenStreamView(
                                      session: widget.currentSession,
                                      stream: e,
                                    ),
                                  ),
                                );
                              },
                            ))))
                .toList()),
          ),
        )
    ];
  }

  bool shouldShowAudioStream(VoipStream element, List<VoipStream> streams) {
    if (element.type == VoipStreamType.audio) {
      // Vommet: a screen share by person, not device (a camera stays
      // upstream's per device). A share published from another of their
      // devices (a second Vommet, a phone) showed their picture and the
      // stream as two separate tiles. With stream watching the person keeps
      // their tile while they share (it carries LIVE, vommetWithLiveMark), as
      // on Discord.
      final keepWhileSharing = vommetKeepsVoiceTile(widget);
      if (streams.any((i) =>
          (i.participantId == element.participantId &&
              i.type == VoipStreamType.video) ||
          (!keepWhileSharing &&
              i.streamUserId == element.streamUserId &&
              i.type == VoipStreamType.screenshare))) {
        {
          return false;
        }
      }

      return true;
    }

    return true;
  }

  Widget callEndedView() {
    return const Center(child: tiamat.Text.label("Call ended"));
  }

  Widget callIncomingView() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Center(
          child: RingShakerAnimation(
            child: Avatar.large(
                image: room.avatar,
                placeholderColor: room.defaultColor,
                placeholderText: room.displayName,
                redactionKey: RedactionScope.of(context).roomAvatarKey(room)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            spacing: 5,
            children: [
              tiamat.CircleButton(
                icon: Icons.call,
                onPressed: () async {
                  await widget.acceptCall?.call();
                  setState(() {});
                },
              ),
              tiamat.CircleButton(
                icon: Icons.call_end,
                onPressed: () async {
                  await widget.declineCall?.call();
                  setState(() {});
                },
              )
            ],
          ),
        ),
      ],
    );
  }
}
