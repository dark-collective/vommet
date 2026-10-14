// Vommet (schema v17): how a call is doing while it runs, once a minute as a
// `call_stats` event, so "robotic audio", "I can't hear X" and "video is a
// slideshow" reports come with numbers. Reads WebRTC's own counters through
// LiveKit (one getStats per track per minute, off the UI thread) and reports
// the change since the previous sample: packets received and lost, jitter,
// concealed audio (the audible glitches), bitrate, round-trip time, video
// frame rate and size. Never which participant, never any audio or video.
//
// Schema v23 adds why a remote voice can be missing: how many audio tracks
// are published, muted, not subscribed, or subscribed but not receiving
// packets, and in encrypted calls each subscribed track's decryption state
// (working, waiting, missing its key, failing), how many were subscribed
// before their sender's media key had arrived, and how many remote
// participants a key has arrived from. Counts only; identities stay on the
// device.

import 'dart:async';

import 'package:commet/telemetry/telemetry.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
// The stats classes are not re-exported by the package entry point.
import 'package:livekit_client/src/stats/stats.dart' as lk;

/// Cumulative WebRTC counters from the previous sample, per track.
class TrackCounters {
  num packets = 0;
  num lost = 0;
  num bytes = 0;
  num concealedSamples = 0;
  num concealments = 0;
  num dropped = 0;
  num limited = 0;
  num timestampMs = 0;
}

/// One sample's totals, before they become an event. Public so the delta
/// arithmetic can be unit-tested without LiveKit.
class CallSample {
  int audioRxTracks = 0;
  int rxPackets = 0;
  int rxLost = 0;
  int rxJitterMs = 0;
  int rxConcealedMs = 0;
  int rxConcealments = 0;
  int rxBytes = 0;
  int txPackets = 0;
  int txLost = 0;
  int? txRttMs;
  int txJitterMs = 0;
  int txBytes = 0;
  int videoRxTracks = 0;
  int audioPublished = 0;
  int audioMuted = 0;
  int audioUnsubscribed = 0;
  int audioRxNoPackets = 0;
  int e2eeOk = 0;
  int e2eePending = 0;
  int e2eeMissingKey = 0;
  int e2eeFailed = 0;
  int subscribedBeforeKey = 0;
  int keyedParticipants = 0;
  bool encrypted = false;
  int videoRxFps = 0;
  int videoRxHeight = 0;
  int videoRxDropped = 0;
  int videoTxHeight = 0;
  int videoTxFps = 0;
  int videoTxLimited = 0;
  int elapsedMs = 0;

  static int _delta(num? now, num prev) =>
      now == null ? 0 : (now - prev).clamp(0, 1000000).toInt();

  /// Audio playback stats for one remote track. Concealed samples are at
  /// the track's clock, 48 kHz for Opus.
  void addAudioReceiver(lk.AudioReceiverStats s, TrackCounters prev) {
    audioRxTracks++;
    final packets = _delta(s.packetsReceived, prev.packets);
    if (packets == 0) audioRxNoPackets++;
    rxPackets += packets;
    rxLost += _delta(s.packetsLost, prev.lost);
    rxBytes += _delta(s.bytesReceived, prev.bytes);
    rxConcealedMs += _delta(s.concealedSamples, prev.concealedSamples) ~/ 48;
    rxConcealments += _delta(s.concealmentEvents, prev.concealments);
    final jitter = ((s.jitter ?? 0) * 1000).round();
    if (jitter > rxJitterMs) rxJitterMs = jitter;
    prev.packets = s.packetsReceived ?? prev.packets;
    prev.lost = s.packetsLost ?? prev.lost;
    prev.bytes = s.bytesReceived ?? prev.bytes;
    prev.concealedSamples = s.concealedSamples ?? prev.concealedSamples;
    prev.concealments = s.concealmentEvents ?? prev.concealments;
  }

  /// One remote audio publication, subscribed or not. [e2ee] is the last
  /// state LiveKit reported for its decryptor (null: none yet).
  void addRemoteAudio(
      {required bool subscribed,
      required bool muted,
      lk.E2EEState? e2ee,
      bool beforeKey = false}) {
    audioPublished++;
    if (muted) audioMuted++;
    if (!subscribed) {
      audioUnsubscribed++;
      return;
    }
    if (!encrypted) return;
    if (beforeKey) subscribedBeforeKey++;
    switch (e2ee) {
      case lk.E2EEState.kOk:
      case lk.E2EEState.kKeyRatcheted:
        e2eeOk++;
      case lk.E2EEState.kMissingKey:
        e2eeMissingKey++;
      case lk.E2EEState.kEncryptionFailed:
      case lk.E2EEState.kDecryptionFailed:
      case lk.E2EEState.kInternalError:
        e2eeFailed++;
      case lk.E2EEState.kNew:
      case null:
        e2eePending++;
    }
  }

