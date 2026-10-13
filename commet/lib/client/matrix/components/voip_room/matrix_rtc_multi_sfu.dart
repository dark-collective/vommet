import 'dart:async';
import 'dart:convert';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_foci.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/debug/log.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as mx;

/// Vommet (multi-SFU experiment, MSC4195): makes one call span several
/// LiveKit SFUs, the way Element Call 0.21+ does.
///
/// * We publish on the call's **elected** SFU (the oldest membership's), the
///   only one legacy clients such as Commet listen on, and where Element Call
///   expects an `oldest_membership` member. When the oldest member leaves and
///   the election moves, we move with it ([_migrate]).
/// * We also connect, subscribe-only, to every other SFU a member publishes
///   on, so people on other homeservers' SFUs are heard.
///
/// Tracks from every SFU feed the same [MatrixLivekitVoipSession] (its stream
/// list, volumes, deafen), and the same media-key provider decrypts them.
class MatrixRtcMultiSfu {
  static final Map<MatrixLivekitVoipSession, MatrixRtcMultiSfu> _active = {};

  static String selfStateKey(MatrixRoom room) =>
      "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";

  /// Live memberships in [room]'s call.
  static List<RtcMember> members(MatrixRoom room, {bool excludeSelf = false}) {
    final state =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (state == null) return [];
    final now = DateTime.now().millisecondsSinceEpoch;
    final self = excludeSelf ? selfStateKey(room) : null;
    final result = <RtcMember>[];
    for (final entry in state.entries) {
      if (entry.key == self) continue;
      final event = entry.value;
      if (event is! mx.Event) continue;
      final m = RtcMember.parse(
        stateKey: entry.key,
        sender: event.senderId,
        content: event.content,
        originServerTs: event.originServerTs.millisecondsSinceEpoch,
        nowMs: now,
      );
      if (m != null) result.add(m);
    }
    return result;
  }

  /// Where to publish when joining: the elected SFU, ignoring a stale
  /// membership of our own from an earlier session.
  static Uri? electedFocus(MatrixRoom room) =>
      RtcFoci.elected(members(room, excludeSelf: true));

  static void start(
      MatrixRoom room, MatrixLivekitVoipSession session, Uri primary) {
    final manager = MatrixRtcMultiSfu._(room, session, primary);
    _active[session] = manager;
    manager._init();
  }

  MatrixRtcMultiSfu._(this.room, this.session, this.primary);

  final MatrixRoom room;
  final MatrixLivekitVoipSession session;

  /// The SFU we publish on (session.livekitRoom's).
  Uri primary;

  final Map<Uri, _RemoteSfu> _remotes = {};
  final Map<Uri, DateTime> _retryAfter = {};
  final List<StreamSubscription> _subs = [];
  Timer? _tick;
  Timer? _migrationTimer;
  Uri? _pendingElection;
  Future<void> _queue = Future.value();
  bool _disposed = false;

  void _init() {
    Log.i("Multi-SFU: publishing on $primary");
    _subs.add(room.matrixRoom.client.onSync.stream.listen((update) {
      final r = update.rooms?.join?[room.matrixRoom.id];
      if (r == null) return;
      final events = [...?r.timeline?.events, ...?r.state];
      if (events
          .any((e) => e.type == MatrixVoipRoomComponent.callMemberStateEvent)) {
        _schedule();
      }
    }));
    _subs.add(session.onStateChanged.listen((_) {
      if (session.state == VoipState.ended) dispose();
    }));
    // Memberships also lapse by time, and failed SFUs get retried.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _schedule());
    _schedule();
  }

  void _schedule() => _run(_reconcile);

  void _run(Future<void> Function() step) {
    _queue = _queue.then((_) => step()).catchError((Object e, StackTrace s) {
      Log.onError(e, s, content: "Multi-SFU step failed");
    });
  }

  Future<void> _reconcile() async {
    if (_disposed) return;
    final all = members(room);
    final self = selfStateKey(room);

    final elected = RtcFoci.elected(all);
    if (elected != null && elected != primary) {
      _considerMigration(elected);
    } else {
      _migrationTimer?.cancel();
      _pendingElection = null;
    }

    final wanted = RtcFoci.remoteTransports(all, (m) => m.stateKey == self)
      ..remove(primary);

    for (final uri in _remotes.keys.toList()) {
      if (!wanted.contains(uri)) await _drop(uri);
    }
    final now = DateTime.now();
    for (final uri in wanted) {
      if (_disposed) return;
      if (_remotes.containsKey(uri)) continue;
      final retry = _retryAfter[uri];
      if (retry != null && now.isBefore(retry)) continue;
      try {
        await _subscribe(uri);
        _retryAfter.remove(uri);
      } catch (e) {
        // A foreign lk-jwt service may refuse us (or be down); don't hammer it.
        Log.w("Multi-SFU: could not subscribe on $uri: ${e.runtimeType} $e");
        _retryAfter[uri] = now.add(const Duration(minutes: 1));
      }
    }
  }

