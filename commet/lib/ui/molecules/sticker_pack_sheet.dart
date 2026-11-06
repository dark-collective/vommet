import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/sticker_shelf/sticker_shelf_component.dart';
import 'package:commet/client/matrix/components/emoticon/peeked_emoticon_pack.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:commet/client/timeline_events/timeline_event_sticker.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/pages/library/library_follow.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:commet/utils/library_sharing.dart';
import 'package:commet/utils/sticker_source_pack.dart';
import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:tiamat/tiamat.dart' as tiamat;

/// Vommet issue 450: tapping a sticker in the timeline shows the pack it
/// came from, with an action to copy that pack into one of your packs,
/// rooms, spaces or sticker rooms. When the pack can't be found, it says so
/// plainly and offers to add just this sticker. Vommet issue 731: when the
/// sticker names a pack room you are not in, it also offers to follow it.
/// Vommet issue 824: a pack in a world-readable room is shown (and can be
/// added) without joining, and a sticker bridged from Telegram offers to
/// import its whole Telegram set.
/// Vommet issue 890: "Favorite this sticker" adds it to the sticker picker's
/// Favorites; saving a GIF sticker to My GIFs is its own button.
class StickerPackSheet extends StatelessWidget {
  const StickerPackSheet(
      {required this.room,
      required this.event,
      required this.pack,
      this.isFavorite = false,
      this.markAsFavorite,
      this.shelfSticker,
      this.isShelfFavorite = false,
      this.canFollow = false,
      this.telegram,
      super.key});

  final Room room;
  final TimelineEventSticker event;

  /// The pack the sticker came from; null when it couldn't be found.
  final EmoticonPack? pack;
  final bool isFavorite;
  final Function(bool favorite)? markAsFavorite;

  /// The sticker as the picker's Favorites keep it; null hides the button.
  final Emoticon? shelfSticker;
  final bool isShelfFavorite;

  /// Whether to offer "Follow pack".
  final bool canFollow;

  /// The Telegram set to offer importing, when [pack] is unknown.
  final TelegramStickerLink? telegram;

  /// The tagged pack room when we are not in it (it can't be checked
  /// before joining whether it is open, so it is always offered).
  static PackRoomLink? followLink(Room room, StickerPackTag? tag) {
    final client = room.client;
    if (tag == null || client is! MatrixClient) return null;
    final joined = client.getMatrixClient().getRoomById(tag.roomId)?.membership;
    if (joined == matrix.Membership.join) return null;
    // Vommet's own tag names no servers: join through the room id's.
    if (tag.via.isEmpty) return LibrarySharing.parseLink(tag.roomId);
    return PackRoomLink(tag.roomId, via: tag.via);
  }

  static Future<void> show(BuildContext context,
      {required Room room,
      required TimelineEventSticker event,
      bool isFavorite = false,
      Function(bool favorite)? markAsFavorite}) async {
    final tag = event.stickerPackTag;
    final follow = followLink(room, tag);
    var pack = findStickerPack(
        stickerPackCandidates(room, tag: tag), event.stickerKey,
        tag: tag);
    final client = room.client;
    if (pack == null &&
        follow != null &&
        tag != null &&
        client is MatrixClient) {
      pack = await PeekedEmoticonPack.peek(client.getMatrixClient(), tag)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (!context.mounted) return;
    }
    final telegram = pack == null ? event.telegramPack : null;
    final shelf = client.getComponent<StickerShelfComponent>();
    final shelfSticker =
        shelf?.stickerFor(event.stickerKey, shortcode: event.stickerName);

    final action = await AdaptiveDialog.show<_SheetAction>(context,
        title: pack?.displayName ?? titleStickerPackUnknown,
        builder: (context) => StickerPackSheet(
            room: room,
            event: event,
            pack: pack,
            isFavorite: isFavorite,
            markAsFavorite: markAsFavorite,
            shelfSticker: shelfSticker,
            isShelfFavorite:
                shelfSticker != null && shelf!.isFavorite(shelfSticker),
            canFollow: follow != null,
            telegram: telegram));

    if (!context.mounted) return;
    if (action == _SheetAction.favorite && shelfSticker != null) {
      await shelf!.setFavorite(shelfSticker, !shelf.isFavorite(shelfSticker));
    } else if (action == _SheetAction.add) {
      await AddStickersDialog.show(context,
          room: room, event: event, pack: pack);
    } else if (action == _SheetAction.telegram && telegram != null) {
      final account = room.client.getComponent<EmoticonComponent>();
      if (account == null) return;
      await EmoticonImportDestinations.show(context, account,
          room: room, initialText: telegramLink(telegram));
    } else if (action == _SheetAction.follow && follow != null) {
      final client = room.client as MatrixClient;
      await LibraryFollow.follow(context, client.getMatrixClient(), follow);
    }
  }

