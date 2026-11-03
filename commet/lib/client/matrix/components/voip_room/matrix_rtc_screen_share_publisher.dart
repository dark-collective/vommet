import 'dart:async';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_membership_writer.dart';
import 'package:commet/client/matrix/components/voip_room/matrix_rtc_screen_share.dart';
import 'package:commet/debug/log.dart';

/// Publishes only the local device's actual screen-share video status.
class MatrixRtcScreenSharePublisher {
  MatrixRtcScreenSharePublisher(
      {required this.writer,
      required this.isSharing,
      required this.enabled,
      required Stream<bool> onEnabledChanged}) {
    writer.beforeSend = _apply;
    _preference =
        onEnabledChanged.listen((_) => unawaited(refresh(force: true)));
  }
  final MatrixRtcMembershipWriter writer;
  final bool Function() isSharing;
  final bool Function() enabled;
  StreamSubscription<bool>? _preference;
  Timer? _retry;
  bool _closed = false;
  bool? _advertised;
  int? _since;
  int _revision = 0;

  Future<void> refresh({bool force = false, int attempt = 0}) async {
    if (_closed) return;
    final sharing = isSharing();
    _since = sharing ? (_since ?? DateTime.now().millisecondsSinceEpoch) : null;
    final active = enabled() && sharing;
    if (!force &&
        (_advertised == active || (_advertised == null && !enabled()))) return;
    _advertised = active;
    final revision = ++_revision;
    _retry?.cancel();
    try {
      await writer.update((_) {});
    } catch (error) {
      Log.w('Could not update screen-share status (${error.runtimeType})');
      if (!_closed && revision == _revision && attempt < 3) {
        _retry = Timer(const Duration(seconds: 10),
            () => unawaited(refresh(force: true, attempt: attempt + 1)));
      }
    }
  }

  void _apply(Map<String, dynamic> content) {
    // Evaluate after queued refresh/focus mutations, never a stale snapshot.
    if (!_closed && enabled() && isSharing()) {
      _since ??= DateTime.now().millisecondsSinceEpoch;
      content[MatrixRtcScreenShare.field] = {'active': true, 'since': _since};
    } else {
      content.remove(MatrixRtcScreenShare.field);
    }
  }

  void close() {
    _closed = true;
    _revision++;
    _retry?.cancel();
    _preference?.cancel();
  }
}
