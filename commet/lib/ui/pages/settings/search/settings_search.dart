// Vommet: search box for the app settings. Matches individual settings (by
// title, description, section and keywords), not just page names. The index
// lives in settings_search_entries.dart.
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/config/experiment_strings.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/ui/pages/settings/search/settings_search_strings.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// One searchable setting. [category] and [tab] are the visible labels of the
/// settings category and page it lives on; entries whose page isn't shown on
/// this device are dropped.
class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.category,
    required this.tab,
    required this.title,
    this.description,
    this.section,
    this.key,
    this.preference,
    this.inline = true,
    this.keywords = const [],
  });

  final String category;
  final String tab;
  final String title;
  final String? description;
  final String? section;

  /// Preference key of the control, used to find and flash it on its page.
  /// Defaults to [preference]'s key.
  final String? key;

  /// When set (and [inline] is true) the result row gets a switch that
  /// flips the setting without leaving the results.
  final BoolPreference? preference;

  /// False for toggles whose page runs extra code when they change.
  final bool inline;

  /// Extra words people might search for.
  final List<String> keywords;

  String get targetId => key ?? preference?.key ?? title;

  bool get hasInlineToggle => preference != null && inline;
}

/// A match, located in the current category/tab list.
class SettingsSearchHit {
  const SettingsSearchHit(
      {required this.entry,
      required this.categoryIndex,
      required this.tabIndex,
      required this.icon,
      this.isPage = false});

  final SettingsSearchEntry entry;
  final int categoryIndex;
  final int tabIndex;
  final IconData? icon;

  /// The hit is a whole settings page (its name matched), not one setting.
  final bool isPage;
}

class SettingsSearch {
  static String normalize(String s) => s.toLowerCase().trim();

  static List<String> tokens(String query) => normalize(query)
      .split(RegExp(r"\s+"))
      .where((t) => t.isNotEmpty)
      .toList();

  /// Every token must appear somewhere in the entry. Lower scores rank first.
  static int? score(SettingsSearchEntry e, List<String> tokens) {
    if (tokens.isEmpty) return null;
    final title = normalize(e.title);
    final rest = normalize([
      e.tab,
      e.section ?? "",
      e.description ?? "",
      ...e.keywords,
    ].join("\n"));

    for (final t in tokens) {
      if (!title.contains(t) && !rest.contains(t)) return null;
    }

    final q = tokens.join(" ");
    if (title.startsWith(q)) return 0;
    if (title.contains(q)) return 1;
    if (tokens.every(title.contains)) return 2;
    final named = normalize([e.tab, e.section ?? "", ...e.keywords].join("\n"));
    if (tokens.every((t) => title.contains(t) || named.contains(t))) return 3;
    return 4;
  }

  /// Searches [entries] plus the page names in [categories] and the
  /// experiments (when the Experiments page is shown).
  static List<SettingsSearchHit> search(String query,
      List<SettingsCategory> categories, List<SettingsSearchEntry> entries,
      {List<Experiment>? experiments, String? experimentsTab}) {
    final toks = tokens(query);
    if (toks.isEmpty) return [];

    final scored = <(int, int, SettingsSearchHit)>[];
    var order = 0;

    void consider(SettingsSearchEntry e, {bool isPage = false}) {
      final loc = _locate(categories, e.category, e.tab);
      if (loc == null) return;
      final s = score(e, toks);
      if (s == null) return;
      final tab = categories[loc.$1].tabs[loc.$2];
      scored.add((
        isPage ? s - 1 : s,
        order++,
        SettingsSearchHit(
            entry: e,
            categoryIndex: loc.$1,
            tabIndex: loc.$2,
            icon: tab.icon,
            isPage: isPage)
      ));
    }

    for (final c in categories) {
      for (final t in c.tabs) {
        consider(
            SettingsSearchEntry(
                category: c.title ?? "", tab: t.label, title: t.label),
            isPage: true);
      }
    }

    for (final e in entries) {
      consider(localizeSettingsSearchEntry(e));
    }

    if (experimentsTab != null) {
      for (final c in categories) {
        if (!c.tabs.any((t) => t.label == experimentsTab)) continue;
        for (final x in experiments ?? ExperimentRegistry.all) {
          final title = experimentTitle(x);
          final description = experimentDescription(x);
          final section = experimentCategoryLabel(x.category);
          consider(SettingsSearchEntry(
              category: c.title ?? "",
              tab: experimentsTab,
              title: title,
              description: description,
              section: section,
              preference: x.preference,
              inline: false,
              keywords: [
                "experiment",
                // The English words still find it.
                if (title != x.title) x.title,
                if (section != x.category.label) x.category.label,
                if (description != x.description) x.description,
              ]));
        }
      }
    }

    scored.sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);

