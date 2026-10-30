// Vommet (Deep Search, stage 2): the Home card. Desktop: the full card's
// body (Mockup 1): the field, the coverage line, "Last search: … ›". Phone:
// one line, "Search all chats" with the coverage dot (Mockup 6A).
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/matrix_encrypted_search_index_component.dart';
import 'package:commet/client/matrix/components/encrypted_search_index/search_index_types.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_coverage.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_entry.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_session.dart';
import 'package:commet/ui/organisms/new_home/deep_search/deep_search_strings.dart';
import 'package:flutter/material.dart';

class DeepSearchCard extends StatefulWidget {
  const DeepSearchCard(
      {super.key,
      required this.clientManager,
      this.filterClient,
      this.phone = false});

  final ClientManager clientManager;
  final Client? filterClient;

  /// Mockup 6A: the one-line bar.
  final bool phone;

  @override
  State<DeepSearchCard> createState() => _DeepSearchCardState();
}

class _DeepSearchCardState extends State<DeepSearchCard> {
  DeepSearchSession get session => DeepSearchSession.instance;

  @override
  void initState() {
    super.initState();
    session.attach(widget.clientManager, widget.filterClient);
    session.addListener(_changed);
    session.refreshCoverage();
  }

  @override
  void didUpdateWidget(DeepSearchCard old) {
    super.didUpdateWidget(old);
    session.attach(widget.clientManager, widget.filterClient);
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Green when done, amber while building or paused, gray otherwise.
  static Color dotColor(EncryptedIndexState state) => switch (state) {
        EncryptedIndexState.done => const Color(0xff43b581),
        EncryptedIndexState.running ||
        EncryptedIndexState.waitingForWifi ||
        EncryptedIndexState.pausedForBattery =>
          const Color(0xfffaa61a),
        _ => const Color(0xff8e9297),
      };

  /// "86%" of the encrypted chats fully indexed (the phone bar).
  static String percent(IndexCoverageTotals t) {
    if (t.rooms <= 0) return "";
    return "${deepSearchPercent(t.complete, t.rooms)}%";
  }

  void _open() => DeepSearchEntry.show(context);

  @override
  Widget build(BuildContext context) =>
      widget.phone ? _phone(context) : _desktop(context);

  Widget _field(BuildContext context, {required bool phone}) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: phone
          ? DeepSearchStrings.phonePlaceholder
          : DeepSearchStrings.placeholder,
      hint: phone ? null : DeepSearchStrings.shortcut,
      excludeSemantics: true,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          key: const ValueKey("DeepSearchCardField"),
          borderRadius: BorderRadius.circular(22),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  size: 20, color: DeepSearchEntry.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    phone
                        ? DeepSearchStrings.phonePlaceholder
                        : DeepSearchStrings.placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted)),
              ),
              if (phone) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor(session.indexState)),
                ),
                const SizedBox(width: 6),
                Text(percent(session.totals),
                    style: TextStyle(fontSize: 12, color: muted)),
              ] else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: muted.withAlpha(90))),
                  child: Text(DeepSearchStrings.shortcut,
                      style: TextStyle(fontSize: 11, color: muted)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _phone(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: _field(context, phone: true),
      );

  Widget _desktop(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final recent = session.recent.entries;
    final last = session.lastSearch ??
        (recent.isEmpty ? null : session.recent.queryOf(recent.first));
    final lastText = last == null
        ? null
        : (last.text.trim().isNotEmpty
            ? last.text.trim()
            : [for (final t in last.tokens) t.label].join(" · "));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(DeepSearchStrings.subtitle,
            style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 8),
        _field(context, phone: false),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: dotColor(session.indexState)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(session.coverageSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: muted)),
          ),
        ]),
        if (lastText != null && lastText.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey("DeepSearchCardLastSearch"),
              onPressed: () => DeepSearchEntry.show(context, query: last),
              child: Text("${DeepSearchStrings.lastSearch(lastText)} ›",
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
      ]),
    );
  }
}
