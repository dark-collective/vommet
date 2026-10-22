import 'package:commet/client/client.dart';
import 'package:commet/client/components/calendar_room/calendar_room_component.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/matrix_room.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/room/appearance/room_appearance_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/bridges/room_bridges_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/calendar/room_calendar_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/general/room_general_settings_page.dart';
import 'package:commet/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:commet/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:commet/ui/pages/settings/settings_category.dart';
import 'package:commet/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:commet/ui/pages/settings/categories/room/advanced/room_advanced_settings_page.dart';

class SettingsCategoryRoom implements SettingsCategory {
  SettingsCategoryRoom(this.room, this.contextSpace);
  Room room;
  Space? contextSpace;

  String get labelRoomSettingsGeneral => Intl.message(
        "General",
        name: "labelRoomSettingsGeneral",
        desc: "Label for general room settings",
      );

  String get labelRoomSettingsAppearance => Intl.message(
        "Appearance",
        name: "labelRoomSettingsAppearance",
        desc: "Label for room appearance settings",
      );

  String get labelRoomSettingsSecurity => Intl.message(
        "Security",
        name: "labelRoomSettingsSecurity",
        desc: "Label for room security settings",
      );

  String get labelRoomSettingsEmoticons => Intl.message(
        "Emoji & Stickers",
        name: "labelRoomSettingsEmoticons",
        desc: "Label for room Emoticon settings",
      );

  String get labelRoomSettingsDeveloper => Intl.message(
        "Developer",
        name: "labelRoomSettingsDeveloper",
        desc: "Label for room developer settings",
      );

  String get labelRoomSettingsCategory => Intl.message(
        "Room Settings",
        name: "labelRoomSettingsCategory",
        desc: "Label for the overall settings category of a room",
      );

  String get labelRoomSettingsPermissions => Intl.message(
        "Permissions",
        name: "labelRoomSettingsPermissions",
        desc: "Label for room permission settings",
      );

  String get labelRoomSettingsAdvanced => Intl.message(
        "Advanced",
        name: "labelRoomSettingsAdvanced",
        desc: "Label for advanced room settings (room version, replacing the "
            "room)",
      );

  String get labelRoomSettingsBridges => Intl.message(
        "Bridges",
        name: "labelRoomSettingsBridges",
        desc: "Label for the room settings tab listing the room's bridges",
      );

  String get labelRoomSettingsCalendar => Intl.message(
        "Calendar",
        name: "labelRoomSettingsCalendar",
        desc: "Label for room calendar settings",
      );

  @override
  String get title => labelRoomSettingsCategory;

  @override
  List<SettingsTab> get tabs => getTabs();

  List<SettingsTab> getTabs() {
    RoomEmoticonComponent? emoticons =
        room.getComponent<RoomEmoticonComponent>();

    CalendarRoom? calendar = room.getComponent<CalendarRoom>();

    return List.from([
      SettingsTab(
        label: labelRoomSettingsGeneral,
        icon: Icons.settings,
        pageBuilder: (context) {
          return RoomGeneralSettingsPage(room: room);
        },
      ),
      SettingsTab(
        label: labelRoomSettingsAppearance,
        icon: Icons.style,
        pageBuilder: (context) {
          return RoomAppearanceSettingsPage(room: room);
        },
      ),
      SettingsTab(
        label: labelRoomSettingsSecurity,
        icon: Icons.lock,
        pageBuilder: (context) {
          return RoomSecuritySettingsPage(
            room: room,
            contextSpace: contextSpace,
          );
        },
      ),
      if (emoticons != null &&
          (room.permissions.canEditRoomEmoticons ||
              emoticons.ownedPacks.isNotEmpty))
        SettingsTab(
          label: labelRoomSettingsEmoticons,
          icon: Icons.emoji_emotions,
          pageBuilder: (context) {
            return RoomEmojiPackSettingsPage(room);
          },
        ),
      if (room is MatrixRoom)
        SettingsTab(
          label: labelRoomSettingsPermissions,
          icon: Icons.admin_panel_settings,
          makeScrollable: false,
          pageBuilder: (context) {
            return MatrixRoomPermissionsPage(
              (room as MatrixRoom).matrixRoom,
              showCalendarPermissions: calendar?.hasCalendar == true,
            );
          },
        ),
      // Vommet: the room's ID and version for everyone; "Replace room" on
      // it for people who may send m.room.tombstone.
      if (room.replacement != null)
        SettingsTab(
          label: labelRoomSettingsAdvanced,
          icon: Icons.construction,
          pageBuilder: (context) {
            return RoomAdvancedSettingsPage(room, contextSpace: contextSpace);
          },
        ),
      // Vommet: the room's bridges (m.bridge), like Element's Bridges tab.
      if (room case MatrixRoom r
          when matrixRoomBridges(r.matrixRoom).isNotEmpty)
        SettingsTab(
          label: labelRoomSettingsBridges,
          icon: Icons.hub_outlined,
          pageBuilder: (context) {
            return MatrixRoomBridgesSettingsPage(r.matrixRoom);
          },
        ),
      if (calendar?.hasCalendar == true)
        SettingsTab(
          icon: Icons.calendar_month,
          label: labelRoomSettingsCalendar,
          pageBuilder: (context) {
            return RoomCalendarSettingsPage(calendar!);
          },
        ),
      if (preferences.developerMode.value)
        SettingsTab(
          label: labelRoomSettingsDeveloper,
          icon: Icons.code,
          pageBuilder: (context) {
            return RoomDeveloperSettingsView(room);
          },
        ),
    ]);
  }
}