    // A page hit and a setting with the same name on that page: keep one.
    final seen = <String>{};
    final result = <SettingsSearchHit>[];
    for (final (_, _, hit) in scored) {
      final id =
          "${hit.categoryIndex}/${hit.tabIndex}/${normalize(hit.entry.title)}";
      if (seen.add(id)) result.add(hit);
    }
    return result;
  }

  static (int, int)? _locate(
      List<SettingsCategory> categories, String category, String tab) {
    for (var c = 0; c < categories.length; c++) {
      if ((categories[c].title ?? "") != category) continue;
      final t = categories[c].tabs.indexWhere((t) => t.label == tab);
      if (t >= 0) return (c, t);
    }
    return null;
  }

  /// Whether [tab] in [categoryIndex] has any hit.
  static bool tabHasHit(
          List<SettingsSearchHit> hits, int categoryIndex, int tabIndex) =>
      hits.any(
          (h) => h.categoryIndex == categoryIndex && h.tabIndex == tabIndex);
}

/// Which control on the opened page should flash. [serial] changes on every
/// jump so the same setting can be flashed twice in a row.
class SettingsHighlight extends InheritedWidget {
  const SettingsHighlight(
      {required this.targetId,
      required this.serial,
      required super.child,
      super.key});

  final String? targetId;
  final int serial;

  static SettingsHighlight? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsHighlight>();

  @override
  bool updateShouldNotify(SettingsHighlight oldWidget) =>
      oldWidget.targetId != targetId || oldWidget.serial != serial;
}

/// Wraps a settings control. When search opens its page for it, it scrolls
/// into view and flashes.
class SettingsSearchTarget extends StatefulWidget {
  const SettingsSearchTarget(
      {required this.ids, required this.child, super.key});

  /// Any of these may be the entry's target id (preference key or title).
  final List<String?> ids;
  final Widget child;

  @override
  State<SettingsSearchTarget> createState() => _SettingsSearchTargetState();
}

class _SettingsSearchTargetState extends State<SettingsSearchTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController flash = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200));
  int? flashedSerial;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final h = SettingsHighlight.maybeOf(context);
    if (h == null || h.targetId == null || h.serial == flashedSerial) return;
    if (!widget.ids.contains(h.targetId)) return;
    flashedSerial = h.serial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context,
          alignment: 0.3, duration: const Duration(milliseconds: 300));
      flash.forward(from: 0);
    });
  }

  @override
  void dispose() {
    flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: flash,
      child: widget.child,
      builder: (context, child) {
        // Hold for a moment, then fade out.
        final v = flash.isAnimating
            ? (flash.value < 0.4 ? 1.0 : 1 - (flash.value - 0.4) / 0.6)
            : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18 * v),
            border: Border.all(color: color.withValues(alpha: 0.7 * v)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: child,
        );
      },
    );
  }
}

class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField(
      {required this.controller, required this.onChanged, super.key});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  static String get promptSearchSettings => Intl.message("Search settings",
      name: "promptSearchSettings",
      desc: "Placeholder of the search box at the top of the settings menu");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: TextField(
        key: const ValueKey("SETTINGS_SEARCH_FIELD"),
        controller: controller,
        onChanged: onChanged,
        textAlignVertical: TextAlignVertical.center,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLowest,
          hintText: promptSearchSettings,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: () {
                      controller.clear();
                      onChanged("");
                    },
                  ),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        ),
      ),
    );
  }
}

/// The list of matching settings shown while a search is typed.
class SettingsSearchResults extends StatefulWidget {
  const SettingsSearchResults(
      {required this.query,
      required this.hits,
      required this.onOpen,
      this.showHeader = true,
      super.key});

  final String query;
  final List<SettingsSearchHit> hits;
  final ValueChanged<SettingsSearchHit> onOpen;
  final bool showHeader;