  /// The set's share link, which the pack import dialog loads.
  static String telegramLink(TelegramStickerLink set) =>
      "https://t.me/${set.isEmojiSet ? "addemoji" : "addstickers"}/${set.setName}";

  static String labelStickerFromTelegram(String name) =>
      Intl.message('From the Telegram sticker set "$name"',
          args: [name],
          name: "labelStickerFromTelegram",
          desc: "Shown when tapping a sticker bridged from Telegram whose "
              "set is known");

  static String get explainStickerFromTelegram =>
      Intl.message("Add the whole set from Telegram, or only this sticker.",
          name: "explainStickerFromTelegram",
          desc: "Under the Telegram set name in the sticker sheet");

  static String get promptAddTelegramSet => Intl.message("Add Telegram set…",
      name: "promptAddTelegramSet",
      desc: "Button that opens the pack import with a bridged sticker's "
          "Telegram set");

  static String get titleStickerPackUnknown => Intl.message("Sticker",
      name: "titleStickerPackUnknown",
      desc: "Title of the sticker sheet when the sticker's pack is unknown");

  static String labelStickerPackInfo(int count, String owner) =>
      Intl.message("$count stickers · $owner",
          args: [count, owner],
          name: "labelStickerPackInfo",
          desc: "Under a sticker pack's name: how many stickers it has and the "
              "room, space or account it belongs to");

  static String get labelStickerPackNotFound =>
      Intl.message("The rest of this sticker's pack isn't available",
          name: "labelStickerPackNotFound",
          desc: "Shown when tapping a sticker whose pack can't be found");

  static String get explainStickerPackNotFound => Intl.message(
      "It wasn't shared in a room or space you're in, so only this one "
      "sticker can be added.",
      name: "explainStickerPackNotFound",
      desc: "Explains why only the tapped sticker is shown, not its pack");

  static String get promptAddStickerPack => Intl.message("Add pack…",
      name: "promptAddStickerPack",
      desc: "Button that copies a sticker pack into a pack, room or space");

  static String get promptAddSingleSticker => Intl.message("Add sticker to…",
      name: "promptAddSingleSticker",
      desc: "Button that copies one sticker into a pack, room or space");

  static String get promptFavoriteSticker =>
      Intl.message("Favorite this sticker",
          name: "promptFavoriteSticker",
          desc: "Button that adds the tapped sticker to the sticker picker's "
              "Favorites");

  static String get promptUnfavoriteSticker =>
      Intl.message("Remove from Favorites",
          name: "promptUnfavoriteSticker",
          desc: "Button that removes the tapped sticker from the sticker "
              "picker's Favorites");

  static String get promptSaveStickerGif => Intl.message("Save to My GIFs",
      name: "promptSaveStickerGif",
      desc: "Button that saves the tapped GIF sticker to My GIFs");

  static String get promptRemoveStickerGif =>
      Intl.message("Remove from My GIFs",
          name: "promptRemoveStickerGif",
          desc: "Button that removes the tapped GIF sticker from My GIFs");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pack = this.pack;
    final stickers = pack?.stickers.isNotEmpty == true
        ? pack!.stickers
        : (pack?.emotes ?? const <Emoticon>[]);

