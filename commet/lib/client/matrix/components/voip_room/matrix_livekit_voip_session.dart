import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/local_voice_level.dart';
import 'package:commet/client/components/voip/voip_participants.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/webrtc_screencapture_source.dart';
import 'package:commet/client/components/voip/android_screencapture_source.dart';
import 'package:commet/client/matrix/components/voip_room/livekit_identity.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';
import 'package:commet/client/matrix/components/voip_room/livekit_call_diagnostics.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_multi_sfu.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_leave.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/call_stats.dart';
import 'package:commet/telemetry/screenshare_audio_telemetry.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/ui_stall.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix_api_lite.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:commet/client/matrix/components/voip_room/vommet_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/vommet_publication_adopt.dart';

class MatrixLivekitVoipSession implements VoipSession, VoipParticipants {
  MatrixRoom room;
  lk.Room livekitRoom;
  Timer? heartbeatTimer;
  String? heartbeatDelayId;

  // Vommet: our membership's `expires` is refreshed hourly while we're in
  // the call, like matrix-js-sdk does; without it Element Call and Element X
  // drop us (and stop sharing media keys with us) four hours after joining.
  Timer? _membershipRefreshTimer;
  int _membershipRefreshIteration = 1;
  late final int _membershipStartMs;

  MatrixLivekitEncryptionKeyProvider? keyProvider;

  final StreamController<void> _onVolumeChanged = StreamController.broadcast();

