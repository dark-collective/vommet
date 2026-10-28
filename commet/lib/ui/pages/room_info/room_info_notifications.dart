import 'package:commet/client/client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:commet/ui/pages/room_info/room_info_settings_pages.dart';
import 'package:flutter/material.dart';

/// Vommet (New room info page): the notification quick action. Its label is
/// the current level ("All messages", "Mentions", "Muted") with
/// "Notifications" underneath; a tap opens the levels and nothing changes
/// until one is picked.

/// The level in one or two words, for the quick action.
String pushRuleShortLabel(PushRule rule) => switch (rule) {
      PushRule.notify => "All messages",
      PushRule.mentionsOnly => "Mentions",
      PushRule.dontNotify => "Muted",
    };

/// A bell for each level: plain, with an "@" badge, or crossed out.
class PushRuleIcon extends StatelessWidget {
  const PushRuleIcon(this.rule, {this.color, this.size = 24, super.key});
  final PushRule rule;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (rule) {
      case PushRule.notify:
        return Icon(Icons.notifications_outlined, size: size, color: color);
      case PushRule.dontNotify:
        return Icon(Icons.notifications_off_outlined, size: size, color: color);
      case PushRule.mentionsOnly:
        final badge = size * 0.55;
        final background = Theme.of(context).colorScheme.surfaceContainerLow;
        return SizedBox(
          key: const ValueKey("push-rule-icon-mentions"),
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.notifications_outlined, size: size, color: color),
            Positioned(
              right: -badge * 0.3,
              top: -badge * 0.2,
              child: Container(
                width: badge,
                height: badge,
                decoration:
                    BoxDecoration(color: background, shape: BoxShape.circle),
                child: Icon(Icons.alternate_email,
                    size: badge * 0.85, color: color),
              ),
            ),
          ]),
        );
    }
  }
}

/// The choice made in the levels list: [rule] null is "Use default (…)".
class NotificationPick {
  const NotificationPick(this.rule);
  final PushRule? rule;
}

/// The levels list: "Use default (…)" first where [defaultLevel] is known,
/// then All messages, Mentions & keywords and Muted. The current one is
/// selected ("Use default" when the room follows the account's defaults).
class NotificationLevelList extends StatelessWidget {
  const NotificationLevelList(
      {required this.pushRule,
      required this.onPicked,
      this.defaultLevel,
      this.followsDefault = false,
      super.key});
  final PushRule pushRule;
  final PushRule? defaultLevel;
  final bool followsDefault;
  final ValueChanged<NotificationPick> onPicked;

  @override
  Widget build(BuildContext context) {
    final selectedDefault = defaultLevel != null && followsDefault;
    Widget choice(PushRule? rule, String text, bool selected) => ListTile(
          key: ValueKey("notification-choice-${rule?.name ?? "default"}"),
          leading: Icon(selected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(text),
          selected: selected,
          onTap: () => onPicked(NotificationPick(rule)),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (defaultLevel case final level?)
        choice(null, "Use default (${pushRuleLabel(level)})", selectedDefault),
      for (final rule in PushRule.values)
        choice(rule, pushRuleLabel(rule), !selectedDefault && rule == pushRule),
    ]);
  }
}

/// Opens the levels list; null when it was closed without a pick.
Future<NotificationPick?> pickNotificationLevel(BuildContext context,
        {required PushRule pushRule,
        PushRule? defaultLevel,
        bool followsDefault = false,
        String title = "Notifications"}) =>
    AdaptiveDialog.show<NotificationPick>(context,
        title: title,
        builder: (context) => NotificationLevelList(
              pushRule: pushRule,
              defaultLevel: defaultLevel,
              followsDefault: followsDefault,
              onPicked: (pick) => Navigator.of(context).pop(pick),
            ));

/// The level the account's defaults give [room], or null where it has no
/// "Use default (…)" choice.
PushRule? roomNotificationDefaultLevel(Room room) =>
    room is MatrixRoom ? room.accountDefaultPushRule : null;

/// Applies a pick like the room's settings page: null removes the room's own
/// rules (it follows the account's defaults); a level is always written as
/// the room's own rule, so it stays when the defaults change.
Future<void> applyRoomPushRule(Room room, PushRule? rule) async {
  if (room is MatrixRoom) {
    if (rule == null) {
      await room.useAccountDefaultPushRule();
    } else {
      await room.setOwnPushRule(rule);
    }
  } else if (rule != null) {
    await room.setPushRule(rule);
  }
}

/// The notification quick action: the current level, "Notifications"
/// ("Notifications (default)" when it comes from the account's defaults)
/// underneath; tap or long-press calls [onTap].
class NotificationQuickAction extends StatelessWidget {
  const NotificationQuickAction(
      {required this.pushRule,
      this.followsDefault = false,
      this.sublabel,
      this.onTap,
      super.key});
  final PushRule pushRule;
  final bool followsDefault;

  /// Replaces "Notifications" underneath.
  final String? sublabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InfoQuickAction(
        iconBuilder: (color, size) =>
            PushRuleIcon(pushRule, color: color, size: size),
        label: pushRuleShortLabel(pushRule),
        sublabel: sublabel ??
            (followsDefault ? "Notifications (default)" : "Notifications"),
        active: pushRule == PushRule.dontNotify,
        onTap: onTap,
        onLongPress: onTap,
      );
}

/// The room's notification quick action, picking with "Use default (…)".
class RoomNotificationQuickAction extends StatelessWidget {
  const RoomNotificationQuickAction(this.room, {super.key});
  final Room room;

  Future<void> _pick(BuildContext context) async {
    final pick = await pickNotificationLevel(context,
        pushRule: room.pushRule,
        defaultLevel: roomNotificationDefaultLevel(room),
        followsDefault: roomFollowsNotificationDefault(room));
    if (pick != null) await applyRoomPushRule(room, pick.rule);
  }

  @override
  Widget build(BuildContext context) => NotificationQuickAction(
        pushRule: room.pushRule,
        followsDefault: roomFollowsNotificationDefault(room),
        onTap: room.permissions.canChangeNotificationSettings
            ? () => _pick(context)
            : null,
      );
}