  static String labelSearchResultsTitle(String query) =>
      Intl.message("Results for “$query”",
          name: "labelSearchResultsTitle",
          args: [query],
          desc: "Heading above settings search results");

  static String labelSearchResultsCount(int count) => Intl.plural(count,
      one: "1 setting",
      other: "$count settings",
      name: "labelSearchResultsCount",
      args: [count],
      desc: "How many settings match the search");

  static String get labelSearchResultsHint => Intl.message(
      "Switches work right here. Click a row to open its page with the setting highlighted.",
      name: "labelSearchResultsHint",
      desc: "Explains what the settings search results do");

  static String labelSearchNoResults(String query) =>
      Intl.message("No settings match “$query”",
          name: "labelSearchNoResults",
          args: [query],
          desc: "Shown when the settings search finds nothing");

  static String get labelSearchNoResultsHint =>
      Intl.message("Try a shorter word, like “theme” or “mic.”",
          name: "labelSearchNoResultsHint",
          desc: "Suggestion shown when the settings search finds nothing");

  @override
  State<SettingsSearchResults> createState() => _SettingsSearchResultsState();
}

class _SettingsSearchResultsState extends State<SettingsSearchResults> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            tiamat.Text.labelEmphasised(
                SettingsSearchResults.labelSearchNoResults(
                    widget.query.trim())),
            const SizedBox(height: 4),
            tiamat.Text.labelLow(
                SettingsSearchResults.labelSearchNoResultsHint),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                    SettingsSearchResults.labelSearchResultsTitle(
                        widget.query.trim()),
                    style: theme.textTheme.titleLarge),
              ),
              tiamat.Text.labelLow(
                  SettingsSearchResults.labelSearchResultsCount(
                      widget.hits.length)),
            ],
          ),
          const SizedBox(height: 4),
          tiamat.Text.labelLow(SettingsSearchResults.labelSearchResultsHint),
          const SizedBox(height: 12),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: tiamat.Text.labelLow(
                SettingsSearchResults.labelSearchResultsCount(
                    widget.hits.length)),
          ),
        for (final hit in widget.hits) _row(context, hit),
      ],
    );
  }

  Widget _row(BuildContext context, SettingsSearchHit hit) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = hit.entry;
    final toks = SettingsSearch.tokens(widget.query);
    final dim = scheme.onSurfaceVariant;
    final crumb = hit.isPage
        ? e.category
        : (e.section == null ? e.tab : "${e.tab}  ›  ${e.section}");

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onOpen(hit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(hit.icon ?? Icons.settings, size: 20, color: dim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(crumb,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: dim, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    _highlighted(
                        context,
                        e.title,
                        toks,
                        theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (!hit.isPage && e.description != null) ...[
                      const SizedBox(height: 2),
                      _highlighted(context, e.description!, toks,
                          theme.textTheme.bodySmall?.copyWith(color: dim),
                          maxLines: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (e.hasInlineToggle)
                tiamat.Switch(
                  state: e.preference!.value,
                  onChanged: (v) async {
                    await e.preference!.set(v);
                    if (mounted) setState(() {});
                  },
                )
              else
                Icon(Icons.chevron_right, color: dim),
            ],
          ),
        ),
      ),
    );
  }

  /// Marks every occurrence of every token.
  static Widget _highlighted(
      BuildContext context, String text, List<String> toks, TextStyle? style,
      {int maxLines = 3}) {
    final scheme = Theme.of(context).colorScheme;
    final lower = text.toLowerCase();
    final marks = List.filled(text.length, false);
    for (final t in toks) {
      var i = lower.indexOf(t);
      while (i >= 0 && t.isNotEmpty) {
        for (var j = i; j < i + t.length && j < marks.length; j++) {
          marks[j] = true;
        }
        i = lower.indexOf(t, i + t.length);
      }
    }

    final mark = style?.copyWith(
        color: scheme.onPrimaryContainer,
        backgroundColor: scheme.primaryContainer,
        fontWeight: FontWeight.w700);
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= text.length; i++) {
      if (i == text.length || marks[i] != marks[start]) {
        spans.add(TextSpan(
            text: text.substring(start, i),
            style: marks[start] ? mark : style));
        start = i;
      }
    }
    return Text.rich(TextSpan(children: spans),
        maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