  MatrixLivekitVoipSession(this.room, this.livekitRoom, {this.keyProvider}) {
    clientManager?.callManager.onClientSessionStarted(this);
    addInitialStreams();
    _maxParticipants = livekitRoom.remoteParticipants.length + 1;
    UiStall.callStarted();
    _callStats = CallStats.start(livekitRoom,
        encrypted: keyProvider != null,
        reconnects: () => _reconnects,
        keyedParticipants:
            keyProvider == null ? null : () => keyProvider!.keyedParticipants);

    final listener = livekitRoom.createListener();
    // Vommet: who's talking (onActiveSpeakersChanged, registered below),
    // mutes and who's in the call, for the sidebar.
    void participantsChanged(_) => _participantsChanged.add(null);
    listener.on<lk.TrackMutedEvent>(participantsChanged);
    listener.on<lk.TrackUnmutedEvent>(participantsChanged);
    listener.on<lk.TrackPublishedEvent>(participantsChanged);
    listener.on<lk.TrackUnpublishedEvent>(participantsChanged);
    listener.on<lk.LocalTrackPublishedEvent>(participantsChanged);
    listener.on<lk.LocalTrackUnpublishedEvent>(participantsChanged);
    listener.on<lk.ParticipantConnectedEvent>(participantsChanged);
    listener.on<lk.ParticipantDisconnectedEvent>(participantsChanged);
    listener.on(onTrackPublished);
    listener.on(onTrackUnpublished);
    listener.on(onLocalTrackPublished);
    listener.on(onLocalTrackUnpublished);
    listener.on(onTrackStreamEvent);
    listener.on(onTrackSubscribed);
    listener.on(onTrackMutedEvent);
    listener.on(onTrackUnmutedEvent);
    listener.on(onParticipantConnected);
    listener.on(onParticipantDisconnected);
    listener.on(onLocalAudioSenderStats);
    listener.on(onActiveSpeakersChanged);
    listener.on<lk.RoomReconnectedEvent>((_) => _reconnects++);
    listener.on<lk.RoomDisconnectedEvent>((event) {
      if (state == VoipState.ended || _hangingUp) return;
      _recordEnd("disconnected");
      // Vommet: LiveKit gave up reconnecting (or the server dropped us), so
      // this call is over. End it here too: it stayed open on screen, and
      // our membership (refreshed, heartbeat kept alive) kept showing us in
      // the call for hours (Vommet issue 749).
      if (!endsCall(event.reason)) return;
      Log.w("Call connection lost (${event.reason}), ending the call");
      unawaited(hangUpCall());
    });

    listener.emitter.listen((e) => Log.i("Stream event: $e"));

    // Vommet: your own row lights up from your microphone's level.
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (state == VoipState.ended) {
        timer.cancel();
        return;
      }
      _pollSelfSpeaking();
    });
    keyProvider?.init(livekitRoom.localParticipant!.identity, livekitRoom);
    // Vommet: other people's screen shares wait for Watch stream.
    LivekitStreamWatching.attach(this);

    LivekitCallDiagnostics.attach(livekitRoom, () => streams);
    startHeartbeat();
    _membershipStartMs = DateTime.now().millisecondsSinceEpoch;
    _scheduleMembershipRefresh();
  }

  void _scheduleMembershipRefresh() {
    _membershipRefreshTimer?.cancel();
    final due = MatrixRtcMembership.refreshDueAt(
        _membershipStartMs, _membershipRefreshIteration + 1);
    final wait = due - DateTime.now().millisecondsSinceEpoch;
    _membershipRefreshTimer =
        Timer(Duration(milliseconds: wait < 0 ? 0 : wait), _refreshMembership);
  }

  void stopMembershipRefresh() {
    _membershipRefreshTimer?.cancel();
    _membershipRefreshTimer = null;
  }

  /// Re-posts our membership with `created_ts` kept and `expires` grown by
  /// one lifetime. Everything else (foci, focus selection) is re-sent as it
  /// currently is, so a multi-SFU migration in between is kept.
  Future<void> _refreshMembership() async {
    if (state == VoipState.ended) return;
    final key = MatrixRtcMultiSfu.selfStateKey(room);
    final current = room
        .matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent]?[key];
    if (current is! mx.Event || current.content.isEmpty) {
      Log.w("Call membership refresh: our membership is gone, not refreshing");
      return;
    }
    final iteration = _membershipRefreshIteration + 1;
    final content = MatrixRtcMembership.refreshed(current.content,
        current.originServerTs.millisecondsSinceEpoch, iteration);
    try {
      await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
          MatrixVoipRoomComponent.callMemberStateEvent, key, content);
      _membershipRefreshIteration = iteration;
      Log.i("Call membership refreshed (expires in "
          "${content["expires"] ~/ 3600000} h from created_ts)");
    } catch (e) {
      Log.e("Call membership refresh failed, retrying in a minute: $e");
      _membershipRefreshTimer =
          Timer(const Duration(minutes: 1), _refreshMembership);
      return;
    }
    if (state != VoipState.ended) _scheduleMembershipRefresh();
  }

  // Diagnostics (see Telemetry): call length, reconnects, peak size.
  final Stopwatch _callClock = Stopwatch()..start();
  int _reconnects = 0;
  int _maxParticipants = 0;
  bool _hangingUp = false;
  bool _endRecorded = false;
  CallStats? _callStats;

  void _recordEnd(String reason) {
    _callStats?.stop();
    if (_endRecorded) return;
    _endRecorded = true;
    UiStall.callEnded(_maxParticipants);
    Telemetry.record("call_end", {
      "kind": "matrixrtc",
      "seconds": (_callClock.elapsedMilliseconds ~/ 1000).clamp(0, 2592000),
      "reason": reason,
      "reconnects": _reconnects,
      "max_participants": _maxParticipants,
    });
  }

  StreamController _stateChanged = StreamController.broadcast();
  final StreamController<VoipState> _onConnectionChanged =
      StreamController.broadcast();

  @override
  Stream<VoipState> get onConnectionStateChanged => _onConnectionChanged.stream;

  void addInitialStreams() {
    if (livekitRoom.localParticipant != null) {
      for (var entry
          in livekitRoom.localParticipant!.trackPublications.entries) {
        if (entry.value.muted && entry.value.kind == lk.TrackType.VIDEO) {
          continue;
        }

        _addStream(entry.value, client.self!.identifier);
      }
    }

    for (var entry in livekitRoom.remoteParticipants.entries) {
      for (var stream in entry.value.trackPublications.entries) {
        if (stream.value.kind == lk.TrackType.VIDEO && stream.value.muted) {
          continue;
        }

        final userId = userIdOfIdentity(entry.key);

        _addStream(stream.value, userId);
      }
    }
  }

  void _addStream(lk.TrackPublication track, String userId) {
    var stream = MatrixLivekitVoipStream(track, userId);

    stream.onStreamChanged.listen((_) {
      print("Stream changed!!!");
      _stateChanged.add(());
    });

    streams.add(stream);

    _stateChanged.add(());
  }

  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) {
    throw UnimplementedError();
  }

  /// Vommet (multi-SFU): tells the call view the stream list changed after
  /// tracks from another SFU's LiveKit room were added or removed.
  void notifyStreamsChanged() => _stateChanged.add(());

  void onTrackStreamEvent(lk.TrackStreamStateUpdatedEvent event) {
    vommetAdoptPublication(streams, event.publication);
    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }
  }

  void onTrackMutedEvent(lk.TrackMutedEvent event) {
    // Vommet: by kind, since an unsubscribed publication has no track and
    // its tile was never removed.
    if (event.publication.kind == lk.TrackType.VIDEO) {
      streams.removeWhere((e) =>
          (e as MatrixLivekitVoipStream).publication.sid ==
          event.publication.sid);
    }

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    print("Track muted");

    _stateChanged.add(());
  }

  void onTrackUnmutedEvent(lk.TrackUnmutedEvent event) {
    final participant = userIdOfIdentity(event.participant.identity);

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    if (vommetAdoptPublication(streams, event.publication)) {
      return;
    }

    _addStream(event.publication, participant);
    _stateChanged.add(());
  }

  void onTrackPublished(lk.TrackPublishedEvent event) {
    final participant = userIdOfIdentity(event.participant.identity);

    // Vommet: like addInitialStreams, no tile for muted video (camera off)
    // and none twice for the same publication.
    if (event.publication.kind == lk.TrackType.VIDEO &&
        event.publication.muted) {
      return;
    }
    if (vommetAdoptPublication(streams, event.publication)) {
      return;
    }

    _addStream(event.publication, participant);
    _stateChanged.add(());
  }

  void onTrackSubscribed(lk.TrackSubscribedEvent event) {
    vommetAdoptPublication(streams, event.publication);
    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onTrackSubscribed();
      }
    }

    _stateChanged.add(());
  }

  void onParticipantConnected(lk.ParticipantConnectedEvent event) {
    _maxParticipants =
        max(_maxParticipants, livekitRoom.remoteParticipants.length + 1);
    clientManager?.callManager.joinCallSound();
  }

  void onParticipantDisconnected(lk.ParticipantDisconnectedEvent event) {
    clientManager?.callManager.endCallSound();
  }

  void onActiveSpeakersChanged(lk.ActiveSpeakersChangedEvent event) {
    for (var track in streams) {
      if (track.type == VoipStreamType.audio) {
        final t = track as MatrixLivekitVoipStream;
        t.markAsSpeaker(event.speakers
            .any((i) => i.identity == track.publication.participant.identity));
      }
    }

    _onVolumeChanged.add(());

    // Vommet: the sidebar's who's-talking set.
    _speaking = {for (final p in event.speakers) _userIdOf(p.identity)};
    _participantsChanged.add(null);
  }

  void onLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    final participant = userIdOfIdentity(event.participant.identity);

    _addStream(event.publication, participant);
  }

  void onLocalTrackUnpublished(lk.LocalTrackUnpublishedEvent event) {
    streams.removeWhere((e) =>
        (e as MatrixLivekitVoipStream).publication.sid ==
        event.publication.sid);

    _stateChanged.add(());
  }

  void onTrackUnpublished(lk.TrackUnpublishedEvent event) {
    streams.removeWhere((e) =>
        (e as MatrixLivekitVoipStream).publication.sid ==
        event.publication.sid);

    _stateChanged.add(());
  }

  @override
  Client get client => room.client;

  @override
  VoipState state = VoipState.connected;

  @override
  Future<void> declineCall() {
    throw UnimplementedError();
  }

  /// Vommet: the microphone state when hanging up started. Leaving
  /// unpublishes the microphone while the call still reads as connected, and
  /// that must not look like the user muting (it carried into the next call).
  bool? _micMutedAtHangUp;

  /// Whether LiveKit disconnecting for [reason] ends the call: always,
  /// except when we closed the connection ourselves.
  static bool endsCall(lk.DisconnectReason? reason) =>
      reason != lk.DisconnectReason.clientInitiated;

  @override
  Future<void> hangUpCall() async {
    _micMutedAtHangUp ??= isMicrophoneMuted;

    Log.i("Hanging up call");
    _hangingUp = true;
    _recordEnd("hangup");

    keyProvider?.dispose();
    stopMembershipRefresh();

    // Diagnostics: how long each step of leaving takes, and which one
    // failed (testers saw leaving "take forever", 10-07). A failed step no
    // longer keeps the call open (Vommet issue 749).
    final clock = Stopwatch()..start();
    final steps = await MatrixRtcLeave.runSteps({
      "state": clearRoomCallState,
      "disconnect": disconnectCall,
      "heartbeat": stopHeartbeat,
    });
    Telemetry.record("call_leave", {
      "kind": "matrixrtc",
      "ms": clock.elapsedMilliseconds,
      "state_ms": steps.ms["state"],
      "disconnect_ms": steps.ms["disconnect"],
      "heartbeat_ms": steps.ms["heartbeat"],
      "failed_step": steps.failedStep,
      ...Telemetry.errorFields(steps.failure, withStatus: true),
    });

    state = VoipState.ended;
    _stateChanged.add(());
    _onConnectionChanged.add(state);

    clientManager?.callManager.onSessionEnded(this);
  }

  @override
  bool get isCameraEnabled =>
      livekitRoom.localParticipant?.isCameraEnabled() ?? false;

  @override
  // Vommet: the microphone's own publication. `isMuted` reads the first
  // audio track, which can be the shared screen's audio, so the mute button
  // could show the wrong state.
  bool get isMicrophoneMuted =>
      _micMutedAtHangUp ??
      !(livekitRoom.localParticipant?.isMicrophoneEnabled() ?? false);

  @override
  bool get isSharingScreen =>
      livekitRoom.localParticipant?.isScreenShareEnabled() ?? false;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  String? get remoteUserId => null;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  String? get remoteUserName => null;

  @override
  String get roomId => room.identifier;

  @override
  String get roomName => room.displayName;

  // Vommet: unique per call. Every LiveKit call used "", so two at once (a
  // double join, or calls on two accounts) shared one mute state in
  // CallManager, and ending one removed both from the call list.
  static int _sessions = 0;
  final String _sessionId = "livekit:${++_sessions}";

  @override
  String get sessionId => _sessionId;

  /// Vommet: a participant's Matrix user (LivekitIdentity), also for the
  /// opaque identities newer lk-jwt services give Element Call.
  String userIdOfIdentity(String identity) {
    final state =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    return LivekitIdentity.userId(identity, [
      for (final e
          in state?.entries ?? <MapEntry<String, StrippedStateEvent>>[])
        (sender: e.value.senderId, content: e.value.content, stateKey: e.key),
    ]);
  }

  /// Vommet: our LiveKit token lets us listen but not speak (see
  /// MatrixRtcPublishRights), so the microphone can't be turned on.
  bool listenOnly = false;

  @override
  Future<void> setMicrophoneMute(bool state) async {
    // Vommet: the SFU ignores a listen-only participant's publish, and
    // LiveKit would wait 10 s per tap before failing.
    if (!state && listenOnly) throw const CallListenOnlyException();
    await livekitRoom.localParticipant?.setMicrophoneEnabled(!state);
    _stateChanged.add(());
    _participantsChanged.add(null);
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {
    if (source is WebrtcAndroidScreencaptureSource) {
      // Vommet: awaited, so a failure reaches the caller (and diagnostics)
      // instead of looking like success; typed by reason (no message text).
      try {
        await livekitRoom.localParticipant?.setScreenShareEnabled(true);
      } catch (e) {
        Log.w("Android screen capture failed: $e");
        // Don't leave the "sharing the screen" notification behind.
        try {
          await FlutterBackground.disableBackgroundExecution();
        } catch (_) {}
        throw AndroidScreenCaptureError.from(e);
      }
      Log.i("Got android screen capture source!");
      _stateChanged.add(());
      return;
    }

    final srcid = source is WebrtcBrowserScreenCaptureSource
        ? ''
        : (source as WebrtcScreencaptureSource).source.id;

    // Vommet: one share at a time; a new share replaces the current one
    // (each press used to add another screen-share stream). With the Wayland
    // portal the user picks the source in the system dialog during capture,
    // so the old share goes only once the new one exists (cancelling keeps
    // it). Elsewhere it goes first: dropping an old desktop capturer stops
    // the current screen-share audio, which would be the new share's.
    final pickedDuringCapture = srcid == Helper.portalScreenCastSourceId;
    if (!pickedDuringCapture) await _unpublishScreenShares();

    var bitrate = (preferences.streamBitrate.value * 1_000_000).toInt();
    var framerate = preferences.streamFramerate.value;
    var codec = preferences.streamCodec.value;
    var res = lk.VideoDimensionsPresets.h720_169;

    try {
      var resolution = preferences.streamResolution;
      var parts = resolution.value.split("x");
      res = lk.VideoDimensions(int.parse(parts[0]), int.parse(parts[1]));
    } catch (e, s) {
      Log.onError(e, s, content: "Error calculating desired resolution");
    }

    Log.i(
        "Starting stream with settings: ${preferences.streamBitrate.value}Mbps, ${framerate}FPS, $codec ${res}");

    // Vommet: the audio picked with the source (none / all apps / one app).
    final audio = source is WebrtcScreencaptureSource
        ? source.audio
        : ScreenShareAudio.none;
    Helper.screenCaptureAudioOptions = audio.toCaptureOptions();

    if (WebrtcScreencaptureSource.supportsSystemAudio &&
        audio.kind != ScreenShareAudioKind.none) {
      final tracks = await _captureScreen(() =>
          lk.LocalVideoTrack.createScreenShareTracksWithAudio(
              lk.ScreenShareCaptureOptions(
            sourceId: srcid,
            maxFrameRate: framerate,
            captureScreenAudio: true,
            params: lk.VideoParameters(
              dimensions: lk.VideoDimensionsPresets.h720_169,
              encoding: lk.VideoEncoding(
                  maxFramerate: framerate.toInt(), maxBitrate: bitrate),
            ),
          )));
      if (tracks == null) return;

      if (pickedDuringCapture) await _unpublishScreenShares();

      for (var track in tracks) {
        if (track is lk.LocalVideoTrack) {
          await livekitRoom.localParticipant?.publishVideoTrack(track,
              publishOptions: lk.VideoPublishOptions(
                simulcast: preferences.doSimulcast.value,
                screenShareEncoding: lk.VideoEncoding(
                    maxFramerate: framerate.toInt(), maxBitrate: bitrate),
                videoEncoding: lk.VideoEncoding(
                    maxFramerate: framerate.toInt(), maxBitrate: bitrate),
                videoCodec: preferences.streamCodec.value,
              ));

          track.setDegradationPreference(
              lk.DegradationPreference.maintainFramerate);
        }

        if (track is lk.LocalAudioTrack) {
          await livekitRoom.localParticipant?.publishAudioTrack(track,
              publishOptions: lk.AudioPublishOptions(
                  name: "screenshare",
                  dtx: false,
                  red: false,
                  // Vommet: actually negotiate stereo (our livekit_client fork).
                  stereo: true,
                  encoding: lk.AudioEncoding.presetMusicHighQualityStereo));
        }
      }
      _recordShareAudio(audio, tracks.any((t) => t is lk.LocalAudioTrack));
    } else {
      final track = await _captureScreen(() =>
          lk.LocalVideoTrack.createScreenShareTrack(
              lk.ScreenShareCaptureOptions(
                  sourceId: srcid,
                  maxFrameRate: framerate,
                  params: lk.VideoParameters(
                    dimensions: lk.VideoDimensionsPresets.h720_169,
                    encoding: lk.VideoEncoding(
                        maxFramerate: framerate.toInt(), maxBitrate: bitrate),
                  ))));
      if (track == null) return;
      if (pickedDuringCapture) await _unpublishScreenShares();

      await livekitRoom.localParticipant?.publishVideoTrack(track,
          publishOptions: lk.VideoPublishOptions(
            simulcast: preferences.doSimulcast.value,
            screenShareEncoding: lk.VideoEncoding(
                maxFramerate: framerate.toInt(), maxBitrate: bitrate),
            videoEncoding: lk.VideoEncoding(
                maxFramerate: framerate.toInt(), maxBitrate: bitrate),
            videoCodec: preferences.streamCodec.value,
          ));

      track
          .setDegradationPreference(lk.DegradationPreference.maintainFramerate);
      _recordShareAudio(audio, false);
    }

    _stateChanged.add(());
  }

  /// Vommet: screen-share audio telemetry (desktop shares that could carry
  /// audio; not awaited).
  void _recordShareAudio(ScreenShareAudio audio, bool audioTrack) {
    if (!WebrtcScreencaptureSource.supportsSystemAudio) return;
    unawaited(ScreenShareAudioTelemetry.recordShare(
        audio: audio,
        audioTrack: audioTrack,
        wayland: PlatformUtils.displayServer == "wayland"));
  }

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {
    if (isCameraEnabled) {
      Log.e("Tried to enable camera when camera already enabled!");
      return;
    }

    await livekitRoom.localParticipant?.setCameraEnabled(true);
    _stateChanged.add(());
  }

  @override
  Future<void> stopCamera() async {
    await livekitRoom.localParticipant?.setCameraEnabled(false);

    _stateChanged.add(());
  }

  /// Vommet: creates the screen-share track(s), or null when the user
  /// cancelled the system's screen-capture dialog (Wayland portal).
  Future<T?> _captureScreen<T>(Future<T> Function() capture) async {
    try {
      return await capture();
    } catch (e) {
      final text = e.toString();
      if (text.contains("NotAllowedError") || text.contains("cancelled")) {
        Log.i("Screen share cancelled in the system dialog");
        return null;
      }
      rethrow;
    }
  }

  /// Vommet: unpublishes every screen-share video and audio track.
  /// setScreenShareEnabled(false) only removes the first of each.
  Future<void> _unpublishScreenShares() async {
    final local = livekitRoom.localParticipant;
    if (local == null) return;
    final sids = local.trackPublications.values
        .where((p) =>
            p.source == lk.TrackSource.screenShareVideo ||
            p.source == lk.TrackSource.screenShareAudio)
        .map((p) => p.sid)
        .toList();
    for (final sid in sids) {
      await local.removePublishedTrack(sid);
    }
  }

  @override
  Future<void> stopScreenshare() async {
    if (PlatformUtils.isAndroid) {
      await livekitRoom.localParticipant?.setScreenShareEnabled(false);
    }
    await _unpublishScreenShares();

    if (PlatformUtils.isAndroid) {
      try {
        await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        Log.e('error disabling screen share: $error');
      }
    }

    _stateChanged.add(());
  }

  @override
  List<VoipStream> streams = List<VoipStream>.empty(growable: true);

  @override
  bool get supportsScreenshare => true;

  @override
  Future<void> updateStats() async {}

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      return WebrtcAndroidScreencaptureSource.getCaptureSource(context);
    }
    if (PlatformUtils.isWeb) {
      return WebrtcBrowserScreenCaptureSource();
    }
    return WebrtcScreencaptureSource.showSelectSourcePrompt(context);
  }

  Future<void> clearRoomCallState() async {
    Log.i("Clearing call state");
    final stateKey =
        "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

    // Vommet: wait a moment for the clear, then let the call end on screen;
    // a slow homeserver no longer keeps people in the call (it keeps
    // retrying in the background, see MatrixRtcLeave).
    await MatrixRtcLeave.clear(
        room.matrixRoom.id,
        stateKey,
        () => room.matrixRoom.client.setRoomStateWithKey(
            room.matrixRoom.id,
            MatrixVoipRoomComponent.callMemberStateEvent,
            stateKey, {})).timeout(const Duration(seconds: 3), onTimeout: () {
      Log.w("Call state not cleared yet, finishing it in the background");
    });
  }

  Future<void> stopHeartbeat() async {
    heartbeatTimer?.cancel();
    heartbeatTimer = null;

    if (heartbeatDelayId == null) {
      return;
    }

    await room.matrixRoom.client.request(RequestType.POST,
        "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(heartbeatDelayId!)}",
        contentType: "application/json",
        data: jsonEncode({"action": "cancel"}));

    heartbeatDelayId = null;
    Log.i("Stopped heartbeat");
  }

  Future<void> startHeartbeat() async {
    final capabilities = await room.matrixRoom.client.getVersions();
    Log.d("${capabilities}");
    if (capabilities.unstableFeatures?["org.matrix.msc4140"] != true) {
      Log.e("Homeserver does not support delayed events");
      return;
    }

    final stateKey =
        "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

    final timerLength = Duration(seconds: 30);

    final result = await room.matrixRoom.client.request(RequestType.PUT,
        "/client/v3/rooms/${Uri.encodeComponent(room.matrixRoom.id)}/state/${Uri.encodeComponent(MatrixVoipRoomComponent.callMemberStateEvent)}/${Uri.encodeComponent(stateKey)}",
        contentType: "application/json",
        data: "{}",
        query: {
          "org.matrix.msc4140.delay": timerLength.inMilliseconds.toString()
        });

    final delayId = result["delay_id"] as String;
    heartbeatDelayId = delayId;

    heartbeatTimer =
        Timer.periodic(timerLength - Duration(seconds: 5), (timer) async {
      print("Sending heartbeat");
      final result = await room.matrixRoom.client.request(RequestType.POST,
          "/client/unstable/org.matrix.msc4140/delayed_events/${Uri.encodeComponent(delayId)}",
          contentType: "application/json",
          data: jsonEncode({"action": "restart"}));
      print(result);
    });
  }

  @override
  double get generalAudioLevel {
    double result =
        streams.fold(0.0, (value, stream) => max(value, stream.audiolevel));
    return result;
  }

  @override
  Stream<void> get onUpdateVolumeVisualizers => _onVolumeChanged.stream;

  Future<void> disconnectCall() async {
    Log.i("Disconnecting livekit room");
    await livekitRoom.disconnect();
    Log.i("Disconnected livekit room");
  }

  void onLocalAudioSenderStats(lk.AudioSenderStatsEvent stats) {
    print("Local audio level: ${stats.stats.audioSourceStats?.audioLevel}");
  }

  // Vommet: who's talking and whose microphone is off, for the sidebar.
  final StreamController<void> _participantsChanged =
      StreamController.broadcast();
  Set<String> _speaking = const {};

  /// The Matrix user id in a LiveKit identity (`@user:server:device`).
  /// Newer lk-jwt services give Element Call an opaque identity (a hash, no
  /// `:`); splitting it threw a RangeError in the voice room list's build,
  /// drawn as an error box. Such a participant is keyed by the identity.
  static String _userIdOf(String identity) {
    final parts = identity.split(":");
    return parts.length < 2 ? identity : parts.take(2).join(":");
  }

  // Vommet: the server's active speakers need a louder voice than a
  // whisper, so your own row also follows your microphone's level (as on
  // Discord): others could hear you while your row stayed dark.
  final LocalVoiceLevel _selfLevel = LocalVoiceLevel();
  bool _selfSpeaking = false;
  bool _pollingSelf = false;

  Future<void> _pollSelfSpeaking() async {
    if (_pollingSelf) return;
    _pollingSelf = true;
    try {
      final track = livekitRoom.localParticipant
          ?.getTrackPublicationBySource(lk.TrackSource.microphone)
          ?.track;
      bool? loud;
      if (track is lk.LocalAudioTrack && !track.muted) {
        final source = (await track.getSenderStats())?.audioSourceStats;
        loud = _selfLevel.update(
            source?.totalAudioEnergy, source?.totalSamplesDuration);
      } else {
        _selfLevel.reset();
        loud = false;
      }
      if (loud != null && loud != _selfSpeaking) {
        _selfSpeaking = loud;
        _participantsChanged.add(null);
      }
    } catch (_) {
      // Stats can fail while the track is being replaced; try next time.
    } finally {
      _pollingSelf = false;
    }
  }

  @override
  Set<String> get speakingUserIds =>
      _selfSpeaking ? {..._speaking, room.client.self!.identifier} : _speaking;

  @override
  Set<String> get micOffUserIds {
    final participants = <lk.Participant>[
      if (livekitRoom.localParticipant != null) livekitRoom.localParticipant!,
      ...livekitRoom.remoteParticipants.values,
    ];
    // Someone in the call on two devices is "off" only if both are.
    final on = <String>{
      for (final p in participants)
        if (p.isMicrophoneEnabled()) _userIdOf(p.identity),
    };
    return {
      for (final p in participants)
        if (!on.contains(_userIdOf(p.identity))) _userIdOf(p.identity),
    };
  }

  @override
  Stream<void> get onParticipantsChanged => _participantsChanged.stream;
}

/// Vommet: unmuting in a call whose SFU lets us listen only.
class CallListenOnlyException implements Exception {
  const CallListenOnlyException();

  @override
  String toString() =>
      "This call's server lets you listen but not speak, and your homeserver "
      "has no call server of its own to speak from";
}
