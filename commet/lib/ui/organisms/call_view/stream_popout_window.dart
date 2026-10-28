import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/call_view/stream_mini_player.dart';
import 'package:commet/ui/organisms/call_view/stream_tile.dart';
import 'package:commet/ui/organisms/call_view/stream_watch_card.dart';
import 'package:commet/ui/organisms/call_view/watched_stream_controls.dart';
import 'package:commet/utils/scaled_app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Vommet: what the native side of a stream's pop-out window tells Dart.
enum StreamPopoutEventKind {
  /// The window's close button: dock the stream back.
  closeRequested,

  /// The window is gone already (the app quits).
  closed,

  /// The window went in or out of full screen.
  fullscreenChanged,
}

class StreamPopoutEvent {
  const StreamPopoutEvent(this.kind, {this.viewId, this.fullscreen = false});

  final StreamPopoutEventKind kind;
  final int? viewId;
  final bool fullscreen;
}

/// Vommet: the native window a popped out stream plays in. On Linux it's a
/// second Flutter view on the app's own engine (linux/stream_popout.cc), so
/// the stream's video texture shows there as in the main window.
abstract class StreamPopoutBackend {
  /// Opens the window (or brings the open one forward) and returns its
  /// Flutter view id; null if it couldn't.
  Future<int?> open({required String title, int width, int height});

  /// Destroys the window. Its view must be out of the widget tree already.
  Future<void> close();

  Future<void> setTitle(String title);

  Future<void> setFullscreen(bool fullscreen);

  Stream<StreamPopoutEvent> get events;
}

/// [StreamPopoutBackend] over the "vommet/stream_popout" method channel.
class MethodChannelStreamPopoutBackend implements StreamPopoutBackend {
  MethodChannelStreamPopoutBackend(
      {this.channel = const MethodChannel("vommet/stream_popout")}) {
    channel.setMethodCallHandler(_handle);
  }

  final MethodChannel channel;
  final StreamController<StreamPopoutEvent> _events =
      StreamController.broadcast();

  Future<void> _handle(MethodCall call) async {
    final args = call.arguments is Map ? call.arguments as Map : const {};
    final viewId = args["viewId"] is int ? args["viewId"] as int : null;
    switch (call.method) {
      case "closeRequested":
        _events.add(StreamPopoutEvent(StreamPopoutEventKind.closeRequested,
            viewId: viewId));
      case "closed":
        _events.add(
            StreamPopoutEvent(StreamPopoutEventKind.closed, viewId: viewId));
      case "fullscreenChanged":
        _events.add(StreamPopoutEvent(StreamPopoutEventKind.fullscreenChanged,
            viewId: viewId, fullscreen: args["fullscreen"] == true));
    }
  }

  @override
  Future<int?> open(
      {required String title, int width = 960, int height = 600}) async {
    final id = await channel.invokeMethod<int>(
        "open", {"title": title, "width": width, "height": height});
    return id;
  }

  @override
  Future<void> close() => channel.invokeMethod("close");

  @override
  Future<void> setTitle(String title) =>
      channel.invokeMethod("setTitle", {"title": title});

  @override
  Future<void> setFullscreen(bool fullscreen) =>
      channel.invokeMethod("setFullscreen", {"fullscreen": fullscreen});

  @override
  Stream<StreamPopoutEvent> get events => _events.stream;
}

/// Vommet: a stream you watch, popped out of the call view into its own OS
/// window (desktop, as on Discord): it can go to another monitor. The
/// stream's tile says "Playing in its own window" with Dock back meanwhile.
/// Closing the window docks it back; the call ending (or leaving it) closes
/// it. Linux only for now: elsewhere [install] isn't called, so the stream
/// tile offers the mini-player instead ([StreamTile.popOutWindow]).
class StreamPopoutWindow extends ChangeNotifier {
  StreamPopoutWindow(this.backend, {Future<void> Function()? afterFrame})
      : _afterFrame = afterFrame ?? _endOfFrame {
    _events = backend.events.listen(_onEvent);
  }

  static Future<void> _endOfFrame() => WidgetsBinding.instance.endOfFrame
      .timeout(const Duration(seconds: 1), onTimeout: () {});

  static StreamPopoutWindow? _instance;

  /// The app's pop-out window, once [install]ed.
  static StreamPopoutWindow? get maybeInstance => _instance;

