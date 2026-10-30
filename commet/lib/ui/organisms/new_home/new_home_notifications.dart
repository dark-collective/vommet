import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/ui/atoms/redaction_scope.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_cards.dart';
import 'package:commet/ui/organisms/new_home/new_home_layout.dart';
import 'package:commet/ui/organisms/new_home/new_home_notifications_model.dart';
import 'package:commet/ui/organisms/new_home/new_home_overview.dart';
import 'package:commet/ui/organisms/new_home/new_home_space_index.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 814: the New Home Notifications card (it was "Mentions &
/// highlights"). Every notification of the last week, following the user's
/// push rules: unread first, the read ones dimmed under "Earlier" (left out
/// with the card's Hide read). A DM, or a room set to every message, gets
/// one entry; anywhere else each notification has its own. Tapping one
/// opens the chat at that message.
/// The list is the shared [NotificationsFeed].
class NewHomeNotificationsCardBody extends StatefulWidget {
  const NewHomeNotificationsCardBody(
      {super.key,
      required this.clientManager,
      required this.filterClient,
      required this.card});

  final ClientManager clientManager;
  final Client? filterClient;
  final HomeCard card;

  @override
  State<NewHomeNotificationsCardBody> createState() =>
      _NotificationsCardState();
}

class _NotificationsCardState extends State<NewHomeNotificationsCardBody> {
  late NotificationsFeed feed;
  bool showAll = false;

  @override
  void initState() {
    super.initState();
    feed = NotificationsFeed.of(widget.clientManager, widget.filterClient)
      ..addListener(changed);
  }

  @override
  void didUpdateWidget(covariant NewHomeNotificationsCardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterClient == widget.filterClient &&
        oldWidget.clientManager == widget.clientManager) {
      return;
    }
    feed.removeListener(changed);
    feed = NotificationsFeed.of(widget.clientManager, widget.filterClient)
      ..addListener(changed);
  }

  @override
  void dispose() {
    feed.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (feed.loading && feed.entries.isEmpty) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: tiamat.Text.labelLow("Loading notifications…"));
    }
    final list = feed.arranged(hideRead: widget.card.unreadOnly);
    if (list.isEmpty) {
      return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: tiamat.Text.labelLow(widget.card.unreadOnly
              ? "You're all caught up."
              : "No notifications in the last 7 days."));
    }
    const limit = NewHomeOverview.collapsedCount;
    var left = showAll ? list.length : limit;
    final unread = list.unread.take(left).toList();
    left -= unread.length;
    final earlier = list.earlier.take(left < 0 ? 0 : left).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...notificationRows(context, feed, unread, earlier),
      if (list.length > limit)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                key: const ValueKey("NewHomeNotificationsShowMore"),
                onPressed: () => setState(() => showAll = !showAll),
                child: Text(showAll
                    ? "Show less"
                    : "Show ${list.length - limit} more")))
    ]);
  }
}

/// The rows of a notifications list: [unread], then [earlier] under
/// "EARLIER". [onOpened] runs after a row opens its chat.
List<Widget> notificationRows(BuildContext context, NotificationsFeed feed,
    List<NotificationEntry> unread, List<NotificationEntry> earlier,
    {VoidCallback? onOpened}) {
  final index = NewHomeSpaceIndex.of(feed.clientManager, feed.filterClient);
  final now = DateTime.now();
  final mixed =
      feed.filterClient == null && feed.clientManager.clients.length > 1;

  Widget row(NotificationEntry e) {
    final room = feed.roomOf(e);
    if (room == null) return const SizedBox.shrink();
    return NotificationRow(e,
        key: ValueKey("NewHomeNotification-${e.roomKey}/${e.eventId}"),
        room: room,
        spaceName:
            isDirectRoom(room) ? null : index.pathOf(room)?.nearest.displayName,
        direct: isDirectRoom(room),
        now: now,
        account: mixed ? room.client.self?.identifier : null,
        onOpened: onOpened);
  }

  return [
    for (final e in unread) row(e),
    if (earlier.isNotEmpty) ...[
      Padding(
          key: const ValueKey("NewHomeNotificationsEarlier"),
          padding: EdgeInsets.fromLTRB(8, unread.isEmpty ? 2 : 10, 8, 4),
          child: Text("EARLIER",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant))),
      for (final e in earlier) row(e)
    ],
  ];
}

