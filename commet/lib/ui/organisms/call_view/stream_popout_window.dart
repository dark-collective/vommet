import 'dart:async';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
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

enum CameraPopoutResult { opened, canceled, failed }

class StreamPopoutEvent {
  const StreamPopoutEvent(this.kind,
      {this.viewId, this.requestId, this.fullscreen = false});

  final StreamPopoutEventKind kind;
  final int? viewId;
  final int? requestId;
  final bool fullscreen;
}

/// Vommet: the native window a popped out stream plays in. On Linux it's a
/// second Flutter view on the app's own engine (linux/stream_popout.cc), so
/// the stream's video texture shows there as in the main window.
abstract class StreamPopoutBackend {
  /// Opens an independent window and returns its
  /// Flutter view id; null if it couldn't.
  Future<int?> open(
      {required String title,
      required int requestId,
      int width,
      int height,
      int minWidth,
      int minHeight});

  /// Destroys the window. Its view must be out of the widget tree already.
  Future<void> close(int viewId);

  Future<void> setTitle(int viewId, String title);

  Future<void> setFullscreen(int viewId, bool fullscreen);

  Future<void> focus(int viewId);

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
            viewId: viewId, requestId: args["requestId"] as int?));
      case "closed":
        _events.add(StreamPopoutEvent(StreamPopoutEventKind.closed,
            viewId: viewId, requestId: args["requestId"] as int?));
      case "fullscreenChanged":
        _events.add(StreamPopoutEvent(StreamPopoutEventKind.fullscreenChanged,
            viewId: viewId,
            requestId: args["requestId"] as int?,
            fullscreen: args["fullscreen"] == true));
    }
  }

  @override
  Future<int?> open(
          {required String title,
          required int requestId,
          int width = 960,
          int height = 600,
          int minWidth = 0,
          int minHeight = 0}) =>
      channel.invokeMethod<int>("open", {
        "title": title,
        "requestId": requestId,
        "width": width,
        "height": height,
        "minWidth": minWidth,
        "minHeight": minHeight
      });

  @override
  Future<void> close(int viewId) =>
      channel.invokeMethod("close", {"viewId": viewId});

  @override
  Future<void> setTitle(int viewId, String title) =>
      channel.invokeMethod("setTitle", {"viewId": viewId, "title": title});

  @override
  Future<void> setFullscreen(int viewId, bool fullscreen) =>
      channel.invokeMethod(
          "setFullscreen", {"viewId": viewId, "fullscreen": fullscreen});

  @override
  Future<void> focus(int viewId) =>
      channel.invokeMethod("focus", {"viewId": viewId});

  @override
  Stream<StreamPopoutEvent> get events => _events.stream;
}

/// Vommet: a stream you watch, popped out of the call view into its own OS
/// window (desktop, as on Discord): it can go to another monitor. The
/// stream's tile says "Playing in its own window" with Dock back meanwhile.
/// Closing the window docks it back; the call ending (or leaving it) closes
/// it. Linux only for now: elsewhere [install] isn't called, so the stream
/// tile offers the mini-player instead ([StreamTile.popOutWindow]). The
/// installed controller also owns one independent camera controller per
/// session/device/source. Cameras share the backend, never the screen-share
/// slot, session tracks, capture, or audio controls.
class StreamPopoutWindow extends ChangeNotifier {
  StreamPopoutWindow(this.backend,
      {this.camera = false, Future<void> Function()? afterFrame})
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

  /// A camera entry owns only its view, never capture, tracks, or call audio.
  final bool camera;
  final StreamPopoutBackend backend;
  final Future<void> Function() _afterFrame;
  late final StreamSubscription<StreamPopoutEvent> _events;
  static int _nextRequestId = 0;
  int? _requestId;
  bool _disposed = false;
  bool _openFailed = false;
  Future<void>? _opening;
  Future<void>? _closing;
  final _retiring = <Future<void>>{};
  VoipSession? _session;
  VoipStream? _stream;
  int? _viewId;
  bool _fullscreen = false;
  String? _title;
  StreamSubscription? _sessionSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _trackSub;
  StreamPopoutWindow? _owner;

  // Only the installed screen-share controller owns camera controllers. The
  // existing screen-share slot/API is preserved; cameras never replace it.
  final List<StreamPopoutWindow> _cameras = [];
  Iterable<StreamPopoutWindow> get windows sync* {
    if (active) yield this;
    yield* _cameras.where((w) => w.active);
  }