  /// Offers the pop-out on stream tiles (Linux, see linux/stream_popout.cc).
  static void install({StreamPopoutBackend? backend}) {
    final window = _instance ??=
        StreamPopoutWindow(backend ?? MethodChannelStreamPopoutBackend());
    StreamTile.popOutWindow = window.open;
  }

  /// Whether this platform has the pop-out window.
  static bool get supported => !kIsWeb && PlatformUtils.isLinux;

  static String get streamPopoutDockBack => Intl.message("Dock back",
      name: "streamPopoutDockBack",
      desc:
          "A screen share playing in its own window: button in that window that closes it and brings the stream back into the call view");

  static String get streamPopoutExitFullscreen => Intl.message(
      "Exit fullscreen",
      name: "streamPopoutExitFullscreen",
      desc:
          "A screen share playing in its own window: tooltip on the fullscreen button while that window is fullscreen");

  /// The window's title: "LIVE Name · title — Room" (title and room when
  /// known).
  static String windowTitle(
      {required String name, String? title, String? room}) {
    final b = StringBuffer("${StreamWatchCard.streamLiveBadge} $name");
    if (title != null && title.isNotEmpty) b.write(" · $title");
    if (room != null && room.isNotEmpty) b.write(" — $room");
    return b.toString();
  }

  final StreamPopoutBackend backend;
  final Future<void> Function() _afterFrame;
  late final StreamSubscription<StreamPopoutEvent> _events;

  VoipSession? _session;
  VoipStream? _stream;
  int? _viewId;
  bool _fullscreen = false;
  String? _title;
  StreamSubscription? _sessionSub;

  VoipSession? get session => _session;
  VoipStream? get stream => _stream;

  /// The window's Flutter view, once it's open.
  int? get viewId => _viewId;

  bool get fullscreen => _fullscreen;

  /// A stream is popped out (its window may still be opening).
  bool get active => _session != null && _stream != null;

  /// [stream] of [session] is the one popped out.
  bool isShowing(VoipSession session, VoipStream stream) =>
      active && _session == session && _stream == stream;

  /// Pops [stream] out into the window (one at a time: another one there is
  /// swapped for it). It leaves the mini-player if it played there.
  Future<void> open(VoipSession session, VoipStream stream) async {
    final player = StreamMiniPlayer.instance;
    if (player.showing && player.stream == stream) player.hide();
    if (_session != session) {
      _sessionSub?.cancel();
      _sessionSub = session.onStateChanged.listen((_) => _follow());
    }
    _session = session;
    _stream = stream;
    _fullscreen = false;
    notifyListeners();
    int? id;
    try {
      id = await backend.open(title: _title ?? "Vommet");
    } catch (error) {
      id = null;
    }
    if (!isShowing(session, stream)) return;
    if (id == null) {
      // No window: the mini-player instead.
      _clear();
      player.show(session, stream, poppedOut: true);
      return;
    }
    _viewId = id;
    notifyListeners();
  }

  /// Closes the window and shows the stream big in the call view again.
  Future<void> dockBack() async {
    final session = _session;
    final stream = _stream;
    await close();
    if (session == null || stream == null) return;
    VoipStreamWatching.of(session)?.requestFocus(stream);
  }

  Future<void> stopWatching() async {
    final session = _session;
    final stream = _stream;
    await close();
    if (session == null || stream == null) return;
    await VoipStreamWatching.of(session)?.setWatching(stream, false);
  }

  /// Closes the window: its view leaves the widget tree first, the window
  /// goes after the next frame (removing a view mid-frame can crash).
  Future<void> close() async {
    if (!active && _viewId == null) return;
    _clear();
    await _afterFrame();
    // Popped out again meanwhile: that one keeps the window.
    if (active) return;
    try {
      await backend.close();
    } catch (_) {}
  }

  /// [stream] is about to be shown elsewhere (the call view): dock it.
  Future<void> closeIfShowing(VoipStream stream) async {
    if (active && _stream == stream) await close();
  }

  Future<void> setFullscreen(bool fullscreen) async {
    if (_viewId == null) return;
    try {
      await backend.setFullscreen(fullscreen);
    } catch (_) {}
  }

  /// The page in the window keeps the title current (it knows the names
  /// as shown, redaction included).
  void setTitle(String title) {
    if (title == _title) return;
    _title = title;
    if (_viewId == null) return;
    unawaited(backend.setTitle(title).catchError((_) {}));
  }

