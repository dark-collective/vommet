import 'dart:convert';

import 'package:flutter/services.dart';

/// Vommet: one testing build's worth of user-facing changes.
class ChangelogEntry {
  final DateTime date;
  final List<String> changes;

  const ChangelogEntry(this.date, this.changes);
}

/// Vommet: the "What's new" changelog shipped in the app
/// (assets/data/changelog.json). The sync session adds one entry per testing
/// build when it cuts the build, written for testers, not developers.
class WhatsNew {
  static const asset = "assets/data/changelog.json";

  /// Parses the changelog; newest entry first. Malformed input gives an empty
  /// list (a broken changelog must never break startup).
  static List<ChangelogEntry> parse(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final entries = <ChangelogEntry>[];
      for (final raw in (json["entries"] as List? ?? const [])) {
        if (raw is! Map) continue;
        final date = DateTime.tryParse(raw["date"]?.toString() ?? "");
        final changes = (raw["changes"] as List? ?? const [])
            .whereType<String>()
            .where((c) => c.trim().isNotEmpty)
            .toList();
        if (date == null || changes.isEmpty) continue;
        entries.add(ChangelogEntry(date.toUtc(), changes));
      }
      entries.sort((a, b) => b.date.compareTo(a.date));
      return entries;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<ChangelogEntry>> load() async {
    try {
      return parse(await rootBundle.loadString(asset));
    } catch (_) {
      return const [];
    }
  }

  /// The entries to show after updating from a build made at [lastSeen] to
  /// one made at [buildDate]: everything in between, newest first. With no
  /// [lastSeen] (an update from a version before this feature existed), only
  /// the newest [whenUnknown] entries.
  static List<ChangelogEntry> since(
      List<ChangelogEntry> all, DateTime? lastSeen, DateTime buildDate,
      {int whenUnknown = 1}) {
    final inBuild = all.where((e) => !e.date.isAfter(buildDate)).toList();
    if (lastSeen == null) return inBuild.take(whenUnknown).toList();
    return inBuild.where((e) => e.date.isAfter(lastSeen)).toList();
  }
}