  StreamPopoutWindow? cameraFor(VoipSession session, VoipStream stream) =>
      _cameras.firstWhereOrNull((w) => w.isShowing(session, stream));

  Future<CameraPopoutResult> openCamera(
      VoipSession session, VoipStream stream) async {
    if (_disposed ||
        stream.type != VoipStreamType.video ||
        session.state == VoipState.ended) return CameraPopoutResult.canceled;
    for (final old in _cameras.where((w) => !w.active).toList()) {
      _removeCamera(old);
    }
    var window = cameraFor(session, stream);
    if (window == null) {
      window =
          StreamPopoutWindow(backend, camera: true, afterFrame: _afterFrame);
      _cameras.add(window);
      window.addListener(notifyListeners);
      window._owner = this;
    }
    await window.open(session, stream);
    if (!window.active) _removeCamera(window);
    return window._openFailed
        ? CameraPopoutResult.failed
        : (window.active
            ? CameraPopoutResult.opened
            : CameraPopoutResult.canceled);
  }

  void _removeCamera(StreamPopoutWindow window) {
    if (!_cameras.remove(window)) return;
    window.removeListener(notifyListeners);
    window.dispose();
    if (!_disposed) notifyListeners();
  }

  Future<void> closeForClient(Client client) async {
    await Future.wait([
      for (final w in windows.toList())
        if (identical(w.session?.client, client)) w.close()
    ]);
    await Future.wait(_retiring.toList());
    for (final w in _cameras.where((w) => !w.active).toList()) {
      _removeCamera(w);
    }
  }

  /// Focus requests for camera docking, separate from screen-share watching.
  final _cameraFocus =
      StreamController<(VoipSession, VoipStream)>.broadcast(sync: true);
  Stream<(VoipSession, VoipStream)> get cameraFocusRequests =>
      _cameraFocus.stream;

  VoipSession? get session => _session;
  VoipStream? get stream => _stream;
  int? get viewId => _viewId;
  bool get fullscreen => _fullscreen;
  bool get active => _session != null && _stream != null;

  bool isShowing(VoipSession session, VoipStream stream) =>
      active &&
      identical(_session, session) &&
      (camera ? _sameCamera(_stream!, stream) : _stream == stream);

  static bool _sameCamera(VoipStream a, VoipStream b) =>
      a.type == VoipStreamType.video &&
      b.type == VoipStreamType.video &&
      a.participantId == b.participantId &&
      a.streamUserId == b.streamUserId &&
      a.direction == b.direction;

  /// The screen-share slot can change feeds. A camera controller is per source.
  /// Concurrent opens share one native request; canceled requests close their
  /// own late result, never a subsequently opened window.
  Future<void> open(VoipSession session, VoipStream stream) async {
    if (_disposed || session.state == VoipState.ended) return;
    if (camera && active && !isShowing(session, stream)) return;
    final player = StreamMiniPlayer.instance;
    if (!camera && player.showing && player.stream == stream) player.hide();
    if (!identical(_session, session)) {
      _sessionSub?.cancel();
      _connectionSub?.cancel();
      _sessionSub = session.onStateChanged.listen((_) => _follow());
      _connectionSub =
          session.onConnectionStateChanged.listen((_) => _follow());
    }
    _session = session;
    _setStream(stream);
    notifyListeners();
    final existing = _viewId;
    if (existing != null) {
      try {
        await backend.focus(existing);
      } catch (_) {}
      return;
    }
    final pending = _opening;
    if (pending != null) return pending;
    _openFailed = false;
    final request = _requestId = ++_nextRequestId;
    final opening = _openNative(request);
    _opening = opening;
    await opening;
    if (identical(_opening, opening)) _opening = null;
  }

  Future<void> _openNative(int request) async {
    int? id;
    try {
      id = await backend.open(
          title: _title ?? "Vommet",
          requestId: request,
          width: camera ? 400 : 960,
          height: camera ? 300 : 600,
          minWidth: camera ? 240 : 0,
          minHeight: camera ? 180 : 0);
    } catch (_) {}
    if (_disposed || _requestId != request || !active) {
      if (id != null) await _destroy(id);
      return;
    }
    if (id == null) {
      _openFailed = true;
      final session = _session!;
      final stream = _stream!;
      _clear();
      if (!camera)
        StreamMiniPlayer.instance.show(session, stream, poppedOut: true);
      return;
    }
    _viewId = id;
    if (_title != null)
      unawaited(backend.setTitle(id, _title!).catchError((_) {}));
    notifyListeners();
  }

