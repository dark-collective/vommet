// Vommet: what a message hidden by one of your message filters leaves in
// the timeline: "🚫 Hidden by your filter "X" · Show". In the flat layout
// it sits where the message text would; with chat bubbles it is a centered
// pill like a date divider, with no bubble or avatar.
import 'package:commet/config/message_density.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String labelHiddenByFilter(String term) => Intl.message(
    "Hidden by your filter “$term”",
    args: [term],
    name: "labelHiddenByFilter",
    desc:
        "Shown in the timeline in place of a message one of your message filters matched; term is the filter's word, phrase or regex");

String get labelShowFilteredMessage => Intl.message("Show",
    name: "labelShowFilteredMessage",
    desc: "Button that shows a message your message filter hid");

class FilteredMessageNote extends StatelessWidget {
  const FilteredMessageNote(
      {required this.term,
      required this.bubbles,
      required this.onShow,
      super.key});

  final String term;

  /// The chat-bubble layout is on.
  final bool bubbles;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: colors.onSurfaceVariant);

    final note = Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(bubbles ? 16 : 8),
        border: bubbles ? null : Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(labelHiddenByFilter(term),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          TextButton(
            onPressed: onShow,
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(labelShowFilteredMessage),
          ),
        ],
      ),
    );

    final density = messageDensity;
    if (bubbles) {
      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: density.verticalPadding + 2),
        child: Center(child: note),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16 + density.avatarSize + 12,
          density.verticalPadding + 2, 8, density.verticalPadding + 2),
      child: Align(alignment: Alignment.centerLeft, child: note),
    );
  }
}
