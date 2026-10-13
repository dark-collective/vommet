import 'dart:convert';

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_encryption_key_provider.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_livekit_voip_session.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_multi_sfu.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_publish_rights.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:commet/client/matrix/components/voip_room/push_to_talk_microphone.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_leave.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_foci.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart';

class MatrixLivekitBackend {
  MatrixRoom room;
  lk.Room? livekitRoom;
  MatrixLivekitBackend(this.room);

  Future<List<Uri>> getFociUrl() async {
    final selectedFocus = findSelectedFocus();

    var wellKnown = await room.matrixRoom.client.getWellknown();
    final livekitJwtServiceUrl = wellKnown
        .additionalProperties["org.matrix.msc4143.rtc_foci"] as List<dynamic>?;

    if (livekitJwtServiceUrl == null) {
      return [
        if (selectedFocus != null) selectedFocus,
      ];
    }

    Uri? fociUrl;
    for (var focus in livekitJwtServiceUrl) {
      Log.d("Focus: ${focus}");
      final data = focus as Map<String, dynamic>;
      if (data["type"] != "livekit") {
        continue;
      }

      final url = data["livekit_service_url"] as String;
      fociUrl = Uri.parse(url);

      return [
        if (selectedFocus != null) selectedFocus,
        if (selectedFocus != fociUrl) fociUrl,
      ];
    }

    return [
      if (selectedFocus != null) selectedFocus,
    ];
  }

  Uri? findSelectedFocus() {
    // Vommet (multi-SFU experiment): MSC4195-aware election.
    if (preferences.experimentMultiSfu.value) {
      return MatrixRtcMultiSfu.electedFocus(room);
    }
    final states =
        room.matrixRoom.states[MatrixVoipRoomComponent.callMemberStateEvent];
    if (states == null) {
      return null;
    }

    // Vommet: "oldest" is by `created_ts` (kept across a member's refreshes;
    // Element Call re-posts hourly), falling back to the event timestamp,
    // ties on the state key — the order matrix-js-sdk uses. Expired and left
    // memberships don't take part.
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = states.values.whereType<Event>().where((event) {
      return MatrixRtcMembership.isLive(
          event.content, event.originServerTs.millisecondsSinceEpoch, now);
    }).toList();
    values.sort((a, b) {
      final byCreated = MatrixRtcMembership.createdTs(
              a.content, a.originServerTs.millisecondsSinceEpoch)
          .compareTo(MatrixRtcMembership.createdTs(
              b.content, b.originServerTs.millisecondsSinceEpoch));
      if (byCreated != 0) return byCreated;
      return (a.stateKey ?? "").compareTo(b.stateKey ?? "");
    });

    for (var entry in values) {
      final focusActive =
          entry.content.tryGet<Map<String, dynamic>>("focus_active");

      if (focusActive == null) {
        continue;
      }

      if (focusActive['type'] != "livekit") {
        Log.e("Unknown focus type: ${focusActive['type']}");
        continue;
      }

      if (focusActive['focus_selection'] != "oldest_membership") {
        Log.e(
            "Unknown focus selection algorithm: ${focusActive['focus_selection']}");
        continue;
      }

      final fociPreferred =
          entry.content.tryGet<List<dynamic>>("foci_preferred");
      Log.e("Selecting focus");
      if (fociPreferred == null) {
        continue;
      }

      for (var item in fociPreferred) {
        final map = item as Map<String, dynamic>;
        if (map['type'] != "livekit") continue;
        if (map['livekit_alias'] != room.identifier) continue;
        return Uri.parse(map['livekit_service_url']);
      }
    }

    return null;
  }

  /// Vommet (multi-SFU experiment): the SFU [join] connected to.
  Uri? joinedFocus;

  /// Vommet: the join in progress. Joining takes seconds (OpenID, JWT,
  /// membership, connect), and a second tap on Call meanwhile made a second
  /// session for the same room: two LiveKit connections under one identity,
  /// where the buttons muted one and the call heard the other (Vommet
  /// issue 167). A join while one runs, or while we're already in this
  /// room's call, gets that call.
  Future<VoipSession?>? _joining;

  Future<VoipSession?> join() {
    final current =
        clientManager?.callManager.getCallInRoom(room.client, room.identifier);
    if (current is MatrixLivekitVoipSession &&
        current.state != VoipState.ended) {
      return Future.value(current);
    }
    return _joining ??= _joinOnce().whenComplete(() => _joining = null);
  }

  Future<VoipSession?> _joinOnce() async {
    final session = await _join();
    if (session is MatrixLivekitVoipSession &&
        (preferences.experimentMultiSfu.value || publishesOnOwnSfu) &&
        joinedFocus != null) {
      MatrixRtcMultiSfu.start(room, session, joinedFocus!,
          pinned: publishesOnOwnSfu);
    }
    return session;
  }

  /// Vommet: the call's SFU only lets us listen, so [_join] publishes on our
  /// own homeserver's SFU instead (see [MatrixRtcPublishRights]).
  bool publishesOnOwnSfu = false;