  void _setStream(VoipStream stream) {
    if (identical(_stream, stream)) return;
    _trackSub?.cancel();
    _stream = stream;
    _trackSub = stream.onStreamChanged.listen((_) => _follow());
  }

  Future<void> dockBack() async {
    final session = _session;
    final stream = _stream;
    await close();
    if (session == null ||
        stream == null ||
        (!camera && _disposed) ||
        active ||
        session.state == VoipState.ended ||
        !session.streams.contains(stream)) return;
    if (camera) {
      // The owner forwards this to its call view; never change camera tracks.
      final owner = _owner;
      if (owner != null &&
          !owner._disposed &&
          owner.cameraFor(session, stream) == null)
        owner._cameraFocus.add((session, stream));
    } else {
      VoipStreamWatching.of(session)?.requestFocus(stream);
    }
  }

  Future<void> stopWatching() async {
    if (camera) return;
    final session = _session;
    final stream = _stream;
    await close();
    if (session != null && stream != null)
      await VoipStreamWatching.of(session)?.setWatching(stream, false);
  }

  Future<void> close() {
    if (!active && _viewId == null) return _closing ?? Future.value();
    final id = _viewId;
    final opening = _opening;
    _clear();
    final owner = _owner ?? this;
    final closing = _finishClose(id, opening);
    _closing = closing;
    owner._retiring.add(closing);
    unawaited(closing.whenComplete(() {
      owner._retiring.remove(closing);
      if (identical(_closing, closing)) _closing = null;
      _owner?._removeCamera(this);
    }));
    return closing;
  }

  Future<void> _finishClose(int? id, Future<void>? opening) async {
    if (id != null) await _destroy(id);
    // Late opens perform their own ID-specific cleanup. Wait on logout too.
    if (opening != null) await opening;
  }

  Future<void> _destroy(int id) async {
    await _afterFrame();
    try {
      await backend.close(id);
    } catch (_) {}
  }

  Future<void> closeIfShowing(VoipStream stream) async {
    if (active && _stream == stream) await close();
  }

  Future<void> setFullscreen(bool fullscreen) async {
    final id = _viewId;
    if (id == null) return;
    try {
      await backend.setFullscreen(id, fullscreen);
    } catch (_) {}
  }

  void setTitle(String title) {
    if (_disposed || title == _title) return;
    _title = title;
    final id = _viewId;
    if (id != null) unawaited(backend.setTitle(id, title).catchError((_) {}));
  }

  void _clear() {
    _sessionSub?.cancel();
    _connectionSub?.cancel();
    _trackSub?.cancel();
    _sessionSub = null;
    _connectionSub = null;
    _trackSub = null;
    _session = null;
    _stream = null;
    _viewId = null;
    _requestId = null;
    _opening = null;
    _fullscreen = false;
    _title = null;
    if (!_disposed) notifyListeners();
  }

  void _onEvent(StreamPopoutEvent event) {
    if (!active ||
        (event.requestId != null
            ? event.requestId != _requestId
            : event.viewId == null || event.viewId != _viewId)) return;
    switch (event.kind) {
      case StreamPopoutEventKind.closeRequested:
        unawaited(dockBack());
      case StreamPopoutEventKind.closed:
        _clear();
        _owner?._removeCamera(this);
      case StreamPopoutEventKind.fullscreenChanged:
        _fullscreen = event.fullscreen;
        notifyListeners();
    }
  }

