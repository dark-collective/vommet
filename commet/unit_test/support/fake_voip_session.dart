// A call at the client/SDK boundary, in each state the room page can show:
// ringing out, connected with nothing published, alone with the microphone,
// with someone else in it, with a screen share, ended, and failed (starting
// the microphone or camera throws and the call stays connected with nothing
// published, as MatrixLivekitVoipSession.setMicrophoneMute does for a
// listen-only token: nothing in the session or the call manager ends it).
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart'
    show CallListenOnlyException;
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../roomlist_fixture.dart';

const remoteUser = "@bob:example.com";

class FakeVoipStream extends Fake implements VoipStream {
  FakeVoipStream(this.streamUserId, this.direction,
      {this.type = VoipStreamType.audio});
  @override
  final String streamUserId;
  @override
  final VoipStreamDirection direction;
  @override
  final VoipStreamType type;
  @override
  String get participantId => streamUserId;
  @override
  String get streamId => "${type.name}-$streamUserId";
  @override
  String get label => streamUserId;
  @override
  String get stats => "";
  @override
  double get audiolevel => 0;
  @override
  bool get isMuted => false;
  @override
  double? get aspectRatio => type == VoipStreamType.audio ? null : 16 / 9;
  @override
  double volume = 1;
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> applyPlaybackVolume() async {}
  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) =>
      type == VoipStreamType.audio
          ? null
          : ColoredBox(key: key, color: Colors.black);
  @override
  Stream<void> get onStreamChanged => const Stream.empty();
}

/// The call states the room page is checked in.
enum CallCase { outgoing, empty, alone, remote, screenShare, ended, failed }

/// A call session like MatrixLivekitVoipSession: fires [onStateChanged]
/// whenever its state or streams change, and tells the call manager when it
/// ends.
class FakeVoipSession extends Fake implements VoipSession {
  FakeVoipSession(this.client, this.roomId,
      {this.state = VoipState.connected,
      List<VoipStream>? streams,
      this.failing = false,
      this.remoteUserId,
      this.remoteUserName,
      this.roomName = "Call"})
      : streams = streams ?? [];

  /// A session in [c] state; [CallCase.failed] connects with nothing
  /// published, and its first [setMicrophoneMute] / [setCamera] throws.
  factory FakeVoipSession.of(Client client, String roomId, CallCase c,
          {String roomName = "Call"}) =>
      FakeVoipSession(client, roomId,
          roomName: roomName,
          state: switch (c) {
            CallCase.outgoing => VoipState.outgoing,
            CallCase.ended => VoipState.ended,
            _ => VoipState.connected,
          },
          failing: c == CallCase.failed,
          remoteUserId: c == CallCase.remote ? remoteUser : null,
          remoteUserName: c == CallCase.remote ? "Bob" : null,
          streams: callStreams(c));

  static List<VoipStream> callStreams(CallCase c) => switch (c) {
        CallCase.outgoing ||
        CallCase.empty ||
        CallCase.ended ||
        CallCase.failed =>
          [],
        CallCase.alone => [FakeVoipStream(me, VoipStreamDirection.outgoing)],
        CallCase.remote => [
            FakeVoipStream(me, VoipStreamDirection.outgoing),
            FakeVoipStream(remoteUser, VoipStreamDirection.incoming),
          ],
        CallCase.screenShare => [
            FakeVoipStream(me, VoipStreamDirection.outgoing),
            FakeVoipStream(remoteUser, VoipStreamDirection.incoming,
                type: VoipStreamType.screenshare),
          ],
      };

  @override
  final Client client;
  @override
  final String roomId;
  @override
  VoipState state;
  @override
  final List<VoipStream> streams;
  @override
  final String roomName;
  @override
  String? remoteUserId;
  @override
  String? remoteUserName;

  /// Starting the microphone or camera throws; the call stays connected.
  /// (The camera is an approximation: the real one fails inside LiveKit,
  /// with another error.)
  final bool failing;
  Object? error;

  static var _ids = 0;
  @override
  final String sessionId = "fake-call-${_ids++}";

  @override
  bool isMicrophoneMuted = false;
  @override
  bool isCameraEnabled = false;
  @override
  bool isSharingScreen = false;
  @override
  bool get supportsScreenshare => true;
  @override
  bool get canSwitchCamera => false;
  @override
  double get generalAudioLevel => 0;
  @override
  VoipStream? get remoteUserMediaStream => streams
      .where((s) =>
          s.direction == VoipStreamDirection.incoming &&
          s.type == VoipStreamType.audio)
      .firstOrNull;

  final _stateChanged = StreamController<void>.broadcast();
  @override
  Stream<void> get onStateChanged => _stateChanged.stream;
  final _connection = StreamController<VoipState>.broadcast();
  @override
  Stream<VoipState> get onConnectionStateChanged => _connection.stream;
  final _volumes = StreamController<void>.broadcast();
  @override
  Stream<void> get onUpdateVolumeVisualizers => _volumes.stream;

  @override
  Future<void> updateStats() async {}

  void _changed() => _stateChanged.add(null);

  /// Publishes [stream], as when the microphone or camera starts.
  void publish(VoipStream stream) {
    streams.add(stream);
    _changed();
  }

