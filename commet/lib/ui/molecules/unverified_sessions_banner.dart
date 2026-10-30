// Vommet issue 947: the strip above the message box naming the sessions that
// can't read what you send here (their owner hasn't verified them), the sheet
// that sends to them too, and the note under your messages they can't read.

import 'dart:async';

import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/client/matrix/unverified_sessions.dart';
import 'package:commet/client/room.dart';
import 'package:commet/ui/atoms/encryption_marker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

/// A session that can't read what you send, as the strip, the sheet and the
/// note name it.
class UnverifiedSessionInfo {
  const UnverifiedSessionInfo(
      {required this.userId,
      required this.owner,
      required this.id,
      this.name,
      this.device});

  factory UnverifiedSessionInfo.of(matrix.Room room, matrix.DeviceKeys d) {
    final name = d.deviceDisplayName?.trim();
    return UnverifiedSessionInfo(
        userId: d.userId,
        owner:
            room.unsafeGetUserFromMemoryOrFallback(d.userId).calcDisplayname(),
        id: d.deviceId ?? "",
        name: name == null || name.isEmpty ? null : name,
        device: d);
  }

  final String userId;

  /// The owner's display name.
  final String owner;
  final String id;

  /// The name the owner gave it, or their app's default; null when the
  /// server doesn't share it.
  final String? name;
  final matrix.DeviceKeys? device;

  String get label => name ?? id;

  String get quotedWithId => name == null ? "(ID $id)" : "\"$name\" (ID $id)";
}

/// When and from which session someone last wrote in the room.
typedef LastWrote = ({String? deviceId, DateTime time});

class UnverifiedSessionsStrings {
  static String bannerOne(String person, String session) => Intl.message(
      "$person's session \"$session\" can't read what you send here.",
      args: [person, session],
      name: "unverifiedSessionsBannerOne",
      desc:
          "Strip above the message box: one session of the other person won't get your message keys; session is its name or id");

  static String bannerOneOwner(String person) => Intl.message(
      "$person hasn't verified it, so Vommet won't send it your message keys.",
      args: [person],
      name: "unverifiedSessionsBannerOneOwner",
      desc:
          "Strip above the message box: why, after unverifiedSessionsBannerOne");

  static String bannerMany(int count) => Intl.plural(count,
      one: "$count session can't read what you send here.",
      other: "$count sessions can't read what you send here.",
      args: [count],
      name: "unverifiedSessionsBannerMany",
      desc:
          "Strip above the message box: several sessions won't get your message keys");

  static String get bannerManyOwners => Intl.message(
      "Their owners haven't verified them.",
      name: "unverifiedSessionsBannerManyOwners",
      desc:
          "Strip above the message box: why, after unverifiedSessionsBannerMany");

  static String sendToOne(String person) => Intl.message(
      "Send to $person's session too…",
      args: [person],
      name: "unverifiedSessionsSendToOne",
      desc:
          "Strip above the message box: button that opens the confirmation to send to the other person's unverified session");

  static String get sendToOneShort => Intl.message("Send to it too…",
      name: "unverifiedSessionsSendToOneShort",
      desc:
          "Phone strip above the message box: short button, right under the line that names the session");

  static String get chooseSessions => Intl.message(
      "Choose sessions to send to…",
      name: "unverifiedSessionsChooseSessions",
      desc:
          "Strip above the message box: button that opens the checklist of unverified sessions to send to");

  static String get why => Intl.message("Why?",
      name: "unverifiedSessionsWhy",
      desc: "Strip above the message box: button that explains the warning");

  static String copyNote(String person) => Intl.message(
      "Copy a note for $person",
      args: [person],
      name: "unverifiedSessionsCopyNote",
      desc:
          "Button that copies a message asking the other person to verify their session");

  static String get noteCopied => Intl.message("Note copied",
      name: "unverifiedSessionsNoteCopied",
      desc: "Shown after the note for the other person was copied");

  static String get notNow => Intl.message("Not now",
      name: "unverifiedSessionsNotNow",
      desc:
          "Strip above the message box: hides the warning in this room until another unverified session shows up");

