// Vommet: Element-style access settings for a room or space's Security tab:
// who can read history (or "Preview space" for spaces), guest access, and
// the visibility options including "Ask to join". These widgets take plain
// values and callbacks; RoomSecuritySettingsPage reads and writes the state.
import 'package:commet/client/client.dart';
import 'package:commet/ui/pages/get_or_create_room/room_creator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' show HistoryVisibility;
import 'package:tiamat/tiamat.dart' as tiamat;

/// The visibility choices offered in the picker. [spaces] are the spaces whose
/// members may join (restricted rooms); knock options only where the room
/// version supports them.
List<RoomVisibility> roomVisibilityChoices({
  required List<String> spaces,
  required bool supportsKnock,
  required bool supportsKnockRestricted,
}) {
  return [
    if (spaces.isNotEmpty) RoomVisibilityRestricted(spaces),
    RoomVisibilityPrivate(),
    if (supportsKnock) RoomVisibilityKnock(const []),
    if (supportsKnockRestricted && spaces.isNotEmpty)
      RoomVisibilityKnock(spaces),
    RoomVisibilityPublic(),
  ];
}

/// One tappable choice in the visibility picker.
Widget buildRoomVisibilityChoice(
    Client client, RoomVisibility item, void Function() callback) {
  return Material(
    borderRadius: BorderRadius.circular(8),
    clipBehavior: Clip.antiAlias,
    color: Colors.transparent,
    child: InkWell(
      onTap: callback,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: RoomFieldVisibility.buildRoomVisibility(client, item),
      ),
    ),
  );
}

/// A row with a title, explanation and switch, greyed out when [enabled] is
/// false.
class AccessSwitchRow extends StatelessWidget {
  const AccessSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              tiamat.Text.labelEmphasised(title),
              tiamat.Text.labelLow(subtitle),
            ]),
          ),
          IgnorePointer(
            ignoring: !enabled,
            child: tiamat.Switch(state: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// Guest access (m.room.guest_access can_join / forbidden).
class GuestAccessPanel extends StatelessWidget {
  const GuestAccessPanel({
    required this.canJoin,
    required this.enabled,
    required this.isSpace,
    required this.onChanged,
    super.key,
  });

  final bool canJoin;
  final bool enabled;
  final bool isSpace;
  final void Function(bool canJoin) onChanged;

  static String get labelGuestAccess => Intl.message(
        "Enable guest access",
        name: "labelGuestAccess",
        desc: "Switch that lets guests (users without an account) join",
      );

  static String get labelGuestAccessRoomExplanation => Intl.message(
        "People with supported apps can join this room without a registered account",
        name: "labelGuestAccessRoomExplanation",
        desc: "Explains guest access for a room",
      );

  static String get labelGuestAccessSpaceExplanation => Intl.message(
        "People with supported apps can join this space without a registered account",
        name: "labelGuestAccessSpaceExplanation",
        desc: "Explains guest access for a space",
      );

  static String get labelAdvancedAccessSettings => Intl.message(
        "Advanced",
        name: "labelAdvancedAccessSettings",
        desc: "Header for advanced access settings of a space",
      );

  @override
  Widget build(BuildContext context) {
    final row = AccessSwitchRow(
      title: labelGuestAccess,
      subtitle: isSpace
          ? labelGuestAccessSpaceExplanation
          : labelGuestAccessRoomExplanation,
      value: canJoin,
      enabled: enabled,
      onChanged: onChanged,
    );
    return tiamat.Panel(
      header: isSpace ? labelAdvancedAccessSettings : null,
      mode: tiamat.TileType.surfaceContainerLow,
      child: row,
    );
  }
}

/// "Preview space": a space's history visibility as Element shows it, on =
/// world_readable, off = shared.
class SpacePreviewPanel extends StatelessWidget {
  const SpacePreviewPanel({
    required this.preview,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final bool preview;
  final bool enabled;
  final void Function(bool preview) onChanged;

  static String get labelPreviewSpace => Intl.message(
        "Preview space",
        name: "labelPreviewSpace",
        desc: "Switch that lets people preview a space before joining",
      );

  static String get labelPreviewSpaceExplanation => Intl.message(
        "Allow people to preview this space before they join. Recommended for public spaces.",
        name: "labelPreviewSpaceExplanation",
        desc: "Explains the preview space switch",
      );

  @override
  Widget build(BuildContext context) {
    return tiamat.Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      child: AccessSwitchRow(
        title: labelPreviewSpace,
        subtitle: labelPreviewSpaceExplanation,
        value: preview,
        enabled: enabled,
        onChanged: onChanged,
      ),
    );
  }
}

/// Who can read history (m.room.history_visibility), Element's four options.
class RoomHistoryVisibilityPanel extends StatelessWidget {
  const RoomHistoryVisibilityPanel({
    required this.value,
    required this.enabled,
    required this.encrypted,
    required this.onChanged,
    super.key,
  });

  /// Current value; null when the room has no (or an unknown) setting.
  final HistoryVisibility? value;
  final bool enabled;
  final bool encrypted;
  final void Function(HistoryVisibility value) onChanged;

  static String get labelHistoryVisibility => Intl.message(
        "Who can read history?",
        name: "labelHistoryVisibility",
        desc: "Header for the room history visibility setting",
      );

  static String get labelHistoryAnyone => Intl.message(
        "Anyone",
        name: "labelHistoryAnyone",
        desc: "History visibility option: anyone can read (world_readable)",
      );

  static String get labelHistoryShared => Intl.message(
        "Members only (since this option was selected)",
        name: "labelHistoryShared",
        desc:
            "History visibility option: members, from when the setting was chosen (shared)",
      );

  static String get labelHistoryInvited => Intl.message(
        "Members only (since they were invited)",
        name: "labelHistoryInvited",
        desc:
            "History visibility option: members, since their invite (invited)",
      );

  static String get labelHistoryJoined => Intl.message(
        "Members only (since they joined)",
        name: "labelHistoryJoined",
        desc: "History visibility option: members, since they joined (joined)",
      );

  static String get labelHistoryFutureOnly => Intl.message(
        "Changes apply to messages sent from now on; who can read earlier messages stays the same.",
        name: "labelHistoryFutureOnly",
        desc:
            "Note that history visibility changes only affect future messages",
      );

  static String get labelHistoryEncryptedNote => Intl.message(
        "This room is encrypted: \"Anyone\" doesn't make older encrypted messages readable. Only people who were given the message keys can read them.",
        name: "labelHistoryEncryptedNote",
        desc:
            "Note in encrypted rooms that world-readable history doesn't decrypt old messages",
      );

  static String label(HistoryVisibility value) => switch (value) {
        HistoryVisibility.worldReadable => labelHistoryAnyone,
        HistoryVisibility.shared => labelHistoryShared,
        HistoryVisibility.invited => labelHistoryInvited,
        HistoryVisibility.joined => labelHistoryJoined,
      };

  static const options = [
    HistoryVisibility.worldReadable,
    HistoryVisibility.shared,
    HistoryVisibility.invited,
    HistoryVisibility.joined,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return tiamat.Panel(
      header: labelHistoryVisibility,
      mode: tiamat.TileType.surfaceContainerLow,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in options)
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: option == value ? null : () => onChanged(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(
                        spacing: 10,
                        children: [
                          Icon(
                            option == value
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: option == value
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          Expanded(child: tiamat.Text.label(label(option))),
                        ],
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: tiamat.Text.labelLow(labelHistoryFutureOnly),
              ),
              if (encrypted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: tiamat.Text.labelLow(labelHistoryEncryptedNote),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
