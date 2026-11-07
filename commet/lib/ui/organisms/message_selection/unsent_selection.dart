part of 'message_selection.dart';

// Vommet issue 1127: shared by the bar and selected-message context menu.
extension UnsentSelection on MessageSelection {
  bool get unsentMode => _hadUnsent;
  List<TimelineEvent> cancelableEvents() =>
      tickedEvents().where(SelectedSends.isOwnLocal).toList();
  List<TimelineEvent> retryableEvents() => tickedEvents()
      .where((e) => SelectedSends.retryReason(e) == null)
      .toList();

  String get statusLabel {
    final events = tickedEvents();
    final sent =
        events.where((e) => e.status == TimelineEventStatus.synced).length;
    final failed = events.where((e) => e.status.isError).length;
    final sending = events.where((e) => e.status.isSending).length;
    final waiting =
        events.where((e) => e.status == TimelineEventStatus.sent).length;
    final unavailable = ticked.length - events.length;
    return [
      if (sent > 0)
        Intl.message('$sent sent',
            args: [sent],
            name: 'selectedSendSyncedStatus',
            desc: 'Selected synced message count'),
      if (failed > 0)
        Intl.message('$failed failed',
            args: [failed],
            name: 'selectedSendFailedStatus',
            desc: 'Selected failed message count'),
      if (sending > 0)
        Intl.message('$sending sending',
            args: [sending],
            name: 'selectedSendSendingStatus',
            desc: 'Selected sending message count'),
      if (waiting > 0)
        Intl.message('$waiting awaiting sync',
            args: [waiting],
            name: 'selectedSendWaitingStatus',
            desc: 'Selected server-accepted message count awaiting sync'),
      if (unavailable > 0)
        Intl.message('$unavailable unavailable',
            args: [unavailable],
            name: 'selectedSendUnavailableStatus',
            desc: 'Selected unavailable message count'),
    ].join(' · ');
  }

  List<String> get sendReasons => [
        for (final event in tickedEvents())
          if (sendErrors[_selectionKey(event.eventId)] ??
                  (event.status.isError
                      ? SelectedSends.retryReason(event)
                      : null)
              case final reason?)
            messageReason(event.plainTextBody, reason),
      ];

  static String messageReason(String message, String reason) => Intl.message(
      '$message: $reason',
      args: [message, reason],
      name: 'selectedSendMessageReason',
      desc:
          'Reason a particular selected message could not be retried or removed');

  void retrySelected() {
    if (busy || !active) return;
    final operation = _sendOperation;
    var started = 0;
    var skipped = 0;
    for (final event in tickedEvents()) {
      if (!event.status.isError) continue;
      final key = _selectionKey(event.eventId);
      sendErrors.remove(key);
      final reason = SelectedSends.retryReason(event);
      if (reason != null) {
        sendErrors[key] = reason;
        skipped++;
        continue;
      }
      if (SelectedSends.retry(event, (error) {
        if (_disposed || !active || _sendOperation != operation) return;
        if (error != null && ticked.contains(key)) sendErrors[key] = error;
        _notify();
      })) started++;
    }
    sendFeedback = retryFeedback(started, skipped);
    _notify();
  }

  Future<void> cancelSelected(BuildContext context) async {
    if (busy || !active) return;
    final keys =
        cancelableEvents().map((e) => _selectionKey(e.eventId)).toList();
    if (keys.isEmpty) return;
    final operation = _sendOperation;
    final messenger = ScaffoldMessenger.maybeOf(context);
    progress = cancelCount(keys.length);
    _notify();
    try {
      final confirmed = await AdaptiveDialog.confirmation(context,
          title: cancelTitle(keys.length),
          prompt: cancelWarning,
          confirmationText: cancelCount(keys.length),
          cancelText: keepMessages,
          dangerous: true);
      if (confirmed != true ||
          _disposed ||
          !active ||
          _sendOperation != operation) return;
      var removed = 0;
      var skipped = 0;
      var failed = 0;
      for (final key in keys) {
        if (_disposed || !active || _sendOperation != operation) break;
        final event = tickedEvents()
            .where((e) => _selectionKey(e.eventId) == key)
            .firstOrNull;
        if (event == null || !SelectedSends.isOwnLocal(event)) {
          skipped++;
          continue;
        }
        try {
          await room.cancelSend(event);
          if (_disposed || !active || _sendOperation != operation) return;
          ticked.remove(key);
          sendErrors.remove(key);
          removed++;
        } catch (error, trace) {
          if (_disposed || !active || _sendOperation != operation) return;
          failed++;
          sendErrors[key] = cancelFailed;
          Log.onError(error, trace,
              content: 'Selected send cancellation failed');
        }
      }
      if (_disposed || !active || _sendOperation != operation) return;
      sendFeedback = cancelFeedback(removed, skipped, failed);
      messenger?.showSnackBar(SnackBar(content: Text(sendFeedback!)));
    } finally {
      if (!_disposed && _sendOperation == operation) {
        progress = null;
        _afterChange();
      }
    }
  }

  static String retryCount(int count) => Intl.message('Retry $count',
      args: [count],
      name: 'selectedSendRetryCount',
      desc: 'Number of eligible failed messages to retry');
  static String cancelCount(int count) => Intl.message('Cancel sending $count',
      args: [count],
      name: 'selectedSendCancelCount',
      desc: 'Number of local unsent messages to remove');
  static String sentCount(int count) => Intl.message('Sent actions ($count)',
      args: [count],
      name: 'selectedSendSentCount',
      desc: 'Menu of actions for the synced selected messages');
  static String copyCount(int count) => Intl.message('Copy $count',
      args: [count],
      name: 'selectedSendCopyCount',
      desc: 'Copy only synced selected messages');
  static String cancelTitle(int count) =>
      Intl.message('Cancel sending $count messages?',
          args: [count],
          name: 'selectedSendCancelTitle',
          desc: 'Confirmation before local removal of unsent messages');
  static String get cancelWarning => Intl.message(
      'Remove these unsent messages from this device. A message already queued or sending may still be delivered. Sent messages will stay.',
      name: 'selectedSendCancelWarning',
      desc: 'The SDK cannot abort in-flight send requests');
  static String get keepMessages => Intl.message('Keep messages',
      name: 'selectedSendKeep',
      desc: 'Dismiss cancellation without removing messages');
  static String get cancelFailed =>
      Intl.message('Could not remove this unsent message.',
          name: 'selectedSendCancelFailed',
          desc: 'Local removal of a selected send failed');
  static String retryFeedback(int started, int skipped) =>
      Intl.message('Retry started for $started; $skipped could not retry.',
          args: [started, skipped],
          name: 'selectedSendRetryFeedback',
          desc: 'Retry handoff result, not delivery confirmation');
  static String cancelFeedback(int removed, int skipped, int failed) =>
      Intl.message(
          '$removed unsent messages removed; $skipped unavailable or already sent; $failed failed. Queued or sending messages may still arrive.',
          args: [removed, skipped, failed],
          name: 'selectedSendCancelFeedback',
          desc: 'Batch local removal result with delivery limitation');
}
