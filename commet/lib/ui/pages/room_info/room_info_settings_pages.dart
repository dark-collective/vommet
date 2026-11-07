import 'package:commet/client/client.dart';
import 'package:commet/client/components/history_reload/history_reload_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:commet/ui/pages/room_info/room_info_notifications.dart';
import 'package:commet/ui/pages/room_info/room_info_rows.dart';
import 'package:commet/ui/pages/settings/categories/account/security/matrix/shared_history_setting.dart';
import 'package:commet/ui/pages/settings/categories/room/advanced/room_advanced_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:commet/ui/pages/settings/categories/room/general/nickname_settings.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_chat_privacy.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_settings_view.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_url_previews.dart';
import 'package:commet/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:flutter/material.dart';

/// Vommet (New room info page): the pages behind the rows. Each re-uses an
/// existing settings view under a title bar naming the row and whose
/// setting it is.

const _gap = SizedBox(height: 10);

String forYouSubtitle(Room room) => "${room.displayName} · just for you";
String forEveryoneSubtitle(Room room) =>
    "${room.displayName} · applies to everyone";

/// The room's notification level in words, for the row and quick action.
String pushRuleLabel(PushRule rule) => switch (rule) {
      PushRule.notify => "All messages",
      PushRule.mentionsOnly => "Mentions & keywords",
      PushRule.dontNotify => "Muted",
    };

bool roomFollowsNotificationDefault(Room room) =>
    room is MatrixRoom && room.followsAccountDefault;

class RoomNotificationsPage extends StatefulWidget {
  const RoomNotificationsPage(this.room, {super.key});
  final Room room;

  @override
  State<RoomNotificationsPage> createState() => _RoomNotificationsPageState();
}

class _RoomNotificationsPageState extends State<RoomNotificationsPage> {
  late PushRule pushRule = widget.room.pushRule;
  late bool followsDefault = roomFollowsNotificationDefault(widget.room);
  late PushRule? defaultLevel = roomNotificationDefaultLevel(widget.room);

  /// Like the room's settings page: [rule] null is "Use default (…)"; a
  /// level is written as the room's own rule.
  Future<void> setPushRule(PushRule? rule) async {
    final room = widget.room;
    if (rule == null && room is! MatrixRoom) return;
    setState(() {
      followsDefault = rule == null;
      if (rule != null) pushRule = rule;
    });
    await applyRoomPushRule(room, rule);
    if (mounted) {
      setState(() {
        pushRule = room.pushRule;
        followsDefault = roomFollowsNotificationDefault(room);
        defaultLevel = roomNotificationDefaultLevel(room);
      });
    }
  }

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Notifications",
        subtitle: forYouSubtitle(widget.room),
        child: RoomGeneralSettingsView(
          pushRule: pushRule,
          onPushRuleChanged:
              widget.room.permissions.canChangeNotificationSettings
                  ? setPushRule
                  : null,
          defaultLevel: defaultLevel,
          followsDefault: followsDefault,
        ),
      );
}

class RoomReceiptsTypingPage extends StatelessWidget {
  const RoomReceiptsTypingPage(this.room, {super.key});
  final Room room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Read receipts & typing",
        subtitle: forYouSubtitle(room),
        child: RoomGeneralChatPrivacySettings(room),
      );
}

/// Link previews: what you see here, and (with the right role) the room's
/// default for everyone. The same view as the old General page.
class RoomLinkPreviewsPage extends StatelessWidget {
  const RoomLinkPreviewsPage(this.room, {super.key});
  final MatrixRoom room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Link previews",
        subtitle: room.displayName,
        child: MatrixRoomUrlPreviewSettings(room.matrixRoom),
      );
}

class RoomNicknamePage extends StatelessWidget {
  const RoomNicknamePage(this.room, {this.space, super.key});
  final Room room;
  final Space? space;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "My nickname here",
        subtitle: forYouSubtitle(room),
        child: NicknameSettings(
            client: room.client as MatrixClient,
            roomId: room.identifier,
            space: space),
      );
}

class RoomEncryptionForYouPage extends StatelessWidget {
  const RoomEncryptionForYouPage(this.room, {super.key});
  final MatrixRoom room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Encryption for you",
        subtitle: forYouSubtitle(room),
        child: SharedHistoryRoomToggle(room),
      );
}

/// Who can join, guest access, who can read history, encryption. The share
/// history opt-out (yours) lives under "Encryption for you" instead.
class RoomPrivacyAccessPage extends StatelessWidget {
  const RoomPrivacyAccessPage(this.room, {this.contextSpace, super.key});
  final Room room;
  final Space? contextSpace;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Privacy & access",
        subtitle: forEveryoneSubtitle(room),
        child: RoomSecuritySettingsPage(room: room, contextSpace: contextSpace),
      );
}

class RoomAddressesPage extends StatelessWidget {
  const RoomAddressesPage(this.room, {super.key});
  final MatrixRoom room;

  @override
  Widget build(BuildContext context) => InfoSubPage(
        title: "Addresses & directory",
        subtitle: forEveryoneSubtitle(room),
        child: MatrixRoomAddressSettings(room.matrixRoom),
      );
}

/// Room ID, version, replace room, developer tools, reload history.
class RoomAdvancedPage extends StatelessWidget {
  const RoomAdvancedPage(this.room, {this.contextSpace, super.key});
  final Room room;
  final Space? contextSpace;

  @override
  Widget build(BuildContext context) {
    final reload = room.getComponent<HistoryReloadComponent>();
    return InfoSubPage(
      title: "Advanced",
      subtitle: room.displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (room.replacement != null)
            RoomAdvancedSettingsPage(room, contextSpace: contextSpace),
          if (reload != null) ...[
            _gap,
            InfoGroup([
              InfoRow(
                icon: Icons.history,
                title: "Reload history",
                subtitle: "Forget this room's stored messages on this device "
                    "and load them again from the server",
                chevron: false,
                onTap: reload.isReloading
                    ? null
                    : () {
                        reload.reloadHistory();
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                                content: Text("Reloading the history…")));
                      },
              ),
            ]),
          ],
          if (preferences.developerMode.value) ...[
            _gap,
            InfoGroup([
              InfoRow(
                icon: Icons.code,
                title: "Developer tools",
                subtitle: "The room's raw state",
                onTap: () => InfoSubPage.open(
                    context,
                    InfoSubPage(
                        title: "Developer tools",
                        subtitle: room.displayName,
                        child: RoomDeveloperSettingsView(room))),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
