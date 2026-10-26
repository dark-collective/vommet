import 'package:commet/client/client.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/atoms/search_highlight.dart';
import 'package:commet/ui/molecules/jump_to_date.dart';
import 'package:commet/ui/organisms/in_chat_search/in_chat_search.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 611: the room header becomes the search field while the
/// room's in-chat search is open.
class InChatSearchField extends StatelessWidget {
  const InChatSearchField(this.search, {super.key});
  final InChatSearch search;

  static Widget orHeader(Room room, Widget Function(BuildContext) header) {
    final search = InChatSearch.of(room);
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) =>
          search.isOpen ? InChatSearchField(search) : header(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: tiamat.Tooltip(
              text: InChatSearch.inChatSearchClose,
              child: tiamat.IconButton(
                icon: Icons.chevron_left,
                size: 24,
                onPressed: search.close,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): search.close,
              },
              child: SizedBox(
                height: 34,
                child: TextField(
                  controller: search.text,
                  focusNode: search.focus,
                  autofocus: true,
                  onChanged: search.onTextChanged,
                  onSubmitted: (_) {
                    if (search.results.isNotEmpty) search.select(0);
                  },
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: CommonStrings.promptSearch,
                    filled: true,
                    fillColor: colors.surfaceContainerHighest,
                    isDense: true,
                    contentPadding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 36, minHeight: 34),
                    suffixIcon: search.text.text.isEmpty
                        ? null
                        : tiamat.Tooltip(
                            text: InChatSearch.inChatSearchClear,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: search.clearText,
                            ),
                          ),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(17),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 34,
            height: 34,
            child: tiamat.Tooltip(
              text: JumpToDate.promptJumpToDate,
              child: tiamat.IconButton(
                icon: Icons.event,
                size: 20,
                onPressed: () => JumpToDate.open(context, search.room),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vommet issue 611: puts the search's words and current match above the
/// room's timeline, rebuilding the messages only when those change (not on
/// every page of results).
class InChatSearchHighlight extends StatefulWidget {
  const InChatSearchHighlight(
      {required this.search, required this.child, super.key});
  final InChatSearch search;
  final Widget child;

  @override
  State<InChatSearchHighlight> createState() => _InChatSearchHighlightState();
}

class _InChatSearchHighlightState extends State<InChatSearchHighlight> {
  List<String> words = const [];
  String? currentEventId;

  @override
  void initState() {
    super.initState();
    _read();
    widget.search.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant InChatSearchHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search) {
      oldWidget.search.removeListener(_onChanged);
      widget.search.addListener(_onChanged);
      _read();
    }
  }

  @override
  void dispose() {
    widget.search.removeListener(_onChanged);
    super.dispose();
  }

  void _read() {
    words = widget.search.highlightWords;
    currentEventId = widget.search.currentEventId;
  }

  void _onChanged() {
    final newWords = widget.search.highlightWords;
    final newCurrent = widget.search.currentEventId;
    if (newCurrent == currentEventId && newWords.join(" ") == words.join(" ")) {
      return;
    }
    setState(() {
      words = newWords;
      currentEventId = newCurrent;
    });
  }

  @override
  Widget build(BuildContext context) => SearchHighlightScope(
      words: words, currentEventId: currentEventId, child: widget.child);
}

/// Vommet issue 611: the list of matches, in place of the chat while
/// searching.
class InChatSearchOverlay extends StatelessWidget {
  const InChatSearchOverlay(this.search, {super.key});
  final InChatSearch search;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: search,
      builder: (context, _) => search.isOpen && search.showingList
          ? InChatSearchResults(search)
          : const SizedBox.shrink(),
    );
  }
}

class InChatSearchResults extends StatefulWidget {
  const InChatSearchResults(this.search, {super.key});
  final InChatSearch search;

  @override
  State<InChatSearchResults> createState() => _InChatSearchResultsState();
}

class _InChatSearchResultsState extends State<InChatSearchResults> {
  final ScrollController scroll = ScrollController();

  InChatSearch get search => widget.search;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  bool get nearEnd => !scroll.hasClients || scroll.position.extentAfter < 400;

  @override
  Widget build(BuildContext context) {
    // More matches while the list is short or scrolled to its end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) search.wantMore(nearEnd: nearEnd);
    });

    final colors = Theme.of(context).colorScheme;
    final words = SearchHighlightScope.wordsOfQuery(search.query);
    final empty = search.results.isEmpty;

