import 'package:commet/client/components/voip/voip_session.dart';

/// Vommet: how long calls have run, for the call timer.
class CallDuration {
  static final Map<String, DateTime> _connectedAt = {};

  /// When we connected to [session], remembered from the first time it was
  /// seen connected (so the time survives the panel being rebuilt or a room
  /// switch). Null while it rings, connects or after it ended.
  static DateTime? connectedSince(VoipSession session, {DateTime? now}) {
    switch (session.state) {
      case VoipState.connected:
        return _connectedAt.putIfAbsent(
            session.sessionId, () => now ?? DateTime.now());
      case VoipState.ended:
        _connectedAt.remove(session.sessionId);
        return null;
      default:
        return null;
    }
  }

  /// "0:05", "41:05", "1:02:09".
  static String format(Duration elapsed) {
    if (elapsed.isNegative) elapsed = Duration.zero;
    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes % 60;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, "0");
    if (hours == 0) return "$minutes:$seconds";
    return "$hours:${minutes.toString().padLeft(2, "0")}:$seconds";
  }
}