  /// The election moved (the oldest member left). Wait until it settles, so a
  /// membership flapping during a reconnect doesn't bounce us around.
  void _considerMigration(Uri elected) {
    if (_pendingElection == elected) return;
    _pendingElection = elected;
    _migrationTimer?.cancel();
    _migrationTimer = Timer(const Duration(seconds: 5), () {
      _run(() async {
        if (_disposed) return;
        if (RtcFoci.elected(members(room)) != elected) return;
        await _migrate(elected);
        _pendingElection = null;
      });
    });
  }

  Future<_Credentials> _credentials(Uri focus) =>
      _fetchCredentials(room.matrixRoom, focus);

  /// An lk-jwt token for [focus] (legacy `/sfu/get` body, as join uses).
  static Future<_Credentials> _fetchCredentials(mx.Room room, Uri focus) async {
    if (focus.scheme != "https") {
      throw Exception("Focus $focus does not use HTTPS");
    }
    final token = await room.client.requestOpenIdToken(room.client.userID!, {});
    final result = await http.post(Uri.parse("$focus/sfu/get"),
        body: jsonEncode({
          "device_id": room.client.deviceID!,
          "room": room.id,
          "openid_token": {
            "matrix_server_name": token.matrixServerName,
            "access_token": token.accessToken,
            "expires_in": token.expiresIn,
          }
        }));
    if (result.statusCode != 200) {
      throw Exception("lk-jwt HTTP ${result.statusCode}");
    }
    final data = jsonDecode(result.body) as Map<String, dynamic>;
    return _Credentials(data["url"] as String, data["jwt"] as String);
  }

  lk.RoomOptions _roomOptions() {
    final provider = session.keyProvider;
    return lk.RoomOptions(
      adaptiveStream: true,
      dynacast: true,
      e2eeOptions:
          provider != null ? lk.E2EEOptions(keyProvider: provider) : null,
    );
  }

  Future<void> _subscribe(Uri uri) async {
    final creds = await _credentials(uri);
    final r = lk.Room(roomOptions: _roomOptions());
    await r.connect(creds.url, creds.jwt);
    if (_disposed || _remotes.containsKey(uri)) {
      await r.disconnect();
      return;
    }
    Log.i("Multi-SFU: listening on $uri "
        "(${r.remoteParticipants.length} participants there)");
    _remotes[uri] = _RemoteSfu(r, _attach(r, primary: false));
    _addStreams(r, includeLocal: false);
    session.notifyStreamsChanged();
  }

  Future<void> _drop(Uri uri) async {
    final remote = _remotes.remove(uri);
    if (remote == null) return;
    Log.i("Multi-SFU: no one publishes on $uri any more, leaving it");
    await remote.listener.dispose();
    _removeStreams(remote.room);
    session.notifyStreamsChanged();
    await remote.room.disconnect();
  }

  lk.EventsListener<lk.RoomEvent> _attach(lk.Room r, {required bool primary}) {
    final l = r.createListener();
    l.on(session.onTrackPublished);
    l.on(session.onTrackUnpublished);
    l.on(session.onTrackStreamEvent);
    // A track subscribed after its tile was made: refresh that tile.
    l.on<lk.TrackSubscribedEvent>((e) {
      for (final s in session.streams) {
        if (s is MatrixLivekitVoipStream &&
            s.publication.sid == e.publication.sid) {
          s.onStreamUpdatedEvent();
        }
      }
      session.notifyStreamsChanged();
    });
    l.on(session.onTrackMutedEvent);
    l.on(session.onTrackUnmutedEvent);
    if (primary) {
      l.on(session.onLocalTrackPublished);
      l.on(session.onLocalTrackUnpublished);
      l.on(session.onParticipantConnected);
      l.on(session.onParticipantDisconnected);
    }
    return l;
  }

  static String _userId(String identity) =>
      identity.split(":").take(2).join(":");

