import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/member.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/bridged_user_marker.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/call_view/call_view.dart';
import 'package:commet/ui/organisms/call_view/stream_popout_window.dart';
import 'package:commet/ui/organisms/call_view/stream_sheet_items.dart';
import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipStreamView extends StatefulWidget {
  const VoipStreamView(this.stream, this.session,
      {super.key,
      this.fit = BoxFit.cover,
      this.borderColor,
      this.canFullscreen = true,
      this.onFullscreen});
  final VoipStream stream;
  final VoipSession session;
  final BoxFit fit;
  final Function()? onFullscreen;
  final Color? borderColor;
  final bool canFullscreen;

  /// Vommet issue 864: the menu of [participantId]'s tile, for a stream
  /// tile of theirs too.
  static List<tiamat.ContextMenuItem> contextMenuItems(
          String participantId, Member user, List<VoipStream> streams,
          {VoipSession? session}) =>
      _VoipStreamViewState.streamContextMenuItems(participantId, user, streams,
          session: session);

  @override
  State<VoipStreamView> createState() => _VoipStreamViewState();
}

class _VoipStreamViewState extends State<VoipStreamView>
    with TickerProviderStateMixin {
  late Member user;
  bool _hovered = false;
  bool _focused = false;
  StreamPopoutWindow? get popouts => StreamPopoutWindow.maybeInstance;
  void _popoutChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _popCamera() async {
    final opened = await popouts?.openCamera(widget.session, widget.stream);
    if (opened == CameraPopoutResult.failed && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(cameraWindowFailed)));
    }
  }

  static String get cameraWindowFailed => Intl.message(
      "Could not open the camera window. The camera is still in the call.",
      name: "cameraWindowFailed",
      desc:
          "A native camera window failed to open; the camera remains in the call view");

  late AnimationController audioLevel;
  List<StreamSubscription> subs = [];

  late GlobalKey rendererKey = GlobalKey();

  @override
  void initState() {
    popouts?.addListener(_popoutChanged);
    Log.d("Initializing stream view!");
    _bindStream();

    audioLevel = AnimationController(
        vsync: this, duration: CallView.volumeAnimationDuration);
    super.initState();
  }

  void _bindStream() {
    for (final sub in subs) {
      sub.cancel();
    }
    final room = widget.session.client.getRoom(widget.session.roomId)!;
    user = room.getMemberOrFallback(widget.stream.streamUserId);
    subs = [
      widget.stream.onStreamChanged.listen(onStreamChanged),
      widget.session.onUpdateVolumeVisualizers.listen((_) => timer())
    ];
  }

  @override
  void didUpdateWidget(covariant VoipStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stream, widget.stream) ||
        !identical(oldWidget.session, widget.session)) _bindStream();
  }

  @override
  void dispose() {
    popouts?.removeListener(_popoutChanged);
    audioLevel.dispose();
    for (var sub in subs) sub.cancel();
    super.dispose();
  }

  void timer() {
    audioLevel.animateTo(_level);
  }

  /// Vommet: a camera or screen share lights up while its person talks,
  /// from their microphone (on whichever device), since the video itself
  /// has no level.
  double get _level {
    final stream = widget.stream;
    if (stream.type != VoipStreamType.video &&
        stream.type != VoipStreamType.screenshare) {
      return stream.audiolevel;
    }
    var level = stream.audiolevel;
    for (final s in widget.session.streams) {
      if (s.type == VoipStreamType.audio &&
          s.streamUserId == stream.streamUserId &&
          s.audiolevel > level) {
        level = s.audiolevel;
      }
    }
    return level;
  }

  @override
  Widget build(BuildContext context) {
    final camera =
        widget.stream.type == VoipStreamType.video && popouts != null;
    final window =
        camera ? popouts!.cameraFor(widget.session, widget.stream) : null;
    if (window != null)
      return CameraPopoutPlaceholder(
          name: RedactionScope.of(context)
              .name(user.displayName, user.identifier),
          mark: BridgedUserMarker(
              client: widget.session.client,
              userId: user.identifier,
              room: widget.session.client.getRoom(widget.session.roomId),
              size: 12,
              inCall: true),
          onDockBack: window.dockBack);
    final tile = AnimatedBuilder(
        animation: audioLevel,
        builder: (context, child) {
          return Material(
            color: Colors.transparent,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                AdaptiveContextMenu(
                  items: _menuItems(
                      widget.stream.participantId, user, widget.session.streams,
                      session: widget.session),
                  // Vommet: fresh when it opens (watching, muted).
                  itemsBuilder: () => _menuItems(
                      widget.stream.participantId, user, widget.session.streams,
                      session: widget.session),
                  child: Container(
                      clipBehavior: Clip.antiAlias,
                      foregroundDecoration: widget.borderColor != null
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: widget.borderColor!,
                                  width: 2,
                                  strokeAlign: BorderSide.strokeAlignCenter))
                          : null,
                      decoration:
                          BoxDecoration(borderRadius: BorderRadius.circular(8)),
                      child: buildDefault()),
                ),
                // Vommet issue 853: the name, and the network mark of
                // bridged people (Discord for the voice bridge's).
                if (widget.stream.type == VoipStreamType.audio ||
                    widget.stream.type == VoipStreamType.video)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: CallTileNameLabel(
                        name: RedactionScope.of(context)
                            .name(user.displayName, user.identifier),
                        mark: BridgedUserMarker(
                            client: widget.session.client,
                            userId: user.identifier,
                            room: widget.session.client
                                .getRoom(widget.session.roomId),
                            size: 12,
                            inCall: true),
                      ),
                    ),
                  ),
                if (preferences.developerMode.value)
                  Align(
                    alignment: AlignmentGeometry.topLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ColorScheme.of(context).surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: tiamat.Text.labelLow(widget.stream.stats),
                      ),
                    ),
                  ),
                // Vommet: parenthesised; canFullscreen: false didn't hide
                // the button on screen shares.
                if (widget.canFullscreen &&
                    (widget.stream.type == VoipStreamType.video ||
                        widget.stream.type == VoipStreamType.screenshare))
                  _tileActions(camera),
                if (camera && !widget.canFullscreen)
                  _tileActions(true, fullscreen: false),
              ],
            ),
          );
        });
    if (!camera) return tile;
    return Focus(
        onFocusChange: (focused) {
          if (mounted) setState(() => _focused = focused);
        },
        child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: tile));
  }

  Widget _tileActions(bool camera, {bool fullscreen = true}) {
    final visible = !camera ||
        _hovered ||
        _focused ||
        MediaQuery.accessibleNavigationOf(context);
    return AnimatedOpacity(
        opacity: visible ? 1 : 0,
        alwaysIncludeSemantics: true,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
            ignoring: !visible,
            child: Material(
                color: camera ? Colors.black54 : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (camera)
                    IconButton(
                        key: const ValueKey("cameraPopOut"),
                        color: Colors.white,
                        tooltip: StreamTile.streamTilePopOutWindow,
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: _popCamera,
                        icon: const Icon(Icons.open_in_new)),
                  if (fullscreen)
                    SizedBox(
                        width: camera ? 48 : 40,
                        height: camera ? 48 : 40,
                        child: tiamat.IconButton(
                            icon: Icons.fullscreen,
                            size: 20,
                            iconColor: camera ? Colors.white : null,
                            onPressed: widget.onFullscreen)),
                ]))));
  }

  List<tiamat.ContextMenuItem> _menuItems(
          String participantId, Member user, List<VoipStream> streams,
          {VoipSession? session}) =>
      [
        if (widget.stream.type == VoipStreamType.video && popouts != null)
          tiamat.ContextMenuItem(
              text: StreamTile.streamTilePopOutWindow,
              icon: Icons.open_in_new,
              onPressed: _popCamera),
        ...streamContextMenuItems(participantId, user, streams,
            session: session),
      ];

  /// Vommet: with [session] (and stream watching on), someone sharing
  /// their screen gets LIVE, Mute stream and Stop watching (or Watch
  /// stream) too, from their own tile and from their stream's tile.
  static List<tiamat.ContextMenuItem> streamContextMenuItems(
      String participantId, Member user, List<VoipStream> streams,
      {VoipSession? session}) {
    var incoming = streams.where((i) =>
        i.direction == VoipStreamDirection.incoming &&
        i.participantId == participantId);

    if (incoming.isEmpty) return [];

    // Vommet: a stream can come from another device than the voice (a
    // bridged share), so the rest is found by user too.
    final share = session == null
        ? null
        : StreamSheetItems.shareOf(session, user.identifier);
    final ofUser = streams.where((i) =>
        i.direction == VoipStreamDirection.incoming &&
        i.streamUserId == user.identifier);
    var audioStream = incoming
            .firstWhereOrNull((i) => i.type == VoipStreamType.audio) ??
        (share == null
            ? null
            : ofUser.firstWhereOrNull((i) => i.type == VoipStreamType.audio));

    var screenShareAudioStream = share == null
        ? incoming
            .firstWhereOrNull((i) => i.type == VoipStreamType.screenshareAudio)
        : VoipStreamWatching.of(session!)!.isWatching(share)
            ? streams.firstWhereOrNull((i) =>
                i.participantId == share.participantId &&
                i.type == VoipStreamType.screenshareAudio)
            : null;

    return [
      tiamat.ContextMenuItem(
        text: "User",
        customBuilder: (context, onClicked, {closeMenu}) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
            child: Row(
              spacing: 12,
              children: [
                tiamat.Avatar(
                    radius: 15,
                    image: user.avatar,
                    placeholderColor: user.defaultColor,
                    placeholderText: user.displayName,
                    redactionKey: user.identifier),
                // Vommet issue 475: redacted mode.
                tiamat.Text.name(
                  RedactionScope.of(context)
                      .name(user.displayName, user.identifier),
                  color: RedactionScope.of(context)
                      .nameColor(user.defaultColor, user.identifier),
                ),
                if (share != null) const StreamLivePill(),
              ],
            ),
          );
        },
      ),
      if (audioStream != null)
        tiamat.ContextMenuItem(
          text: "Volume",
          customBuilder: (context, onClicked, {closeMenu}) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                      height: 24,
                      width: 24,
                      child: Center(
                        child: Icon(
                          Icons.mic,
                          size: 16,
                        ),
                      )),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      child: StreamVolumeSlider(audioStream),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      if (screenShareAudioStream != null)
        tiamat.ContextMenuItem(
          text: "Volume",
          customBuilder: (context, onClicked, {closeMenu}) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                      height: 24,
                      width: 24,
                      child: Center(
                        child: Icon(
                          Icons.screen_share,
                          size: 16,
                        ),
                      )),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      child: StreamVolumeSlider(screenShareAudioStream),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      if (share != null) ...StreamSheetItems.items(session!, share),
    ];
  }

  Widget buildDefault() {
    switch (widget.stream.type) {
      case VoipStreamType.screenshareAudio:
      case VoipStreamType.audio:
        return tiamat.Tile.low(
          child: Center(
              child: Stack(
            alignment: AlignmentGeometry.bottomRight,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: AnimatedOpacity(
                  opacity: widget.stream.isMuted ? 0.5 : 1.0,
                  duration: Duration(milliseconds: 200),
                  child: tiamat.Avatar(
                      border: Border.all(
                          strokeAlign: 0.5,
                          color: getBorderColor(context),
                          width: clampDouble(audioLevel.value * 15, 0, 5)),
                      radius: 50,
                      image: user.largeAvatar,
                      placeholderColor: user.defaultColor,
                      placeholderText: user.displayName,
                      redactionKey: user.identifier),
                ),
              ),
              AnimatedScale(
                scale: widget.stream.isMuted ? 1.0 : 0.0,
                curve: widget.stream.isMuted
                    ? Curves.bounceOut
                    : Curves.easeInExpo,
                duration:
                    Duration(milliseconds: widget.stream.isMuted ? 500 : 200),
                child: Container(
                  decoration: BoxDecoration(
                      color: ColorScheme.of(context).primary,
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      Icons.mic_off_rounded,
                      size: 18,
                      color: ColorScheme.of(context).onPrimary,
                    ),
                  ),
                ),
              )
            ],
          )),
        );

      case VoipStreamType.video:
      case VoipStreamType.screenshare:
        return Stack(
          children: [
            // Vommet: the spinner sits behind the renderer, which paints
            // nothing until its first frame, so a tile shown again (or a
            // stream that never delivers a frame) keeps the spinner.
            const Center(child: CircularProgressIndicator()),
            Center(
              child:
                  widget.stream.buildVideoRenderer(widget.fit, rendererKey) ??
                      const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: tiamat.Avatar.small(
                  border: Border.all(
                      strokeAlign: 0.5,
                      color: getBorderColor(context),
                      width: clampDouble(audioLevel.value * 15, 0, 5)),
                  image: user.avatar,
                  placeholderColor: user.defaultColor,
                  placeholderText: user.displayName,
                  redactionKey: user.identifier),
            ),
          ],
        );
    }
  }

  Color getBorderColor(BuildContext context) {
    return Color.lerp(Theme.of(context).primaryColor,
        Theme.of(context).colorScheme.primary, audioLevel.value)!;
  }

  void onStreamChanged(void event) {
    print("Stream state changed!");
    setState(() {});
  }
}