  static String whyOwner(String person) => Intl.message(
      "$person has turned on verification for their account. Each new phone or browser they sign in on has to be confirmed from one of their other sessions, or with their recovery key, before people's apps trust it.",
      args: [person],
      name: "unverifiedSessionsWhyOwner",
      desc: "Explanation shown by the Why? button, first paragraph");

  static String whyThisOne(String person, String session) => Intl.message(
      "\"$session\" hasn't been confirmed yet. It's probably a new device $person hasn't finished setting up. It could also be someone else who got into $person's account, so Vommet doesn't send it your messages unless you say so.",
      args: [person, session],
      name: "unverifiedSessionsWhyThisOne",
      desc: "Explanation shown by the Why? button, second paragraph");

  static String whyFix(String person) => Intl.message(
      "The safest fix is for $person to verify it. You can copy a note to send them, then come back. The warning goes away by itself once they do.",
      args: [person],
      name: "unverifiedSessionsWhyFix",
      desc: "Explanation shown by the Why? button, last paragraph");

  static String get whyManyOwners => Intl.message(
      "These people have turned on verification for their accounts. Each new phone or browser they sign in on has to be confirmed from one of their other sessions, or with their recovery key, before people's apps trust it.",
      name: "unverifiedSessionsWhyManyOwners",
      desc:
          "Explanation shown by the Why? button when several people's sessions are listed, first paragraph");

  static String get whyManyThese => Intl.message(
      "These sessions haven't been confirmed yet. They're probably new devices, but one could also be someone else who got into the account, so Vommet doesn't send them your messages unless you say so. The safest fix is for each person to verify theirs.",
      name: "unverifiedSessionsWhyManyThese",
      desc:
          "Explanation shown by the Why? button when several people's sessions are listed, second paragraph");

  static String andMore(int count) => Intl.message("and $count more",
      args: [count],
      name: "unverifiedSessionsAndMore",
      desc: "Strip above the message box: after the first 5 sessions listed");

  static String sheetTitleOne(String person, String session) =>
      Intl.message("Send your messages to $person's \"$session\" too?",
          args: [person, session],
          name: "unverifiedSessionsSheetTitleOne",
          desc: "Title of the confirmation to send to one unverified session");

  static String get sheetTitleMany =>
      Intl.message("Send your messages to these sessions too?",
          name: "unverifiedSessionsSheetTitleMany",
          desc: "Title of the checklist of unverified sessions to send to");

  static String notVerifiedBy(String person) =>
      Intl.message("not verified by $person",
          args: [person],
          name: "unverifiedSessionsNotVerifiedBy",
          desc: "Under a session's name and id in the confirmation");

  static String wroteFromThis(String person, String when) => Intl.message(
      "$person wrote from this session · $when",
      args: [person, when],
      name: "unverifiedSessionsWroteFromThis",
      desc:
          "Chip on the session the other person's latest message here came from; when is a relative time like '2 min ago'");

  static String lastFromThis(String person) => Intl.message(
      "$person's last message here came from this session, so they're probably using it right now.",
      args: [person],
      name: "unverifiedSessionsLastFromThis",
      desc: "Confirmation: the other person wrote from the listed session");

  static String notWrittenYet(String person) => Intl.message(
      "$person hasn't written here yet, so Vommet can't tell which session they use.",
      args: [person],
      name: "unverifiedSessionsNotWrittenYet",
      desc: "Confirmation: the other person hasn't written in this room yet");

  static String trustWarning(String person) => Intl.message(
      "Only do this if you're sure it's really $person. Anyone using this session will be able to read what you send to $person, in every room you share.",
      args: [person],
      name: "unverifiedSessionsTrustWarning",
      desc: "Confirmation: warning before sending to an unverified session");

  static String get trustWarningMany => Intl.message(
      "Only do this if you're sure these are really theirs. Anyone using a session you tick will be able to read what you send to its owner, in every room you share.",
      name: "unverifiedSessionsTrustWarningMany",
      desc: "Checklist: warning before sending to unverified sessions");

