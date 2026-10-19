import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/config/sticker_preferences.dart';
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
  static String get labelImportNewPersonalPack =>
      Intl.message("New personal pack",
          name: "labelImportNewPersonalPack",
          desc: "Import destination: the user's one personal pack");

  static String labelImportNewPackIn(String owner) =>
      Intl.message("New pack in $owner",
          args: [owner],
          name: "labelImportNewPackIn",
          desc: "Import destination: create a new pack in a room or space");

  static String labelImportNewPackInStickerRoom(String room) =>
      Intl.message("New pack in sticker room \"$room\"",
          args: [room],
          name: "labelImportNewPackInStickerRoom",
          desc: "Import destination: a new pack in an existing sticker room");

  static String get labelImportNewStickerRoom =>
      Intl.message("New pack in a new sticker room",
          name: "labelImportNewStickerRoom",
          desc: "Import destination: create a sticker room for the pack");

  static String labelImportAddToPack(String pack, String owner) =>
      Intl.message("Add to $pack ($owner)",
          args: [pack, owner],
          name: "labelImportAddToPack",
          desc: "Import destination: add the images to an existing pack");

  static String get labelImportPersonalOwner => Intl.message("personal",
      name: "labelImportPersonalOwner",
      desc: "Owner shown for the user's own pack in the import destination");

  static String get explainStickerRoomsV2 => Intl.message(
      "Packs live in sticker rooms: private rooms that only hold packs. "
      "Vommet keeps them out of your room list and shows them under "
      "Settings › Account › Emoticons; other apps show them as ordinary "
      "rooms. Invite friends to a sticker room to share its packs with them.",
      name: "explainStickerRoomsV2",
      desc: "Explains sticker rooms in the pack import dialog");

  static String labelImportEachNewPackIn(String owner) =>
      Intl.message("Each as a new pack in $owner",
          args: [owner],
          name: "labelImportEachNewPackIn",
          desc: "Multi-pack import destination: one new pack per link in a "
              "room or space");

  static String labelImportEachNewPackInStickerRoom(String room) =>
      Intl.message("Each as a new pack in sticker room \"$room\"",
          args: [room],
          name: "labelImportEachNewPackInStickerRoom",
          desc: "Multi-pack import destination: one new pack per link in an "
              "existing sticker room");

  static String get labelImportEachNewPackInNewStickerRoom =>
      Intl.message("Each as a new pack in a new sticker room",
          name: "labelImportEachNewPackInNewStickerRoom",
          desc: "Multi-pack import destination: create a sticker room holding "
              "one new pack per link");

  static String get titleImportPacksDialog => Intl.message("Import packs",
      name: "titleImportPacksDialog",
      desc: "Title of the dialog that imports sticker or emoji packs");

  static String get titleImportPackDialog => Intl.message("Import pack",
      name: "titleImportPackDialog",
      desc: "Title of the dialog that imports a sticker or emoji pack");

  /// Every destination the user may import into. [origin] is where import
  /// was opened; [room] adds that room's packs when opened from the
  /// composer. New packs first (origin first), then packs to add to.
  /// The personal pack (account data) is offered only with "Use a
  /// personal pack" on: "New personal pack" while you have none, "Add to …
  /// (personal)" once you do.
  static List<EmoticonImportDestination> build(EmoticonComponent origin,
      {Room? room, bool? usePersonalPack}) {
    final account = origin.client.getComponent<EmoticonComponent>();
    return buildFrom(
      origin: origin,
      account: account,
      stickerRooms: account?.stickerRoomComponents ?? const [],
      roomComponent: room?.getComponent<RoomEmoticonComponent>(),
      usePersonalPack:
          usePersonalPack ?? StickerPreferences.usePersonalPack.value,
    );
  }

  /// [build] without the client lookups (tests use it directly).
  static List<EmoticonImportDestination> buildFrom({
    required EmoticonComponent origin,
    required EmoticonComponent? account,
    required List<EmoticonComponent> stickerRooms,
    required RoomEmoticonComponent? roomComponent,
    required bool usePersonalPack,
  }) {
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
            label: labelImportNewPackIn(_ownerName(c)), component: c),
      for (final c in editableStickerRooms)
        EmoticonImportDestination.newPack(
            label: labelImportNewPackInStickerRoom(_ownerName(c)),
            component: c),
      if (account != null && usePersonalPack && account.ownedPacks.isEmpty)
        EmoticonImportDestination.newPack(
            label: labelImportNewPersonalPack, component: account),
      if (account != null)
        EmoticonImportDestination.newStickerRoom(
            label: labelImportNewStickerRoom, component: account),
    ];

    // Opened from the account page or the composer: personal pack first.
    if (_isAccount(origin)) {
      // (Only the personal pack itself: the "new sticker room" entry also
      // belongs to the account component.)
      final personal = result.indexWhere((d) =>
          d.kind == EmoticonImportKind.newPack && d.component == account);
      if (personal > 0) result.insert(0, result.removeAt(personal));
    }

    final owners = <EmoticonComponent>[
      if (account != null && usePersonalPack) account,
      ...editableStickerRooms,
      ...places,
    ];
    for (final c in owners) {
      for (final pack in c.ownedPacks) {
        result.add(EmoticonImportDestination.addTo(
            label: labelImportAddToPack(pack.displayName,
                _isAccount(c) ? labelImportPersonalOwner : _ownerName(c)),
            component: c,
            pack: pack));
      }
    }

    return result;
  }

  /// Vommet: the destinations for a multi-link import, where each link
  /// becomes its own new pack (adding to the personal pack or to one
  /// existing pack doesn't fit), labelled "Each as a new pack in …". The
  /// first editable sticker room comes first, else a new sticker room.
  static List<EmoticonImportDestination> forMultiImport(
      List<EmoticonImportDestination> all) {
    final result = <EmoticonImportDestination>[];
    for (final d in all) {
      if (d.kind == EmoticonImportKind.newStickerRoom) {
        result.add(EmoticonImportDestination.newStickerRoom(
            label: labelImportEachNewPackInNewStickerRoom,
            component: d.component));
      } else if (d.kind == EmoticonImportKind.newPack &&
          !_isAccount(d.component)) {
        final owner = _ownerName(d.component);
        result.add(EmoticonImportDestination.newPack(
            label: _isStickerRoom(d.component)
                ? labelImportEachNewPackInStickerRoom(owner)
                : labelImportEachNewPackIn(owner),
            component: d.component));
      }
    }
    final preferred = result.indexWhere((d) => _isStickerRoom(d.component));
    final fallback =
        result.indexWhere((d) => d.kind == EmoticonImportKind.newStickerRoom);
    final first = preferred >= 0 ? preferred : fallback;
    if (first > 0) result.insert(0, result.removeAt(first));
    return result;
  }

  static bool _isAccount(EmoticonComponent c) =>
      c is! RoomEmoticonComponent && c is! SpaceEmoticonComponent;

  static bool _isStickerRoom(EmoticonComponent c) =>
      c is RoomEmoticonComponent && c.isStickerRoom;

  static String _ownerName(EmoticonComponent c) => switch (c) {
        RoomEmoticonComponent r => r.room.displayName,
        SpaceEmoticonComponent s => s.space.displayName,
        _ => labelImportPersonalOwner,
      };

  /// Opens the pack import dialog with a destination picker.
  static Future<void> show(BuildContext context, EmoticonComponent origin,
      {Room? room}) {
    return AdaptiveDialog.show(
      context,
      title: titleImportPacksDialog,
      builder: (context) => EmoticonBulkImportDialog(
        destinations: build(origin, room: room),
      ),
    );
  }
}
