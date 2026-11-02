import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/matrix/components/room_call/matrix_room_call_component.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Vommet: an Element-style call ringing us (MSC4075 call notification with
/// "ring"), shown through the same incoming-call UI as a legacy 1:1 call:
/// ringtone, notification, accept/decline. Accepting joins the room call.
class MatrixRoomCallInvite implements VoipSession {
  final MatrixRoomCallComponent component;
  final String eventId;
  final String callerId;
  Timer? _expiry;
  StreamSubscription? _participants;
  bool _sawCaller = false;

  MatrixRoomCallInvite(this.component,
      {required this.eventId, required this.callerId, required Duration ring}) {
    _expiry = Timer(ring, _end);
    // Stop ringing if the caller hangs up first.
    // (Their membership may arrive after the notification.)
    _participants = component.onParticipantsChanged.listen((_) {
      final inCall = component.getCurrentParticipants().contains(callerId);
      if (inCall) _sawCaller = true;
      if (_sawCaller && !inCall) _end();
    });
  }

  @override
  VoipState state = VoipState.incoming;

  final StreamController<VoipState> _connection = StreamController.broadcast();
  final StreamController<void> _changed = StreamController.broadcast();

  void _end() {
    if (state == VoipState.ended) return;
    state = VoipState.ended;
    _expiry?.cancel();
    _participants?.cancel();
    _connection.add(state);
    _changed.add(null);
    clientManager?.callManager.onSessionEnded(this);
  }

  @override
  Future<void> acceptCall(
      {bool withMicrophone = false, bool withCamera = false}) async {
    _end();
    try {
      await component.joinCall();
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to join the call we were rung for");
    }
  }

  @override
  Future<void> declineCall() async => _end();

  @override
  Future<void> hangUpCall() async => _end();

  @override
  Client get client => component.client;

  @override
  String get sessionId => "room-call-invite:$eventId";

  @override
  String get roomId => component.room.identifier;

  @override
  String get roomName => component.room.displayName;

  @override
  String? get remoteUserId => callerId;

  @override
  String? get remoteUserName =>
      component.room.getMemberOrFallback(callerId).displayName;

  @override
  Stream<VoipState> get onConnectionStateChanged => _connection.stream;

  @override
  Stream<void> get onStateChanged => _changed.stream;

  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream.empty();

  @override
  bool get isMicrophoneMuted => false;

  @override
  bool get supportsScreenshare => false;

  @override
  bool get isSharingScreen => false;

  @override
  bool get isCameraEnabled => false;

  @override
  double get generalAudioLevel => 0;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  List<VoipStream> get streams => const [];

  @override
  Future<void> setMicrophoneMute(bool state) async {}

  @override
  Future<void> updateStats() async {}

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async =>
      null;

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {}

  @override
  Future<void> stopScreenshare() async {}

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {}

  @override
  Future<void> stopCamera() async {}
}