    return Material(
      color: colors.surface,
      child: Column(
        children: [
          InChatSearchStatus(search),
          Expanded(
            child: empty
                ? Center(
                    child: search.searching || search.query.isEmpty
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : tiamat.Text.labelLow(
                            InChatSearch.inChatSearchNoResults))
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.extentAfter < 400) {
                        search.wantMore(nearEnd: true);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: scroll,
                      itemCount: search.results.length + 1,
                      itemBuilder: (context, i) => i < search.results.length
                          ? InChatSearchResultRow(
                              room: search.room,
                              event: search.results[i],
                              words: words,
                              onTap: () => search.select(i),
                              key: ValueKey(search.results[i].eventId),
                            )
                          : _footer(context),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Center(
        child: search.searching
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : tiamat.Text.labelLow(InChatSearch.inChatSearchTapToJump),
      ),
    );
  }
}

/// "Searching older messages: March 2025 · 17 found".
class InChatSearchStatus extends StatelessWidget {
  const InChatSearchStatus(this.search, {super.key});
  final InChatSearch search;

  static String month(DateTime date) => DateFormat.yMMMM().format(date);

  String? get leading {
    final backTo = search.searchedBackTo;
    if (backTo != null && !search.searchedEverything) {
      return search.searching
          ? InChatSearch.inChatSearchSearchingOlder(month(backTo))
          : InChatSearch.inChatSearchSearchedBackTo(month(backTo));
    }
    if (search.searching) return InChatSearch.inChatSearchSearching;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lead = leading;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: colors.onSurfaceVariant);
    return Container(
      color: colors.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          if (search.searching)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: colors.onSurfaceVariant)),
            ),
          Expanded(
            child: Text(lead ?? "",
                style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (search.query.isNotEmpty)
            Text(InChatSearch.inChatSearchFound(search.results.length),
                style: style),
        ],
      ),
    );
  }
}

class InChatSearchResultRow extends StatelessWidget {
  const InChatSearchResultRow(
      {required this.room,
      required this.event,
      required this.words,
      required this.onTap,
      super.key});
  final Room room;
  final TimelineEvent event;
  final List<String> words;
  final VoidCallback onTap;

  static String dateOf(DateTime ts, {DateTime? now}) {
    now ??= DateTime.now();
    final local = ts.toLocal();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return DateFormat.jm().format(local);
    }
    return local.year == now.year
        ? DateFormat.MMMd().format(local)
        : DateFormat.yMMMd().format(local);
  }

  /// The part of [body] to show: when the first match is far in, start
  /// shortly before it.
  static String snippetOf(String body, List<String> words) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    final ranges = SearchHighlightScope.matches(text, words);
    if (ranges.isEmpty || ranges.first.$1 <= 40) return text;
    var start = ranges.first.$1 - 30;
    final space = text.indexOf(' ', start);
    if (space >= 0 && space < ranges.first.$1) start = space + 1;
    return "…${text.substring(start)}";
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final isMe = room.client.self?.identifier == event.senderId;
    final member = room.getMemberOrFallback(event.senderId);
    // Vommet issue 475: the results follow redacted mode.
    final redaction = RedactionScope.of(context);
    final name = isMe
        ? InChatSearch.inChatSearchYou
        : redaction.name(member.displayName, event.senderId);
    final body = snippetOf(event.plainTextBody, words);

    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Avatar(
              radius: 14,
              image: member.avatar,
              placeholderText: member.displayName,
              placeholderColor: member.defaultColor,
              redactionKey: event.senderId,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.titleSmall),
                      ),
                      const SizedBox(width: 8),
                      Text(dateOf(event.originServerTs),
                          style: theme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (redaction.redactsText)
                    RedactedText(body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.bodyMedium)
                  else
                    Text.rich(
                      TextSpan(
                          children: SearchHighlightScope.textSpans(body, words,
                              SearchHighlightScope.styleOf(context))),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vommet issue 611: "3 of 17", up and down through the matches and the
/// List button, in place of the composer after a jump.
class InChatSearchBar extends StatelessWidget {
  const InChatSearchBar(this.search, {super.key});
  final InChatSearch search;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final index = search.current;
    return Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    index == null
                        ? InChatSearch.inChatSearchFound(search.results.length)
                        : InChatSearch.inChatSearchPosition(
                            index + 1, search.results.length),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (search.searching)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                IconButton(
                  tooltip: InChatSearch.inChatSearchOlder,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: search.hasOlder ? search.older : null,
                ),
                IconButton(
                  tooltip: InChatSearch.inChatSearchNewer,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: search.hasNewer ? search.newer : null,
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: search.showList,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: Text(InChatSearch.inChatSearchList),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 611: the composer, or the search bar in its place while the
/// chat shows search results. The composer stays mounted (offstage) so a
/// half-written message survives the search.
class InChatSearchFooter extends StatelessWidget {
  const InChatSearchFooter(
      {required this.search, required this.composer, super.key});
  final InChatSearch search;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: search,
      child: composer,
      builder: (context, composer) {
        final hide = search.isOpen && (search.showingList || search.showingBar);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (search.showingBar) InChatSearchBar(search),
            Offstage(offstage: hide, child: composer),
          ],
        );
      },
    );
  }
}