  static String get pastStayLocked => Intl.message(
      "Messages you already sent stay locked on this session. You can send any of them again from the note under the message.",
      name: "unverifiedSessionsPastStayLocked",
      desc:
          "Confirmation: earlier messages can't be unlocked for the session, only sent again");

  static String get pastStayLockedMany => Intl.message(
      "Messages you already sent stay locked on these sessions. You can send any of them again from the note under the message.",
      name: "unverifiedSessionsPastStayLockedMany",
      desc:
          "Checklist: earlier messages can't be unlocked for the sessions, only sent again");

  static String sendToSession(String session) =>
      Intl.message("Send to $session too",
          args: [session],
          name: "unverifiedSessionsSendToSession",
          desc: "Confirmation button; session is the session's name or id");

  static String sendToCount(int count) => Intl.plural(count,
      one: "Send to $count session too",
      other: "Send to $count sessions too",
      args: [count],
      name: "unverifiedSessionsSendToCount",
      desc: "Checklist confirmation button");

  static String noteText(String person, String sessions) => Intl.message(
      "Hi $person, my app says your session $sessions isn't verified, so my messages won't open on it. Could you verify it, from one of your other sessions or with your recovery key?",
      args: [person, sessions],
      name: "unverifiedSessionsNoteText",
      desc:
          "Note copied for the other person; sessions is like '\"Pixel 8\" (ID LKQWZTRNAB)'");

  static String cantReadOne(String person, String session) =>
      Intl.message("$person's \"$session\" can't read this",
          args: [person, session],
          name: "unverifiedSessionsCantReadOne",
          desc: "Note under your own message that one session can't read");

  static String cantReadMany(int count) => Intl.plural(count,
      one: "$count session can't read this",
      other: "$count sessions can't read this",
      args: [count],
      name: "unverifiedSessionsCantReadMany",
      desc: "Note under your own message that several sessions can't read");

  static String cantReadShort(int count) => Intl.plural(count,
      one: "$count session can't read",
      other: "$count sessions can't read",
      args: [count],
      name: "unverifiedSessionsCantReadShort",
      desc: "Short note in a chat bubble's time row");

  static String get sendAgain => Intl.message("Send again",
      name: "unverifiedSessionsSendAgain",
      desc:
          "Under a message some sessions can't read: posts a new copy they can read");

  static String sendToThemToo(int count) => Intl.plural(count,
      one: "Send to this session too…",
      other: "Send to these sessions too…",
      args: [count],
      name: "unverifiedSessionsSendToThemToo",
      desc:
          "Under a message some sessions can't read: opens the confirmation for the sessions still left out");

  static String get unnamedSession => Intl.message("Unnamed session",
      name: "unverifiedSessionsUnnamed",
      desc: "A session whose name the other person's server doesn't share");

  static String get justNow => Intl.message("just now",
      name: "unverifiedSessionsJustNow",
      desc: "Relative time: under a minute ago");

  static String minutesAgo(int minutes) => Intl.message("$minutes min ago",
      args: [minutes],
      name: "unverifiedSessionsMinutesAgo",
      desc: "Relative time in minutes");
}

List<UnverifiedSessionInfo> _sessions(
        MatrixRoom room, List<matrix.DeviceKeys> devices) =>
    [for (final d in devices) UnverifiedSessionInfo.of(room.matrixRoom, d)];

/// The note to send [sessions]' first owner, naming their sessions there.
String unverifiedSessionsNote(List<UnverifiedSessionInfo> sessions) {
  final userId = sessions.first.userId;
  return UnverifiedSessionsStrings.noteText(
      sessions.first.owner,
      sessions
          .where((s) => s.userId == userId)
          .map((s) => s.quotedWithId)
          .join(", "));
}

Future<void> _copyNote(
    BuildContext context, List<UnverifiedSessionInfo> sessions) async {
  await Clipboard.setData(
      ClipboardData(text: unverifiedSessionsNote(sessions)));
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(UnverifiedSessionsStrings.noteCopied)));
  }
}

/// Above the message box: shows the room's [UnverifiedSessions].
class UnverifiedSessionsBanner extends StatefulWidget {
  const UnverifiedSessionsBanner(this.room, {this.recentEvents, super.key});

