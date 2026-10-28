// Vommet: what happened to each notification, as counters, for the opt-in
// "notify_counts" diagnostics event. Notifications are often handled in a
// background isolate where Telemetry isn't running, so each outcome is added
// to a counter in shared preferences (only while the user has said yes to
// diagnostics), and the app reports and subtracts them once per session.
// Counts only: never the room, sender, event or content. Undercounts by
// design: a notification handled before preferences are loaded, or lost
// before it reaches NotificationManager.notify (e.g. not routed to an
// account), isn't counted.

import 'dart:math' as math;

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/main.dart';
import 'package:commet/telemetry/telemetry.dart';

/// One notification's fate; [field] is its counter's name in the event.
enum NotifyOutcome {
  /// Shown normally.
  shown("shown"),

  /// Shown quietly: you're chatting in that room on another device.
  quietedOtherDevice("quieted_other_device"),

  /// Shown quietly by another rule.
  quietedOther("quieted_other"),

  /// Not shown: that room is open on screen.
  droppedActiveRoom("dropped_active_room"),

  /// Not shown: Do Not Disturb.
  droppedDnd("dropped_dnd"),

  /// Not shown: notifications are turned off in Vommet.
  droppedOff("dropped_off"),

  /// Not shown: another rule.
  droppedOther("dropped_other"),

  /// A "couldn't show this notification" notice was shown instead.
  errorNotice("error_notice"),

  /// Handling failed (exception, or no notifier).
  failed("failed");

  const NotifyOutcome(this.field);
  final String field;
}

class NotifyCounts {
  static const _prefix = "vommet_notify_count_";
  static const _total = "pushes";
  static const _msTotal = "handle_ms_total";
  static const _msMax = "handle_ms_max";

  static List<String> get _counters => [
        _total,
        for (final o in NotifyOutcome.values) o.field,
        _msTotal,
      ];

  /// Count one notification's [outcome] and how long handling took.
  /// Approximate: two isolates adding at once can lose a count, which is
  /// fine for diagnostics. Never throws.
  static Future<void> add(NotifyOutcome outcome, int ms) async {
    try {
      final prefs = Preference.preferences;
      if (prefs == null) return;
      await prefs.reload();
      if (preferences.telemetryConsent.value != true) return;
      for (final key in [_total, outcome.field]) {
        await prefs.setInt(
            _prefix + key, (prefs.getInt(_prefix + key) ?? 0) + 1);
      }
      await prefs.setInt(
          _prefix + _msTotal, (prefs.getInt(_prefix + _msTotal) ?? 0) + ms);
      await prefs.setInt(
          _prefix + _msMax, math.max(prefs.getInt(_prefix + _msMax) ?? 0, ms));
    } catch (_) {}
  }

  /// Record the counters as one "notify_counts" event, then subtract what was
  /// reported (rather than zeroing, so a notification counted meanwhile
  /// isn't lost). Nothing is recorded when there were no notifications.
  static Future<void> report() async {
    if (!Telemetry.enabled) return;
    final prefs = Preference.preferences;
    if (prefs == null) return;
    await prefs.reload();
    final read = {
      for (final key in [..._counters, _msMax])
        key: prefs.getInt(_prefix + key) ?? 0,
    };
    if (read[_total] == 0) return;
    // The schema caps a duration at one day.
    Telemetry.record("notify_counts", {
      ...read,
      _msTotal: math.min(read[_msTotal]!, 86400000),
      _msMax: math.min(read[_msMax]!, 86400000),
    });
    await prefs.reload();
    for (final key in _counters) {
      final now = prefs.getInt(_prefix + key) ?? 0;
      await prefs.setInt(_prefix + key, math.max(0, now - read[key]!));
    }
    if ((prefs.getInt(_prefix + _msMax) ?? 0) <= read[_msMax]!) {
      await prefs.remove(_prefix + _msMax);
    }
  }

  /// Forget all counters (consent withdrawn, or "Delete my diagnostics").
  static Future<void> clear() async {
    final prefs = Preference.preferences;
    if (prefs == null) return;
    for (final key in [..._counters, _msMax]) {
      await prefs.remove(_prefix + key);
    }
  }
}