  void addVideoReceiver(lk.VideoReceiverStats s, TrackCounters prev) {
    videoRxTracks++;
    rxPackets += _delta(s.packetsReceived, prev.packets);
    rxLost += _delta(s.packetsLost, prev.lost);
    rxBytes += _delta(s.bytesReceived, prev.bytes);
    videoRxDropped += _delta(s.framesDropped, prev.dropped);
    final fps = (s.framesPerSecond ?? 0).round();
    if (fps > videoRxFps) videoRxFps = fps;
    final h = (s.frameHeight ?? 0).round();
    if (h > videoRxHeight) videoRxHeight = h;
    prev.packets = s.packetsReceived ?? prev.packets;
    prev.lost = s.packetsLost ?? prev.lost;
    prev.bytes = s.bytesReceived ?? prev.bytes;
    prev.dropped = s.framesDropped ?? prev.dropped;
  }

  /// Our own microphone or camera as the server sees it (losses and jitter
  /// are reported back by the server; round-trip time is to the SFU).
  void addSender(lk.SenderStats s, TrackCounters prev) {
    txPackets += _delta(s.packetsSent, prev.packets);
    txLost += _delta(s.packetsLost, prev.lost);
    txBytes += _delta(s.bytesSent, prev.bytes);
    final jitter = ((s.jitter ?? 0) * 1000).round();
    if (jitter > txJitterMs) txJitterMs = jitter;
    if (s.roundTripTime != null) {
      final rtt = (s.roundTripTime! * 1000).round();
      if (txRttMs == null || rtt > txRttMs!) txRttMs = rtt;
    }
    if (s is lk.VideoSenderStats) {
      final fps = (s.framesPerSecond ?? 0).round();
      if (fps > videoTxFps) videoTxFps = fps;
      final h = (s.frameHeight ?? 0).round();
      if (h > videoTxHeight) videoTxHeight = h;
      videoTxLimited +=
          _delta(s.qualityLimitationResolutionChanges, prev.limited);
      prev.limited = s.qualityLimitationResolutionChanges ?? prev.limited;
    }
    prev.packets = s.packetsSent ?? prev.packets;
    prev.lost = s.packetsLost ?? prev.lost;
    prev.bytes = s.bytesSent ?? prev.bytes;
  }

  static int _kbps(int bytes, int ms) =>
      ms <= 0 ? 0 : (bytes * 8 / ms).round().clamp(0, 1000000);

  Map<String, Object?> fields() => {
        "audio_rx_tracks": audioRxTracks,
        "rx_packets": rxPackets,
        "rx_lost": rxLost,
        "rx_jitter_ms": rxJitterMs.clamp(0, 86400000),
        "rx_concealed_ms": rxConcealedMs.clamp(0, 86400000),
        "rx_concealments": rxConcealments,
        "rx_kbps": _kbps(rxBytes, elapsedMs),
        "tx_packets": txPackets,
        "tx_lost": txLost,
        if (txRttMs != null) "tx_rtt_ms": txRttMs!.clamp(0, 86400000),
        "tx_jitter_ms": txJitterMs.clamp(0, 86400000),
        "tx_kbps": _kbps(txBytes, elapsedMs),
        "video_rx_tracks": videoRxTracks,
        "audio_published": audioPublished,
        "audio_muted": audioMuted,
        "audio_unsubscribed": audioUnsubscribed,
        "audio_rx_no_packets": audioRxNoPackets,
        if (encrypted) ...{
          "e2ee_ok": e2eeOk,
          "e2ee_pending": e2eePending,
          "e2ee_missing_key": e2eeMissingKey,
          "e2ee_failed": e2eeFailed,
          "subscribed_before_key": subscribedBeforeKey,
          "keyed_participants": keyedParticipants,
        },
        if (videoRxTracks > 0) ...{
          "video_rx_fps": videoRxFps.clamp(0, 1000000),
          "video_rx_height": videoRxHeight.clamp(0, 100000),
          "video_rx_dropped": videoRxDropped,
        },
        if (videoTxHeight > 0) ...{
          "video_tx_height": videoTxHeight.clamp(0, 100000),
          "video_tx_fps": videoTxFps.clamp(0, 1000000),
          "video_tx_limited": videoTxLimited,
        },
      };
}

class CallStats {
  static const period = Duration(seconds: 60);

  final lk.Room room;
  final bool encrypted;
  final int Function() reconnects;

  /// Remote participant identities a media key has arrived from (encrypted
  /// calls). Read on the device only.
  final Set<String> Function()? keyedParticipants;
  final Map<String, TrackCounters> _prev = {};
  final Map<String, lk.E2EEState> _e2ee = {};
  final Set<String> _beforeKey = {};
  lk.EventsListener<lk.RoomEvent>? _listener;
  final Stopwatch _sinceSample = Stopwatch()..start();
  Timer? _timer;
  int _minute = 0;
  bool _sampling = false;

  CallStats._(this.room,
      {required this.encrypted,
      required this.reconnects,
      this.keyedParticipants});

