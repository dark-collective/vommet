// Vommet issue 947 (redesign): in group rooms the warning moves off the
// message box. A message sent from a session that can't read what you send
// (its owner hasn't verified it) gets a small mark by its time; tapping it
// explains and offers to let that session read your messages. Room settings ›
// Security lists every such session, the ones in use first.

import 'dart:async';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/molecules/unverified_sessions_banner.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class UnverifiedSenderStrings {
  static String get markTooltip => Intl.message(
      "Sent from an unverified session. It can't read what you send here.",
      name: "unverifiedSenderMarkTooltip",
      desc:
          "Tooltip of the mark by the time of a message sent from a session its owner hasn't verified");

  static String get cardTitle => Intl.message("Sent from an unverified session",
      name: "unverifiedSenderCardTitle",
      desc:
          "Title of the card opened from the mark on a message sent from an unverified session");

  static String cardBody(String person, String session) => Intl.message(
      "$person sent this from \"$session\", which $person hasn't verified. That session can't read what you send here.",
      args: [person, session],
      name: "unverifiedSenderCardBody",
      desc:
          "Card opened from the mark on a message sent from an unverified session");

  static String get letRead => Intl.message("Let this session read my messages",
      name: "unverifiedSenderLetRead",
      desc:
          "Button: send your messages to an unverified session too (opens a confirmation)");

  static String get sectionTitle => Intl.message(
      "Sessions that can't read your messages",
      name: "unverifiedSessionsSectionTitle",
      desc:
          "Room settings › Security: header of the list of unverified sessions");

  static String get sectionHint => Intl.message(
      "Their owners haven't verified them, so Vommet doesn't send them your messages. Sessions in use come first; the rest are often old devices nobody signed out of.",
      name: "unverifiedSessionsSectionHint",
      desc:
          "Room settings › Security: under the header of the list of unverified sessions");

  static String get sectionNone =>
      Intl.message("Every session in this room can read your messages.",
          name: "unverifiedSessionsSectionNone",
          desc: "Room settings › Security: no unverified sessions in the room");

  static String showQuiet(int count) => Intl.plural(count,
      one: "Show 1 session not in use",
      other: "Show $count sessions not in use",
      args: [count],
      name: "unverifiedSessionsShowQuiet",
      desc:
          "Room settings › Security: expands the unverified sessions that haven't written or asked for a key");

  static String get allow => Intl.message("Allow…",
      name: "unverifiedSessionsAllow",
      desc:
          "Room settings › Security: button on an unverified session; opens the confirmation to send it your messages");

  static String get allowTooltip =>
      Intl.message("Let this session read my messages",
          name: "unverifiedSessionsAllowTooltip",
          desc: "Tooltip of the Allow… button on an unverified session");
}

/// The mark by the time of someone's [event], when it was sent from a
/// session that gets none of our keys.
class UnverifiedSenderMark extends StatelessWidget {
  const UnverifiedSenderMark(
      {required this.room, required this.event, super.key});

  final MatrixRoom room;
  final matrix.Event event;

  @override
  Widget build(BuildContext context) {
    final state = UnverifiedSessions.of(room)..ensureLooked();
    return ValueListenableBuilder(
      valueListenable: state.revision,
      builder: (context, _, __) {
        final device = state.withheldSender(event);
        if (device == null) return const SizedBox.shrink();
        return UnverifiedSenderMarkView(
          session: UnverifiedSessionInfo.of(room.matrixRoom, device),
          onAllow: () =>
              UnverifiedSessionsSheet.show(context, room, devices: [device]),
        );
      },
    );
  }
}

/// The mark by a message's time. Hover shows a short reason; tapping opens
/// [UnverifiedSenderCard] (a bottom sheet on phones, a popup elsewhere).
class UnverifiedSenderMarkView extends StatelessWidget {
  const UnverifiedSenderMarkView(
      {required this.session, required this.onAllow, super.key});

  final UnverifiedSessionInfo session;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final color = EncryptionMarker.warningColor(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: UnverifiedSenderStrings.markTooltip,
        child: InkWell(
          key: const ValueKey("message-unverified-sender-mark"),
          borderRadius: BorderRadius.circular(8),
          onTap: () => open(context),
          child: Icon(Icons.warning_amber_rounded, size: 14, color: color),
        ),
      ),
    );
  }

  void open(BuildContext context) {
    final card = Builder(
        builder: (sheetContext) => UnverifiedSenderCard(
            session: session,
            onAllow: () {
              Navigator.of(sheetContext).pop();
              onAllow();
            }));
    if (MediaQuery.sizeOf(context).width < 600) {
      showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (_) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: card));
    } else {
      showDialog(
          context: context,
          builder: (_) => Dialog(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Padding(
                      padding: const EdgeInsets.all(16), child: card))));
    }
  }
}

