import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership.dart';

/// Vommet: decides when a call membership change needs a new media key.
///
/// Every own-membership refresh, re-post or status update is a new
/// `call.member` state event with the same `created_ts`. Rotating the key on
/// each of them makes every peer re-send keys to every device of the call.
/// Like matrix-js-sdk, a membership is new only when its `created_ts` changes
/// (or it wasn't known); a leave always rotates, so the leaver can't decrypt
/// what comes after.
class MatrixRtcKeyRotation {
  /// State key -> `created_ts` of the memberships seen so far.
  final Map<String, int> _created = {};

  /// Records a membership already in the room's state, without rotating.
  void seed(String stateKey, Map<String, dynamic> content, int originServerTs) {
    if (content.isEmpty) return;
    _created[stateKey] = MatrixRtcMembership.createdTs(content, originServerTs);
  }

  /// Whether this `call.member` event changes who holds the key.
  bool needsRotation(
      String stateKey, Map<String, dynamic> content, int originServerTs) {
    if (content.isEmpty) {
      _created.remove(stateKey);
      return true;
    }
    final created = MatrixRtcMembership.createdTs(content, originServerTs);
    if (_created[stateKey] == created) return false;
    _created[stateKey] = created;
    return true;
  }
}
