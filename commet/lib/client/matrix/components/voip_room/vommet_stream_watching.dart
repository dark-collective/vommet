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
    final session = _session;
    if (session is MatrixLivekitVoipSession) {
      _dataSub = session.onData.listen(_onData);
      // Someone who joins without publishing anything changes no stream,
      // and still needs to be told what we watch.
      _peersSub = session.onParticipantsChanged.listen((_) {
        _forgetLeft();
        unawaited(_shareWatching());
      });
    }
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
  StreamSubscription? _dataSub;
  StreamSubscription? _peersSub;

  /// Participants (LiveKit identities) whose screen share you watch.
  final Set<String> _watchedSharers = {};

  /// Participants whose screen-share audio you muted in this call.
  final Set<String> _mutedSharers = {};

  final StreamController<void> _focusRequests = StreamController.broadcast();
  final StreamController<void> _changed = StreamController.broadcast();
  VoipStream? _focusRequest;

  /// What we last asked the SFU to show as [watchingAttribute] (null: not
  /// asked yet), so it is set again only when it changes or after moving
  /// to another SFU; [_attributeDenied] when the SFU refused it and
  /// [_attributeTimedOut] when it never answered (both reset on a move).
  String? _sentAttribute;
  lk.Room? _attributeRoom;
  bool _attributeDenied = false;
  bool _attributeTimedOut = false;

  /// Vommet issue 871: see [useDataMessages]. [_sentData] is the last data
  /// message and [_dataPeers] who was in the room then, so it is sent again
  /// to everyone who joins later.
  String? _sentData;
  lk.Room? _dataRoom;
  Set<String> _dataPeers = {};

  /// [_shareWatching] is running; [_shareAgain] when it was asked again
  /// meanwhile.
  bool _sharing = false;
  bool _shareAgain = false;

  /// What others said in such messages, by LiveKit identity.
  final Map<String, String> _dataWatching = {};

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
    _changed.add(null);
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
    _changed.add(null);
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
  Stream<void> get onChanged => _changed.stream;

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
        if (mergeWatching(
                p.attributes[watchingAttribute], _dataWatching[p.identity])
            .contains(sharer)) {
          viewers.add(session.userIdOfIdentity(p.identity));
        }
      }
    }
    return viewers.toList();
  }

  /// Whom a participant watches, from its [watchingAttribute] attribute
  /// and its data message (either may be missing or empty): both together.
  static Set<String> mergeWatching(String? attribute, String? data) => {
        ..._parseWatching(attribute),
        ..._parseWatching(data),
      };

  static List<String> _parseWatching(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final list = jsonDecode(value);
      if (list is List) return list.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  /// Vommet issue 871: whether who we watch also goes out as data
  /// messages: when our token lacks the grant to set our own attributes
  /// (lk-jwt-service without canUpdateOwnMetadata), or the SFU refused the
  /// attribute or never answered. Viewers merge both ([mergeWatching]).
  static bool useDataMessages({
    required bool canUpdateMetadata,
    bool denied = false,
    bool timedOut = false,
  }) =>
      !canUpdateMetadata || denied || timedOut;

  /// Whom to send [value] as a data message: `send` false for nobody, else
  /// [to] (null: everyone). Everyone when it changed or we moved to another
  /// SFU ([sameRoom] false), else only those who joined since ([peers] minus
  /// [lastPeers]); nothing when nothing is watched and nobody was told
  /// otherwise on this SFU.
  static ({bool send, List<String>? to}) dataTargets({
    required String value,
    required String? lastValue,
    required bool sameRoom,
    required Set<String> peers,
    required Set<String> lastPeers,
  }) {
    if (!sameRoom || value != lastValue) {
      final nothingToClear = value.isEmpty && (!sameRoom || lastValue == null);
      return (send: !nothingToClear, to: null);
    }
    final joined = peers.difference(lastPeers);
    if (value.isEmpty || joined.isEmpty) return (send: false, to: null);
    return (send: true, to: joined.toList()..sort());
  }

  /// Tells the call whose streams we watch (or nothing, with
  /// [showWatching] off), on the SFU we publish on. One at a time; a call
  /// while one runs makes it run once more.
  Future<void> _shareWatching() async {
    if (_sharing) {
      _shareAgain = true;
      return;
    }
    _sharing = true;
    try {
      do {
        _shareAgain = false;
        await _shareOnce();
      } while (_shareAgain);
    } finally {
      _sharing = false;
    }
  }

  Future<void> _shareOnce() async {
    final session = _session;
    if (session.state == VoipState.ended ||
        session is! MatrixLivekitVoipSession) {
      return;
    }
    final room = session.livekitRoom;
    final local = room.localParticipant;
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
    if (!identical(_attributeRoom, room)) {
      _attributeRoom = room;
      _sentAttribute = null;
      _attributeDenied = false;
      _attributeTimedOut = false;
    }
    final canUpdate = local.permissions.canUpdateMetadata;
    if (useDataMessages(
        canUpdateMetadata: canUpdate,
        denied: _attributeDenied,
        timedOut: _attributeTimedOut)) {
      await _sendData(room, value);
    }
    // Without the grant the SFU refuses it; with it, keep it current even
    // after a timeout, so an attribute applied quietly doesn't go stale.
    if (!canUpdate || _attributeDenied || value == _sentAttribute) return;
    _sentAttribute = value;
    try {
      await local.setAttributes({watchingAttribute: value});
    } on TimeoutException {
      // The SFU may have applied it without answering, or dropped it.
      if (_attributeTimedOut) return;
      _attributeTimedOut = true;
      Log.w("Stream watching: the call didn't answer when told what we "
          "watch, sending it as data messages too");
      await _sendData(room, value);
    } catch (e) {
      _attributeDenied = true;
      Log.w("Stream watching: can't tell the call what we watch ($e), "
          "sending it as data messages instead");
      await _sendData(room, value);
    }
  }

  Future<void> _sendData(lk.Room room, String value) async {
    final local = room.localParticipant;
    if (local == null) return;
    final peers = room.remoteParticipants.keys.toSet();
    final target = dataTargets(
        value: value,
        lastValue: _sentData,
        sameRoom: identical(room, _dataRoom),
        peers: peers,
        lastPeers: _dataPeers);
    _sentData = value;
    _dataRoom = room;
    _dataPeers = peers;
    if (!target.send) return;
    try {
      await local.publishData(utf8.encode(value.isEmpty ? "[]" : value),
          reliable: true,
          topic: watchingAttribute,
          destinationIdentities: target.to);
    } catch (e) {
      Log.w("Stream watching: can't send what we watch ($e)");
    }
  }

  void _onData(lk.DataReceivedEvent event) {
    final from = event.participant?.identity;
    if (event.topic != watchingAttribute || from == null) return;
    try {
      _dataWatching[from] = utf8.decode(event.data);
    } catch (_) {
      return;
    }
    final session = _session;
    if (session is MatrixLivekitVoipSession) session.notifyStreamsChanged();
  }

  /// Forgets the messages of those who left, so a rejoin starts fresh.
  void _forgetLeft() {
    final session = _session;
    if (_dataWatching.isEmpty || session is! MatrixLivekitVoipSession) return;
    final present = {
      for (final room in [
        session.livekitRoom,
        ...MatrixRtcMultiSfu.extraRooms(session),
      ])
        ...room.remoteParticipants.keys,
    };
    _dataWatching.removeWhere((identity, _) => !present.contains(identity));
  }

  Future<void> _applyAll() async {
    if (_session.state == VoipState.ended) {
      await _sub?.cancel();
      _sub = null;
      await _settingSub?.cancel();
      _settingSub = null;
      await _dataSub?.cancel();
      _dataSub = null;
      await _peersSub?.cancel();
      _peersSub = null;
      _focusRequest = null;
      return;
    }
    for (final s
        in _session.streams.whereType<MatrixLivekitVoipStream>().toList()) {
      await _apply(s);
    }
    _forgetLeft();
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
