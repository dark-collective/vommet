import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How far a foldable device is open, as iOS reports it.
enum HingeStatus { closed, partiallyOpen, fullyOpen, unknown }

/// One hinge reading: its [status] and its [angle] in degrees (0 closed, 180
/// flat).
@immutable
class HingeState {
  const HingeState(this.status, this.angle);

  final HingeStatus status;
  final double angle;

  @override
  bool operator ==(Object other) =>
      other is HingeState && other.status == status && other.angle == angle;

  @override
  int get hashCode => Object.hash(status, angle);

  @override
  String toString() => 'HingeState(${status.name}, ${angle.round()}°)';
}

/// The hinge of a foldable iPhone (iOS 27.1+). On every other device the
/// stream never emits.
class Hinge {
  static const _channel = EventChannel('im.nether.vommet/hinge');

  /// Hinge changes; `null` when the view is no longer on a display with a
  /// hinge.
  static Stream<HingeState?> get states {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Stream.empty();
    }
    return _channel.receiveBroadcastStream().map(_parse);
  }

  static HingeState? _parse(dynamic event) {
    if (event is! Map) return null;
    final status = HingeStatus.values.firstWhere(
      (s) => s.name == event['status'],
      orElse: () => HingeStatus.unknown,
    );
    final angle = (event['angle'] as num?)?.toDouble() ?? 0;
    return HingeState(status, angle);
  }
}
