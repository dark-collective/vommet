// Vommet: the splash never waits silently forever. If loading the accounts
// takes far longer than it should, the splash says so; in a browser with
// little storage (a private window) it says why. Loading carries on, and the
// app replaces the splash as soon as it is in.

import 'dart:async';

import 'package:commet/utils/startup_watchdog/storage_probe.dart'
    if (dart.library.js_interop) 'package:commet/utils/startup_watchdog/storage_probe_web.dart';
import 'package:intl/intl.dart';

class StartupWatchdog {
  StartupWatchdog(
    this.onSlow, {
    this.after = const Duration(seconds: 40),
    this.probe = readStorageEstimate,
  });

  /// Called at most once, with the message for the splash, and never after
  /// [finished] (the app, or the fatal error page, is shown by then).
  final void Function(String message) onSlow;
  final Duration after;
  final Future<StorageEstimate?> Function() probe;
  Timer? _timer;
  bool _done = false;

  /// Private windows get a small, memory-only store: a few hundred MB in
  /// Chromium, against a share of the disk in a normal window.
  static const int smallQuota = 1500 * 1024 * 1024;

  void start() {
    if (_done || _timer != null) return;
    _timer = Timer(after, () async {
      StorageEstimate? estimate;
      try {
        estimate = await probe();
      } catch (_) {}
      // The app may have come up while the probe ran.
      if (_done) return;
      _done = true;
      onSlow(messageFor(estimate));
    });
  }

  void finished() {
    _done = true;
    _timer?.cancel();
    _timer = null;
  }

  static String messageFor(StorageEstimate? estimate) {
    if (estimate != null &&
        estimate.quota > 0 &&
        (estimate.quota < smallQuota ||
            estimate.usage >= estimate.quota * 0.9)) {
      return startupSlowSmallStorage;
    }
    return startupSlow;
  }
}

String get startupSlow => Intl.message(
      "This is taking longer than usual.\nVommet is still loading your rooms.",
      name: "startupSlow",
      desc:
          "Splash screen text when loading the app takes much longer than usual",
    );

String get startupSlowSmallStorage => Intl.message(
      "This is taking longer than usual.\nThis browser window gives Vommet very little storage, which happens in private or incognito windows. With many rooms, Vommet may not fit: open it in a normal window instead.",
      name: "startupSlowSmallStorage",
      desc:
          "Splash screen text when loading takes too long and the browser's storage quota is small, as in a private window",
    );
