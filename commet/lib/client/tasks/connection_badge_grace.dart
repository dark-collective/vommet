import 'dart:async';

import 'package:commet/client/client.dart';

/// Vommet: holds back the "disconnected" badge for a sync that fails once and
/// then recovers.
///
/// A single failed sync used to put "disconnected" in the corner at once and
/// the retry's "connected" right after it, so a phone on a VPN or a weak
/// network saw the badge come and go all day. Once the account has synced,
/// trouble now has to last [grace] without a successful sync before the badge
/// shows. Before the first sync it shows straight away, as before, since that
/// is the startup progress.
class ConnectionBadgeGrace {
  ConnectionBadgeGrace({
    required this.show,
    this.grace = const Duration(seconds: 20),
    Timer Function(Duration, void Function())? timer,
  }) : _timer = timer ?? Timer.new;

  final void Function(ClientConnectionStatusUpdate update) show;
  final Duration grace;
  final Timer Function(Duration, void Function()) _timer;

  bool _synced = false;
  bool _overdue = false;
  Timer? _pending;

  /// A sync went through: the connection works.
  void onSync() {
    _synced = true;
    _overdue = false;
    _pending?.cancel();
    _pending = null;
  }

  void onStatus(ClientConnectionStatusUpdate update) {
    if (update.status == ClientConnectionStatus.connected) return;

    if (!_synced || _overdue) {
      show(update);
      return;
    }

    _pending ??= _timer(grace, () {
      _pending = null;
      _overdue = true;
      show(ClientConnectionStatusUpdate(ClientConnectionStatus.disconnected));
    });
  }

  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}
