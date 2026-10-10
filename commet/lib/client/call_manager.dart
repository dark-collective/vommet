import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/push_notification/notification_content.dart';
import 'package:commet/client/components/push_notification/notification_manager.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
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
    final audio = audioOf(event);
    // Both ways: the microphone opened per [nextCallMuted] when the join
    // started, and a (un)mute while connecting must still land. A ringing
    // call is never unmuted here.
    if (event.state != VoipState.incoming &&
        audio.muted != event.isMicrophoneMuted) {
      event.setMicrophoneMute(audio.muted);
    }
    // Streams made before the call was listed here took the next call's
    // deafen; now they can find their own.
    _streamsChanged(event);
    // A call you join or start comes to the front (not one that rings).
    if (event.state != VoipState.incoming) {
      _focusedSessionId = event.sessionId;
      _onSelfAudioChanged.add(null);
    }

    event.onConnectionStateChanged.listen((_) => onCallStateChanged(event));
    event.onStateChanged.listen((_) {
      _streamsChanged(event);
      _followSessionMute(event);
    });
  }

  void onSessionEnded(VoipSession event) {
    currentSessions
        .removeWhere((element) => element.sessionId == event.sessionId);
    _audio.remove(event.sessionId);
    if (_focusedSessionId == event.sessionId) _focusedSessionId = null;
    _onSelfAudioChanged.add(null);

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
    if (!playSounds) return;
    if (player?.state.playing == true) {
      return;
    }

    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/ringtone_out.ogg"));
    player?.setPlaylistMode(PlaylistMode.loop);
  }

  void joinCallSound() {
    if (!playSounds) return;
    player = getSoundPlayer();
    player?.open(Media("asset:///assets/sound/joined_call.ogg"));
    player?.setPlaylistMode(PlaylistMode.none);
  }

  /// Vommet: mute and deafen are the user's own state, as in Discord. With
  /// experiment_call_cards each call has its own (Vommet can be in several
  /// calls at once, on different accounts), and a new call starts with the
  /// state last used; without it, one state for every call, as before. Out
  /// of a call it's the state the next call starts with, so joining muted
  /// works.
  final Map<String, CallAudio> _audio = {};
  final CallAudio _next = CallAudio();

  /// The call on screen in the call panel (its open card): the user panel's
  /// buttons and the shortcuts act on it.
  String? _focusedSessionId;

  static bool get perCall => preferences.experimentCallCards.value;

  /// Calls we're in or joining (not ringing ones).
  Iterable<VoipSession> get _liveCalls => currentSessions.where(
      (s) => s.state != VoipState.ended && s.state != VoipState.incoming);

  VoipSession? get focusedCall {
    final live = _liveCalls.toList();
    if (live.isEmpty) return null;
    return live.where((s) => s.sessionId == _focusedSessionId).firstOrNull ??
        live.last;
  }

  void focusCall(VoipSession session) {
    if (_focusedSessionId == session.sessionId) return;
    _focusedSessionId = session.sessionId;
    _onSelfAudioChanged.add(null);
  }

  CallAudio audioOf(VoipSession session) =>
      _audio.putIfAbsent(session.sessionId, () => _next.copy());

  CallAudio get _focusedAudio {
    final call = focusedCall;
    return call == null ? _next : audioOf(call);
  }

  /// The focused call's state, or the next call's when there's none.
  bool get isMuted => _focusedAudio.muted;
  bool get isDeafened => _focusedAudio.deafened;

  /// What the next call starts with (the microphone opens unmuted or not).
  bool get nextCallMuted => _next.muted;

  bool isMutedIn(VoipSession session) => audioOf(session).muted;
  bool isDeafenedIn(VoipSession session) => audioOf(session).deafened;

  /// Whether [stream]'s call is deafened (its incoming audio silenced).
  /// A stream not in its call's list yet (its constructor applies the
  /// volume before it's added) gets the next call's state, never another
  /// call's; it's re-applied once added (see [_streamsChanged]).
  bool isDeafenedFor(VoipStream stream) {
    for (final session in currentSessions) {
      if (session.streams.contains(stream)) return audioOf(session).deafened;
    }
    return _next.deafened;
  }

  /// A call's streams changed (someone joined, a track was published):
  /// re-apply its volumes, so new streams follow this call's deafen.
  void _streamsChanged(VoipSession session) {
    final audio = audioOf(session);
    final now = session.streams;
    // The same streams (by identity, so one leaving and another joining
    // between two events still counts as a change).
    if (now.length == audio.streams.length &&
        Iterable.generate(now.length)
            .every((i) => identical(now[i], audio.streams[i]))) {
      return;
    }
    audio.streams = List.of(now);
    for (final stream in now) {
      stream.applyPlaybackVolume();
    }
  }

  final StreamController<void> _onSelfAudioChanged =
      StreamController.broadcast();

  /// Fires when any call's mute or deafen (or the focused call) changes.
  Stream<void> get onSelfAudioChanged => _onSelfAudioChanged.stream;

  /// The calls a change to [session] applies to: just it with the
  /// experiment, every call without (and none out of a call).
  List<VoipSession> _targets(VoipSession? session) {
    if (session == null) return const [];
    return perCall ? [session] : _liveCalls.toList();
  }

  /// Applies [change] to [session]'s state (and, without the experiment or
  /// out of a call, to every call's and the next call's), then makes the
  /// next call start like this one.
  List<VoipSession> _change(
      VoipSession? session, void Function(CallAudio audio) change) {
    final targets = _targets(session);
    for (final target in targets) {
      change(audioOf(target));
    }
    if (!perCall || session == null) {
      change(_next);
    } else {
      _next.copyFrom(audioOf(session));
    }
    return targets;
  }

  Future<void> _applyMicrophones(List<VoipSession> sessions) async {
    await Future.wait(sessions.map((session) async {
      final audio = audioOf(session);
      if (session.isMicrophoneMuted == audio.muted) return;
      // While our own change lands, [_followSessionMute] must not read the
      // not-yet-updated session as the user's choice (deafen would undo
      // itself).
      audio.applying++;
      try {
        await session.setMicrophoneMute(audio.muted);
      } finally {
        audio.applying--;
      }
    }));
  }

  /// The call view mutes its session directly; follow it, so the panel's
  /// buttons and the next call match. Unmuting there also undeafens.
  void _followSessionMute(VoipSession session) {
    final audio = audioOf(session);
    if (audio.applying > 0 || session.state != VoipState.connected) return;
    final muted = session.isMicrophoneMuted;
    if (muted == audio.muted) return;

    var undeafened = false;
    void follow(CallAudio a) {
      a.muted = muted;
      if (!muted && a.deafened) {
        a.deafened = false;
        undeafened = true;
      }
    }

    if (perCall) {
      follow(audio);
      _next.copyFrom(audio);
    } else {
      // One state for every call, as before: the others' microphones are
      // left as they are, their state follows.
      for (final target in _liveCalls) {
        follow(audioOf(target));
      }
      follow(_next);
    }
    if (undeafened) refreshPlaybackVolumes();
    _onSelfAudioChanged.add(null);
  }

  /// Mutes or unmutes [session] (the focused call by default; the next call
  /// out of one). Unmuting while deafened also undeafens.
  void setMutedIn(VoipSession? session, bool muted) {
    var undeafened = false;
    final targets = _change(session, (a) {
      if (!muted && a.deafened) {
        a.deafened = false;
        undeafened = true;
      }
      a.muted = muted;
    });
    _applyMicrophones(targets);
    if (undeafened) refreshPlaybackVolumes();
    _onSelfAudioChanged.add(null);
    muted ? playMuteSound() : playUnmuteSound();
  }

  /// Deafen silences everyone in the call and mutes the microphone;
  /// undeafening unmutes only if deafen did the muting.
  void setDeafenedIn(VoipSession? session, bool deafened) {
    final current = session == null ? _next : audioOf(session);
    if (current.deafened == deafened) return;
    final targets = _change(session, (a) {
      if (a.deafened == deafened) return;
      if (deafened) {
        a.mutedBeforeDeafen = a.muted;
        a.deafened = true;
        a.muted = true;
      } else {
        a.deafened = false;
        if (!a.mutedBeforeDeafen) a.muted = false;
      }
    });
    _applyMicrophones(targets);
    refreshPlaybackVolumes();
    _onSelfAudioChanged.add(null);
    deafened ? playMuteSound() : playUnmuteSound();
  }

  /// After experiment_call_cards changes: turned off, every call takes the
  /// focused call's state (one state again).
  void syncAudioMode() {
    if (!perCall) {
      final state = _focusedAudio.copy();
      final calls = _liveCalls.toList();
      for (final call in calls) {
        audioOf(call).copyFrom(state);
      }
      _next.copyFrom(state);
      _applyMicrophones(calls);
    }
    refreshPlaybackVolumes();
    _onSelfAudioChanged.add(null);
  }

  void toggleMuteIn(VoipSession session) =>
      setMutedIn(session, !isMutedIn(session));

  void toggleDeafenIn(VoipSession session) =>
      setDeafenedIn(session, !isDeafenedIn(session));

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

  // The user panel and the shortcuts: the focused call (or the next one).
  void mute() => setMutedIn(focusedCall, true);

  void unmute() => setMutedIn(focusedCall, false);

  void toggleMute() => isMuted ? unmute() : mute();

  void setDeafened(bool deafened) => setDeafenedIn(focusedCall, deafened);

  void toggleDeafen() => setDeafened(!isDeafened);

  /// Off in unit tests (no audio player there).
  bool playSounds = true;

  void playMuteSound() {
    if (!playSounds) return;
    if (muteSoundPlayer == null) {
      muteSoundPlayer ??= Player(configuration: PlayerConfiguration());
      muteSoundPlayer?.open(Media("asset:///assets/sound/muted.ogg"));
      muteSoundPlayer?.setPlaylistMode(PlaylistMode.none);
    }

    muteSoundPlayer!.setVolume(preferences.notificationsVolume.value);
    muteSoundPlayer?.seek(Duration.zero);
    muteSoundPlayer?.play();
  }

  void playUnmuteSound() {
    if (!playSounds) return;
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
    if (!playSounds) return;
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

/// Vommet: one call's mute and deafen (see [CallManager.audioOf]).
class CallAudio {
  bool muted = false;
  bool deafened = false;

  /// Whether the microphone was muted before deafening, so undeafening only
  /// unmutes when deafen did the muting.
  bool mutedBeforeDeafen = false;

  /// Our own microphone changes still landing on the session.
  int applying = 0;

  /// The call's streams when its volumes were last applied.
  List<VoipStream> streams = const [];

  CallAudio copy() => CallAudio()..copyFrom(this);

  void copyFrom(CallAudio other) {
    muted = other.muted;
    deafened = other.deafened;
    mutedBeforeDeafen = other.mutedBeforeDeafen;
  }
}