/// Vommet issue 853: a call tile's name label: the name ellipsizes first,
/// the [mark] after it always shows.
class CallTileNameLabel extends StatelessWidget {
  const CallTileNameLabel({required this.name, this.mark, super.key});

  final String name;
  final Widget? mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
        if (mark != null) mark!,
      ]),
    );
  }
}

class StreamVolumeSlider extends StatefulWidget {
  const StreamVolumeSlider(this.stream, {super.key});

  final VoipStream stream;
  @override
  State<StreamVolumeSlider> createState() => _StreamVolumeSliderState();
}

class _StreamVolumeSliderState extends State<StreamVolumeSlider> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: tiamat.Slider(
            min: 0.0,
            max: 2.5,
            value: widget.stream.volume,
            onChanged: (value) {
              print(value);
              setState(() {
                widget.stream.setVolume(value);
              });
            },
          ),
        ),
        SizedBox(
            width: 40,
            child: tiamat.Text.labelLow(
                "${(widget.stream.volume * 100).toInt()}%")),
      ],
    );
  }
}

/// Keeps the camera in the call's layout without creating a second renderer.
class CameraPopoutPlaceholder extends StatelessWidget {
  const CameraPopoutPlaceholder(
      {required this.onDockBack, this.name, this.mark, super.key});
  final String? name;
  final Widget? mark;
  final VoidCallback onDockBack;
  @override
  Widget build(BuildContext context) => tiamat.Tile.low(
      child: Center(
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (name != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: CallTileNameLabel(name: name!, mark: mark)),
                    const Icon(Icons.open_in_new, size: 28),
                    const SizedBox(height: 8),
                    Text(StreamTile.streamTileInOwnWindow,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: onDockBack,
                        child: Text(StreamPopoutWindow.streamPopoutDockBack)),
                  ])))));
}
