/// Vommet: who in a call is talking and whose microphone is off, for the
/// sidebar's speaking rings. Implemented by call sessions that know it
/// (room calls over LiveKit); others simply don't show it.
abstract class VoipParticipants {
  /// User ids talking right now (as the call server reports it, already
  /// smoothed).
  Set<String> get speakingUserIds;

  /// User ids in the call whose microphone is off.
  Set<String> get micOffUserIds;

  /// Fires when [speakingUserIds] or [micOffUserIds] change.
  Stream<void> get onParticipantsChanged;
}
