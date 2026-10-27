import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/client/components/voip/voip_stream_watching.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_multi_sfu.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet: [VoipStreamWatching] for LiveKit calls (experiment
/// `vommet_experiment_stream_watching`).
///
/// The room still subscribes to everything automatically; screen shares you
/// don't watch are then held back per publication:
/// * video with a low simulcast layer: kept on that layer, for the preview;
/// * video without one: disabled, so the server stops sending it;
/// * screen-share audio: unsubscribed (also while you muted it).
/// It re-applies whenever the call's streams change (a share starts, a
/// track is subscribed, a stream arrives from another SFU); every step is
/// a no-op when the publication is already as wanted.
class LivekitStreamWatching implements VoipStreamWatching {
  LivekitStreamWatching._(this._session) {
    _sub = _session.onStateChanged.listen((_) => _applyAll());
    _settingSub = VoipStreamWatching.showWatching.onChanged
        .listen((_) => _shareWatching());
    _applyAll();
  }

  /// The experiment's switch. Read when a call starts.
  static final BoolPreference experiment =
      BoolPreference("vommet_experiment_stream_watching", defaultValue: false);

  /// The LiveKit participant attribute that lists the sharers (Matrix user
  /// ids, a JSON list) a Vommet viewer watches.
  static const String watchingAttribute = "im.vommet.watching";

  /// Starts stream watching for a new LiveKit call, when the experiment is
  /// on. The one hook in the session's constructor.
  static void attach(VoipSession session) {
    if (!experiment.value) return;
    VoipStreamWatching.register(session, LivekitStreamWatching._(session));
  }

  final VoipSession _session;
  StreamSubscription? _sub;
  StreamSubscription? _settingSub;

  /// Participants (LiveKit identities) whose screen share you watch.
  final Set<String> _watchedSharers = {};

  /// Participants whose screen-share audio you muted in this call.
  final Set<String> _mutedSharers = {};

  final StreamController<void> _focusRequests = StreamController.broadcast();
  VoipStream? _focusRequest;

  /// What we last asked the SFU to show as [watchingAttribute] (null: not
  /// asked yet), so it is set again only when it changes or after moving
  /// to another SFU; [_attributeDenied] when our token can't set it.
  String? _sentAttribute;
  lk.Room? _attributeRoom;
  bool _attributeDenied = false;

  /// Subscription changes asked for and not seen yet, by publication, so
  /// they aren't sent again on every stream change.
  final Map<String, bool> _pendingSubscribe = {};

  static bool _isShare(VoipStream stream) =>
      stream.type == VoipStreamType.screenshare ||
      stream.type == VoipStreamType.screenshareAudio;

  @override
  bool isWatching(VoipStream stream) =>
      stream.direction == VoipStreamDirection.outgoing ||
      !_isShare(stream) ||
      _watchedSharers.contains(stream.participantId);

  @override
  bool hasPreview(VoipStream stream) =>
      stream is MatrixLivekitVoipStream && stream.publication.simulcasted;

  @override
  Future<void> setWatching(VoipStream stream, bool watching) async {
    if (watching) {
      _watchedSharers.add(stream.participantId);
    } else {
      _watchedSharers.remove(stream.participantId);
    }
    await _applyAll();
  }

  @override
  bool isStreamAudioMuted(VoipStream stream) =>
      _mutedSharers.contains(stream.participantId);

  @override
  Future<void> setStreamAudioMuted(VoipStream stream, bool muted) async {
    if (muted) {
      _mutedSharers.add(stream.participantId);
    } else {
      _mutedSharers.remove(stream.participantId);
    }
    await _applyAll();
  }

  @override
  void requestFocus(VoipStream stream) {
    _focusRequest = stream;
    _focusRequests.add(null);
  }

  @override
  VoipStream? takeFocusRequest() {
    final stream = _focusRequest;
    _focusRequest = null;
    return stream;
  }

  @override
  Stream<void> get onFocusRequest => _focusRequests.stream;

  @override
  List<String> viewersOf(VoipStream stream) {
    final sharer = stream.streamUserId;
    final session = _session;
    final me = session.client.self?.identifier;
    final viewers = <String>{
      if (me != null &&
          stream.direction == VoipStreamDirection.incoming &&
          isWatching(stream))
        me,
    };
    if (session is! MatrixLivekitVoipSession) return viewers.toList();
    final rooms = [
      session.livekitRoom,
      ...MatrixRtcMultiSfu.extraRooms(session),
    ];
    for (final room in rooms) {
      for (final p in room.remoteParticipants.values) {
        final value = p.attributes[watchingAttribute];
        if (value == null || value.isEmpty) continue;
        if (_parseWatching(value).contains(sharer)) {
          viewers.add(session.userIdOfIdentity(p.identity));
        }
      }
    }
    return viewers.toList();
  }

  static List<String> _parseWatching(String value) {
    try {
      final list = jsonDecode(value);
      if (list is List) return list.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  /// Tells the call whose streams we watch (or nothing, with
  /// [showWatching] off), on the SFU we publish on.
  Future<void> _shareWatching() async {
    final session = _session;
    if (_attributeDenied ||
        session.state == VoipState.ended ||
        session is! MatrixLivekitVoipSession) {
      return;
    }
    final local = session.livekitRoom.localParticipant;
    if (local == null) return;
    final sharers = <String>{
      if (VoipStreamWatching.showWatching.value)
        for (final s in session.streams)
          if (s.type == VoipStreamType.screenshare &&
              s.direction == VoipStreamDirection.incoming &&
              _watchedSharers.contains(s.participantId))
            s.streamUserId,
    }.toList()
      ..sort();
    final value = sharers.isEmpty ? "" : jsonEncode(sharers);
    if (value == _sentAttribute &&
        identical(_attributeRoom, session.livekitRoom)) {
      return;
    }
    _sentAttribute = value;
    _attributeRoom = session.livekitRoom;
    try {
      await local.setAttributes({watchingAttribute: value});
    } on TimeoutException {
      // Older SFUs apply it without answering.
    } catch (e) {
      // Older lk-jwt services don't let participants change their own
      // attributes; then nobody sees what we watch, and that's all.
      _attributeDenied = true;
      Log.w("Stream watching: can't tell the call what we watch ($e)");
    }
  }

  Future<void> _applyAll() async {
    if (_session.state == VoipState.ended) {
      await _sub?.cancel();
      _sub = null;
      await _settingSub?.cancel();
      _settingSub = null;
      _focusRequest = null;
      return;
    }
    for (final s
        in _session.streams.whereType<MatrixLivekitVoipStream>().toList()) {
      await _apply(s);
    }
    unawaited(_shareWatching());
  }

  Future<void> _apply(MatrixLivekitVoipStream stream) async {
    final pub = stream.publication;
    if (pub is! lk.RemoteTrackPublication || !_isShare(stream)) return;
    final watched = _watchedSharers.contains(stream.participantId);
    try {
      if (stream.type == VoipStreamType.screenshare) {
        if (watched || pub.simulcasted) {
          await pub.enable();
          if (pub.subscribed) {
            // Vommet issue 776: at most the middle layer while "Use less
            // data for calls" is on.
            await pub.setVideoQuality(watched
                ? CallDataSaver.receiveQuality(screenShare: true)
                : lk.VideoQuality.LOW);
          }
        } else {
          await pub.disable();
        }
        return;
      }
      final want = watched && !_mutedSharers.contains(stream.participantId);
      if (pub.subscribed == want) {
        _pendingSubscribe.remove(pub.sid);
        return;
      }
      // Unsubscribing only works once the track has arrived; the next
      // stream change (its subscription) brings us back here.
      if (!want && !pub.subscribed) return;
      if (_pendingSubscribe[pub.sid] == want) return;
      _pendingSubscribe[pub.sid] = want;
      if (want) {
        await pub.subscribe();
      } else {
        await pub.unsubscribe();
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Could not apply stream watching");
    }
  }
}
