// Vommet (Deep Search, stage 2): the Deep Search page. Desktop: Home's
// main area (the side list stays). Phone: a pushed page.
//
//   Mockup 2B  empty field: shortcuts, recent searches, typed examples
//   Mockup 3   results: chips, Most matches strip, coverage, this device's
//              section (best match), then the homeserver's (newest first)
//   Mockup 4   one room: the in: chip + "All chats › #room" breadcrumb
//   Mockup 5   the coverage lines, in every state, + the confirm sheet
//   Mockup 6   the phone's layout (short headers, Has/Date sheet)
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_entry.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_coverage.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_entry.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_query.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_recent.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_results.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_session.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_view_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_search.dart';
import 'package:commet/ui/organisms/new_home/new_home_search_view.dart';
import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DeepSearchPage extends StatefulWidget {
  const DeepSearchPage({super.key, this.phone = false});

  static const routeName = "deep_search";

  /// The phone's layout (Mockup 6): a pushed page, short headers.
  final bool phone;

  @override
  State<DeepSearchPage> createState() => DeepSearchPageState();
}

class DeepSearchPageState extends State<DeepSearchPage> {
  DeepSearchSession get session => DeepSearchSession.instance;

  late final TextEditingController field =
      TextEditingController(text: session.query.text);
  final FocusNode focus = FocusNode();
  late final ScrollController scroll =
      ScrollController(initialScrollOffset: session.scrollOffset);

  Timer? _announce;
  int? _announced;