    return SizedBox(
      width: 480,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pack != null) ...[
              tiamat.Text.labelLow(
                  labelStickerPackInfo(stickers.length, pack.ownerDisplayName)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sticker in stickers)
                    _tile(scheme, sticker.image,
                        selected: sticker.key == event.stickerKey),
                ],
              ),
            ] else ...[
              Center(
                  child: _tile(scheme, event.stickerImage,
                      selected: false, size: 128)),
              const SizedBox(height: 12),
              if (telegram != null) ...[
                tiamat.Text.labelEmphasised(
                    labelStickerFromTelegram(telegram!.setName)),
                const SizedBox(height: 4),
                tiamat.Text.labelLow(explainStickerFromTelegram),
              ] else ...[
                tiamat.Text.labelEmphasised(labelStickerPackNotFound),
                const SizedBox(height: 4),
                tiamat.Text.labelLow(explainStickerPackNotFound),
              ],
            ],
            const SizedBox(height: 16),
            if (telegram != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: tiamat.Button(
                  text: promptAddTelegramSet,
                  onTap: () => Navigator.of(context).pop(_SheetAction.telegram),
                ),
              ),
            if (telegram != null)
              tiamat.Button.secondary(
                text: promptAddSingleSticker,
                onTap: () => Navigator.of(context).pop(_SheetAction.add),
              )
            else
              tiamat.Button(
                text: pack != null
                    ? promptAddStickerPack
                    : promptAddSingleSticker,
                // [show] opens the add dialog once this sheet has closed.
                onTap: () => Navigator.of(context).pop(_SheetAction.add),
              ),
            if (canFollow)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: tiamat.Button.secondary(
                  text: LibraryFollow.promptFollowPack,
                  onTap: () => Navigator.of(context).pop(_SheetAction.follow),
                ),
              ),
            if (shelfSticker != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: tiamat.Button.secondary(
                  text: isShelfFavorite
                      ? promptUnfavoriteSticker
                      : promptFavoriteSticker,
                  onTap: () => Navigator.of(context).pop(_SheetAction.favorite),
                ),
              ),
            if (markAsFavorite != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: tiamat.Button.secondary(
                  text: isFavorite
                      ? promptRemoveStickerGif
                      : promptSaveStickerGif,
                  onTap: () {
                    markAsFavorite!(!isFavorite);
                    Navigator.of(context).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ColorScheme scheme, ImageProvider? image,
      {required bool selected, double size = 72}) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected ? scheme.primary : Colors.transparent, width: 2),
      ),
      child: image == null
          ? const Icon(Icons.broken_image_outlined)
          : Image(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium),
    );
  }
}

enum _SheetAction { add, follow, telegram, favorite }

/// Vommet issue 450: copies a sticker [pack] (or, without one, the tapped
/// sticker alone) into a place you choose. The images are downloaded and
/// uploaded again, as with any other pack import.
class AddStickersDialog extends StatefulWidget {
  const AddStickersDialog(
      {required this.room,
      required this.event,
      required this.pack,
      required this.destinations,
      super.key});

  final Room room;
  final TimelineEventSticker event;
  final EmoticonPack? pack;
  final List<EmoticonImportDestination> destinations;

  static Future<void> show(BuildContext context,
      {required Room room,
      required TimelineEventSticker event,
      required EmoticonPack? pack}) {
    final account = room.client.getComponent<EmoticonComponent>();
    final destinations = account == null
        ? <EmoticonImportDestination>[]
        : EmoticonImportDestinations.build(account, room: room);

    return AdaptiveDialog.show(context,
        title: pack != null
            ? titleAddStickerPack(pack.displayName)
            : StickerPackSheet.promptAddSingleSticker,
        builder: (context) => AddStickersDialog(
            room: room, event: event, pack: pack, destinations: destinations));
  }

  static String titleAddStickerPack(String name) => Intl.message('Add "$name"',
      args: [name],
      name: "titleAddStickerPack",
      desc: "Title of the dialog that copies a sticker pack somewhere");

  static String get labelAddTo => Intl.message("Add to",
      name: "labelAddTo",
      desc: "Label above the place a sticker pack is copied to");

  static String get labelPackName => Intl.message("Pack name",
      name: "labelPackName", desc: "Label of the new pack's name field");

  static String get labelStickerRoomName => Intl.message("Sticker room name",
      name: "labelStickerRoomName",
      desc: "Label of the new sticker room's name field");

  static String get labelNoDestinations =>
      Intl.message("You have nowhere to add stickers yet.",
          name: "labelNoDestinations",
          desc: "Shown when there is no pack, room or space to add to");

  static String get labelStickersDownloadFailed =>
      Intl.message("The stickers couldn't be downloaded. Try again later.",
          name: "labelStickersDownloadFailed",
          desc: "Shown when no sticker image could be downloaded");

  static String get promptAdd => Intl.message("Add",
      name: "promptAddStickers", desc: "Button that copies the stickers");

  @override
  State<AddStickersDialog> createState() => _AddStickersDialogState();
}

