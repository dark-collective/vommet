// Vommet (Deep Search, stage 2): the results bar over a chat opened from
// Deep Search (Mockup 4b): "‹ Results", the search, "3 of 14", ↑ ↓ across
// chats (Ctrl+Shift+G / Ctrl+G), × ends it.
import 'package:commet/client/client.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_entry.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_session.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:flutter/material.dart';

class DeepSearchResultsBar extends StatelessWidget {
  const DeepSearchResultsBar({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final session = DeepSearchSession.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final hit = session.openHit;
        final index = session.openIndex;
        if (hit == null ||
            index == null ||
            hit.roomId != room.identifier ||
            hit.accountId != room.client.identifier) {
          return const SizedBox.shrink();
        }
        final total = session.openList.length;
        final q = session.query;
        final label = q.text.trim().isNotEmpty
            ? q.text.trim()
            : [for (final t in q.tokens) t.label].join(" · ");
        final scheme = Theme.of(context).colorScheme;
        final muted = scheme.onSurfaceVariant;
        return Material(
          color: DeepSearchEntry.color.withAlpha(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(children: [
              TextButton.icon(
                key: const ValueKey("DeepSearchBarResults"),
                onPressed: () => DeepSearchEntry.backToResults(context),
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                label: Text(DeepSearchStrings.results),
              ),
              Expanded(
                child: Text("“$label”",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Semantics(
                liveRegion: true,
                child: Text(DeepSearchStrings.position(index + 1, total),
                    style: TextStyle(fontSize: 12, color: muted)),
              ),
              IconButton(
                tooltip: DeepSearchStrings.previous,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                onPressed:
                    index > 0 ? () => DeepSearchEntry.step(context, -1) : null,
              ),
              IconButton(
                tooltip: DeepSearchStrings.next,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                onPressed: index < total - 1
                    ? () => DeepSearchEntry.step(context, 1)
                    : null,
              ),
              IconButton(
                tooltip: DeepSearchStrings.endSearch,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: session.endRun,
              ),
            ]),
          ),
        );
      },
    );
  }
}
