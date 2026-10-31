import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/config/sticker_preferences.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet: Settings › Account › Emoticons section for an existing personal
/// pack (account data `im.ponies.user_emotes`). Shown whenever one exists,
/// whatever the "Use a personal pack" switch says, so nobody loses
/// stickers; offers moving it into a sticker room.
class PersonalPackPanel extends StatefulWidget {
  const PersonalPackPanel({required this.account, super.key});

  /// The account-level emoticon component.
  final EmoticonComponent account;

  @override
  State<PersonalPackPanel> createState() => _PersonalPackPanelState();
}

class _PersonalPackPanelState extends State<PersonalPackPanel> {
  bool moving = false;

  String get headerPersonalPack => Intl.message("Personal pack",
      name: "headerPersonalPack",
      desc: "Header of the settings section showing the account's own pack");

  String get promptMovePersonalPackToStickerRoom =>
      Intl.message("Move to sticker room",
          name: "promptMovePersonalPackToStickerRoom",
          desc: "Moves the personal pack into a sticker room");

  String get promptConfirmMovePersonalPack => Intl.message(
      "Copy your personal pack into a sticker room, then remove it from your "
      "account settings? Its stickers keep working, in Vommet and in other "
      "apps that show favorited packs.",
      name: "promptConfirmMovePersonalPack",
      desc: "Confirmation before moving the personal pack to a sticker room");

  Future<void> move() async {
    final confirm = await AdaptiveDialog.confirmation(context,
        title: promptMovePersonalPackToStickerRoom,
        prompt: promptConfirmMovePersonalPack,
        confirmationText: promptMovePersonalPackToStickerRoom,
        cancelText: "Cancel");
    if (confirm != true || !mounted) return;

    setState(() => moving = true);
    try {
      await widget.account.movePersonalPackToStickerRoom();
    } catch (e, s) {
      Log.onError(e, s, content: "Could not move the personal pack: $e");
    }
    if (mounted) setState(() => moving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: tiamat.Text.labelEmphasised(headerPersonalPack)),
                tiamat.Button.secondary(
                  text: promptMovePersonalPackToStickerRoom,
                  isLoading: moving,
                  onTap: moving ? null : move,
                ),
              ],
            ),
            const SizedBox(height: 8),
            RoomEmojiPackSettingsView(
              component: widget.account,
              editable: true,
              showCreateButtons: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// Vommet: the collapsed "Advanced" section of Settings › Account ›
/// Emoticons: the off-by-default "Use a personal pack" switch, with sticker
/// rooms and the personal pack compared.
class EmoticonAdvancedSettings extends StatefulWidget {
  const EmoticonAdvancedSettings({super.key});

  @override
  State<EmoticonAdvancedSettings> createState() =>
      _EmoticonAdvancedSettingsState();
}

class _EmoticonAdvancedSettingsState extends State<EmoticonAdvancedSettings> {
  String get headerEmoticonAdvanced => Intl.message("Advanced",
      name: "headerEmoticonAdvanced",
      desc: "Collapsed section with advanced emoticon settings");

  String get labelUsePersonalPack => Intl.message("Use a personal pack",
      name: "labelUsePersonalPack",
      desc: "Setting that lets imports use the account's one personal pack");

  String get descUsePersonalPack =>
      Intl.message("Lets you import into your account's one personal pack.",
          name: "descUsePersonalPack",
          desc: "Explains the 'Use a personal pack' setting");

  String get labelUsePersonalPackNotSure =>
      Intl.message("Not sure? You probably don't need this.",
          name: "labelUsePersonalPackNotSure",
          desc: "Reassurance under the 'Use a personal pack' setting");

  String get headerCompareStickerRooms =>
      Intl.message("Sticker rooms (default)",
          name: "headerCompareStickerRooms",
          desc: "Column header comparing sticker rooms with the personal pack");

  String get headerComparePersonalPack => Intl.message("Personal pack",
      name: "headerComparePersonalPack",
      desc: "Column header comparing the personal pack with sticker rooms");

  String get compareStickerRoomsMany =>
      Intl.message("As many packs as you like",
          name: "compareStickerRoomsMany",
          desc: "Sticker rooms vs personal pack: any number of packs");
  String get compareStickerRoomsShare =>
      Intl.message("Share a pack by inviting friends",
          name: "compareStickerRoomsShare",
          desc: "Sticker rooms vs personal pack: shareable");
  String get compareStickerRoomsOtherApps => Intl.message(
      "Shows in other apps when favorited (Vommet does that for you)",
      name: "compareStickerRoomsOtherApps",
      desc: "Sticker rooms vs personal pack: other apps");
  String get compareStickerRoomsListed =>
      Intl.message("Other apps list it as a room",
          name: "compareStickerRoomsListed",
          desc: "Sticker rooms vs personal pack: visible as a room");
  String get comparePersonalOne => Intl.message("Only one per account",
      name: "comparePersonalOne",
      desc: "Personal pack vs sticker rooms: just one");
  String get comparePersonalNoShare => Intl.message("Can't be shared",
      name: "comparePersonalNoShare",
      desc: "Personal pack vs sticker rooms: not shareable");
  String get comparePersonalOtherApps =>
      Intl.message("Works in other apps that support packs",
          name: "comparePersonalOtherApps",
          desc: "Personal pack vs sticker rooms: other apps");
  String get comparePersonalNoRoom =>
      Intl.message("Kept in your account settings, no room",
          name: "comparePersonalNoRoom",
          desc: "Personal pack vs sticker rooms: stored in account data");

  List<String> get stickerRoomPoints => [
        compareStickerRoomsMany,
        compareStickerRoomsShare,
        compareStickerRoomsOtherApps,
        compareStickerRoomsListed,
      ];

  List<String> get personalPoints => [
        comparePersonalOne,
        comparePersonalNoShare,
        comparePersonalOtherApps,
        comparePersonalNoRoom,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: ExpansionTile(
        initiallyExpanded: false,
        controlAffinity: ListTileControlAffinity.leading,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: tiamat.Text.labelEmphasised(headerEmoticonAdvanced),
        children: [
          tiamat.Panel(
            mode: tiamat.TileType.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tiamat.Text.labelEmphasised(labelUsePersonalPack),
                          tiamat.Text.labelLow(descUsePersonalPack),
                          tiamat.Text.label(labelUsePersonalPackNotSure),
                        ],
                      ),
                    ),
                    tiamat.Switch(
                      state: StickerPreferences.usePersonalPack.value,
                      onChanged: (value) async {
                        await StickerPreferences.usePersonalPack.set(value);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    comparison(Icons.meeting_room_outlined,
                        headerCompareStickerRooms, stickerRoomPoints, colors),
                    comparison(Icons.person_outline, headerComparePersonalPack,
                        personalPoints, colors),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget comparison(
      IconData icon, String title, List<String> points, ColorScheme colors) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              tiamat.Text.labelEmphasised(title),
            ],
          ),
          const SizedBox(height: 4),
          for (final point in points)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
              child: tiamat.Text.labelLow("• $point"),
            ),
        ],
      ),
    );
  }
}
