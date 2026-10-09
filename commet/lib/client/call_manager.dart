import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/stale_info.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';

class CallManager {
  ClientManager clientManager;
  final StreamController<VoipSession> _onSessionStarted =
      StreamController.broadcast();

  String notificationContentUserIsCalling(String user) => Intl.message(
      "$user is calling!",
      desc:
          "Notification body content for when receiving an incoming call from another user",
      args: [user],
      name: "notificationContentUserIsCalling");

  String notificationTitleIncomingCall(String roomName) =>
      Intl.message("Incoming Call! ($roomName)",
          desc: "Notification title for when a call is being received",
          args: [roomName],
          name: "notificationTitleIncomingCall");

  Stream<VoipSession> get onSessionStarted => _onSessionStarted.stream;

  NotifyingList<VoipSession> currentSessions =
      NotifyingList.empty(growable: true);

  CallManager(this.clientManager) {
    clientManager.onClientAdded.stream.listen(_onClientAdded);
    clientManager.onClientRemoved.stream.listen(_onClientRemoved);
  }

  Player? player;
  Player? muteSoundPlayer;
  Player? unmuteSoundPlayer;

  void _onClientAdded(int index) {
    var client = clientManager.clients[index];

    var voip = client.getComponent<VoipComponent>();
    if (voip == null) {
      return;
    }

    voip.onSessionStarted.listen(onClientSessionStarted);
    voip.onSessionEnded.listen(onSessionEnded);
  }

  void _onClientRemoved(StalePeerInfo event) {}

  void onClientSessionStarted(VoipSession event) {
    var room = event.client.getRoom(event.roomId);
    currentSessions.add(event);

    if (event.state == VoipState.incoming) {
      startRingtone();

      var member = room?.getMemberOrFallback(event.remoteUserId!);

      NotificationManager.notify(CallNotificationContent(
          title: notificationTitleIncomingCall(event.roomName),
          content: notificationContentUserIsCalling(
              event.remoteUserName ?? event.remoteUserId!),
          roomId: event.roomId,
          roomName: event.roomName,
          senderName: member?.displayName ?? event.remoteUserId!,
          roomImage: room?.avatar,
          callId: event.sessionId,
          senderId: event.remoteUserId!,
          senderImage: member?.avatar,
          senderImageId: member?.avatarId,
          roomImageId: room?.avatarId,
          clientId: event.client.identifier,
          accountLabel: NotificationContent.accountLabelFor(event.client),
          isDirectMessage: event.client
                  .getComponent<DirectMessagesComponent>()
                  ?.isRoomDirectMessage(room!) ==
              true));
    }

    if (event.state == VoipState.outgoing) {
      startOutgoingTone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
    }

    // Vommet: a call joined while muted or deafened stays that way. LiveKit
    // calls never open the microphone when muted (see MatrixLivekitBackend);
    // this covers the others.
    if (isMuted && !event.isMicrophoneMuted) {
      event.setMicrophoneMute(true);
    }

    event.onConnectionStateChanged.listen((_) => onCallStateChanged(event));
    event.onStateChanged.listen((_) => _followSessionMute(event));
  }

  void onSessionEnded(VoipSession event) {
    currentSessions
        .removeWhere((element) => element.sessionId == event.sessionId);

    if (currentSessions.where((e) => e.state == VoipState.incoming).isEmpty) {
      stopRingtone();
    }

    endCallSound();
  }

  VoipSession? getCallInRoom(Client client, String roomId) {
    return currentSessions
        .where(
            (element) => element.client == client && element.roomId == roomId)
        .firstOrNull;
  }

  void startRingtone() {
    // Let push notifications do the ringtone
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/ringtone_in.ogg"));
  }

  void startOutgoingTone() {
    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/ringtone_out.ogg"));
    player?.setPlaylistMode(PlaylistMode.loop);
  }

  void joinCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/joined_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  /// Vommet: mute and deafen are the user's own state, as in Discord: they
  /// can be set outside a call and carry into the next one.
  bool isMuted = false;
  bool isDeafened = false;

  /// Whether the microphone was muted before deafening, so undeafening only
  /// unmutes when deafen did the muting.
  bool _mutedBeforeDeafen = false;