  /// Starts sampling [room] once a minute; returns null when telemetry is
  /// off. Call [stop] when the call ends.
  static CallStats? start(lk.Room room,
      {required bool encrypted,
      required int Function() reconnects,
      Set<String> Function()? keyedParticipants}) {
    if (!Telemetry.enabled) return null;
    final stats = CallStats._(room,
        encrypted: encrypted,
        reconnects: reconnects,
        keyedParticipants: keyedParticipants);
    stats._watchTracks();
    stats._timer = Timer.periodic(period, (_) => stats._sample());
    return stats;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _listener?.dispose();
    _listener = null;
  }

  bool _hasKey(String identity) =>
      keyedParticipants?.call().contains(identity) ?? false;

  /// Remembers each remote track's decryption state and whether it was
  /// subscribed before its sender's key had arrived (a decryptor built
  /// without a key may never recover).
  void _watchTracks() {
    if (!encrypted) return;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        if (pub.track != null && !_hasKey(p.identity)) _beforeKey.add(pub.sid);
      }
    }
    _listener = room.createListener()
      ..on<lk.TrackE2EEStateEvent>((e) {
        if (e.participant is lk.RemoteParticipant) {
          _e2ee[e.publication.sid] = e.state;
        }
      })
      ..on<lk.TrackSubscribedEvent>((e) {
        if (e.track is! lk.RemoteAudioTrack) return;
        if (_hasKey(e.participant.identity)) {
          _beforeKey.remove(e.publication.sid);
        } else {
          _beforeKey.add(e.publication.sid);
        }
      })
      ..on<lk.TrackUnsubscribedEvent>((e) {
        _e2ee.remove(e.publication.sid);
        _beforeKey.remove(e.publication.sid);
      });
  }

  static String quality(lk.ConnectionQuality? q) => switch (q) {
        lk.ConnectionQuality.lost => "lost",
        lk.ConnectionQuality.poor => "poor",
        lk.ConnectionQuality.good => "good",
        lk.ConnectionQuality.excellent => "excellent",
        _ => "unknown",
      };

  TrackCounters _prevFor(String sid) =>
      _prev.putIfAbsent(sid, TrackCounters.new);

  Future<void> _sample() async {
    if (_sampling || !Telemetry.enabled) return;
    _sampling = true;
    try {
      final sample = CallSample()
        ..elapsedMs = _sinceSample.elapsedMilliseconds
        ..encrypted = encrypted;
      _sinceSample.reset();
      var remotePoor = 0;
      var screenShare = false;
      final live = <String>{};
      for (final p in room.remoteParticipants.values) {
        if (p.connectionQuality == lk.ConnectionQuality.poor ||
            p.connectionQuality == lk.ConnectionQuality.lost) {
          remotePoor++;
        }
        if (encrypted && _hasKey(p.identity)) sample.keyedParticipants++;
        for (final pub in p.trackPublications.values) {
          if (pub.source == lk.TrackSource.screenShareVideo) screenShare = true;
          final track = pub.track;
          if (pub.kind == lk.TrackType.AUDIO) {
            sample.addRemoteAudio(
                subscribed: track != null,
                muted: pub.muted,
                e2ee: _e2ee[pub.sid],
                beforeKey: _beforeKey.contains(pub.sid));
          }
          if (track == null) continue;
          live.add(pub.sid);
          if (track is lk.RemoteAudioTrack) {
            final s = await track.getReceiverStats();
            if (s != null) sample.addAudioReceiver(s, _prevFor(pub.sid));
          } else if (track is lk.RemoteVideoTrack) {
            final s = await track.getReceiverStats();
            if (s != null) sample.addVideoReceiver(s, _prevFor(pub.sid));
          }
        }
      }
      final local = room.localParticipant;
      if (local != null) {
        for (final pub in local.trackPublications.values) {
          if (pub.source == lk.TrackSource.screenShareVideo) screenShare = true;
          final track = pub.track;
          if (track == null || pub.muted) continue;
          live.add(pub.sid);
          if (track is lk.LocalAudioTrack) {
            final s = await track.getSenderStats();
            if (s != null) sample.addSender(s, _prevFor(pub.sid));
          } else if (track is lk.LocalVideoTrack) {
            // One entry per simulcast layer; the previous counters are kept
            // per layer id so each layer's delta is its own.
            for (final s in await track.getSenderStats()) {
              sample.addSender(
                  s, _prevFor("${pub.sid}/${s.rid ?? s.streamId}"));
            }
          }
        }
      }
      _prev.removeWhere((sid, _) => !live.any((l) => sid.startsWith(l)));
      Telemetry.record("call_stats", {
        "quality": quality(local?.connectionQuality),
        "minute": ++_minute,
        "participants": room.remoteParticipants.length + 1,
        "remote_poor": remotePoor,
        "encrypted": encrypted,
        "screen_share": screenShare,
        "reconnects": reconnects().clamp(0, 1000000),
        ...sample.fields(),
      });
    } catch (_) {
      // Diagnostics never get in the way of the call.
    } finally {
      _sampling = false;
    }
  }
}
