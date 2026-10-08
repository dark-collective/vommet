import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/voip/voip_stream.dart';
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
  /// speaking indicator was never set up for people who joined later).
  void onTrackSubscribed() {
    _attachAudio();
    onStreamUpdatedEvent();
  }

  void _attachAudio() {
    if (visualizer != null) return;
    if (publication.track case AudioTrack t) {
      visualizer = createVisualizer(t,
          options:
              AudioVisualizerOptions(barCount: 1, smoothTransition: false));

      applyPlaybackVolume();

      var _listener = visualizer!.createListener();
      _listener.on<AudioVisualizerEvent>((e) {
        setAudioLevel(e);
      });

      visualizer!.start();
    }
  }

  @override
  double audiolevel = 0.0;

  void setAudioLevel(AudioVisualizerEvent e) {
    audiolevel = (e.event[0] as double) > 0.5 ? 1 : 0;
  }

  void onStreamUpdatedEvent() {
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

    if (isAudio && publication.name == "screenshare") {
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
    await applyPlaybackVolume();
  }

  @override
  Future<void> applyPlaybackVolume() async {
    if (publication.track case AudioTrack track) {
      final incoming = direction == VoipStreamDirection.incoming;
      final calls = clientManager?.callManager;
      final deafened = incoming && (calls?.isDeafened ?? false);
      final output = incoming ? (calls?.outputVolume ?? 1.0) : 1.0;
      await Helper.setVolume(
          deafened ? 0 : volume * output, track.mediaStreamTrack);
    }
  }

  @override
  double get volume => preferences.getVoipUserVolume(volumeKey);

  @override
  String get participantId => publication.participant.identity;
}