  void _clear() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _session = null;
    _stream = null;
    _viewId = null;
    _fullscreen = false;
    notifyListeners();
  }

  void _onEvent(StreamPopoutEvent event) {
    if (event.viewId != null && _viewId != null && event.viewId != _viewId) {
      return;
    }
    switch (event.kind) {
      case StreamPopoutEventKind.closeRequested:
        unawaited(dockBack());
      case StreamPopoutEventKind.closed:
        if (active || _viewId != null) _clear();
      case StreamPopoutEventKind.fullscreenChanged:
        if (_fullscreen != event.fullscreen) {
          _fullscreen = event.fullscreen;
          notifyListeners();
        }
    }
  }

  /// Follows the sharer to a new stream when they switch what they share;
  /// closes when they stop, you stop watching, or the call ends.
  void _follow() {
    final session = _session;
    final stream = _stream;
    if (session == null || stream == null) return;
    final watching = VoipStreamWatching.of(session);
    if (session.state == VoipState.ended || watching == null) {
      unawaited(close());
      return;
    }
    var current = stream;
    if (!session.streams.contains(stream)) {
      final next = session.streams.firstWhereOrNull((s) =>
          s.participantId == stream.participantId && s.type == stream.type);
      if (next == null) {
        unawaited(close());
        return;
      }
      current = next;
    }
    if (!watching.isWatching(current)) {
      unawaited(close());
      return;
    }
    _stream = current;
    notifyListeners();
  }

  @override
  void dispose() {
    _events.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }
}

/// Vommet: draws the popped out stream ([StreamPopoutWindow]) into its own
/// window's Flutter view, from the app's widget tree (so it shares the
/// theme, the call and redaction). Put it above everything that should
/// reach the window; [child] is the app and is never rebuilt by it.
class StreamPopoutHost extends StatefulWidget {
  const StreamPopoutHost({required this.child, this.window, super.key});

  final Widget child;

  /// For tests; the installed one otherwise.
  final StreamPopoutWindow? window;

  @override
  State<StreamPopoutHost> createState() => _StreamPopoutHostState();
}

