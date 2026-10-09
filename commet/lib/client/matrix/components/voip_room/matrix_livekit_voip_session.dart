import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/screen_share_audio.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/webrtc_screencapture_source.dart';
import 'package:commet/client/components/voip/android_screencapture_source.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix_api_lite.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

class MatrixLivekitVoipSession implements VoipSession {
  MatrixRoom room;
  lk.Room livekitRoom;
  Timer? heartbeatTimer;
  String? heartbeatDelayId;

  MatrixLivekitEncryptionKeyProvider? keyProvider;

  final StreamController<void> _onVolumeChanged = StreamController.broadcast();

  MatrixLivekitVoipSession(this.room, this.livekitRoom, {this.keyProvider}) {
    clientManager?.callManager.onClientSessionStarted(this);
    addInitialStreams();
    _maxParticipants = livekitRoom.remoteParticipants.length + 1;

    final listener = livekitRoom.createListener();
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
    listener.on<lk.RoomReconnectedEvent>((_) => _reconnects++);
    listener.on<lk.RoomDisconnectedEvent>((_) {
      if (state != VoipState.ended && !_hangingUp) _recordEnd("disconnected");
    });

    Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (state == VoipState.ended) timer.cancel();
      _onVolumeChanged.add(());
    });

    keyProvider?.init(livekitRoom.localParticipant!.identity, livekitRoom);

    startHeartbeat();
  }

  // Diagnostics (see Telemetry): call length, reconnects, peak size.
  final Stopwatch _callClock = Stopwatch()..start();
  int _reconnects = 0;
  int _maxParticipants = 0;
  bool _hangingUp = false;
  bool _endRecorded = false;

  void _recordEnd(String reason) {
    if (_endRecorded) return;
    _endRecorded = true;
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

        streams.add(
            MatrixLivekitVoipStream(entry.value, room.client.self!.identifier));
      }
    }

    for (var entry in livekitRoom.remoteParticipants.entries) {
      for (var stream in entry.value.trackPublications.entries) {
        if (stream.value.kind == lk.TrackType.VIDEO && stream.value.muted) {
          continue;
        }

        String userId = entry.key;
        userId = userId.split(":").getRange(0, 2).join(":");

        streams.add(MatrixLivekitVoipStream(stream.value, userId));
      }
    }
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
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    for (var track in streams) {
      final t = track as MatrixLivekitVoipStream;
      if (t.publication.sid == event.publication.sid) {
        t.onStreamUpdatedEvent();
      }
    }

    if (streams.any((e) => e.streamId == event.publication.sid)) {
      return;
    }

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
  }

  void onTrackPublished(lk.TrackPublishedEvent event) {
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    // Vommet: like addInitialStreams, no tile for muted video (camera off)
    // and none twice for the same publication.
    if (event.publication.kind == lk.TrackType.VIDEO &&
        event.publication.muted) {
      return;
    }
    if (streams.any((e) => e.streamId == event.publication.sid)) {
      return;
    }

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
  }

  void onTrackSubscribed(lk.TrackSubscribedEvent event) {
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

  void onLocalTrackPublished(lk.LocalTrackPublishedEvent event) {
    final participant =
        event.participant.identity.split(":").getRange(0, 2).join(":");

    streams.add(MatrixLivekitVoipStream(event.publication, participant));
    _stateChanged.add(());
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

  @override
  Future<void> hangUpCall() async {
    Log.i("Hanging up call");
    _hangingUp = true;
    _recordEnd("hangup");

    keyProvider?.dispose();

    // Diagnostics: how long each step of leaving takes, and which one
    // failed (testers saw leaving "take forever", 10-07).
    final clock = Stopwatch()..start();
    final stepMs = <String, int>{};
    String failedStep = "none";
    Object? failure;
    Future<void> timed(String name, Future<void> Function() step) async {
      final stepClock = Stopwatch()..start();
      try {
        await step();
      } catch (e) {
        if (failure == null) {
          failure = e;
          failedStep = name;
        }
        rethrow;
      } finally {
        stepMs[name] = stepClock.elapsedMilliseconds;
      }
    }

    try {
      await Future.wait([
        timed("state", clearRoomCallState),
        timed("disconnect", disconnectCall),
        timed("heartbeat", stopHeartbeat),
      ]);
    } finally {
      Telemetry.record("call_leave", {
        "kind": "matrixrtc",
        "ms": clock.elapsedMilliseconds,
        "state_ms": stepMs["state"],
        "disconnect_ms": stepMs["disconnect"],
        "heartbeat_ms": stepMs["heartbeat"],
        "failed_step": failedStep,
        ...Telemetry.errorFields(failure, withStatus: true),
      });
    }

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

  @override
  String get sessionId => "";

  @override
  Future<void> setMicrophoneMute(bool state) async {
    await livekitRoom.localParticipant?.setMicrophoneEnabled(!state);
    _stateChanged.add(());
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

    // Vommet: one share at a time; a new share replaces the current one
    // (each press used to add another screen-share stream).
    await _unpublishScreenShares();

    final srcid = source is WebrtcBrowserScreenCaptureSource
        ? ''
        : (source as WebrtcScreencaptureSource).source.id;

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
      var tracks = await lk.LocalVideoTrack.createScreenShareTracksWithAudio(
          lk.ScreenShareCaptureOptions(
        sourceId: srcid,
        maxFrameRate: framerate,
        captureScreenAudio: true,
        params: lk.VideoParameters(
          dimensions: lk.VideoDimensionsPresets.h720_169,
          encoding: lk.VideoEncoding(
              maxFramerate: framerate.toInt(), maxBitrate: bitrate),
        ),
      ));

      print(tracks);

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
          // Vommet: livekit_client implements setAudioProcessingOptions only
          // on iOS, macOS and Android, so on Linux and Windows it always
          // threw (logged on every share). Not needed there either: the
          // loopback capture is a custom source that skips audio processing.
          if (!PlatformUtils.isLinux && !PlatformUtils.isWindows) {
            try {
              // ignore: experimental_member_use
              await track.setAudioProcessingOptions(
                  // ignore: experimental_member_use
                  lk.AudioProcessingOptions.noProcessing());
            } catch (e, s) {
              Log.w(
                  "Failed to set audio processing options on screenshare audio track");
              Log.onError(e, s);
            }
          }

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
    } else {
      var track = await lk.LocalVideoTrack.createScreenShareTrack(
          lk.ScreenShareCaptureOptions(
              sourceId: srcid,
              maxFrameRate: framerate,
              params: lk.VideoParameters(
                dimensions: lk.VideoDimensionsPresets.h720_169,
                encoding: lk.VideoEncoding(
                    maxFramerate: framerate.toInt(), maxBitrate: bitrate),
              )));

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
    }

    _stateChanged.add(());
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

    await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent, stateKey, {});

    Log.i("Cleared call state");
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
}
