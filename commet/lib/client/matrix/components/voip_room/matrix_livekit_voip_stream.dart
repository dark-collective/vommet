import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

class MatrixLivekitVoipStream implements VoipStream {
  TrackPublication publication;
  String userId;

  AudioVisualizer? visualizer;

  StreamController _onChanged = StreamController.broadcast();

  @override
  Stream<void> get onStreamChanged => _onChanged.stream;

  MatrixLivekitVoipStream(this.publication, this.userId) {
    _attachAudio();
  }

  /// Vommet: a remote publication usually arrives before its track is
  /// subscribed, so the session calls this again on TrackSubscribed (the
  /// saved volume was never applied for people who joined later, and the
  /// tile was not redrawn once the track arrived).
  void onTrackSubscribed() {
    _attachAudio();
    onStreamUpdatedEvent();
  }

  void _attachAudio() {
    if (publication.track is AudioTrack) {
      if (volume != 1.0) {
        Log.i("Call volume: sid=${publication.sid} track arrived, "
            "applying the saved volume $volume");
      }
      applyPlaybackVolume();
    }
  }

  @override
  double audiolevel = 0.0;

  void markAsSpeaker(bool isSpeaker) {
    audiolevel = isSpeaker ? 1.0 : 0.0;
  }

  void onStreamUpdatedEvent() {
    print("Stream updated!");
    _onChanged.add(());
  }

  @override
  double? get aspectRatio {
    if (publication.dimensions == null) {
      return null;
    }
    return publication.dimensions!.width.toDouble() /
        publication.dimensions!.height.toDouble();
  }

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) {
    if (publication.track is VideoTrack) {
      return VideoTrackRenderer(publication.track as VideoTrack);
    }

    return null;
  }

  @override
  VoipStreamDirection get direction => publication is LocalTrackPublication
      ? VoipStreamDirection.outgoing
      : VoipStreamDirection.incoming;

  @override
  String get label => "label";

  @override
  String get streamId => publication.sid;

  @override
  String get streamUserId => userId;

  @override
  VoipStreamType get type {
    // Vommet: fall back to the publication's kind while the track is not
    // subscribed yet; a late joiner's microphone was typed as video and
    // shown as a tile that spun forever.
    final isAudio = publication.track is AudioTrack ||
        (publication.track == null && publication.kind == TrackType.AUDIO);

    // Vommet: by source too. Only Commet names its share audio
    // "screenshare"; other senders' share audio (golive-relay's
    // "screen-audio") was typed as a microphone, so it kept playing after
    // you stopped watching the share and followed the person's volume.
    if (isAudio &&
        (publication.source == TrackSource.screenShareAudio ||
            publication.name == "screenshare")) {
      return VoipStreamType.screenshareAudio;
    }

    if (isAudio) {
      return VoipStreamType.audio;
    }

    if (publication.isScreenShare) {
      return VoipStreamType.screenshare;
    }

    return VoipStreamType.video;
  }

  @override
  bool get isMuted => publication.track?.muted ?? false;

  @override
  // TODO: implement stats
  String get stats => JsonEncoder.withIndent("  ").convert({
        "is encrypted": publication.participant.isEncrypted,
        "encryption type": publication.encryptionType.toString(),
        "publication": publication.name
      });

  String get volumeKey =>
      type == VoipStreamType.screenshareAudio ? "stream:${userId}" : userId;

  @override
  Future<void> setVolume(double volume) async {
    preferences.setVoipUserVolume(volumeKey, volume);
    await _applyPlaybackVolume(fromSlider: true);
  }

  @override
  Future<void> applyPlaybackVolume() => _applyPlaybackVolume(fromSlider: false);

  /// Vommet: a volume change that didn't take effect used to vanish without
  /// a trace (no track yet, or the native call failed unawaited). Slider
  /// changes and every failure are now logged.
  Future<void> _applyPlaybackVolume({required bool fromSlider}) async {
    final track = publication.track;
    if (track is! AudioTrack) {
      if (fromSlider) {
        _logVolume("pending",
            "no audio track yet, $volume is saved and applied when it arrives");
      }
      return;
    }
    final incoming = direction == VoipStreamDirection.incoming;
    final calls = clientManager?.callManager;
    final deafened = incoming && (calls?.isDeafenedFor(this) ?? false);
    final output = incoming ? (calls?.outputVolume ?? 1.0) : 1.0;
    final applied = deafened ? 0.0 : volume * output;
    final detail = "track=${track.mediaStreamTrack.id} volume=$volume "
        "output=$output deafened=$deafened applied=$applied";
    try {
      await Helper.setVolume(applied, track.mediaStreamTrack);
      if (fromSlider) _logVolume("applied", detail);
    } catch (e) {
      _logVolume("failed", "$detail error: $e");
    }
  }

  // The slider calls setVolume for every step of a drag: one line per
  // outcome, then at most one every two seconds while it stays the same.
  String? _lastVolumeOutcome;
  DateTime _lastVolumeLog = DateTime.fromMillisecondsSinceEpoch(0);

  void _logVolume(String outcome, String detail) {
    final now = DateTime.now();
    if (outcome == _lastVolumeOutcome &&
        now.difference(_lastVolumeLog) < const Duration(seconds: 2)) {
      return;
    }
    _lastVolumeOutcome = outcome;
    _lastVolumeLog = now;
    final line = "Call volume: sid=${publication.sid} $outcome, $detail";
    outcome == "failed" ? Log.w(line) : Log.i(line);
  }

  @override
  double get volume => preferences.getVoipUserVolume(volumeKey);

  @override
  String get participantId => publication.participant.identity;
}