class _StreamPopoutHostState extends State<StreamPopoutHost>
    with WidgetsBindingObserver {
  StreamPopoutWindow? get window =>
      widget.window ?? StreamPopoutWindow.maybeInstance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A new view (the window just opened) shows up as a metrics change.
  @override
  void didChangeMetrics() {
    if (mounted && window?.viewId != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final window = this.window;
    if (window == null) return widget.child;
    return ListenableBuilder(
      listenable: window,
      // The same child either way, so the app keeps its state.
      child: widget.child,
      builder: (context, child) {
        final id = window.viewId;
        final view = id == null
            ? null
            : WidgetsBinding.instance.platformDispatcher.view(id: id);
        final session = window.session;
        final stream = window.stream;
        return ViewAnchor(
          view: view == null || session == null || stream == null
              ? null
              : View(
                  view: view,
                  child: StreamPopoutPage(
                      key: ValueKey("streamPopout_$id"),
                      window: window,
                      session: session,
                      stream: stream),
                ),
          child: child!,
        );
      },
    );
  }
}

/// Vommet: the popped out stream's window: the stream, and on hover its
/// name, volume, fullscreen, Dock back and Stop watching.
class StreamPopoutPage extends StatefulWidget {
  const StreamPopoutPage(
      {required this.window,
      required this.session,
      required this.stream,
      super.key});

  final StreamPopoutWindow window;
  final VoipSession session;
  final VoipStream stream;

  @override
  State<StreamPopoutPage> createState() => _StreamPopoutPageState();
}

class _StreamPopoutPageState extends State<StreamPopoutPage> {
  bool controls = true;
  bool overControls = false;
  Timer? hideTimer;
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.session.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    hideSoon();
  }

  @override
  void dispose() {
    hideTimer?.cancel();
    sub?.cancel();
    super.dispose();
  }

  void show() {
    if (!controls) setState(() => controls = true);
    hideSoon();
  }

  void hideSoon() {
    hideTimer?.cancel();
    if (overControls) return;
    hideTimer = Timer(WatchedStreamControls.hideAfter, () {
      if (mounted) setState(() => controls = false);
    });
  }

  VoipStream? get audio => widget.session.streams.firstWhereOrNull((s) =>
      s.participantId == widget.stream.participantId &&
      s.type == VoipStreamType.screenshareAudio);

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final stream = widget.stream;
    final window = widget.window;
    final watching = VoipStreamWatching.of(session);
    final room = session.client.getRoom(session.roomId);
    final member = room?.getMemberOrFallback(stream.streamUserId);
    final redaction = RedactionScope.of(context);
    final name = redaction.name(
        member?.displayName ?? stream.streamUserId, stream.streamUserId);
    final roomName = room == null
        ? null
        : redaction.roomName(room.displayName, room.identifier);
    final title = StreamPopoutWindow.windowTitle(name: name, room: roomName);
    WidgetsBinding.instance.addPostFrameCallback((_) => window.setTitle(title));
    final audio = this.audio;
    final muted =
        audio != null && (watching?.isStreamAudioMuted(stream) ?? false);
    final fullscreen = window.fullscreen;

    final media = MediaQuery.of(context);
    return MediaQuery(
      // As the main window: the app's own scale.
      data: ScaledWidgetsFlutterBinding.maybeInstance == null
          ? media
          : media.scale(),
      child: Material(
        color: Colors.black,
        child: Overlay(initialEntries: [
          OverlayEntry(
            builder: (context) => MouseRegion(
              onHover: (_) => show(),
              onEnter: (_) => show(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (controls) {
                    hideTimer?.cancel();
                    setState(() => controls = false);
                  } else {
                    show();
                  }
                },
                onDoubleTap: () => window.setFullscreen(!fullscreen),
                child: Stack(fit: StackFit.expand, children: [
                  Center(
                      child: stream.buildVideoRenderer(
                              BoxFit.contain,
                              ValueKey(
                                  "streamPopoutVideo_${stream.streamId}")) ??
                          const CircularProgressIndicator()),
                  IgnorePointer(
                    ignoring: !controls,
                    child: AnimatedOpacity(
                      opacity: controls ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: _controls(
                          name, roomName, watching, audio, muted, fullscreen),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed,
          {Color? tint, Key? key}) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: .6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: InkWell(
            key: key,
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              show();
              onPressed();
            },
            child: SizedBox(
                width: 36,
                height: 34,
                child: Icon(icon, size: 20, color: tint ?? Colors.white)),
          ),
        ),
      );

  Widget _controls(String name, String? roomName, VoipStreamWatching? watching,
      VoipStream? audio, bool muted, bool fullscreen) {
    final window = widget.window;
    final stream = widget.stream;
    Widget bar(Widget child) => MouseRegion(
        onEnter: (_) {
          overControls = true;
          hideTimer?.cancel();
        },
        onExit: (_) {
          overControls = false;
          hideSoon();
        },
        child: child);
    return DecoratedBox(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [
            0,
            .18,
            .78,
            1
          ],
              colors: [
            Color(0xa0000000),
            Colors.transparent,
            Colors.transparent,
            Color(0xb0000000),
          ])),
      child: Stack(children: [
        Positioned(
          left: 12,
          top: 12,
          right: 12,
          child: Row(children: [
            const StreamLivePill(size: 10),
            const SizedBox(width: 8),
            Flexible(
              child: Text(roomName == null ? name : "$name · $roomName",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ]),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: bar(Row(children: [
            if (audio != null && watching != null) ...[
              _button(
                  muted ? Icons.volume_off : Icons.volume_up,
                  muted
                      ? WatchedStreamControlsStrings.watchedStreamUnmute
                      : WatchedStreamControlsStrings.watchedStreamMute,
                  () async {
                await watching.setStreamAudioMuted(stream, !muted);
                if (mounted) setState(() {});
              }, tint: muted ? streamLiveRed : null),
              if (!muted)
                SizedBox(
                  width: 120,
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
                      onChanged: (v) => setState(() => audio.setVolume(v)),
                    ),
                  ),
                ),
            ],
            const Spacer(),
            _button(
                fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                fullscreen
                    ? StreamPopoutWindow.streamPopoutExitFullscreen
                    : WatchedStreamControlsStrings.watchedStreamFullscreen,
                () => window.setFullscreen(!fullscreen),
                key: const ValueKey("streamPopoutFullscreen")),
            const SizedBox(width: 6),
            _button(Icons.login_rounded,
                StreamPopoutWindow.streamPopoutDockBack, window.dockBack,
                key: const ValueKey("streamPopoutDockBack")),
            const SizedBox(width: 6),
            _button(
                Icons.close,
                WatchedStreamControlsStrings.watchedStreamStopWatching,
                window.stopWatching,
                tint: streamLiveRed,
                key: const ValueKey("streamPopoutStopWatching")),
          ])),
        ),
      ]),
    );
  }
}