  final Room room;

  /// The room's loaded events, newest first, to find the session someone
  /// last wrote from.
  final Iterable<matrix.Event> Function()? recentEvents;

  @override
  State<UnverifiedSessionsBanner> createState() =>
      _UnverifiedSessionsBannerState();
}

class _UnverifiedSessionsBannerState extends State<UnverifiedSessionsBanner> {
  UnverifiedSessions? state;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    if (room is! MatrixRoom) return;
    final s = state = UnverifiedSessions.of(room);
    s.revision.addListener(_changed);
    _subs.add(UnverifiedSessions.onPolicyChanged.listen((_) => _changed()));
    // Members joining or leaving, or keys arriving, change who's left out.
    _subs.add(
        EncryptionMarker.keysUpdated(room).listen((_) => s.refreshIfStale()));
    unawaited(s.refresh());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    state?.revision.removeListener(_changed);
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final s = state;
    if (room is! MatrixRoom || s == null) return const SizedBox.shrink();
    final devices = s.shown;
    if (devices.isEmpty) return const SizedBox.shrink();
    return UnverifiedSessionsStrip(
      sessions: _sessions(room, devices),
      onSend: () => UnverifiedSessionsSheet.show(context, room,
          devices: devices, recentEvents: widget.recentEvents),
      onNotNow: () => s.dismiss(devices),
    );
  }
}

/// The strip itself.
class UnverifiedSessionsStrip extends StatefulWidget {
  const UnverifiedSessionsStrip(
      {required this.sessions,
      required this.onSend,
      required this.onNotNow,
      this.showWhy = false,
      super.key});

  final List<UnverifiedSessionInfo> sessions;
  final VoidCallback onSend;
  final VoidCallback onNotNow;

  /// Starts with the explanation open.
  final bool showWhy;

  @override
  State<UnverifiedSessionsStrip> createState() =>
      _UnverifiedSessionsStripState();
}

class _UnverifiedSessionsStripState extends State<UnverifiedSessionsStrip> {
  late bool showWhy = widget.showWhy;

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final one = sessions.length == 1 ? sessions.single : null;
    final people = sessions.map((e) => e.userId).toSet();
    final onePerson = people.length == 1 ? sessions.first.owner : null;
    final phone = MediaQuery.sizeOf(context).width < 600;

    final theme = Theme.of(context);
    final color = EncryptionMarker.warningColor(context);
    final shown = sessions.take(5).toList();