  void _follow() {
    final session = _session;
    final stream = _stream;
    if (session == null || stream == null) return;
    final watching = VoipStreamWatching.of(session);
    if (session.state == VoipState.ended || (!camera && watching == null)) {
      unawaited(close());
      return;
    }
    final current = session.streams.firstWhereOrNull((s) => camera
        ? _sameCamera(stream, s)
        : s.participantId == stream.participantId && s.type == stream.type);
    if (current == null || (!camera && !watching!.isWatching(current))) {
      unawaited(close());
      return;
    }
    _setStream(current);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    // Notify the host while camera listeners are still attached, so every
    // root leaves the widget tree before native destruction after a frame.
    for (final w in _cameras.toList()) {
      unawaited(w.close());
    }
    unawaited(close());
    _disposed = true;
    _events.cancel();

    for (final w in _cameras.toList()) {
      w.removeListener(notifyListeners);
      w.dispose();
    }
    _cameras.clear();
    _cameraFocus.close();
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
    if (mounted) setState(() {});
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
        return ViewAnchor(
          view: ViewCollection(views: [
            for (final entry in window.windows)
              if (WidgetsBinding.instance.platformDispatcher
                      .view(id: entry.viewId ?? -1)
                  case final view?)
                View(
                    key: ObjectKey(entry),
                    view: view,
                    child: StreamPopoutPage(
                        key: ValueKey("streamPopout_${entry.viewId}"),
                        window: entry,
                        session: entry.session!,
                        stream: entry.stream!))
          ]),
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
  bool controlsFocused = false;
  bool accessibleNavigation = false;
  Timer? hideTimer;
  StreamSubscription? sub;

  @override
  void initState() {
    super.initState();
    sub = widget.session.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    hideSoon();
  }

  @override
  void didUpdateWidget(covariant StreamPopoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      sub?.cancel();
      sub = widget.session.onStateChanged.listen((_) {
        if (mounted) setState(() {});
      });
    }
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
    if (overControls || controlsFocused || accessibleNavigation) return;
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
    final title = window.camera
        ? (roomName == null ? name : "$name — $roomName")
        : StreamPopoutWindow.windowTitle(name: name, room: roomName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(widget.stream, stream) &&
          window.isShowing(session, stream)) window.setTitle(title);
    });
    final audio = window.camera ? null : this.audio;
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
        child: Overlay.wrap(
            child: Focus(
                onFocusChange: (focused) {
                  controlsFocused = focused;
                  if (focused)
                    show();
                  else
                    hideSoon();
                },
                child: MouseRegion(
                  onHover: (_) => show(),
                  onEnter: (_) => show(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (controls &&
                          !controlsFocused &&
                          !accessibleNavigation) {
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
                        child: ExcludeFocus(
                            excluding: !controls,
                            child: AnimatedOpacity(
                              opacity: controls ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: _controls(name, roomName, watching, audio,
                                  muted, fullscreen),
                            )),
                      ),
                    ]),
                  ),
                ))),
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed,
          {Color? tint, Key? key}) =>
      Semantics(
          button: true,
          label: tooltip,
          child: Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: Material(
              color: Colors.black.withValues(alpha: .6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: InkWell(
                key: key,
                mouseCursor: WidgetStateMouseCursor.clickable,
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  show();
                  onPressed();
                },
                child: SizedBox(
                    width: widget.window.camera ? 48 : 36,
                    height: widget.window.camera ? 48 : 34,
                    child: Icon(icon, size: 20, color: tint ?? Colors.white)),
              ),
            ),
          ));

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
        if (!window.camera)
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
          child: bar(window.camera
              ? CameraPopoutControls(
                  fullscreen: fullscreen,
                  onFullscreen: () => window.setFullscreen(!fullscreen),
                  onDockBack: window.dockBack)
              : Row(children: [
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
                            onChanged: (v) =>
                                setState(() => audio.setVolume(v)),
                          ),
                        ),
                      ),
                  ],
                  const Spacer(),
                  _button(
                      fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      fullscreen
                          ? StreamPopoutWindow.streamPopoutExitFullscreen
                          : WatchedStreamControlsStrings
                              .watchedStreamFullscreen,
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

/// Camera windows expose view controls only: no audio/capture/session actions.
class CameraPopoutControls extends StatelessWidget {
  const CameraPopoutControls(
      {required this.fullscreen,
      required this.onFullscreen,
      required this.onDockBack,
      super.key});
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final VoidCallback onDockBack;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final dock = StreamPopoutWindow.streamPopoutDockBack;
        final compact = constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 22;
        return Row(children: [
          IconButton(
              key: const ValueKey("streamPopoutFullscreen"),
              color: Colors.white,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: fullscreen
                  ? StreamPopoutWindow.streamPopoutExitFullscreen
                  : WatchedStreamControlsStrings.watchedStreamFullscreen,
              onPressed: onFullscreen,
              icon:
                  Icon(fullscreen ? Icons.fullscreen_exit : Icons.fullscreen)),
          const Spacer(),
          if (compact)
            IconButton(
                key: const ValueKey("streamPopoutDockBack"),
                color: Colors.white,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: dock,
                onPressed: onDockBack,
                icon: const Icon(Icons.call_to_action_outlined))
          else
            TextButton.icon(
                key: const ValueKey("streamPopoutDockBack"),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48)),
                onPressed: onDockBack,
                icon: const Icon(Icons.call_to_action_outlined),
                label: Text(dock)),
        ]);
      });
}
