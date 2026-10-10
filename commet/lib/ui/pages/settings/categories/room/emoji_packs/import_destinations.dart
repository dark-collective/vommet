import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/bulk_import_view.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

enum EmoticonImportKind { newPack, addToPack, newStickerRoom }

/// Vommet: where an imported pack goes.
class EmoticonImportDestination {
  const EmoticonImportDestination.newPack(
      {required this.label, required this.component})
      : kind = EmoticonImportKind.newPack,
        pack = null;

  const EmoticonImportDestination.addTo(
      {required this.label, required this.component, required this.pack})
      : kind = EmoticonImportKind.addToPack;

  /// [component] is the account-level component.
  const EmoticonImportDestination.newStickerRoom(
      {required this.label, required this.component})
      : kind = EmoticonImportKind.newStickerRoom,
        pack = null;

  final EmoticonImportKind kind;
  final String label;
  final EmoticonComponent component;
  final EmoticonPack? pack;
}

class EmoticonImportDestinations {
  static String get labelNewPersonalPack => Intl.message("New personal pack",
      name: "labelImportNewPersonalPack",
      desc: "Import destination: the user's one personal pack");

  static String labelNewPackIn(String owner) =>
      Intl.message("New pack in $owner",
          args: [owner],
          name: "labelImportNewPackIn",
          desc: "Import destination: create a new pack in a room or space");

  static String labelNewPackInStickerRoom(String room) =>
      Intl.message("New pack in sticker room \"$room\"",
          args: [room],
          name: "labelImportNewPackInStickerRoom",
          desc: "Import destination: a new pack in an existing sticker room");

  static String get labelNewStickerRoom =>
      Intl.message("New pack in a new sticker room",
          name: "labelImportNewStickerRoom",
          desc: "Import destination: create a sticker room for the pack");

  static String labelAddToPack(String pack, String owner) =>
      Intl.message("Add to $pack ($owner)",
          args: [pack, owner],
          name: "labelImportAddToPack",
          desc: "Import destination: add the images to an existing pack");

  static String get labelPersonal => Intl.message("personal",
      name: "labelImportPersonalOwner",
      desc: "Owner shown for the user's own pack in the import destination");

  static String get explainStickerRooms => Intl.message(
      "A Matrix account holds one personal pack. More packs live in sticker "
      "rooms: private rooms that only hold packs. Vommet keeps them out of "
      "your room list and shows them under Settings › Account › Emoticons; "
      "other apps show them as ordinary rooms. Invite friends to a sticker "
      "room to share its packs with them.",
      name: "explainStickerRooms",
      desc: "Explains sticker rooms in the pack import dialog");

  static String get titleImportPack => Intl.message("Import pack",
      name: "titleImportPackDialog",
      desc: "Title of the dialog that imports a sticker or emoji pack");

  /// Every destination the user may import into. [origin] is where import
  /// was opened; [room] adds that room's packs when opened from the
  /// composer. New packs first (origin first), then packs to add to.
  static List<EmoticonImportDestination> build(EmoticonComponent origin,
      {Room? room}) {
    final account = origin.client.getComponent<EmoticonComponent>();
    final stickerRooms = account?.stickerRoomComponents ?? const [];
    final roomComponent = room?.getComponent<RoomEmoticonComponent>();

    // Rooms and spaces you can edit, other than sticker rooms.
    final places = <EmoticonComponent>[
      if (!_isAccount(origin) && !_isStickerRoom(origin)) origin,
      if (roomComponent != null && !roomComponent.isStickerRoom) roomComponent,
    ].toSet().where((c) => c.canCreatePack).toList();

    final editableStickerRooms =
        stickerRooms.where((c) => c.canCreatePack).toList();
    // Opened from a sticker room's own settings: offer it first.
    if (_isStickerRoom(origin) && origin.canCreatePack) {
      editableStickerRooms
        ..remove(origin)
        ..insert(0, origin);
    }

    final result = <EmoticonImportDestination>[
      for (final c in places)
        EmoticonImportDestination.newPack(
            label: labelNewPackIn(_ownerName(c)), component: c),
      for (final c in editableStickerRooms)
        EmoticonImportDestination.newPack(
            label: labelNewPackInStickerRoom(_ownerName(c)), component: c),
      if (account != null && account.ownedPacks.isEmpty)
        EmoticonImportDestination.newPack(
            label: labelNewPersonalPack, component: account),
      if (account != null)
        EmoticonImportDestination.newStickerRoom(
            label: labelNewStickerRoom, component: account),
    ];

    // Opened from the account page or the composer: personal pack first.
    if (_isAccount(origin)) {
      final personal = result.indexWhere((d) => d.component == account);
      if (personal > 0) result.insert(0, result.removeAt(personal));
    }

    final owners = <EmoticonComponent>[
      if (account != null) account,
      ...editableStickerRooms,
      ...places,
    ];
    for (final c in owners) {
      for (final pack in c.ownedPacks) {
        result.add(EmoticonImportDestination.addTo(
            label: labelAddToPack(pack.displayName,
                _isAccount(c) ? labelPersonal : _ownerName(c)),
            component: c,
            pack: pack));
      }
    }

    return result;
  }

  static bool _isAccount(EmoticonComponent c) =>
      c is! RoomEmoticonComponent && c is! SpaceEmoticonComponent;

  static bool _isStickerRoom(EmoticonComponent c) =>
      c is RoomEmoticonComponent && c.isStickerRoom;

  static String _ownerName(EmoticonComponent c) => switch (c) {
        RoomEmoticonComponent r => r.room.displayName,
        SpaceEmoticonComponent s => s.space.displayName,
        _ => labelPersonal,
      };

  /// Opens the pack import dialog with a destination picker.
  static Future<void> show(BuildContext context, EmoticonComponent origin,
      {Room? room}) {
    return AdaptiveDialog.show(
      context,
      title: titleImportPack,
      builder: (context) => EmoticonBulkImportDialog(
        destinations: build(origin, room: room),
      ),
    );
  }
}