    return Padding(
      key: const ValueKey("unverified-sessions-banner"),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: one != null
                            ? UnverifiedSessionsStrings.bannerOne(
                                one.owner, one.label)
                            : UnverifiedSessionsStrings.bannerMany(
                                sessions.length),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: " "),
                    TextSpan(
                        text: one != null
                            ? UnverifiedSessionsStrings.bannerOneOwner(
                                one.owner)
                            : UnverifiedSessionsStrings.bannerManyOwners),
                  ]),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface, height: 1.3),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 0, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: [
                  for (final session in shown)
                    _SessionRow(session, showOwner: people.length > 1),
                  if (sessions.length > shown.length)
                    Text(
                        UnverifiedSessionsStrings.andMore(
                            sessions.length - shown.length),
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (showWhy)
              Padding(
                key: const ValueKey("unverified-sessions-why"),
                padding: const EdgeInsets.fromLTRB(28, 10, 4, 0),
                child: _Why(sessions: sessions),
              ),
            SizedBox(
              width: double.infinity,
              child: Wrap(alignment: WrapAlignment.end, children: [
                TextButton(
                  key: const ValueKey("unverified-sessions-send"),
                  onPressed: widget.onSend,
                  child: Text(
                      one == null
                          ? UnverifiedSessionsStrings.chooseSessions
                          : phone
                              ? UnverifiedSessionsStrings.sendToOneShort
                              : UnverifiedSessionsStrings.sendToOne(one.owner),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                TextButton(
                  key: const ValueKey("unverified-sessions-why-button"),
                  onPressed: () => setState(() => showWhy = !showWhy),
                  child: Text(UnverifiedSessionsStrings.why),
                ),
                if (onePerson != null && !phone)
                  TextButton(
                    onPressed: () => _copyNote(context, sessions),
                    child: Text(UnverifiedSessionsStrings.copyNote(onePerson),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                TextButton(
                  key: const ValueKey("unverified-sessions-not-now"),
                  onPressed: widget.onNotNow,
                  child: Text(UnverifiedSessionsStrings.notNow),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Why extends StatelessWidget {
  const _Why({required this.sessions});

  final List<UnverifiedSessionInfo> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final one = sessions.length == 1 ? sessions.single : null;
    final paragraphs = one != null
        ? [
            UnverifiedSessionsStrings.whyOwner(one.owner),
            UnverifiedSessionsStrings.whyThisOne(one.owner, one.label),
            UnverifiedSessionsStrings.whyFix(one.owner),
          ]
        : [
            UnverifiedSessionsStrings.whyManyOwners,
            UnverifiedSessionsStrings.whyManyThese,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (final p in paragraphs)
          Text(p,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface, height: 1.35)),
      ],
    );
  }
}

/// One session: its owner (when several people are listed), name and id.
class _SessionRow extends StatelessWidget {
  const _SessionRow(this.session, {required this.showOwner});

  final UnverifiedSessionInfo session;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6)),
      child: Wrap(
        spacing: 10,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showOwner)
            Text(session.owner,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          Text(session.name ?? UnverifiedSessionsStrings.unnamedSession,
              style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: session.name == null ? null : FontWeight.w700,
                  color: session.name == null ? muted : null)),
          SelectableText("ID ${session.id}",
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: muted, fontFamily: "monospace")),
        ],
      ),
    );
  }
}

/// The confirmation before sending to [sessions].
class UnverifiedSessionsSheet extends StatefulWidget {
  const UnverifiedSessionsSheet(
      {required this.sessions,
      required this.lastWrote,
      required this.onConfirm,
      super.key});

  final List<UnverifiedSessionInfo> sessions;

  /// Per owner: when and from which session they last wrote here, or null
  /// if they haven't.
  final Map<String, LastWrote?> lastWrote;
  final Future<void> Function(List<UnverifiedSessionInfo> chosen) onConfirm;

  static String title(List<UnverifiedSessionInfo> sessions) =>
      sessions.length == 1
          ? UnverifiedSessionsStrings.sheetTitleOne(
              sessions.single.owner, sessions.single.label)
          : UnverifiedSessionsStrings.sheetTitleMany;

  static Future<void> show(BuildContext context, MatrixRoom room,
      {required List<matrix.DeviceKeys> devices,
      Iterable<matrix.Event> Function()? recentEvents}) async {
    final state = UnverifiedSessions.of(room);
    final sessions = _sessions(room, devices);
    final events = recentEvents?.call() ?? const <matrix.Event>[];
    final lastWrote = <String, LastWrote?>{
      for (final userId in sessions.map((s) => s.userId).toSet())
        userId: switch (state.lastSession(userId, events)) {
          null => null,
          final last => (deviceId: last.device?.deviceId, time: last.time),
        },
    };
    await AdaptiveDialog.show(context,
        title: title(sessions),
        builder: (_) => UnverifiedSessionsSheet(
            sessions: sessions,
            lastWrote: lastWrote,
            onConfirm: (chosen) => state.allow([
                  for (final s in chosen)
                    if (s.device != null) s.device!,
                ])));
  }

  @override
  State<UnverifiedSessionsSheet> createState() =>
      _UnverifiedSessionsSheetState();
}

class _UnverifiedSessionsSheetState extends State<UnverifiedSessionsSheet> {
  late final Set<UnverifiedSessionInfo> ticked = widget.sessions.toSet();
  bool saving = false;

  List<UnverifiedSessionInfo> get sessions => widget.sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final single = sessions.length == 1;
    final owners = {for (final s in sessions) s.userId: s.owner};