  Future<VoipSession?> _join() async {
    WebrtcDefaultDevices.selectOutputDevice();
    publishesOnOwnSfu = false;

    var fociUrl = await getFociUrl();

    if (fociUrl.isEmpty) {
      throw Exception("Failed to find a valid LiveKit service");
    }

    final selectedFocus = fociUrl.first;
    joinedFocus = selectedFocus;
    Log.d("Got Foci Url: ${fociUrl}");

    final token = await room.matrixRoom.client
        .requestOpenIdToken(room.matrixRoom.client.userID!, {});

    if (selectedFocus.scheme != "https") {
      throw Exception("Selected focus JWT does not use HTTPS");
    }

    Log.d("Received token from homeserver: ${token}");
    final uri = Uri.parse(selectedFocus.toString() + "/sfu/get");

    final body = {
      "device_id": room.matrixRoom.client.deviceID!,
      "room": room.matrixRoom.id,
      "openid_token": {
        "matrix_server_name": token.matrixServerName,
        "access_token": token.accessToken,
        "expires_in": token.expiresIn,
      }
    };

    var result = await http.post(uri, body: jsonEncode(body));
    if (result.statusCode != 200) {
      throw Exception("Failed to get sfu! HTTP Error ${result.statusCode}");
    }

    var data = jsonDecode(result.body) as Map<String, dynamic>;

    var sfuUrl = data["url"] as String;
    Log.d("Got sfu: ${sfuUrl}");
    var jwt = data["jwt"] as String;

    // Vommet: a listen-only token (the call's SFU is another homeserver's):
    // publish on ours, listen on the call's, like Element Call's multi_sfu.
    var focusSelection = RtcFocusSelection.oldestMembership;
    if (!MatrixRtcPublishRights.canPublish(jwt)) {
      final own = fociUrl.skip(1).where((f) => f.scheme == "https").firstOrNull;
      if (own == null) {
        Log.w("The call's SFU lets us listen only, and our homeserver has "
            "no SFU of its own: joining listen-only");
      } else {
        try {
          final ours = await MatrixRtcPublishRights.fetch(room.matrixRoom, own);
          if (MatrixRtcPublishRights.canPublish(ours.jwt)) {
            Log.i("The call's SFU $selectedFocus lets us listen only: "
                "publishing on our own SFU $own (multi_sfu)");
            sfuUrl = ours.url;
            jwt = ours.jwt;
            fociUrl = [own];
            joinedFocus = own;
            focusSelection = RtcFocusSelection.multiSfu;
            publishesOnOwnSfu = true;
          } else {
            Log.w("Our own SFU lets us listen only too: joining listen-only");
          }
        } catch (e) {
          Log.w("Could not get a token from our own SFU, joining the call's "
              "listen-only: ${e.runtimeType} $e");
        }
      }
    }
    lk.E2EEOptions? e2eeOptions;

    MatrixLivekitEncryptionKeyProvider? provider;

    if (room.isE2EE) {
      provider =
          await MatrixLivekitEncryptionKeyProvider.create(room.matrixRoom);
      e2eeOptions = lk.E2EEOptions(keyProvider: provider);
    }

    var device = await WebrtcDefaultDevices.getDefaultMicrophoneId();

    final roomOptions = lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        e2eeOptions: e2eeOptions,
        // Vommet: used when the microphone is first opened by an unmute, e.g.
        // after joining muted from the call panel.
        defaultAudioCaptureOptions: microphoneCaptureOptions(device),
        defaultAudioPublishOptions: lk.AudioPublishOptions(
          encoding: lk.AudioEncoding(
              maxBitrate:
                  (preferences.streamAudioBitrate.value * 1000).toInt()),
        ));

    final lkRoom = lk.Room(roomOptions: roomOptions);

    await lkRoom.prepareConnection(sfuUrl, jwt);
    final stateKey =
        "_${room.client.self!.identifier}_${room.matrixRoom.client.deviceID!}_m.call";
    // Vommet: a leave from the last call here may still be in flight.
    await MatrixRtcLeave.settle(room.matrixRoom.id, stateKey);

    await room.matrixRoom.client.setRoomStateWithKey(room.matrixRoom.id,
        MatrixVoipRoomComponent.callMemberStateEvent, stateKey, {
      "application": "m.call",
      "call_id": "",
      "device_id": room.matrixRoom.client.deviceID!,
      // Vommet: refreshed hourly by the session (see MatrixRtcMembership).
      "expires": MatrixRtcMembership.expiresMs,
      "foci_preferred": fociUrl
          .map((e) => {
                "type": "livekit",
                "livekit_alias": room.identifier,
                "livekit_service_url": e.toString()
              })
          .toList(),
      "focus_active": {"focus_selection": focusSelection, "type": "livekit"},
      "scope": "m.room"
    });

    await lkRoom.connect(sfuUrl, jwt);

    // Desktop already did this in getDefaultMicrophoneId; Android needs it
    // here, after connect() brought libwebrtc up.
    await VoiceFilter.apply();

    print("Using default device: ${device}");

    // Vommet: with push to talk the microphone is published muted, capture
    // kept open (see PushToTalkMicrophone); the key opens it.
    if (preferences.voipPushToTalk.value) {
      if (!clientManager!.callManager.nextCallMuted) {
        PushToTalkMicrophone.publishMuted(lkRoom.localParticipant!,
            PushToTalkMicrophone.captureOptions(lkRoom));
      }
    } else {
      lkRoom.localParticipant?.setMicrophoneEnabled(
          !clientManager!.callManager.nextCallMuted,
          audioCaptureOptions: microphoneCaptureOptions(device));
    }

    livekitRoom = lkRoom;
    final session =
        MatrixLivekitVoipSession(room, lkRoom, keyProvider: provider);
    session.listenOnly = !MatrixRtcPublishRights.canPublish(jwt);
    return session;
  }

  /// Vommet: one place for the microphone's processing options, so a
  /// microphone opened later by an unmute gets the same ones as at join.
  static lk.AudioCaptureOptions microphoneCaptureOptions(String? device) =>
      lk.AudioCaptureOptions(
          deviceId: device,
          noiseSuppression: VoiceFilter.useWebrtcNoiseSuppression,
          autoGainControl: WebrtcDefaultDevices.useAutoGainControl);
}