class _AddStickersDialogState extends State<AddStickersDialog> {
  late EmoticonImportDestination? destination = widget.destinations.firstOrNull;
  late final TextEditingController packName = TextEditingController(
      text: widget.pack?.displayName ?? widget.event.stickerName);
  final TextEditingController stickerRoomName =
      TextEditingController(text: "Sticker packs");
  bool working = false;
  String? error;

  @override
  void dispose() {
    packName.dispose();
    stickerRoomName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (destination == null) {
      return tiamat.Text.labelLow(AddStickersDialog.labelNoDestinations);
    }

    return SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow(AddStickersDialog.labelAddTo),
          ),
          SizedBox(
            height: 44,
            child: tiamat.DropdownSelector<EmoticonImportDestination>(
              itemHeight: 44,
              items: widget.destinations,
              value: destination!,
              onItemSelected: (item) => setState(() => destination = item),
              itemBuilder: (item) => Row(
                children: [
                  Icon(switch (item.kind) {
                    EmoticonImportKind.newPack => Icons.add,
                    EmoticonImportKind.addToPack => Icons.library_add,
                    EmoticonImportKind.newStickerRoom => Icons.add_home_work,
                  }),
                  const SizedBox(width: 8),
                  Flexible(
                      child: tiamat.Text.label(item.label,
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          if (destination!.kind == EmoticonImportKind.newStickerRoom)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: tiamat.TextInput(
                controller: stickerRoomName,
                label: AddStickersDialog.labelStickerRoomName,
                maxLines: 1,
              ),
            ),
          if (destination!.kind != EmoticonImportKind.addToPack)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: tiamat.TextInput(
                controller: packName,
                label: AddStickersDialog.labelPackName,
                maxLines: 1,
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: tiamat.Text.error(error!),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: tiamat.Button(
              text: AddStickersDialog.promptAdd,
              isLoading: working,
              onTap: working ? null : add,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> add() async {
    final dest = destination!;
    final name = packName.text.trim();
    if (dest.kind != EmoticonImportKind.addToPack && name.isEmpty) return;

    setState(() {
      working = true;
      error = null;
    });

    final names = <String>[];
    final datas = <Uint8List>[];
    final pack = widget.pack;
    if (pack != null) {
      final stickers = pack.stickers.isNotEmpty ? pack.stickers : pack.emotes;
      for (final sticker in stickers) {
        final data = await _download(widget.room.client, sticker.key);
        if (data == null || sticker.shortcode == null) continue;
        names.add(sticker.shortcode!);
        datas.add(data);
      }
    } else {
      final data = await _download(widget.room.client, widget.event.stickerKey,
          event: widget.event);
      if (data != null) {
        names.add(_shortcodeFromBody(widget.event.stickerName));
        datas.add(data);
      }
    }

    if (!mounted) return;
    if (datas.isEmpty) {
      setState(() {
        working = false;
        error = AddStickersDialog.labelStickersDownloadFailed;
      });
      return;
    }

    final roomName = stickerRoomName.text.trim();
    final work = switch (dest.kind) {
      EmoticonImportKind.addToPack =>
        dest.component.addToPack(dest.pack!, names, datas),
      EmoticonImportKind.newPack =>
        dest.component.importEmoticonPack(name, 0, names, datas),
      EmoticonImportKind.newStickerRoom => dest.component
          .importIntoNewStickerRoom(
              roomName.isEmpty ? "Sticker packs" : roomName,
              name,
              0,
              names,
              datas),
    };
    work.catchError((Object e) => Log.e("Sticker pack copy failed: $e"));
    Navigator.of(context).pop();
  }

  static Future<Uint8List?> _download(Client client, String key,
      {TimelineEventSticker? event}) async {
    if (client is! MatrixClient) return null;
    try {
      return await MxcFileProvider(client.getMatrixClient(), Uri.parse(key),
              event: switch (event) {
                MatrixTimelineEvent e => e.event,
                _ => null,
              })
          .getFileData();
    } catch (e) {
      Log.w("Sticker download $key failed: $e");
      return null;
    }
  }

  /// A sticker's body is its shortcode, sometimes with a file extension
  /// (Element needs one to render it).
  static String _shortcodeFromBody(String body) {
    final name = body.replaceFirst(RegExp(r"\.[A-Za-z0-9]{2,5}$"), "").trim();
    return name.isEmpty ? "sticker" : name.replaceAll(RegExp(r"\s+"), "_");
  }
}
