import 'dart:async';

import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Vommet issue 565: a message sent with an account-switch prefix is sent
/// from the other account, so its local echo only appears in that account's
/// timeline. Until the event reaches the timeline being viewed (which can
/// take seconds over federation), the chat shows "Sending as <account>…"
/// above the composer instead.
class PrefixedSend {
  PrefixedSend(this.account, this.retry, {required this.awaitArrival});

  /// The account the message is sent from.
  final String account;

  /// Sends the message again after a failure.
  final Future<TimelineEvent?> Function() retry;

  /// Whether to wait for the event to show up in the viewed timeline (an
  /// edit is folded into the message it edits, so it never shows up alone).
  final bool awaitArrival;

  String? eventId;
  bool failed = false;
  DateTime sentAt = DateTime.now();
}

class PrefixedSends extends ChangeNotifier {
  PrefixedSends(this.isInTimeline,
      {this.pollInterval = const Duration(milliseconds: 500),
      this.giveUpAfter = const Duration(minutes: 2)});

  /// Whether the event with this id is in the timeline being viewed.
  final bool Function(String eventId) isInTimeline;
  final Duration pollInterval;

  /// A sent event that still hasn't arrived by then stops being shown.
  final Duration giveUpAfter;

  final List<PrefixedSend> sends = [];
  Timer? _poll;
  bool _disposed = false;

  Iterable<PrefixedSend> get pending => sends.where((s) => !s.failed);
  Iterable<PrefixedSend> get failed => sends.where((s) => s.failed);

  void track(String account, Future<TimelineEvent?> sending,
      {required Future<TimelineEvent?> Function() retry,
      bool awaitArrival = true}) {
    final send = PrefixedSend(account, retry, awaitArrival: awaitArrival);
    sends.add(send);
    _changed();
    _follow(send, sending);
  }

  void retry(PrefixedSend send) {
    if (!sends.contains(send)) return;
    send.failed = false;
    send.sentAt = DateTime.now();
    _changed();
    _follow(send, send.retry());
  }

  void dismiss(PrefixedSend send) {
    if (sends.remove(send)) _changed();
  }

  Future<void> _follow(
      PrefixedSend send, Future<TimelineEvent?> sending) async {
    TimelineEvent? event;
    try {
      event = await sending;
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to send as ${send.account}");
    }
    if (_disposed || !sends.contains(send)) return;

    if (event == null) {
      send.failed = true;
    } else if (!send.awaitArrival) {
      sends.remove(send);
    } else {
      send.eventId = event.eventId;
    }
    _changed();
    _check();
  }

  /// Drops sends whose event arrived; polls while any is still on its way.
  void _check() {
    if (_disposed) return;
    final now = DateTime.now();
    final before = sends.length;
    sends.removeWhere((s) =>
        !s.failed &&
        s.eventId != null &&
        (isInTimeline(s.eventId!) || now.difference(s.sentAt) > giveUpAfter));
    if (sends.length != before) _changed();

    final waiting = sends.any((s) => !s.failed && s.eventId != null);
    if (waiting) {
      _poll ??= Timer.periodic(pollInterval, (_) => _check());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

/// The "Sending as <account>…" chip, plus one for a send that failed.
class PrefixedSendStatus extends StatelessWidget {
  const PrefixedSendStatus(this.sends, {super.key});

  final PrefixedSends sends;

  static String sendingAs(int count, String account) => Intl.plural(count,
      one: "Sending as $account…",
      other: "Sending $count messages as $account…",
      args: [count, account],
      name: "prefixedSendSendingAs",
      desc:
          "Shown above the message box while messages sent from another account (with an account-switch prefix) are on their way to this timeline: how many, and the account(s) they are sent from");

  static String failedAs(String account) => Intl.message(
      "Couldn't send as $account",
      args: [account],
      name: "prefixedSendFailedAs",
      desc:
          "Shown above the message box when a message sent from another account (with an account-switch prefix) failed to send");

  static String get retry => Intl.message("Retry",
      name: "prefixedSendRetry",
      desc: "Button that sends a failed message from another account again");

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sends,
      builder: (context, _) {
        final pending = sends.pending.toList();
        final failed = sends.failed.firstOrNull;
        if (pending.isEmpty && failed == null) return const SizedBox.shrink();

        final accounts = pending.map((s) => s.account).toSet().join(", ");
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed != null)
                _chip(context,
                    error: true,
                    label: failedAs(failed.account),
                    actions: [
                      TextButton(
                          onPressed: () => sends.retry(failed),
                          child: Text(retry)),
                      TextButton(
                          onPressed: () => sends.dismiss(failed),
                          child: Text(CommonStrings.promptDismiss)),
                    ]),
              if (failed != null && pending.isNotEmpty)
                const SizedBox(height: 4),
              if (pending.isNotEmpty)
                _chip(context,
                    error: false,
                    label: sendingAs(pending.length, accounts),
                    actions: const []),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context,
      {required bool error,
      required String label,
      required List<Widget> actions}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colour = error ? scheme.error : scheme.onSurfaceVariant;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 2,
      shape: const StadiumBorder(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, actions.isEmpty ? 12 : 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error)
              Icon(Icons.error_outline, size: 16, color: colour)
            else
              SizedBox.square(
                  dimension: 12,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: colour)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: colour)),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}