  void _addStreams(lk.Room r, {required bool includeLocal}) {
    bool known(String? sid) => session.streams.any((s) => s.streamId == sid);

    final local = r.localParticipant;
    if (includeLocal && local != null) {
      for (final pub in local.trackPublications.values) {
        if (pub.muted && pub.kind == lk.TrackType.VIDEO) continue;
        if (known(pub.sid)) continue;
        session.streams
            .add(MatrixLivekitVoipStream(pub, room.client.self!.identifier));
      }
    }
    for (final p in r.remoteParticipants.values) {
      for (final pub in p.trackPublications.values) {
        if (pub.muted && pub.kind == lk.TrackType.VIDEO) continue;
        if (known(pub.sid)) continue;
        session.streams.add(MatrixLivekitVoipStream(pub, _userId(p.identity)));
      }
    }
  }

  void _removeStreams(lk.Room r) {
    final sids = <String>{
      for (final p in r.remoteParticipants.values) ...p.trackPublications.keys,
      ...?r.localParticipant?.trackPublications.keys,
    };
    session.streams.removeWhere((s) =>
        s is MatrixLivekitVoipStream && sids.contains(s.publication.sid));
  }

  /// Moves our publishing to [focus]: connect there, publish the microphone
  /// (and camera) as they were, swap it in as the session's room, re-post our
  /// membership naming it (keeping our original `created_ts`), then leave the
  /// old SFU. Screen shares stop; the user can start them again.
  Future<void> _migrate(Uri focus) async {
    Log.i("Multi-SFU: the call's elected SFU moved to $focus, following it");
    final old = session.livekitRoom;
    final creds = await _credentials(focus);

    // Already listening there: that connection is replaced by the new one.
    if (_remotes.containsKey(focus)) await _drop(focus);

    final r = lk.Room(roomOptions: old.roomOptions);
    await r.connect(creds.url, creds.jwt);
    if (_disposed) {
      await r.disconnect();
      return;
    }

    final provider = session.keyProvider;
    final identity = r.localParticipant?.identity;
    if (provider != null && identity != null) {
      provider.lkRoom = r;
      final index = (provider.indexCounter - 1) % provider.options.keyRingSize;
      r.e2eeManager
          ?.setKeyIndex(index < 0 ? 0 : index, participantIdentity: identity);
    }

    final micOn = old.localParticipant?.isMicrophoneEnabled() ?? true;
    final cameraOn = old.localParticipant?.isCameraEnabled() ?? false;

    _removeStreams(old);
    final newListener = _attach(r, primary: true);
    session.livekitRoom = r;
    _primaryListener?.dispose();
    _primaryListener = newListener;
    _addStreams(r, includeLocal: true);
    session.notifyStreamsChanged();

    if (micOn) {
      final device = await WebrtcDefaultDevices.getDefaultMicrophoneId();
      await r.localParticipant?.setMicrophoneEnabled(true,
          audioCaptureOptions: lk.AudioCaptureOptions(deviceId: device));
    }
    if (cameraOn) await r.localParticipant?.setCameraEnabled(true);

    final previous = primary;
    primary = focus;
    await _repostMembership(focus);
    await old.disconnect();
    Log.i("Multi-SFU: moved from $previous to $focus");
    _schedule();
  }

  lk.EventsListener<lk.RoomEvent>? _primaryListener;

  Future<void> _repostMembership(Uri focus) async {
    final key = selfStateKey(room);
    final current = room
        .matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent]?[key];
    if (current is! mx.Event || current.content.isEmpty) return;
    final content = Map<String, dynamic>.from(current.content);
    content["created_ts"] ??= current.originServerTs.millisecondsSinceEpoch;
    final foci = (content["foci_preferred"] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    foci.removeWhere((f) =>
        RtcMember.normalize(
            Uri.tryParse(f["livekit_service_url"]?.toString() ?? "")) ==
        focus);
    foci.insert(0, {
      "type": "livekit",
      "livekit_alias": room.identifier,
      "livekit_service_url": focus.toString(),
    });
    content["foci_preferred"] = foci;
    await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent, key, content);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active.remove(session);
    _tick?.cancel();
    _migrationTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _primaryListener?.dispose();
    for (final remote in _remotes.values) {
      remote.listener.dispose();
      remote.room.disconnect();
    }
    _remotes.clear();
    Log.i("Multi-SFU: call ended, left every extra SFU");
  }
}

class _RemoteSfu {
  final lk.Room room;
  final lk.EventsListener<lk.RoomEvent> listener;
  _RemoteSfu(this.room, this.listener);
}

class _Credentials {
  final String url;
  final String jwt;
  _Credentials(this.url, this.jwt);
}
