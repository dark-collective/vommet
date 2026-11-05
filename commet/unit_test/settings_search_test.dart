import 'dart:io';

import 'package:commet/ui/pages/settings/search/settings_search.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Category implements SettingsCategory {
  _Category(this.title, List<String> labels)
      : tabs = [
          for (final l in labels)
            SettingsTab(label: l, pageBuilder: (_) => const SizedBox())
        ];

  @override
  final String? title;

  @override
  final List<SettingsTab> tabs;
}

final _categories = [
  _Category("Account", ["Profile", "Privacy"]),
  _Category("App Settings", ["General", "Appearance", "Privacy"]),
];

const _entries = [
  SettingsSearchEntry(
      category: "App Settings",
      tab: "Appearance",
      title: "Use room avatars",
      description: "Show room avatar images instead of icons"),
  SettingsSearchEntry(
      category: "App Settings",
      tab: "Appearance",
      title: "Use placeholder avatars",
      description: "When a room does not have an avatar set, fall back"),
  SettingsSearchEntry(
      category: "Account",
      tab: "Profile",
      title: "Avatar",
      keywords: ["profile picture"]),
  SettingsSearchEntry(
      category: "App Settings",
      tab: "Privacy",
      title: "Send diagnostics",
      key: "telemetry_consent",
      keywords: ["telemetry"]),
  SettingsSearchEntry(
      category: "Account",
      tab: "Privacy",
      title: "Read receipts",
      section: "Chat Privacy"),
  SettingsSearchEntry(
      category: "App Settings", tab: "Sounds", title: "Notification sounds"),
];

List<String> _titles(String q) =>
    SettingsSearch.search(q, _categories, _entries)
        .map((h) => h.entry.title)
        .toList();

void main() {
  test("empty query finds nothing", () {
    expect(_titles(""), isEmpty);
    expect(_titles("   "), isEmpty);
  });

  test("matches titles, descriptions and keywords, case-insensitively", () {
    expect(_titles("AVATAR"),
        ["Avatar", "Use room avatars", "Use placeholder avatars"]);
    expect(_titles("picture"), ["Avatar"]);
    expect(_titles("telemetry"), ["Send diagnostics"]);
  });

  test("every word must match", () {
    expect(_titles("room avatar"),
        ["Use room avatars", "Use placeholder avatars"]);
    expect(_titles("room telemetry"), isEmpty);
  });

  test("page names match, and same-named tabs stay in their category", () {
    final hits = SettingsSearch.search("privacy", _categories, _entries);
    final pages = hits.where((h) => h.isPage).toList();
    expect(pages.map((h) => (h.categoryIndex, h.tabIndex)),
        containsAll([(0, 1), (1, 2)]));
    final receipts = hits.firstWhere((h) => h.entry.title == "Read receipts");
    expect((receipts.categoryIndex, receipts.tabIndex), (0, 1));
  });

  test("entries on pages this device doesn't show are dropped", () {
    expect(_titles("notification sounds"), isEmpty);
  });

  test("target id prefers the preference key, then the title", () {
    expect(_entries[3].targetId, "telemetry_consent");
    expect(_entries[0].targetId, "Use room avatars");
    expect(_entries[0].hasInlineToggle, isFalse);
  });

  test("tabHasHit", () {
    final hits = SettingsSearch.search("avatar", _categories, _entries);
    expect(SettingsSearch.tabHasHit(hits, 1, 1), isTrue);
    expect(SettingsSearch.tabHasHit(hits, 1, 0), isFalse);
  });

  // Every preference a settings page shows must be findable. Add an entry
  // to lib/ui/pages/settings/search/settings_search_entries.dart (with
  // `preference:` if it exists on main, else its `key:`).
  test("every settings page preference is in the search index", () {
    final entries =
        File("lib/ui/pages/settings/search/settings_search_entries.dart")
            .readAsStringSync();

    final keys = <String, String>{};
    final keyPattern =
        RegExp(r'(\w+)\s*=\s*\w*Preference(?:<[^>]*>)?\(\s*"([^"]+)"');
    for (final f in Directory("lib/config").listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith(".dart")) continue;
      for (final m in keyPattern.allMatches(f.readAsStringSync())) {
        keys[m.group(1)!] = m.group(2)!;
      }
    }

    final missing = <String>[];
    final usePattern = RegExp(r'preference:\s*preferences\.(\w+)');
    for (final dir in ["app", "account", "developer"]) {
      final d = Directory("lib/ui/pages/settings/categories/$dir");
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith(".dart")) continue;
        // Experiments are indexed from their registry.
        if (f.path.endsWith("experiments_settings_page.dart")) continue;
        for (final m in usePattern.allMatches(f.readAsStringSync())) {
          final name = m.group(1)!;
          final key = keys[name];
          if (entries.contains("preferences.$name,") ||
              (key != null && entries.contains('key: "$key"'))) {
            continue;
          }
          missing.add("$name (${f.path})");
        }
      }
    }

    expect(missing, isEmpty,
        reason: "Settings not in settings_search_entries.dart: $missing");
  });
}
