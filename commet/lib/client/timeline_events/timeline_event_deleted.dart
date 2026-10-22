/// Vommet issue 306: what is known about a deleted (redacted) message, for the
/// placeholder that takes its place in the timeline.
class DeletedMessageInfo {
  const DeletedMessageInfo({this.deletedBy, this.reason});

  /// Who deleted it, when known.
  final String? deletedBy;

  /// The reason given when it was deleted, if any.
  final String? reason;
}