  @override
  void initState() {
    super.initState();
    session.addListener(_changed);
    scroll.addListener(() {
      if (scroll.hasClients) session.scrollOffset = scroll.offset;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (session.wantsFocus) {
        session.wantsFocus = false;
        focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    _announce?.cancel();
    field.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // The query was set from elsewhere (a recent search, a shortcut).
    if (field.text != session.query.text) {
      field.value = TextEditingValue(
          text: session.query.text,
          selection:
              TextSelection.collapsed(offset: session.query.text.length));
    }
    if (session.wantsFocus) {
      session.wantsFocus = false;
      focus.requestFocus();
    }
    _scheduleAnnounce();
    setState(() {});
  }

  /// Screen readers hear the result count once typing settles (review
  /// fix 16), never every keystroke.
  void _scheduleAnnounce() {
    final n = session.results.local.length + session.results.server.length;
    if (session.query.isEmpty || session.tooShort) {
      _announced = null;
      return;
    }
    if (n == _announced) return;
    _announce?.cancel();
    _announce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      _announced = n;
      SemanticsService.announce(
          DeepSearchStrings.resultsAnnounce(n), Directionality.of(context));
    });
  }

  // --------------------------------------------------------------- field

  void _onText(String text) {
    final q = session.parser.parse(text, onto: session.query);
    session.setQuery(q);
  }

  void _onSubmit() {
    session.submit();
    focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace &&
        field.text.isEmpty &&
        session.query.canBackspace) {
      session.setQuery(session.query.backspace());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (field.text.isNotEmpty || session.query.tokens.isNotEmpty) {
        session.setQuery(const DeepSearchQuery());
      } else {
        _close();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _close() {
    if (widget.phone) {
      Navigator.of(context).maybePop();
    } else {
      session.hide();
    }
  }

  void _addToken(DeepSearchToken<Space> token) {
    session.setQuery(session.query.withToken(token), immediate: true);
  }

  void _removeToken(DeepSearchToken<Space> token) {
    session.setQuery(session.query.withoutToken(token), immediate: true);
  }

  /// A pick from the in: / from: / has: picker replaces the word typed.
  void _pick(DeepSearchToken<Space> token, String key) {
    final text = field.text;
    final at = text.toLowerCase().lastIndexOf("$key:");
    final rest = at < 0 ? text : text.substring(0, at).trimRight();
    session.setQuery(
        DeepSearchQuery<Space>(
                tokens: session.query.tokens,
                text: rest.isEmpty ? "" : "$rest ")
            .withToken(token),
        immediate: true);
    focus.requestFocus();
  }

  void _open(DeepSearchResult r) {
    if (widget.phone) {
      final ok = session.roomOf(r.accountId, r.roomId) != null;
      if (ok) Navigator.of(context).maybePop();
    }
    DeepSearchEntry.openResult(context, r);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        _chips(context),
        if (session.query.scope?.roomId != null) _breadcrumb(context),
        _picker(context),
        Expanded(child: _list(context)),
      ],
    );
    if (!widget.phone)
      return Material(type: MaterialType.transparency, child: body);
    return Scaffold(body: SafeArea(child: body));
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(children: [
        IconButton(
            tooltip: DeepSearchStrings.back,
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _close),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  size: 20, color: DeepSearchEntry.color),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final t in session.query.tokens)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _tokenChip(context, t),
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          minWidth: 120, maxWidth: widget.phone ? 240 : 520),
                      child: IntrinsicWidth(
                        child: Focus(
                          onKeyEvent: _onKey,
                          child: TextField(
                            controller: field,
                            focusNode: focus,
                            onChanged: _onText,
                            onSubmitted: (_) => _onSubmit(),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: widget.phone
                                    ? DeepSearchStrings.phonePlaceholder
                                    : DeepSearchStrings.placeholder),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              if (!session.query.isEmpty)
                IconButton(
                    tooltip: DeepSearchStrings.clear,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      session.setQuery(const DeepSearchQuery());
                      focus.requestFocus();
                    }),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _tokenChip(BuildContext context, DeepSearchToken<Space> t) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: t.label,
      hint: DeepSearchStrings.removeChip(t.label),
      excludeSemantics: true,
      child: InputChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: DeepSearchEntry.color.withAlpha(40),
        side: BorderSide.none,
        label: Text(t.label,
            style: TextStyle(fontSize: 13, color: scheme.onSurface)),
        onDeleted: () => _removeToken(t),
        deleteButtonTooltipMessage: DeepSearchStrings.removeChip(t.label),
      ),
    );
  }

  // ---------------------------------------------------------------- chips

  Widget _chips(BuildContext context) {
    final q = session.query;
    final scope = q.scope;
    final dms = scope?.directMessages == true;
    final rooms = scope?.directMessages == false;
    final dated = q.beforeTs != null || q.afterTs != null;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _chip(context, DeepSearchStrings.chipFrom,
              dropdown: true,
              selected: q.fromUserIds.isNotEmpty,
              onTap: () => _startTyping("from:")),
          _chip(context, DeepSearchStrings.chipIn,
              dropdown: true,
              selected: scope != null && scope.directMessages == null,
              onTap: () => _startTyping("in:")),
          _chip(context, DeepSearchStrings.chipDms,
              selected: dms,
              onTap: () => dms
                  ? _removeToken(
                      DeepSearchToken.scope(const SearchScope.kind(true)))
                  : _addToken(
                      DeepSearchToken.scope(const SearchScope.kind(true)))),
          _chip(context, DeepSearchStrings.chipRooms,
              selected: rooms,
              onTap: () => rooms
                  ? _removeToken(
                      DeepSearchToken.scope(const SearchScope.kind(false)))
                  : _addToken(
                      DeepSearchToken.scope(const SearchScope.kind(false)))),
          _chip(context, DeepSearchStrings.chipDate,
              dropdown: true, selected: dated, onTap: () => _dateMenu(context)),
          _chip(context, DeepSearchStrings.chipHas,
              dropdown: true,
              selected: q.has.isNotEmpty,
              onTap: () => _hasMenu(context)),
          _chip(context, "@ ${DeepSearchStrings.chipMentionsMe}",
              selected: q.mentionsMe,
              onTap: () => q.mentionsMe
                  ? _removeToken(const DeepSearchToken.mentionsMe())
                  : _addToken(const DeepSearchToken.mentionsMe())),
          const SizedBox(width: 8),
          _chip(
              context,
              session.newestFirst
                  ? DeepSearchStrings.sortNewest
                  : DeepSearchStrings.sortBest,
              dropdown: true,
              selected: false,
              onTap: () => session.setNewestFirst(!session.newestFirst)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label,
      {required bool selected,
      required VoidCallback onTap,
      bool dropdown = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: selected,
        child: FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          showCheckmark: false,
          selected: selected,
          selectedColor: DeepSearchEntry.color.withAlpha(60),
          label: dropdown
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  const Icon(Icons.arrow_drop_down_rounded, size: 18),
                ])
              : Text(label, style: const TextStyle(fontSize: 13)),
          onSelected: (_) => onTap(),
        ),
      ),
    );
  }

  /// From ▾ / In ▾: types the key so the picker shows.
  void _startTyping(String key) {
    final text = field.text.trimRight();
    final next = text.isEmpty ? key : "$text $key";
    session.setQuery(session.query.withText(next));
    focus.requestFocus();
  }

  Future<void> _hasMenu(BuildContext context) async {
    final picked = await _choose<DeepSearchHas>(context, [
      (DeepSearchHas.link, DeepSearchStrings.hasLink, Icons.link_rounded),
      (DeepSearchHas.image, DeepSearchStrings.hasImage, Icons.image_outlined),
      (DeepSearchHas.video, DeepSearchStrings.hasVideo, Icons.movie_outlined),
      (
        DeepSearchHas.file,
        DeepSearchStrings.hasFile,
        Icons.attach_file_rounded
      ),
      (DeepSearchHas.voice, DeepSearchStrings.hasVoice, Icons.mic_none_rounded),
    ]);
    if (picked == null) return;
    final token = DeepSearchToken<Space>.has(picked);
    if (session.query.tokens.contains(token)) {
      _removeToken(token);
    } else {
      _addToken(token);
    }
  }

  Future<void> _dateMenu(BuildContext context) async {
    final picked = await _choose<int>(context, [
      (0, DeepSearchStrings.dateAny, Icons.all_inclusive_rounded),
      (7, DeepSearchStrings.date7, Icons.calendar_view_week_rounded),
      (30, DeepSearchStrings.date30, Icons.calendar_month_rounded),
      (365, DeepSearchStrings.dateYear, Icons.calendar_today_rounded),
      (-1, DeepSearchStrings.dateRange, Icons.date_range_rounded),
    ]);
    if (picked == null || !context.mounted) return;
    var q = DeepSearchQuery<Space>(tokens: [
      for (final t in session.query.tokens)
        if (t.kind != DeepSearchTokenKind.before &&
            t.kind != DeepSearchTokenKind.after)
          t
    ], text: session.query.text);
    final now = DateTime.now();
    if (picked > 0) {
      q = q.withToken(DeepSearchToken.afterDay(
          DateTime(now.year, now.month, now.day - picked)));
    } else if (picked < 0) {
      final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2014),
          lastDate: DateTime(now.year, now.month, now.day));
      if (range == null) return;
      q = q
          .withToken(DeepSearchToken.afterDay(
              range.start.subtract(const Duration(days: 1))))
          .withToken(DeepSearchToken.beforeDay(
              range.end.add(const Duration(days: 1))));
    }
    session.setQuery(q, immediate: true);
  }

  /// A menu on desktop, a bottom sheet on the phone (Mockup 6C).
  Future<T?> _choose<T>(
      BuildContext context, List<(T, String, IconData)> options) {
    if (widget.phone) {
      return showModalBottomSheet<T>(
          context: context,
          builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final o in options)
                    ListTile(
                        leading: Icon(o.$3),
                        title: Text(o.$2),
                        onTap: () => Navigator.of(context).pop(o.$1)),
                ]),
              ));
    }
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    return showMenu<T>(
        context: context,
        position: RelativeRect.fromLTRB(
            origin.dx + 200, origin.dy + 100, origin.dx + 400, 0),
        items: [
          for (final o in options)
            PopupMenuItem<T>(
                value: o.$1,
                child: Row(children: [
                  Icon(o.$3, size: 18),
                  const SizedBox(width: 10),
                  Text(o.$2),
                ])),
        ]);
  }

  // --------------------------------------------------------------- picker

  /// The in: / from: / has: picker for the word being typed.
  Widget _picker(BuildContext context) {
    final pending = DeepSearchParser.pendingOf(field.text);
    if (pending == null) return const SizedBox.shrink();
    final tiles = <Widget>[];
    switch (pending.key) {
      case "in":
        final index = session.nameIndex;
        if (index != null) {
          final found = index.search(pending.value);
          for (final s in found.spaces.take(3)) {
            tiles.add(ListTile(
                dense: true,
                leading: const Icon(Icons.workspaces_outline, size: 18),
                title: Text(s.name),
                onTap: () => _pick(
                    DeepSearchToken.scope(
                        NewHomeSearchView.spaceScope(index, s.space)),
                    "in")));
          }
          for (final h in found.names.take(6)) {
            final scope = session.roomScope(h.room);
            tiles.add(ListTile(
                dense: true,
                leading: tiamat.Avatar(
                    radius: 12,
                    image: h.room.avatar,
                    placeholderText: h.room.displayName,
                    placeholderColor: h.room.defaultColor),
                title: Text(scope.label),
                subtitle: _maybeText(NewHomeSearchView.pathLine(h.room, index)),
                onTap: () => _pick(DeepSearchToken.scope(scope), "in")));
          }
        }
      case "from":
        for (final p in session.fromCandidates(pending.value)) {
          tiles.add(ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline_rounded, size: 18),
              title: Text(p.name),
              subtitle: Text(p.userId),
              onTap: () =>
                  _pick(DeepSearchToken.from(p.userId, p.name), "from")));
        }
      case "has":
        for (final h in DeepSearchHas.values) {
          if (!h.name.startsWith(pending.value.toLowerCase())) continue;
          tiles.add(ListTile(
              dense: true,
              title: Text("has:${h.name}"),
              onTap: () => _pick(DeepSearchToken.has(h), "has")));
        }
    }
    if (tiles.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: Material(
        elevation: 2,
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: ListView(shrinkWrap: true, children: tiles),
      ),
    );
  }

  Widget? _maybeText(String? text) =>
      text == null || text.isEmpty ? null : Text(text, maxLines: 1);

  // ----------------------------------------------------------- breadcrumb

  /// Mockup 4: "All chats › #room".
  Widget _breadcrumb(BuildContext context) {
    final scope = session.query.scope;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(children: [
        InkWell(
          onTap: () {
            final t = session.query.tokens
                .where((t) => t.kind == DeepSearchTokenKind.scope)
                .toList();
            var q = session.query;
            for (final x in t) {
              q = q.withoutToken(x);
            }
            session.setQuery(q, immediate: true);
          },
          child: Text(_allChats, style: TextStyle(color: muted)),
        ),
        Text("  ›  ", style: TextStyle(color: muted)),
        Flexible(
            child: Text(scope?.label ?? "",
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }

  static String get _allChats => Intl.message("All chats",
      name: "deepSearchAllChats",
      desc: "Deep Search: the breadcrumb back from one chat to every chat");

  // ----------------------------------------------------------------- list

  Widget _list(BuildContext context) {
    final children = <Widget>[];
    children.addAll(_coverage(context));
    if (session.query.isEmpty) {
      children.addAll(_emptyState(context));
    } else {
      children.addAll(_results(context));
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 32),
      children: children,
    );
  }

  // ------------------------------------------------------------- coverage

  List<Widget> _coverage(BuildContext context) {
    final lines = session.coverageLines();
    if (lines.isEmpty) {
      return [
        _note(context, Icons.check_circle_outline_rounded,
            session.coverageSummary, null)
      ];
    }
    return [for (final l in lines) _coverageLine(context, l)];
  }

  Widget _coverageLine(BuildContext context, DeepSearchCoverageLine line) {
    final label = line.actionLabel;
    final action = line.action;
    return _note(
      context,
      switch (line.kind) {
        DeepSearchCoverageKind.web => Icons.public_rounded,
        DeepSearchCoverageKind.off => Icons.toggle_off_outlined,
        _ => Icons.info_outline_rounded,
      },
      line.title,
      line.detail,
      actionLabel: label,
      onAction: action == null ? null : () => _coverageAction(line),
    );
  }

  Widget _note(
      BuildContext context, IconData icon, String title, String? detail,
      {String? actionLabel, VoidCallback? onAction}) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 13, color: muted, fontWeight: FontWeight.w600)),
              if (detail != null && detail.isNotEmpty)
                Text(detail, style: TextStyle(fontSize: 12, color: muted)),
              if (actionLabel != null && onAction != null)
                InkWell(
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(actionLabel,
                        style: const TextStyle(
                            fontSize: 13,
                            color: DeepSearchEntry.color,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _coverageAction(DeepSearchCoverageLine line) async {
    switch (line.action) {
      case DeepSearchCoverageAction.indexOnMobileData:
        session.allowMobileData();
      case DeepSearchCoverageAction.openSettings:
      case DeepSearchCoverageAction.keyDetails:
        await NavigationUtils.navigateTo(context, const AppSettingsPage());
      case DeepSearchCoverageAction.lookFurtherBack:
        if (line.confirm && !await _confirmFurtherBack()) return;
        await session.lookFurtherBack();
      case null:
        return;
    }
  }

  Future<bool> _confirmFurtherBack() async {
    final sheet = deepSearchConfirmSheet(
        session.query.scope?.label ?? "", session.indexState);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(sheet.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(sheet.body),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(sheet.cancel)),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(sheet.confirm)),
                ]),
              ]),
        ),
      ),
    );
    return ok == true;
  }

  // ---------------------------------------------------------- empty state

  List<Widget> _emptyState(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final now = DateTime.now();
    final recent = session.recent.entries.take(5).toList();
    return [
      _sectionHeader(context, DeepSearchStrings.shortcutsHeader),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(
              avatar: const Icon(Icons.alternate_email_rounded, size: 16),
              label: Text(DeepSearchStrings.chipMentionsMe),
              onPressed: () => _addToken(const DeepSearchToken.mentionsMe())),
          ActionChip(
              avatar: const Icon(Icons.link_rounded, size: 16),
              label: Text(DeepSearchStrings.shortcutLinks),
              onPressed: () =>
                  _addToken(const DeepSearchToken.has(DeepSearchHas.link))),
          ActionChip(
              avatar: const Icon(Icons.attach_file_rounded, size: 16),
              label: Text(DeepSearchStrings.shortcutFilesWeek),
              onPressed: () => session.setQuery(
                  DeepSearchQuery<Space>(tokens: [
                    const DeepSearchToken.has(DeepSearchHas.file),
                    DeepSearchToken.afterDay(
                        DateTime(now.year, now.month, now.day - 7)),
                  ]),
                  immediate: true)),
          ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 16),
              label: Text(DeepSearchStrings.shortcutImages),
              onPressed: () =>
                  _addToken(const DeepSearchToken.has(DeepSearchHas.image))),
        ]),
      ),
      if (recent.isNotEmpty) ...[
        Row(children: [
          Expanded(
              child: _sectionHeader(context, DeepSearchStrings.recentHeader)),
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 12),
            child: TextButton(
                onPressed: () async {
                  await session.recent.clear();
                  if (mounted) setState(() {});
                },
                child: Text(DeepSearchStrings.clear)),
          ),
        ]),
        for (final e in recent) _recentRow(context, e),
      ],
      _sectionHeader(context, DeepSearchStrings.narrowHeader),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(
            "from:mira   in:#design   has:link   is:dm   before:${now.year}-06",
            style:
                TextStyle(fontFamily: "monospace", fontSize: 13, color: muted)),
      ),
    ];
  }

  Widget _recentRow(BuildContext context, DeepSearchRecent e) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.history_rounded, size: 20),
      title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: e.summary.isEmpty || e.summary == e.title
          ? null
          : Text(e.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
          tooltip: DeepSearchStrings.removeRecent,
          icon: const Icon(Icons.close_rounded, size: 16),
          onPressed: () async {
            await session.recent.remove(e);
            if (mounted) setState(() {});
          }),
      onTap: () => session.setQuery(session.recent.queryOf(e), immediate: true),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }

  // -------------------------------------------------------------- results

  List<Widget> _results(BuildContext context) {
    final results = session.results;
    final server = session.server;
    final out = <Widget>[];
    if (session.tooShort) return out;

    final strip = results.mostMatches();
    if (strip.isNotEmpty && session.query.scope?.roomId == null) {
      out.add(_sectionHeader(context, DeepSearchStrings.mostMatches));
      out.add(_strip(context, results, strip));
    }

    out.add(_sectionHeader(
        context,
        !session.indexAvailable
            ? DeepSearchStrings.webLocalHeader
            : widget.phone
                ? DeepSearchStrings.localHeaderShort
                : DeepSearchStrings.localHeader(session.newestFirst)));
    if (results.local.isEmpty) {
      out.add(session.searchingLocal
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))))
          : _muted(context, DeepSearchStrings.noResults));
    } else {
      for (final row
          in deepSearchCollapse(results.local, expanded: session.expanded)) {
        out.add(_row(context, row));
      }
    }

    // The homeserver's own section, below and never mixed in.
    if (!session.query.hasWords) {
      out.add(_muted(context, DeepSearchStrings.serverNeedsWords));
    } else if (!server.skipped || server.loading) {
      out.add(_sectionHeader(
          context,
          widget.phone
              ? DeepSearchStrings.serverHeaderShort
              : DeepSearchStrings.serverHeader));
      if (server.failed) {
        out.add(ListTile(
            dense: true,
            leading: const Icon(Icons.cloud_off_rounded, size: 18),
            title: Text(DeepSearchStrings.serverFailed),
            onTap: session.retryServer));
      } else if (server.loading && results.server.isEmpty) {
        out.add(const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)))));
      } else if (results.server.isEmpty) {
        out.add(_muted(context, DeepSearchStrings.noServerResults));
      } else {
        for (final row
            in deepSearchCollapse(results.server, expanded: session.expanded)) {
          out.add(_row(context, row));
        }
      }
      if (server.canLoadMore || server.loadingMore) {
        out.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Center(
            child: server.loadingMore
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    onPressed: session.loadMoreFromServer,
                    child: Text(DeepSearchStrings.loadMore)),
          ),
        ));
      }
    }

    // Footer: chats still indexing (Mockup 3).
    final totals = session.totals;
    final still = totals.rooms - totals.complete;
    if (session.indexAvailable &&
        still > 0 &&
        session.query.scope?.roomId == null) {
      out.add(_note(context, Icons.hourglass_bottom_rounded,
          DeepSearchStrings.stillIndexing(still), null,
          actionLabel: DeepSearchStrings.pickToSearchBack,
          onAction: () => _startTyping("in:")));
    }
    return out;
  }

  Widget _muted(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _strip(BuildContext context, DeepSearchResults results,
      List<DeepSearchRoomCount> strip) {
    final more = results.moreRooms();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final c in strip)
            if (session.roomOf(c.accountId, c.roomId) case final Room room)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: tiamat.Avatar(
                      radius: 10,
                      image: room.avatar,
                      placeholderText: room.displayName,
                      placeholderColor: room.defaultColor),
                  label: Text(
                      "${session.roomScope(room).label} · ${deepSearchStripCount(c.count, capped: results.capped)}"),
                  onPressed: () =>
                      _addToken(DeepSearchToken.scope(session.roomScope(room))),
                ),
              ),
          if (more > 0)
            Center(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(DeepSearchStrings.moreRooms(more)),
            )),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, DeepSearchRow row) {
    final r = row.result;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final room = session.roomOf(r.accountId, r.roomId);
    final member =
        room?.getMember(r.senderId) ?? room?.getMemberOrFallback(r.senderId);
    final sender = member?.displayName ?? r.senderId;
    final index = session.nameIndex;
    final doc = room == null ? null : index?.docOf(room);
    final dm = doc?.isDirectMessage ?? false;
    final where = room == null
        ? r.roomId
        : dm
            ? DeepSearchStrings.directMessage
            : DeepSearchStrings.inRoom([
                "#${room.displayName}",
                if (session.isOldVersion(r)) DeepSearchStrings.oldVersion,
                if (index != null)
                  if (NewHomeSearchView.pathLine(room, index) case final p?) p,
              ].join(" · "));
    final words = session.highlightWords;
    final snippet = deepSearchSnippet(
        r.body.isNotEmpty ? r.body : (r.fileName ?? ""), words);
    final tags = [
      if (r.edited) DeepSearchStrings.tagEdited,
      if (r.fileName case final f?)
        if (r.kind != SharedContentKind.text) f,
      if (r.links.isNotEmpty) DeepSearchStrings.tagLink,
      if (r.threadRoot != null) DeepSearchStrings.tagThread,
    ];
    final seen = session.marks.isSeen(r);
    final last = session.marks.isLastOpened(r);
    final client = session.clientOf(r.accountId);

    Widget tile = InkWell(
      onTap: () => _open(r),
      onLongPress: room == null ? null : () => _rowMenu(context, room),
      onSecondaryTap: room == null ? null : () => _rowMenu(context, room),
      child: Container(
        decoration: last
            ? BoxDecoration(
                border: Border(
                    left: BorderSide(color: DeepSearchEntry.color, width: 3)))
            : null,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(clipBehavior: Clip.none, children: [
            tiamat.Avatar(
                radius: 16,
                image: member?.avatar,
                placeholderText: sender,
                placeholderColor:
                    member?.defaultColor ?? room?.getColorOfUser(r.senderId)),
            if (session.multiAccount && client != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: client.self?.defaultColor ?? muted,
                      border: Border.all(
                          color: theme.colorScheme.surface, width: 1.5)),
                ),
              ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: sender,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        TextSpan(
                            text: "  $where",
                            style: TextStyle(color: muted, fontSize: 12)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text(_time(r.ts), style: TextStyle(color: muted, fontSize: 12)),
              ]),
              const SizedBox(height: 2),
              Text.rich(
                  TextSpan(
                      children: SearchHighlightScope.textSpans(snippet, words,
                          SearchHighlightScope.styleOf(context))),
                  maxLines: widget.phone ? 2 : 3,
                  overflow: TextOverflow.ellipsis),
              if (tags.isNotEmpty || seen || row.more.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(spacing: 8, children: [
                    for (final t in tags)
                      Text(t, style: TextStyle(fontSize: 11, color: muted)),
                    if (seen)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_rounded,
                            size: 12, color: DeepSearchEntry.color),
                        const SizedBox(width: 2),
                        Text(DeepSearchStrings.seen,
                            style: const TextStyle(
                                fontSize: 11, color: DeepSearchEntry.color)),
                      ]),
                    if (last)
                      Text(DeepSearchStrings.lastOpened,
                          style: const TextStyle(
                              fontSize: 11, color: DeepSearchEntry.color)),
                    if (row.more.isNotEmpty)
                      InkWell(
                        onTap: () {
                          session.expanded.add(r.eventId);
                          setState(() {});
                        },
                        child: Text(DeepSearchStrings.moreHere(row.more.length),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: DeepSearchEntry.color)),
                      ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
    return Semantics(
      button: true,
      label: "$sender, $where, ${_time(r.ts)}",
      child: tile,
    );
  }

  Future<void> _rowMenu(BuildContext context, Room room) async {
    final picked = await _choose<int>(context, [
      (1, DeepSearchStrings.searchThisChat, Icons.manage_search_rounded),
    ]);
    if (picked == 1) _addToken(DeepSearchToken.scope(session.roomScope(room)));
  }

  static String _time(int ts) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat.jm().format(t);
    }
    if (t.year == now.year) return DateFormat.MMMd().format(t);
    return DateFormat.yMMMd().format(t);
  }
}