/// One notification: the sender's picture; the sender, the room (and its
/// space) and the time; then up to two lines of the message, your name and
/// keywords marked. Read ones are dimmed.
class NotificationRow extends StatelessWidget {
  const NotificationRow(this.entry,
      {super.key,
      required this.room,
      required this.now,
      this.spaceName,
      this.direct = false,
      this.account,
      this.onOpened});

  final NotificationEntry entry;
  final Room room;
  final String? spaceName;
  final bool direct;
  final DateTime now;

  /// The account it came to, shown while several accounts are mixed.
  final String? account;

  /// Runs after the chat opens (the bell's pop-over closes).
  final VoidCallback? onOpened;

  /// Your name, user id and keywords, for marking the message.
  List<String> terms() {
    final client = room.client;
    final self = client.self;
    final terms = <String>[
      if (self != null) ...[self.displayName, self.identifier],
      if (self != null && self.identifier.startsWith("@"))
        self.identifier.substring(1).split(":").first
    ];
    if (client is MatrixClient) {
      terms.addAll(keywordTerms([
        for (final rule in client.matrixClient.globalPushRules?.content ??
            const <matrix.PushRule>[])
          if (rule.enabled && !rule.ruleId.startsWith(".")) rule.pattern
      ]));
    }
    return terms;
  }

  void open() {
    onOpened?.call();
    EventBus.doOpenRoom(room.identifier,
        clientId: room.client.identifier,
        eventId: entry.eventId,
        threadId: entry.threadId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final redaction = RedactionScope.of(context);
    final member = room.getMemberOrFallback(entry.senderId);
    final sender = redaction.name(member.displayName, entry.senderId);
    final roomName = direct ? null : redaction.roomDisplayName(room);
    final place = [
      if (roomName != null) roomName,
      if (spaceName != null) spaceName!,
      if (account != null) account!
    ].join(" · ");
    final time = formatChatTime(entry.time, now,
        use24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
    final body = redaction.text(entry.preview);
    final baseStyle = TextStyle(fontSize: 13, color: scheme.onSurfaceVariant);
    final markStyle =
        baseStyle.copyWith(color: scheme.primary, fontWeight: FontWeight.w700);
    final runs = entry.highlight && body == entry.preview
        ? highlightRuns(body, terms())
        : [(body, false)];

    final content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          tiamat.Avatar(
              radius: 16,
              image: member.avatar,
              placeholderText: member.displayName,
              placeholderColor: member.defaultColor,
              redactionKey: entry.senderId),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface))),
                  if (place.isNotEmpty)
                    Flexible(
                        child: Text(" · $place",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant))),
                  const SizedBox(width: 6),
                  Text(time,
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  if (!entry.read && entry.count > 1)
                    Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text("${entry.count}",
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onPrimary))))
                ]),
                const SizedBox(height: 2),
                Text.rich(
                    TextSpan(children: [
                      for (final (text, marked) in runs)
                        TextSpan(text: text, style: marked ? markStyle : null)
                    ]),
                    style: redaction.redactedTextStyle(
                        baseStyle, scheme.onSurfaceVariant.withAlpha(120)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis)
              ]))
        ]));

    return Opacity(
        opacity: entry.read ? 0.6 : 1,
        child: Material(
            color: entry.highlight && !entry.read
                ? scheme.primary.withAlpha(18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                mouseCursor: WidgetStateMouseCursor.clickable,
                onTap: open,
                child: content)));
  }
}

