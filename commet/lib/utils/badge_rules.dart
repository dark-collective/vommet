/// Vommet issue 719: what a room's badge shows, from the counts it displays
/// (see `Room.displayNotificationCount` and
/// `Room.displayHighlightedNotificationCount`).
///
/// - nothing counted: the unread dot, or nothing;
/// - a grey number: silent notifications (the push rule notifies without
///   a sound);
/// - a red number: mentions and keywords, or messages whose push rule plays
///   a sound ("Noisy"). Red wins when both are counted.
class BadgeRules {
  /// Every notifying message on All messages (the server's count includes
  /// mentions), else the mentions and keywords.
  static int count({required int notifications, required int highlights}) =>
      notifications > highlights ? notifications : highlights;

  /// Whether the badge is red rather than grey.
  static bool noisy(
          {required int notifications,
          required int highlights,
          required bool messagesAreNoisy}) =>
      highlights > 0 || (notifications > 0 && messagesAreNoisy);
}