  final StreamController<void> _onSelfAudioChanged =
      StreamController.broadcast();

  /// Fires when [isMuted] or [isDeafened] changes.
  Stream<void> get onSelfAudioChanged => _onSelfAudioChanged.stream;

  /// True while [_setSessionsMuted] is applying our own change, so
  /// [_followSessionMute] doesn't read the not-yet-updated session as the
  /// user's choice.
  bool _applyingMute = false;

  Future<void> _setSessionsMuted(bool muted) async {
    _applyingMute = true;
    try {
      await Future.wait(
          currentSessions.map((session) => session.setMicrophoneMute(muted)));
    } finally {
      _applyingMute = false;
    }
  }

  /// The call view mutes the session directly; follow it, so the panel's
  /// buttons and the next call match. Unmuting there also undeafens.
  void _followSessionMute(VoipSession session) {
    if (_applyingMute || session.state != VoipState.connected) return;
    final muted = session.isMicrophoneMuted;
    if (muted == isMuted) return;

    isMuted = muted;
    if (!muted && isDeafened) {
      isDeafened = false;
      refreshPlaybackVolumes();
    }
    _onSelfAudioChanged.add(null);
  }

  /// Output volume for everyone in a call (Discord's output volume slider).
  double get outputVolume => preferences.experimentQuickProfileControls.value
      ? preferences.voipOutputVolume.value
      : 1.0;

  /// Re-applies every call's playback volumes, after deafen or the output
  /// volume changed.
  void refreshPlaybackVolumes() {
    for (var session in currentSessions) {
      for (var stream in session.streams) {
        stream.applyPlaybackVolume();
      }
    }
  }

  void mute() {
    isMuted = true;
    _setSessionsMuted(true);
    _onSelfAudioChanged.add(null);

    playMuteSound();
  }

  void toggleMute() {
    if (isMuted) {
      unmute();
    } else {
      mute();
    }
  }

  /// Deafen silences everyone in the call and mutes the microphone; unmuting
  /// while deafened also undeafens.
  void setDeafened(bool deafened) {
    if (deafened == isDeafened) return;

    if (deafened) {
      _mutedBeforeDeafen = isMuted;
      isDeafened = true;
      isMuted = true;
      _setSessionsMuted(true);
      playMuteSound();
    } else {
      isDeafened = false;
      if (!_mutedBeforeDeafen) {
        isMuted = false;
        _setSessionsMuted(false);
      }
      playUnmuteSound();
    }

    refreshPlaybackVolumes();
    _onSelfAudioChanged.add(null);
  }

  void toggleDeafen() => setDeafened(!isDeafened);

  void playMuteSound() {
    if (muteSoundPlayer == null) {
      muteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      muteSoundPlayer?.open(Media("asset:///assets/sound/muted.ogg"));
      muteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    muteSoundPlayer!.setVolume(preferences.notificationsVolume.value);
    muteSoundPlayer?.seek(Duration.zero);
    muteSoundPlayer?.play();
  }

  void unmute() {
    if (isDeafened) {
      isDeafened = false;
      refreshPlaybackVolumes();
    }
    isMuted = false;
    _setSessionsMuted(false);
    _onSelfAudioChanged.add(null);

    playUnmuteSound();
  }

  void playUnmuteSound() {
    if (unmuteSoundPlayer == null) {
      unmuteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      unmuteSoundPlayer?.open(Media("asset:///assets/sound/unmuted.ogg"));
      unmuteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    unmuteSoundPlayer!.setVolume(preferences.notificationsVolume.value);
    unmuteSoundPlayer?.seek(Duration.zero);
    unmuteSoundPlayer?.play();
  }

  void endCallSound() {
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/left_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  void stopRingtone() {
    player?.stop();
    player?.dispose();
    player = null;
  }

  void onCallStateChanged(VoipSession event) {
    if (event.state == VoipState.connected ||
        event.state == VoipState.connecting) {
      stopRingtone();
    }

    if (event.state == VoipState.connected) {
      joinCallSound();
    }
  }

  Player getSoundPlayer() {
    player ??= Player(configuration: PlayerConfiguration());
    player!.setVolume(preferences.notificationsVolume.value);

    return player!;
  }
}