class UnverifiedSenderCard extends StatefulWidget {
  const UnverifiedSenderCard(
      {required this.session,
      required this.onAllow,
      this.showWhy = false,
      super.key});

  final UnverifiedSessionInfo session;
  final VoidCallback onAllow;
  final bool showWhy;

  @override
  State<UnverifiedSenderCard> createState() => _UnverifiedSenderCardState();
}

class _UnverifiedSenderCardState extends State<UnverifiedSenderCard> {
  late bool showWhy = widget.showWhy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = EncryptionMarker.warningColor(context);
    final s = widget.session;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(UnverifiedSenderStrings.cardTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        Text(UnverifiedSenderStrings.cardBody(s.owner, s.label),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.3)),
        const SizedBox(height: 8),
        UnverifiedSessionRow(s, showOwner: false),
        if (showWhy)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: UnverifiedSessionsWhy(sessions: [s])),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                    onPressed: () => setState(() => showWhy = !showWhy),
                    child: Text(UnverifiedSessionsStrings.why)),
                TextButton(
                    onPressed: () => copyUnverifiedSessionsNote(context, [s]),
                    child: Text(UnverifiedSessionsStrings.copyNote(s.owner))),
                FilledButton.tonal(
                    key: const ValueKey("unverified-sender-let-read"),
                    onPressed: widget.onAllow,
                    child: Text(UnverifiedSenderStrings.letRead)),
              ]),
        ),
      ],
    );
  }
}

/// Room settings › Security: every session in the room that can't read your
/// messages. [active] ones (wrote here, or asked us for a key) come first;
/// the rest fold away.
class UnverifiedSessionsSection extends StatefulWidget {
  const UnverifiedSessionsSection(
      {required this.active,
      required this.quiet,
      required this.onAllow,
      this.expanded = false,
      super.key});

  final List<UnverifiedSessionInfo> active;
  final List<UnverifiedSessionInfo> quiet;
  final void Function(UnverifiedSessionInfo) onAllow;
  final bool expanded;

  @override
  State<UnverifiedSessionsSection> createState() =>
      _UnverifiedSessionsSectionState();
}

class _UnverifiedSessionsSectionState extends State<UnverifiedSessionsSection> {
  late bool expanded = widget.expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final none = widget.active.isEmpty && widget.quiet.isEmpty;

    Widget row(UnverifiedSessionInfo s) => Row(children: [
          Expanded(child: UnverifiedSessionRow(s, showOwner: true)),
          const SizedBox(width: 8),
          Tooltip(
            message: UnverifiedSenderStrings.allowTooltip,
            child: TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: () => widget.onAllow(s),
                child: Text(UnverifiedSenderStrings.allow)),
          ),
        ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(UnverifiedSenderStrings.sectionTitle,
            style: theme.textTheme.titleMedium),
        Text(
            none
                ? UnverifiedSenderStrings.sectionNone
                : UnverifiedSenderStrings.sectionHint,
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        for (final s in widget.active) row(s),
        if (widget.quiet.isNotEmpty && !expanded)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: () => setState(() => expanded = true),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                    UnverifiedSenderStrings.showQuiet(widget.quiet.length))),
          ),
        if (expanded && widget.quiet.isNotEmpty) ...[
          if (widget.active.isNotEmpty) const Divider(height: 12),
          for (final s in widget.quiet) row(s),
        ],
      ],
    );
  }
}

/// Room settings › Security: the room's [UnverifiedSessions], live.
class RoomUnverifiedSessions extends StatefulWidget {
  const RoomUnverifiedSessions(this.room, {super.key});

  final MatrixRoom room;

  @override
  State<RoomUnverifiedSessions> createState() => _RoomUnverifiedSessionsState();
}

class _RoomUnverifiedSessionsState extends State<RoomUnverifiedSessions> {
  late final UnverifiedSessions state = UnverifiedSessions.of(widget.room);

  @override
  void initState() {
    super.initState();
    state.revision.addListener(_changed);
    unawaited(state.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    state.revision.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    if (!room.matrixRoom.encrypted ||
        UnverifiedSessions.policy == UnverifiedSessionsPolicy.always) {
      return const SizedBox.shrink();
    }
    final client = room.matrixRoom.client;
    final active = <UnverifiedSessionInfo>[];
    final quiet = <UnverifiedSessionInfo>[];
    final byInfo = <UnverifiedSessionInfo, matrix.DeviceKeys>{};
    for (final d in state.withheld.value) {
      final info = UnverifiedSessionInfo.of(room.matrixRoom, d);
      byInfo[info] = d;
      (UnverifiedSessions.activityOf(client, d) != null ? active : quiet)
          .add(info);
    }
    return UnverifiedSessionsSection(
      key: const ValueKey("room-unverified-sessions"),
      active: active,
      quiet: quiet,
      onAllow: (info) => UnverifiedSessionsSheet.show(context, room,
          devices: [if (byInfo[info] != null) byInfo[info]!]),
    );
  }
}