    final notes = <String>[
      for (final MapEntry(key: userId, value: owner) in owners.entries)
        if (widget.lastWrote[userId] == null)
          UnverifiedSessionsStrings.notWrittenYet(owner)
        else if (sessions.any((s) =>
            s.userId == userId && widget.lastWrote[userId]?.deviceId == s.id))
          UnverifiedSessionsStrings.lastFromThis(owner),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            for (final session in sessions)
              _sheetRow(context, session, single: single),
            for (final note in notes)
              Text(note,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            Text(
                single
                    ? UnverifiedSessionsStrings.trustWarning(
                        sessions.single.owner)
                    : UnverifiedSessionsStrings.trustWarningMany,
                style: theme.textTheme.bodyMedium),
            Text(
                single
                    ? UnverifiedSessionsStrings.pastStayLocked
                    : UnverifiedSessionsStrings.pastStayLockedMany,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (owners.length == 1)
                    TextButton(
                      onPressed: () => _copyNote(context, sessions),
                      child: Text(
                          UnverifiedSessionsStrings.copyNote(
                              sessions.first.owner),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(CommonStrings.promptCancel),
                  ),
                  FilledButton(
                    key: const ValueKey("unverified-sessions-confirm"),
                    onPressed: saving || ticked.isEmpty
                        ? null
                        : () async {
                            setState(() => saving = true);
                            await widget.onConfirm([
                              for (final s in sessions)
                                if (ticked.contains(s)) s,
                            ]);
                            if (context.mounted) {
                              await Navigator.of(context).maybePop();
                            }
                          },
                    child: Text(
                        single
                            ? UnverifiedSessionsStrings.sendToSession(
                                sessions.single.label)
                            : UnverifiedSessionsStrings.sendToCount(
                                ticked.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow(BuildContext context, UnverifiedSessionInfo session,
      {required bool single}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final last = widget.lastWrote[session.userId];
    final wroteHere = last != null && last.deviceId == session.id;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(session.name ?? UnverifiedSessionsStrings.unnamedSession,
                  style: theme.textTheme.titleSmall),
              if (wroteHere)
                Container(
                  key: const ValueKey("unverified-sessions-wrote-here"),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  decoration: BoxDecoration(
                      color: EncryptionMarker.verifiedColor(context)
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text(
                      UnverifiedSessionsStrings.wroteFromThis(
                          session.owner, unverifiedSessionsAgo(last.time)),
                      style: theme.textTheme.labelSmall),
                ),
            ]),
        SelectableText(
            "${session.owner} · ID ${session.id} · ${UnverifiedSessionsStrings.notVerifiedBy(session.owner)}",
            style: theme.textTheme.labelMedium?.copyWith(color: muted)),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        if (single)
          Icon(Icons.smartphone,
              size: 20, color: EncryptionMarker.warningColor(context))
        else
          Checkbox(
              value: ticked.contains(session),
              onChanged: (v) => setState(() =>
                  v == true ? ticked.add(session) : ticked.remove(session))),
        const SizedBox(width: 10),
        Expanded(child: details),
      ]),
    );
  }
}

/// "just now", "5 min ago", or the date and time.
String unverifiedSessionsAgo(DateTime time, {DateTime? now}) {
  final minutes = (now ?? DateTime.now()).difference(time).inMinutes;
  if (minutes < 1) return UnverifiedSessionsStrings.justNow;
  if (minutes < 60) return UnverifiedSessionsStrings.minutesAgo(minutes);
  return DateFormat.MMMd().add_jm().format(time);
}

/// Under your own message: which sessions can't read it, with what to do.
/// [compact] is the chat bubble's time row.
class UnverifiedSessionsNote extends StatelessWidget {
  const UnverifiedSessionsNote(
      {required this.room,
      required this.event,
      this.compact = false,
      this.recentEvents,
      super.key});

  final MatrixRoom room;
  final matrix.Event event;
  final bool compact;
  final Iterable<matrix.Event> Function()? recentEvents;

  @override
  Widget build(BuildContext context) {
    final state = UnverifiedSessions.of(room);
    return ValueListenableBuilder<int>(
        valueListenable: state.revision,
        builder: (context, _, __) {
          final devices = state.cantRead(event);
          if (devices.isEmpty) return const SizedBox.shrink();
          return UnverifiedSessionsNoteView(
              sessions: _sessions(room, devices),
              compact: compact,
              onTapUp: (at) => _menu(context, at, state, devices));
        });
  }

  Future<void> _menu(BuildContext context, Offset at, UnverifiedSessions state,
      List<matrix.DeviceKeys> devices) async {
    final stillLeftOut =
        devices.where((d) => state.withheld.value.contains(d)).toList();
    final canResend = stillLeftOut.length < devices.length && _resendable;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
            at & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          if (stillLeftOut.isNotEmpty)
            PopupMenuItem(
                value: "allow",
                child: Text(UnverifiedSessionsStrings.sendToThemToo(
                    stillLeftOut.length))),
          if (canResend)
            PopupMenuItem(
                value: "again",
                child: Text(UnverifiedSessionsStrings.sendAgain)),
        ]);
    if (!context.mounted) return;
    switch (choice) {
      case "allow":
        await UnverifiedSessionsSheet.show(context, room,
            devices: stillLeftOut, recentEvents: recentEvents);
      case "again":
        await _sendAgain();
    }
  }

  /// Text messages can be sent again as they are.
  bool get _resendable =>
      event.type == matrix.EventTypes.Message &&
      const {
        matrix.MessageTypes.Text,
        matrix.MessageTypes.Emote,
        matrix.MessageTypes.Notice,
      }.contains(event.messageType);

  /// Posts a new copy of [event] (its text and formatting, and what it
  /// replied to), which every session we send to now can read.
  Future<void> _sendAgain() =>
      room.matrixRoom.sendEvent(unverifiedSessionsResendContent(event.content));
}

/// The content of a new copy of a message: its text and formatting, its
/// thread, and what it replied to, but not an edit or other relation.
Map<String, Object?> unverifiedSessionsResendContent(
    Map<String, Object?> content) {
  final relates = content.tryGetMap<String, Object?>("m.relates_to");
  final reply = relates?.tryGetMap<String, Object?>("m.in_reply_to");
  final newContent = content.tryGetMap<String, Object?>("m.new_content");
  final source = newContent ?? content;
  return {
    "msgtype": source["msgtype"],
    "body": source["body"],
    if (source["format"] != null) "format": source["format"],
    if (source["formatted_body"] != null)
      "formatted_body": source["formatted_body"],
    if (relates?["rel_type"] == matrix.RelationshipTypes.thread)
      "m.relates_to": relates
    else if (reply != null)
      "m.relates_to": {"m.in_reply_to": reply},
  };
}

/// The note itself.
class UnverifiedSessionsNoteView extends StatelessWidget {
  const UnverifiedSessionsNoteView(
      {required this.sessions, this.compact = false, this.onTapUp, super.key});

  final List<UnverifiedSessionInfo> sessions;
  final bool compact;
  final void Function(Offset globalPosition)? onTapUp;

  @override
  Widget build(BuildContext context) {
    final color = EncryptionMarker.warningColor(context);
    final theme = Theme.of(context);
    final text = compact
        ? UnverifiedSessionsStrings.cantReadShort(sessions.length)
        : sessions.length == 1
            ? UnverifiedSessionsStrings.cantReadOne(
                sessions.single.owner, sessions.single.label)
            : UnverifiedSessionsStrings.cantReadMany(sessions.length);
    final note = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.lock_outline, size: compact ? 12 : 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (compact
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(color: color)),
      ),
    ]);
    return Padding(
      padding: compact
          ? const EdgeInsets.only(right: 6)
          : const EdgeInsets.only(top: 2),
      child: Tooltip(
        message: sessions
            .map((s) => "${s.owner}: ${s.label} (ID ${s.id})")
            .join("\n"),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const ValueKey("unverified-sessions-note"),
            onTapUp: onTapUp == null
                ? null
                : (details) => onTapUp!(details.globalPosition),
            child: note,
          ),
        ),
      ),
    );
  }
}