  void setState(VoipState s) {
    if (state == s) return;
    state = s;
    _changed();
    _connection.add(s);
  }

  /// Ends the call the way the real session does: state, then the manager.
  void end() {
    if (state == VoipState.ended) return;
    streams.clear();
    setState(VoipState.ended);
    clientManager?.callManager.onSessionEnded(this);
  }

  /// What the real session does for a listen-only token: throws, publishes
  /// nothing and leaves the call as it was.
  Never _fail() {
    error = const CallListenOnlyException();
    throw error!;
  }

  @override
  Future<void> setMicrophoneMute(bool muted) async {
    // Like the real session: only turning the microphone on fails; muting
    // works.
    if (failing && !muted) _fail();
    isMicrophoneMuted = muted;
    if (!muted &&
        !streams.any((s) => s.direction == VoipStreamDirection.outgoing)) {
      publish(FakeVoipStream(me, VoipStreamDirection.outgoing));
    } else {
      _changed();
    }
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {
    if (failing) _fail();
    isCameraEnabled = true;
    publish(FakeVoipStream(me, VoipStreamDirection.outgoing,
        type: VoipStreamType.video));
  }

  @override
  Future<void> stopCamera() async {
    isCameraEnabled = false;
    streams.removeWhere((s) => s.type == VoipStreamType.video);
    _changed();
  }

  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) async {
    setState(VoipState.connected);
    if (withMicrophone) await setMicrophoneMute(false);
    if (withCamera) await setCamera(null);
  }

  @override
  Future<void> declineCall() async => end();
  @override
  Future<void> hangUpCall() async => end();

  /// Stops sharing the way the real session does: the share's tracks are
  /// unpublished and their streams removed (onLocalTrackUnpublished,
  /// matrix_livekit_voip_session.dart), then [onStateChanged].
  @override
  Future<void> stopScreenshare() async {
    isSharingScreen = false;
    streams.removeWhere((s) =>
        s.direction == VoipStreamDirection.outgoing &&
        (s.type == VoipStreamType.screenshare ||
            s.type == VoipStreamType.screenshareAudio));
    _changed();
  }

  /// Our screen share is published (onLocalTrackPublished): its stream is
  /// added, then [onStateChanged].
  void startScreenshare() {
    isSharingScreen = true;
    publish(FakeVoipStream(me, VoipStreamDirection.outgoing,
        type: VoipStreamType.screenshare));
  }

  /// Someone's track is unpublished (they left, muted their camera or
  /// stopped sharing): onTrackUnpublished removes its stream, then fires
  /// [onStateChanged] (matrix_livekit_voip_session.dart).
  void unpublish(VoipStream stream) {
    streams.remove(stream);
    _changed();
  }

  /// The real session's 100 ms level poll (onUpdateVolumeVisualizers): fires
  /// with no change to the streams.
  void tickVolumes() => _volumes.add(null);

  /// LiveKit reconnecting: VoipState has no reconnecting state, the real
  /// session stays connected (RoomReconnectedEvent only counts reconnects),
  /// and LiveKit re-subscribes the tracks it had: each TrackSubscribedEvent
  /// fires [onStateChanged] with the streams unchanged (onTrackSubscribed).
  void reconnect() {
    for (var i = 0; i < streams.length; i++) {
      _changed();
    }
    tickVolumes();
  }
}

/// Stream watching like LivekitStreamWatching (vommet_stream_watching.dart):
/// your own streams, cameras and microphones always play; someone's screen
/// share (and its audio) once you watch its sharer; [requestFocus] is kept
/// until the call view takes it.
class FakeStreamWatching extends Fake implements VoipStreamWatching {
  final _watched = <String>{};
  VoipStream? _focus;
  final _changes = StreamController<void>.broadcast();
  final _focusRequests = StreamController<void>.broadcast();

  static bool _isShare(VoipStream s) =>
      s.type == VoipStreamType.screenshare ||
      s.type == VoipStreamType.screenshareAudio;

  @override
  bool isWatching(VoipStream stream) =>
      stream.direction == VoipStreamDirection.outgoing ||
      !_isShare(stream) ||
      _watched.contains(stream.participantId);
  @override
  bool hasPreview(VoipStream stream) => false;
  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {
    watching
        ? _watched.add(stream.participantId)
        : _watched.remove(stream.participantId);
    _changes.add(null);
  }

  @override
  bool isStreamAudioMuted(VoipStream stream) => false;
  @override
  Future<void> setStreamAudioMuted(VoipStream stream, bool muted) async {}
  @override
  void requestFocus(VoipStream stream) {
    _focus = stream;
    _focusRequests.add(null);
  }

  @override
  VoipStream? takeFocusRequest() {
    final s = _focus;
    _focus = null;
    return s;
  }

  @override
  Stream<void> get onFocusRequest => _focusRequests.stream;
  @override
  Stream<void> get onChanged => _changes.stream;
  @override
  List<String> viewersOf(VoipStream stream) => [
        if (stream.direction == VoipStreamDirection.incoming &&
            isWatching(stream))
          me
      ];
}
