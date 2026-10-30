import 'dart:async';
import 'dart:math' as math;

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/notification_badge.dart';
import 'package:commet/ui/organisms/new_home/new_home_notifications.dart';
import 'package:commet/ui/organisms/new_home/notifications_feed.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issues 841 and 873: the bell's list leaves read notifications out.
final BoolPreference notificationsHideRead = BoolPreference(
  "vommet_notifications_hide_read",
  defaultValue: false,
);

/// Vommet issues 841 and 873: a bell with a red count of unread
/// notifications (the New Home Notifications card's list, so it follows each
/// room's notification level). It opens that list in a pop-over by the bell,
/// or a bottom sheet on phones. It sits on the profile card in every layout,
/// and in the New Home header on phones, where Home covers the profile card.
/// It follows the account filter of the profile card's menu.
class NotificationsBell extends StatefulWidget {
  const NotificationsBell({super.key, this.size = 32});

  final double size;

  @override
  State<NotificationsBell> createState() => _NotificationsBellState();
}

class _NotificationsBellState extends State<NotificationsBell> {
  NotificationsFeed? feed;
  StreamSubscription? filterSub;

  @override
  void initState() {
    super.initState();
    final manager = clientManager;
    if (manager == null) return;
    attach(manager, clientById(manager, preferences.filterClient.value));
    filterSub = EventBus.setFilterClient.stream.listen((client) {
      if (!mounted) return;
      setState(() => attach(manager, client));
    });
  }

  @override
  void dispose() {
    filterSub?.cancel();
    feed?.removeListener(changed);
    super.dispose();
  }

  static Client? clientById(ClientManager manager, String? id) => id == null
      ? null
      : manager.clients.where((c) => c.identifier == id).firstOrNull;

  void attach(ClientManager manager, Client? filter) {
    final next = NotificationsFeed.of(manager, filter);
    if (next == feed) return;
    feed?.removeListener(changed);
    feed = next..addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void open() {
    final feed = this.feed;
    if (feed == null) return;
    if (MediaQuery.of(context).mobile) {
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) => FractionallySizedBox(
              heightFactor: 0.85,
              child: NotificationsPanel(
                  feed: feed,
                  sheet: true,
                  onClose: () => Navigator.of(context).pop())));
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final bell = box.localToGlobal(Offset.zero) & box.size;
    showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "Close",
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, __) {
          final screen = MediaQuery.of(context).size;
          final width = math.min(400.0, screen.width - 16);
          final left = (bell.center.dx - width / 2)
              .clamp(8.0, math.max(8.0, screen.width - width - 8))
              .toDouble();
          // Upward from a bell in the lower half (the profile card),
          // downward from one in the upper half (a header).
          final up = bell.center.dy > screen.height / 2;
          final room = up ? bell.top - 16 : screen.height - bell.bottom - 16;
          return Stack(children: [
            Positioned(
                left: left,
                width: width,
                top: up ? null : bell.bottom + 6,
                bottom: up ? screen.height - bell.top + 6 : null,
                child: ConstrainedBox(
                    constraints:
                        BoxConstraints(maxHeight: math.min(520.0, room)),
                    child: NotificationsPanel(
                        feed: feed,
                        onClose: () => Navigator.of(context).pop())))
          ]);
        });
  }

  @override
  Widget build(BuildContext context) {
    final count = feed?.unreadCount ?? 0;
    return Tooltip(
        message: count == 0
            ? "Notifications"
            : "Notifications: ${notificationBadgeText(count)} unread",
        child: SizedBox(
            key: const ValueKey("NotificationsBell"),
            width: widget.size,
            height: widget.size,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: tiamat.IconButton(
                      icon: Icons.notifications_rounded,
                      size: widget.size * 0.55,
                      onPressed: open)),
              if (count > 0)
                Positioned(
                    top: 0,
                    right: 0,
                    child: IgnorePointer(
                        child: NotificationBadge(count,
                            key: const ValueKey("NotificationsBellCount")))),
            ])));
  }
}

/// The bell's list: "Notifications", "Mark all read" and a settings menu
/// with Hide read, then the Notifications card's rows (all of them,
/// scrolling). Opening one closes the list.
class NotificationsPanel extends StatefulWidget {
  const NotificationsPanel(
      {super.key,
      required this.feed,
      required this.onClose,
      this.sheet = false});

  final NotificationsFeed feed;
  final VoidCallback onClose;

  /// Shown as a phone's bottom sheet (no border or shadow of its own).
  final bool sheet;

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  bool hideRead = notificationsHideRead.value;

  @override
  void initState() {
    super.initState();
    widget.feed.addListener(changed);
  }

  @override
  void dispose() {
    widget.feed.removeListener(changed);
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void toggleHideRead() {
    setState(() => hideRead = !hideRead);
    notificationsHideRead.set(hideRead);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feed = widget.feed;
    final list = feed.arranged(hideRead: hideRead);

    Widget body;
    if (feed.loading && feed.entries.isEmpty) {
      body = const _PanelNote("Loading notifications…");
    } else if (list.isEmpty) {
      body = _PanelNote(hideRead
          ? "You're all caught up."
          : "No notifications in the last 7 days.");
    } else {
      body = ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          children: notificationRows(context, feed, list.unread, list.earlier,
              onOpened: widget.onClose));
    }

    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 8),
              child: Row(children: [
                const Expanded(
                    child: Text("Notifications",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800))),
                MarkAllReadButton(
                    clientManager: feed.clientManager,
                    filterClient: feed.filterClient),
                PopupMenuButton<void>(
                    key: const ValueKey("NotificationsPanelSettings"),
                    tooltip: "Notification list settings",
                    icon: Icon(Icons.settings_rounded,
                        size: 18, color: scheme.onSurfaceVariant),
                    itemBuilder: (context) => [
                          CheckedPopupMenuItem<void>(
                              key: const ValueKey("NotificationsPanelHideRead"),
                              checked: hideRead,
                              onTap: toggleHideRead,
                              child: const Text("Hide read"))
                        ])
              ])),
          Divider(height: 1, color: scheme.outlineVariant),
          Flexible(child: body)
        ]);

    return Material(
        key: const ValueKey("NotificationsPanel"),
        color: scheme.surfaceContainerLow,
        elevation: widget.sheet ? 0 : 8,
        shape: widget.sheet
            ? null
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: content);
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: tiamat.Text.labelLow(text));
}
