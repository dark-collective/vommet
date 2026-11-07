/// Where a forwarded message came from. Every field is optional and is only
/// what the person who forwarded it claims.
class ForwardedFrom {
  const ForwardedFrom(
      {this.senderId, this.roomId, this.eventId, this.originalTime});

  final String? senderId;
  final String? roomId;
  final String? eventId;
  final DateTime? originalTime;
}

/// Vommet: events that can be forwards of another message.
abstract class TimelineEventFeatureForwarded {
  /// Null when the event is not a forward.
  ForwardedFrom? get forwardedFrom;
}