/// The rooms "Mark all read" in the card's header reads: every room on the
/// card's account(s) with unread notifications.
List<Room> roomsWithUnreadNotifications(
        ClientManager manager, Client? filterClient) =>
    [
      for (final client in manager.clients)
        if (filterClient == null || client == filterClient)
          for (final room in client.rooms)
            if (!hiddenFromNewHome(room) &&
                room.pushRule != PushRule.dontNotify &&
                (room.notificationCount > 0 ||
                    room.highlightedNotificationCount > 0))
              room
    ];

Future<void> markAllNotificationsRead(
    ClientManager manager, Client? filterClient) async {
  for (final room in roomsWithUnreadNotifications(manager, filterClient)) {
    try {
      await room.markAsRead();
    } catch (e, s) {
      matrix.Logs().w("[New Home] Mark all read failed for a room", e, s);
    }
  }
}

/// The card's settings: Hide read.
Future<void> editNotificationsSettings(
    BuildContext context, HomeCard card) async {
  final next = await showDialog<HomeCard>(
      context: context,
      builder: (context) => NotificationsSettingsDialog(card: card));
  if (next == null) return;
  final store = HomeLayoutStore.instance;
  await store.save(store.layout.value.replace(next));
}

class NotificationsSettingsDialog extends StatefulWidget {
  const NotificationsSettingsDialog({super.key, required this.card});
  final HomeCard card;

  @override
  State<NotificationsSettingsDialog> createState() =>
      _NotificationsSettingsDialogState();
}

class _NotificationsSettingsDialogState
    extends State<NotificationsSettingsDialog> {
  late HomeCard card = widget.card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
        backgroundColor: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(spacing: 10, children: [
                        const CardIcon(HomeLayout.mentions, size: 28),
                        const Expanded(
                            child: Text("Notifications settings",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800))),
                        IconButton(
                            tooltip: "Close",
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(context).pop())
                      ]),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                          key: const ValueKey("NewHomeNotificationsHideRead"),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: card.unreadOnly,
                          onChanged: (v) => setState(
                              () => card = card.copyWith(unreadOnly: v)),
                          title: const Text("Hide read"),
                          subtitle: const Text(
                              "Show only unread notifications, without \"Earlier\".")),
                      Text(
                          "The card follows your notification settings and shows the "
                          "last 7 days.",
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          spacing: 8,
                          children: [
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text("Cancel")),
                            FilledButton(
                                key: const ValueKey("NewHomeNotificationsSave"),
                                onPressed: () =>
                                    Navigator.of(context).pop(card),
                                child: const Text("Save"))
                          ])
                    ]))));
  }
}

/// "Mark all read" in the Notifications card's header, shown while any room
/// on the card has unread notifications.
class MarkAllReadButton extends StatefulWidget {
  const MarkAllReadButton(
      {super.key, required this.clientManager, required this.filterClient});

  final ClientManager clientManager;
  final Client? filterClient;

  @override
  State<MarkAllReadButton> createState() => _MarkAllReadButtonState();
}

class _MarkAllReadButtonState extends State<MarkAllReadButton> {
  StreamSubscription? syncSub;
  bool any = false;
  bool busy = false;

  bool check() =>
      roomsWithUnreadNotifications(widget.clientManager, widget.filterClient)
          .isNotEmpty;

  @override
  void initState() {
    super.initState();
    any = check();
    syncSub = widget.clientManager.onSync.stream.listen((_) {
      final next = check();
      if (next != any && mounted) setState(() => any = next);
    });
  }

  @override
  void dispose() {
    syncSub?.cancel();
    super.dispose();
  }

  Future<void> markAll() async {
    setState(() => busy = true);
    await markAllNotificationsRead(widget.clientManager, widget.filterClient);
    if (!mounted) return;
    setState(() {
      busy = false;
      any = check();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!any) return const SizedBox.shrink();
    return SizedBox(
        height: 18,
        child: TextButton(
            key: const ValueKey("NewHomeNotificationsMarkAllRead"),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 18),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            onPressed: busy ? null : markAll,
            child: const Text("Mark all read")));
  }
}
