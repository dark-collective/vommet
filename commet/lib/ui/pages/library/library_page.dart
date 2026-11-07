// Vommet issue 731: the Library, one page to organize your packs and My
// GIFs. Sidebar: sticker rooms with their packs, other rooms and spaces
// holding packs you may edit, packs still turned on from rooms you left,
// and My GIFs folders. The pane shows the chosen pack or folder as a grid;
// tap tiles to select them, then move, copy, clone, reorder or delete. On
// a computer, selected tiles can be dragged onto another pack (moves them)
// or onto a tile of the same pack (puts them before it). Phones show the
// sidebar first and the pack full width, with back.
//
// Phase 2 (sharing): a collection (sticker room) you admin has Share…;
// collections you follow are listed under FOLLOWING (view only, Unfollow,
// Make my own copy); a selection can be sent to someone as a copy; packs
// someone else changed since you last looked get a dot.
import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/library_store.dart';
import 'package:commet/client/matrix/components/gif/matrix_gif_component.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_file_provider.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/molecules/my_gifs.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/organisms/new_home/new_home_people_model.dart';
import 'package:commet/ui/pages/library/library_follow.dart';
import 'package:commet/ui/pages/library/library_share_dialog.dart';
import 'package:commet/ui/pages/settings/categories/account/account_emoji/sticker_rooms_panel.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/library_ops.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matrix/matrix.dart' as matrix;

class LibraryPage extends StatefulWidget {
  const LibraryPage({required this.client, super.key});

  final MatrixClient client;

  /// Opens the Library of [client] (Matrix accounts only).
  static Future<void> open(BuildContext context, Client client) async {
    if (client is! MatrixClient) return;
    await NavigationUtils.navigateTo(context, LibraryPage(client: client));
  }

  static String get title => Intl.message("Library",
      desc: "Title of the page organizing your sticker packs, emoji and GIFs",
      name: "libraryTitle");

  static String get promptOpen => Intl.message("Open Library",
      desc:
          "Button in Settings › Account › Emoji & Stickers that opens the Library page",
      name: "libraryPromptOpen");

  static String get explainOpen => Intl.message(
      "Move, copy and reorder stickers and emoji between your packs, and sort My GIFs into folders.",
      desc:
          "Explains the Library button in Settings › Account › Emoji & Stickers",
      name: "libraryExplainOpen");

  static String get promptManage => Intl.message("Manage",
      desc: "Tooltip of the picker button that opens the Library page",
      name: "libraryPromptManage");

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

/// What the pane shows: a pack, or a My GIFs folder (null: Unsorted).
class _View {
  const _View.pack(String this.roomId, String this.stateKey)
      : gifs = false,
        folder = null;
  const _View.gifs(this.folder)
      : gifs = true,
        roomId = null,
        stateKey = null;

  final String? roomId;
  final String? stateKey;
  final bool gifs;
  final String? folder;

  bool isPack(LibraryPack p) =>
      !gifs && p.room.id == roomId && p.stateKey == stateKey;

  @override
  bool operator ==(Object other) =>
      other is _View &&
      other.gifs == gifs &&
      other.folder == folder &&
      other.roomId == roomId &&
      other.stateKey == stateKey;

  @override
  int get hashCode => Object.hash(gifs, folder, roomId, stateKey);
}

/// Tiles being dragged out of a pack.
class _Drag {
  const _Drag(this.source, this.keys);

  final LibraryPack source;
  final List<String> keys;
}

/// A Move to / Copy to choice: a pack, or a new one.
class _Destination {
  const _Destination(this.pack);

  final LibraryPack? pack;
}

class _LibraryPageState extends State<LibraryPage> {
  late final LibraryStore store = LibraryStore(widget.client.matrixClient);
  StreamSubscription? syncSub;
  Timer? refreshTimer;

  _View? view;

  /// The change by someone else the shown pack had when it was opened.
  matrix.Event? changedNote;
  final Set<String> selected = {};
  String query = "";
  bool busy = false;

  // Strings.
  String get searchHint => Intl.message("Search stickers, emoji, GIFs",
      desc: "Hint of the search field of the Library page",
      name: "librarySearchHint");

  String get headerStickerRooms => Intl.message("Sticker rooms",
      desc: "Library sidebar heading: your sticker rooms and their packs",
      name: "libraryHeaderStickerRooms");

  String get headerRoomPacks => Intl.message("Room and space packs",
      desc:
          "Library sidebar heading: rooms and spaces holding packs you may edit",
      name: "libraryHeaderRoomPacks");

  String get headerGone => Intl.message("Turned on, room left",
      desc:
          "Library sidebar heading: packs still turned on everywhere though you left their room",
      name: "libraryHeaderGone");

  String get headerGifs => Intl.message("My GIFs (folders)",
      desc: "Library sidebar heading: the folders of My GIFs",
      name: "libraryHeaderGifs");

  String get labelNoStickerRooms => Intl.message("No sticker rooms yet",
      desc: "Library sidebar, when you have no sticker rooms",
      name: "libraryLabelNoStickerRooms");

  String get labelNoPacks => Intl.message("No packs",
      desc: "Library sidebar, under a room without packs",
      name: "libraryLabelNoPacks");

  String get labelGoneRoom => Intl.message("A room you left",
      desc: "Library sidebar: stands in for the name of a room you left",
      name: "libraryLabelGoneRoom");

  String get promptTurnOff => Intl.message("Turn off",
      desc:
          "Library button that stops offering a pack whose room you left everywhere",
      name: "libraryPromptTurnOff");

  String get labelPickSomething =>
      Intl.message("Pick a pack or a GIF folder on the left.",
          desc: "Library pane before anything is chosen",
          name: "libraryLabelPickSomething");

  String get labelEmpty => Intl.message("Nothing here yet",
      desc: "Library pane for an empty pack or folder",
      name: "libraryLabelEmpty");

  String get labelNoMatches => Intl.message("Nothing matches the search",
      desc: "Library pane when the search hides every tile",
      name: "libraryLabelNoMatches");

  String librarySelectedCount(int count) => Intl.plural(count,
      one: "1 selected",
      other: "$count selected",
      args: [count],
      name: "librarySelectedCount",
      desc: "Library action bar: how many tiles are selected");

  String libraryStickerCount(int count) => Intl.plural(count,
      one: "1 sticker",
      other: "$count stickers",
      args: [count],
      name: "libraryStickerCount",
      desc: "Library pane subtitle: how many images a sticker pack holds");

  String libraryEmojiCount(int count) => Intl.plural(count,
      one: "1 emoji",
      other: "$count emoji",
      args: [count],
      name: "libraryEmojiCount",
      desc: "Library pane subtitle: how many images an emoji pack holds");

  String libraryGifCount(int count) => Intl.plural(count,
      one: "1 GIF",
      other: "$count GIFs",
      args: [count],
      name: "libraryGifCount",
      desc: "Library pane subtitle: how many GIFs a folder holds");

  String get useAsStickers => Intl.message("Use as stickers",
      desc: "Library pane subtitle: the pack's images are stickers",
      name: "libraryUseAsStickers");

  String get useAsEmoji => Intl.message("Use as emoji",
      desc: "Library pane subtitle: the pack's images are emoji",
      name: "libraryUseAsEmoji");

  String get useAsBoth => Intl.message("Use as emoji and stickers",
      desc: "Library pane subtitle: the pack's images are emoji and stickers",
      name: "libraryUseAsBoth");

  String get labelViewOnly => Intl.message("View only",
      desc: "Library pane subtitle: you may not edit this pack",
      name: "libraryLabelViewOnly");

  String get promptMoveTo => Intl.message("Move to…",
      desc: "Library action: move the selected images to another pack",
      name: "libraryPromptMoveTo");

  String get promptCopyTo => Intl.message("Copy to…",
      desc: "Library action: copy the selected images to another pack",
      name: "libraryPromptCopyTo");

  String get promptClone => Intl.message("Clone",
      desc:
          "Library action: duplicate the selected images in the same pack under new shortcodes",
      name: "libraryPromptClone");

  String get promptMoveEarlier => Intl.message("Move earlier",
      desc: "Library action: move the selected images one place earlier",
      name: "libraryPromptMoveEarlier");

  String get promptMoveLater => Intl.message("Move later",
      desc: "Library action: move the selected images one place later",
      name: "libraryPromptMoveLater");

  String get promptClearSelection => Intl.message("Clear selection",
      desc: "Library action: unselect every tile",
      name: "libraryPromptClearSelection");

  String get promptMoveToFolder => Intl.message("Move to folder…",
      desc: "Library action: move the selected GIFs to another folder",
      name: "libraryPromptMoveToFolder");

  String get promptNewPack => Intl.message("New pack…",
      desc: "Library Move to / Copy to choice that makes a new pack",
      name: "libraryPromptNewPack");

  String get labelNewPackName => Intl.message("Pack name",
      desc: "Hint of the name field of a new pack in the Library",
      name: "libraryLabelNewPackName");

  String get defaultNewPackName => Intl.message("New pack",
      desc: "Pre-filled name of a new pack made in the Library",
      name: "libraryDefaultNewPackName");

  String get titleMoveTo => Intl.message("Move to",
      desc: "Title of the Library list of packs to move images to",
      name: "libraryTitleMoveTo");

  String get titleCopyTo => Intl.message("Copy to",
      desc: "Title of the Library list of packs to copy images to",
      name: "libraryTitleCopyTo");

  String get labelNoDestinations =>
      Intl.message("You have no other pack you can edit.",
          desc: "Library Move to / Copy to list when there is no other pack",
          name: "libraryLabelNoDestinations");

  String get promptDeletePack => Intl.message("Delete pack",
      desc: "Library action deleting the shown pack",
      name: "libraryPromptDeletePack");

  String get promptRenameFolder => Intl.message("Rename folder",
      desc: "Library action renaming the shown GIF folder",
      name: "libraryPromptRenameFolder");

  String get promptDeleteFolder => Intl.message("Delete folder",
      desc: "Library action deleting the shown GIF folder",
      name: "libraryPromptDeleteFolder");

  String libraryDeleteImagesPrompt(int count) => Intl.plural(count,
      one: "Delete 1 image from this pack? Everyone using the pack loses it.",
      other:
          "Delete $count images from this pack? Everyone using the pack loses them.",
      args: [count],
      name: "libraryDeleteImagesPrompt",
      desc: "Library: confirms deleting the selected images");

  String libraryDeletePackPrompt(String name) =>
      Intl.message("Delete the pack \"$name\"? Everyone using it loses it.",
          args: [name],
          name: "libraryDeletePackPrompt",
          desc: "Library: confirms deleting a pack");

  String libraryRemoveGifsPrompt(int count) => Intl.plural(count,
      one: "Remove 1 GIF from My GIFs?",
      other: "Remove $count GIFs from My GIFs?",
      args: [count],
      name: "libraryRemoveGifsPrompt",
      desc: "Library: confirms removing the selected GIFs from My GIFs");

  String libraryDeleteFolderPrompt(String name) =>
      Intl.message("Delete the folder \"$name\"? Its GIFs move to Unsorted.",
          args: [name],
          name: "libraryDeleteFolderPrompt",
          desc: "Library: confirms deleting a My GIFs folder");

  String get packFull =>
      Intl.message("This pack is full. Split it into another pack.",
          desc: "Library error: the pack would be too big to save",
          name: "libraryPackFull");

  String get failed => Intl.message("That didn't work. Try again.",
      desc: "Library error: a change could not be saved",
      name: "libraryFailed");

  String libraryRenamedNote(int count) => Intl.plural(count,
      one: "1 shortcode was taken there and got a number.",
      other: "$count shortcodes were taken there and got a number.",
      args: [count],
      name: "libraryRenamedNote",
      desc:
          "Library: after a move or copy, how many images were renamed name_2, name_3 because the name was taken");

  // Sharing strings (phase 2).
  String get headerFollowing => Intl.message("Following",
      desc:
          "Library sidebar heading: collections of packs you follow but can't edit",
      name: "libraryHeaderFollowing");

  String get promptUnfollow => Intl.message("Unfollow",
      desc: "Library action: stop following a collection and leave its room",
      name: "libraryPromptUnfollow");

  String get promptLeave => Intl.message("Leave",
      desc: "Library action: leave a sticker room", name: "libraryPromptLeave");

  String get promptMakeCopy => Intl.message("Make my own copy",
      desc:
          "Library action: copy a followed pack into your own sticker room, uploading its images again",
      name: "libraryPromptMakeCopy");

  String get promptSendCopy => Intl.message("Send a copy…",
      desc:
          "Library action: send the selected images to someone as a new collection of their own",
      name: "libraryPromptSendCopy");

  String get titleSendCopyTo => Intl.message("Send a copy to",
      desc: "Title of the person picker of Send a copy",
      name: "libraryTitleSendCopyTo");

  String get promptSend => Intl.message("Send",
      desc: "Confirms sending a copy of images to someone",
      name: "libraryPromptSend");

  String librarySendCopyPrompt(int count) => Intl.plural(count,
      one:
          "They get a copy of this item. Later changes you make won't reach them.",
      other:
          "They get a copy of these $count items. Later changes you make won't reach them.",
      args: [count],
      name: "librarySendCopyPrompt",
      desc: "Library: confirms sending a copy of the selected images");

  String librarySendCopyRoomName(String pack, String person) => Intl.message(
      "$pack for $person",
      args: [pack, person],
      name: "librarySendCopyRoomName",
      desc:
          "Name of the sticker room made to send a copy of a pack to someone");

  String librarySentCopy(String person) =>
      Intl.message("Sent. $person can join it from their invites.",
          args: [person],
          name: "librarySentCopy",
          desc: "Library: after sending a copy of images to someone");

  String libraryUnfollowPrompt(String room) => Intl.message(
      "Unfollow $room? Its packs are turned off and you leave its room.",
      args: [room],
      name: "libraryUnfollowPrompt",
      desc: "Library: confirms unfollowing a collection");

  String libraryLeavePrompt(String room) =>
      Intl.message("Leave $room? Its packs are turned off for you.",
          args: [room],
          name: "libraryLeavePrompt",
          desc: "Library: confirms leaving a sticker room");

  String get warnOnlyAdmin => Intl.message(
      "You're its only admin. Nobody will be able to change its packs after you leave.",
      desc:
          "Library: warning before leaving a collection you are the only admin of",
      name: "libraryWarnOnlyAdmin");

  String libraryWarnCopyNotJoined(String person) => Intl.message(
      "$person hasn't joined yet. If you leave now, they may not be able to.",
      args: [person],
      name: "libraryWarnCopyNotJoined",
      desc:
          "Library: warning before leaving a copy you sent that its recipient hasn't joined");

  String libraryChangedBy(String person, String when) => Intl.message(
      "Changed by $person, $when",
      args: [person, when],
      name: "libraryChangedBy",
      desc:
          "Library pane subtitle: who last changed a followed pack, and how long ago");

  String get labelChanged => Intl.message("Changed",
      desc:
          "Library sidebar: tooltip of the dot on a pack someone changed since you last looked",
      name: "libraryLabelChanged");

  String libraryCopyMade(String pack) =>
      Intl.message("\"$pack\" is copied into your sticker room.",
          args: [pack],
          name: "libraryCopyMade",
          desc: "Library: after Make my own copy");

  @override
  void initState() {
    super.initState();
    // Note collections we never looked at, so only later changes show.
    store.seedSeen([
      for (final r in [...store.followedRooms, ...store.stickerRooms])
        if (r.packs.any(store.tracksChanges)) r.room,
    ]);
    // Packs live in room state and the folders in account data; any sync
    // may change them. Rebuild at most twice a second.
    syncSub = widget.client.matrixClient.onSync.stream.listen((_) {
      if (refreshTimer?.isActive == true) return;
      refreshTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    syncSub?.cancel();
    refreshTimer?.cancel();
    store.flushSeen();
    super.dispose();
  }

  bool get desktop => MediaQuery.of(context).desktop;

  void show(_View next) {
    setState(() {
      if (view != next) {
        selected.clear();
        changedNote = null;
      }
      view = next;
    });
  }

  void snack(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Runs one change; the selection clears once it is saved.
  Future<void> run(Future<String?> Function() op) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final note = await op();
      if (!mounted) return;
      setState(selected.clear);
      if (note != null) snack(note);
    } on PackFullException catch (e) {
      Log.w("Library: $e");
      if (mounted) snack(packFull);
    } catch (e) {
      Log.w("Library: change failed: $e");
      if (mounted) snack(failed);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // Data.

  List<LibraryPackRoom> get stickerRooms => store.stickerRooms;
  List<LibraryPackRoom> get followedRooms => store.followedRooms;
  List<LibraryPackRoom> get editableRooms => store.editableRooms;

  LibraryPack? get shownPack {
    final v = view;
    if (v == null || v.gifs) return null;
    final room = widget.client.matrixClient.getRoomById(v.roomId!);
    if (room == null) return null;
    return LibraryStore.packsOf(room).firstWhereOrNull(v.isPack);
  }

  /// Every pack we may edit, except [except].
  List<LibraryPack> destinations(LibraryPack except) => [
        for (final r in [...stickerRooms, ...editableRooms])
          for (final p in r.packs)
            if (p.editable && !p.sameAs(except)) p,
      ];

  bool matches(String text) =>
      query.isEmpty || text.toLowerCase().contains(query.toLowerCase());

  bool packMatches(LibraryPack p) =>
      matches(p.name) || p.images.any((e) => matches(e.key));

  // Actions.

  List<String> selectedInOrder(LibraryPack pack) => [
        for (final e in pack.images)
          if (selected.contains(e.key)) e.key
      ];

  Future<_Destination?> pickDestination(LibraryPack source,
      {required bool move}) {
    final packs = destinations(source);
    return AdaptiveDialog.show<_Destination>(context,
        title: move ? titleMoveTo : titleCopyTo,
        builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (packs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(labelNoDestinations),
                  ),
                for (final p in packs)
                  ListTile(
                    leading: _PackAvatar(pack: p, mx: store.mx, size: 28),
                    title: Text("${p.name} · ${p.roomName}",
                        overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, _Destination(p)),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(promptNewPack),
                  onTap: () => Navigator.pop(context, const _Destination(null)),
                ),
              ],
            ));
  }

  Future<void> transfer(LibraryPack source, List<String> keys,
      {required bool move, LibraryPack? target}) async {
    if (keys.isEmpty) return;
    final dest = target != null
        ? _Destination(target)
        : await pickDestination(source, move: move);
    if (dest == null || !mounted) return;
    if (dest.pack != null) {
      await run(() async {
        final renamed =
            await store.transfer(source, keys, dest.pack!, move: move);
        return renamed.isEmpty ? null : libraryRenamedNote(renamed.length);
      });
      return;
    }
    final name = await AdaptiveDialog.textPrompt(context,
        title: promptNewPack,
        hintText: labelNewPackName,
        initialText: defaultNewPackName,
        submitText: MyGifs.promptCreate);
    final clean = name?.trim();
    if (clean == null || clean.isEmpty || !mounted) return;
    await run(() async {
      final room = await store.newPackRoom(source, createStickerRoom);
      await store.toNewPack(source, keys, room, clean, move: move);
      return null;
    });
  }

  Future<String> createStickerRoom() {
    final account = widget.client.getComponent<EmoticonComponent>();
    if (account == null) throw StateError("No emoticon component");
    return account.createStickerRoom(stickerRoomDefaultName);
  }

  Future<void> deleteSelected(LibraryPack pack) async {
    final keys = selected.toSet();
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: libraryDeleteImagesPrompt(keys.length),
        title: CommonStrings.promptDelete,
        confirmationText: CommonStrings.promptDelete,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (yes != true) return;
    await run(() async {
      await store.deleteImages(pack, keys);
      return null;
    });
  }

  Future<void> deletePack(LibraryPack pack) async {
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: libraryDeletePackPrompt(pack.name),
        title: promptDeletePack,
        confirmationText: CommonStrings.promptDelete,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (yes != true) return;
    await run(() async {
      await store.deletePack(pack);
      if (mounted) setState(() => view = null);
      return null;
    });
  }

  Future<void> nudge(LibraryPack pack, int step) async {
    final order = [for (final e in pack.images) e.key];
    final next = LibraryOps.nudge(order, selected.toSet(), step);
    if (const ListEquality<String>().equals(order, next)) return;
    final keep = selected.toSet();
    await run(() async {
      await store.reorder(pack, next);
      return null;
    });
    // Keep the selection so the images can be nudged again.
    if (mounted) setState(() => selected.addAll(keep));
  }

  Future<void> dropBefore(LibraryPack pack, _Drag drag, String before) async {
    final order = [for (final e in pack.images) e.key];
    final next = LibraryOps.moveBefore(order, drag.keys.toSet(), before);
    if (const ListEquality<String>().equals(order, next)) return;
    await run(() async {
      await store.reorder(pack, next);
      return null;
    });
  }

  Future<void> moveGifs(Set<String> urls) async {
    final picked = await MyGifs.pickFolder(
        context, GifFolders.folders(store.gifContent),
        current: view?.folder);
    if (picked == null) return;
    await run(() async {
      await store.editGifs((c) => GifFolders.moveTo(c, urls, picked.folder));
      return null;
    });
  }

  Future<void> removeGifs(Set<String> urls) async {
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: libraryRemoveGifsPrompt(urls.length),
        title: CommonStrings.promptRemove,
        confirmationText: CommonStrings.promptRemove,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (yes != true) return;
    await run(() async {
      await store.editGifs((c) => GifFolders.remove(c, urls));
      return null;
    });
  }

  Future<void> newFolder() async {
    final name = await MyGifs.askFolderName(context);
    if (name == null) return;
    await run(() async {
      await store.editGifs((c) => GifFolders.addFolder(c, name));
      return null;
    });
    if (mounted) show(_View.gifs(name));
  }

  Future<void> renameFolder(String from) async {
    final to = await MyGifs.askFolderName(context,
        initial: from, submit: MyGifs.promptRenameFolder);
    if (to == null || to == from) return;
    await run(() async {
      await store.editGifs((c) => GifFolders.rename(c, from, to));
      return null;
    });
    if (mounted) show(_View.gifs(to));
  }

  Future<void> deleteFolder(String name) async {
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: libraryDeleteFolderPrompt(name),
        title: promptDeleteFolder,
        confirmationText: CommonStrings.promptDelete,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (yes != true) return;
    await run(() async {
      await store.editGifs((c) => GifFolders.delete(c, name));
      return null;
    });
    if (mounted) show(const _View.gifs(null));
  }

  // Sharing (phase 2).

  Future<void> share(matrix.Room room) => LibraryShareDialog.show(context,
      client: widget.client, store: store, room: room);

  Future<void> followFromLink() async {
    final room = await LibraryFollow.followFromLink(context, store.mx);
    if (room == null || !mounted) return;
    final first = LibraryStore.packsOf(room).firstOrNull;
    setState(() {});
    if (first != null) show(_View.pack(room.id, first.stateKey));
  }

  /// Leaves (or unfollows) [room] after a confirm that warns when we are
  /// its only admin or a copy we sent wasn't picked up yet.
  Future<void> leave(matrix.Room room, {required bool unfollow}) async {
    final name = room.getLocalizedDisplayname();
    final notJoined = store.copyNotJoinedYet(room);
    final prompt = [
      unfollow ? libraryUnfollowPrompt(name) : libraryLeavePrompt(name),
      if (store.isOnlyAdmin(room)) warnOnlyAdmin,
      if (notJoined != null)
        libraryWarnCopyNotJoined(room
            .unsafeGetUserFromMemoryOrFallback(notJoined)
            .calcDisplayname()),
    ].join("\n\n");
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: prompt,
        title: unfollow ? promptUnfollow : promptLeave,
        confirmationText: unfollow ? promptUnfollow : promptLeave,
        cancelText: CommonStrings.promptCancel,
        dangerous: true);
    if (yes != true) return;
    await run(() async {
      await store.leave(room);
      if (mounted) setState(() => view = null);
      return null;
    });
  }

  /// Decision 5: copies a followed pack into our own sticker room,
  /// downloading and uploading every image again (as "Add pack…" does),
  /// so the copy doesn't depend on the original's media.
  Future<void> makeOwnCopy(LibraryPack pack) async {
    final account = widget.client.getComponent<EmoticonComponent>();
    if (account == null) return;
    await run(() async {
      final names = <String>[];
      final datas = <Uint8List>[];
      for (final e in pack.images) {
        final url = e.value["url"];
        if (url is! String) continue;
        try {
          final data =
              await MxcFileProvider(store.mx, Uri.parse(url)).getFileData();
          if (data == null) continue;
          names.add(e.key);
          datas.add(data);
        } catch (err) {
          Log.w("Library: could not download $url: $err");
        }
      }
      if (datas.isEmpty) return failed;
      final usage = switch (pack.usage) {
        [] => null,
        final u when u.contains("sticker") && u.contains("emoticon") =>
          EmoticonUsage.all,
        final u when u.contains("sticker") => EmoticonUsage.sticker,
        _ => EmoticonUsage.emoji,
      };
      final own = account.stickerRoomComponents
          .whereType<RoomEmoticonComponent>()
          .firstWhereOrNull((c) => c.isOwnStickerRoom && c.canCreatePack);
      if (own != null) {
        await own.importEmoticonPack(pack.name, 0, names, datas, usage: usage);
      } else {
        await account.importIntoNewStickerRoom(
            stickerRoomDefaultName, pack.name, 0, names, datas,
            usage: usage);
      }
      return libraryCopyMade(pack.name);
    });
  }

  /// Decision 4: a snapshot of the selection in a new sticker room for
  /// someone, who is invited as its admin.
  Future<void> sendCopy(LibraryPack pack, List<String> keys) async {
    final invitation = widget.client.getComponent<InvitationComponent>();
    if (invitation == null || keys.isEmpty) return;
    String? picked;
    await AdaptiveDialog.show(context,
        title: titleSendCopyTo,
        builder: (context) => SendInvitationWidget(widget.client, invitation,
                onUserPicked: (userId) async {
              picked = userId;
            }));
    final userId = picked;
    if (userId == null || !mounted) return;
    final yes = await AdaptiveDialog.confirmation(context,
        prompt: librarySendCopyPrompt(keys.length),
        title: promptSendCopy,
        confirmationText: promptSend,
        cancelText: CommonStrings.promptCancel);
    if (yes != true) return;
    await run(() async {
      var person = userId;
      try {
        final profile = await store.mx.getProfileFromUserId(userId);
        person = profile.displayName ?? userId;
      } catch (e) {
        Log.w("Library: no profile for $userId: $e");
      }
      await store.sendCopy(pack, keys,
          userId: userId,
          roomName: librarySendCopyRoomName(pack.name, person),
          packName: pack.name);
      return librarySentCopy(person);
    });
  }

  // Layout.

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      final paneOnly = !wide && view != null;
      return PopScope(
        canPop: !paneOnly,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && paneOnly) setState(() => view = null);
        },
        child: Scaffold(
          backgroundColor: scheme.surfaceContainer,
          appBar: AppBar(
            backgroundColor: scheme.surfaceContainer,
            title: Text(LibraryPage.title),
            bottom: busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(2),
                    child: LinearProgressIndicator(minHeight: 2))
                : null,
          ),
          body: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 300, child: sidebar()),
                    VerticalDivider(width: 1, color: scheme.outlineVariant),
                    Expanded(child: pane(wide: true)),
                  ],
                )
              : paneOnly
                  ? pane(wide: false)
                  : sidebar(),
        ),
      );
    });
  }

  Widget sidebar() {
    final theme = Theme.of(context);
    final gifs = store.gifContent;
    final folders = GifFolders.folders(gifs);
    final stickers = stickerRooms;
    final followed = followedRooms;
    final others = editableRooms;
    final gone = store.gonePacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: searchHint),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              heading(headerStickerRooms),
              if (stickers.isEmpty)
                hint(labelNoStickerRooms)
              else
                for (final r in stickers) ...roomGroup(r, Icons.sticky_note_2),
              heading(headerFollowing),
              for (final r in followed) ...roomGroup(r, Icons.rss_feed),
              ListTile(
                dense: true,
                leading: Icon(Icons.add_link, color: theme.colorScheme.primary),
                title: Text(LibraryFollow.promptFollowAPack,
                    style: TextStyle(color: theme.colorScheme.primary)),
                onTap: busy ? null : followFromLink,
              ),
              if (others.isNotEmpty) ...[
                heading(headerRoomPacks),
                for (final r in others)
                  ...roomGroup(
                      r,
                      r.room.isSpace
                          ? Icons.workspaces_outline
                          : Icons.tag_rounded),
              ],
              if (gone.isNotEmpty) ...[
                heading(headerGone),
                for (final g in gone) goneRow(g),
              ],
              heading(headerGifs),
              folderRow(null, GifFolders.inFolder(gifs, null).length),
              for (final f in folders)
                folderRow(f, GifFolders.inFolder(gifs, f).length),
              ListTile(
                dense: true,
                leading: Icon(Icons.add, color: theme.colorScheme.primary),
                title: Text(MyGifs.promptNewFolder,
                    style: TextStyle(color: theme.colorScheme.primary)),
                onTap: busy ? null : newFolder,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget heading(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Text(text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  List<Widget> roomGroup(LibraryPackRoom r, IconData icon) {
    final packs = r.packs.where(packMatches).toList();
    if (query.isNotEmpty && packs.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
        child: Row(children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Expanded(
              child: Text(r.room.getLocalizedDisplayname(),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge)),
        ]),
      ),
      if (packs.isEmpty) hint(labelNoPacks),
      for (final p in packs) packRow(p),
    ];
  }

  Widget packRow(LibraryPack p) {
    final scheme = Theme.of(context).colorScheme;
    final isShown = view?.isPack(p) == true;
    Widget tile(bool hovered) => _DropOutline(
          active: hovered,
          radius: 8,
          child: ListTile(
            dense: true,
            selected: isShown,
            selectedTileColor: scheme.secondaryContainer,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            leading: _PackAvatar(pack: p, mx: store.mx, size: 24),
            title: Text(p.name, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (!isShown && store.changedEvent(p) != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Tooltip(
                    message: labelChanged,
                    child: Semantics(
                      label: labelChanged,
                      child: CircleAvatar(
                          radius: 4, backgroundColor: scheme.primary),
                    ),
                  ),
                ),
              Text("${p.images.length}",
                  style: Theme.of(context).textTheme.labelSmall),
            ]),
            onTap: () => show(_View.pack(p.room.id, p.stateKey)),
          ),
        );
    if (!desktop || !p.editable) return tile(false);
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) =>
          d.data.source.editable && !d.data.source.sameAs(p) && !busy,
      onAcceptWithDetails: (d) =>
          transfer(d.data.source, d.data.keys, move: true, target: p),
      builder: (context, candidates, _) => tile(candidates.isNotEmpty),
    );
  }

  Widget goneRow(LibraryGonePack g) => ListTile(
        dense: true,
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
        leading: const Icon(Icons.link_off, size: 20),
        title: Text(g.stateKey.isEmpty ? labelGoneRoom : g.stateKey,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(g.roomId, overflow: TextOverflow.ellipsis),
        trailing: TextButton(
          onPressed: busy
              ? null
              : () => run(() async {
                    await store.turnOff(g);
                    return null;
                  }),
          child: Text(promptTurnOff),
        ),
      );

  Widget folderRow(String? folder, int count) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: view == _View.gifs(folder),
      selectedTileColor: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      leading:
          Icon(folder == null ? Icons.inbox_outlined : Icons.folder, size: 20),
      title: Text(folder ?? MyGifs.unsorted, overflow: TextOverflow.ellipsis),
      trailing: Text("$count", style: Theme.of(context).textTheme.labelSmall),
      onTap: () => show(_View.gifs(folder)),
    );
  }

  Widget pane({required bool wide}) {
    final v = view;
    if (v == null) {
      return Center(child: hint(labelPickSomething));
    }
    return v.gifs ? gifPane(v.folder, wide) : packPane(wide);
  }

  Widget paneHeader(
      {required bool wide,
      required String title,
      required String subtitle,
      List<Widget> actions = const []}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(children: [
        if (!wide)
          IconButton(
              tooltip: CommonStrings.promptBack,
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => view = null)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis),
              Text(subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        ...actions,
      ]),
    );
  }

  String usageLabel(LibraryPack p) {
    final u = p.usage;
    final emoji = u.isEmpty || u.contains("emoticon");
    final stickers = u.isEmpty || u.contains("sticker");
    if (emoji && stickers) return useAsBoth;
    return emoji ? useAsEmoji : useAsStickers;
  }

  Widget packPane(bool wide) {
    final pack = shownPack;
    if (pack == null) {
      return Center(child: hint(labelPickSomething));
    }
    final images = pack.images;
    final shown = images.where((e) => matches(e.key)).toList();
    final emojiOnly = pack.usage.isNotEmpty && !pack.usage.contains("sticker");
    final count = emojiOnly
        ? libraryEmojiCount(images.length)
        : libraryStickerCount(images.length);
    // Opening a pack someone else changed notes it as seen; the note
    // stays while it is shown.
    final changed = store.changedEvent(pack);
    if (changed != null) {
      changedNote = changed;
      store.markSeen(pack.room, [pack]);
    }
    final note = changedNote;
    final subtitle = [
      pack.roomName,
      count,
      usageLabel(pack),
      if (!pack.editable) labelViewOnly,
      if (note != null)
        libraryChangedBy(note.senderFromMemoryOrFallback.calcDisplayname(),
            PeopleModel.relativeTime(note.originServerTs, DateTime.now())),
    ].join(" · ");
    final room = pack.room;
    final followed = !LibraryStore.canEdit(room) &&
        MatrixEmoticonComponent.isStickerRoom(room);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        paneHeader(
          wide: wide,
          title: pack.name,
          subtitle: subtitle,
          actions: [
            if (LibraryStore.canShare(room))
              TextButton.icon(
                icon: const Icon(Icons.share_outlined, size: 18),
                label: Text(LibraryShareDialog.promptShare),
                onPressed: busy ? null : () => share(room),
              ),
            if (followed)
              IconButton(
                tooltip: promptMakeCopy,
                icon: const Icon(Icons.library_add_outlined),
                onPressed: busy ? null : () => makeOwnCopy(pack),
              ),
            if (pack.editable)
              IconButton(
                tooltip: promptDeletePack,
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : () => deletePack(pack),
              ),
            if (MatrixEmoticonComponent.isStickerRoom(room))
              PopupMenuButton<void>(
                enabled: !busy,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: () => leave(room, unfollow: followed),
                    child: Text(followed ? promptUnfollow : promptLeave),
                  ),
                ],
              ),
          ],
        ),
        if (selected.isNotEmpty) packActions(pack),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: hint(images.isEmpty ? labelEmpty : labelNoMatches))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 112,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.82),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => imageTile(pack, shown[i]),
                ),
        ),
      ],
    );
  }

  Widget actionBar(List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10)),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(librarySelectedCount(selected.length),
                style: Theme.of(context).textTheme.labelLarge),
          ),
          ...children,
          IconButton(
              tooltip: promptClearSelection,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => setState(selected.clear)),
        ],
      ),
    );
  }

  Widget packActions(LibraryPack pack) {
    final keys = selectedInOrder(pack);
    final enabled = !busy;
    return actionBar([
      if (pack.editable)
        TextButton.icon(
            icon: const Icon(Icons.drive_file_move_outline, size: 18),
            label: Text(promptMoveTo),
            onPressed: enabled ? () => transfer(pack, keys, move: true) : null),
      TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: Text(promptCopyTo),
          onPressed: enabled ? () => transfer(pack, keys, move: false) : null),
      if (pack.editable) ...[
        TextButton.icon(
            icon: const Icon(Icons.control_point_duplicate, size: 18),
            label: Text(promptClone),
            onPressed: enabled
                ? () => run(() async {
                      await store.clone(pack, keys);
                      return null;
                    })
                : null),
        IconButton(
            tooltip: promptMoveEarlier,
            icon: const Icon(Icons.arrow_back, size: 18),
            onPressed: enabled ? () => nudge(pack, -1) : null),
        IconButton(
            tooltip: promptMoveLater,
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: enabled ? () => nudge(pack, 1) : null),
        TextButton.icon(
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(CommonStrings.promptDelete),
            onPressed: enabled ? () => deleteSelected(pack) : null),
        TextButton.icon(
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(promptSendCopy),
            onPressed: enabled ? () => sendCopy(pack, keys) : null),
      ],
    ]);
  }

  void toggle(String key) => setState(() {
        if (!selected.remove(key)) selected.add(key);
      });

  Widget imageTile(
      LibraryPack pack, MapEntry<String, Map<String, dynamic>> image) {
    final url = image.value["url"];
    final provider = url is String
        ? MatrixMxcImage(Uri.parse(url), store.mx,
            fullResHeight: 256,
            doThumbnail: false,
            doFullres: true,
            autoLoadFullRes: true)
        : null;
    final key = image.key;
    Widget tile({bool dropHere = false}) => _Tile(
          label: key,
          image: provider,
          selected: selected.contains(key),
          dropHere: dropHere,
          onTap: () => toggle(key),
        );
    if (!desktop) return tile();

    final drag =
        _Drag(pack, selected.contains(key) ? selectedInOrder(pack) : [key]);
    final draggable = Draggable<_Drag>(
      data: drag,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragFeedback(count: drag.keys.length, image: provider),
      childWhenDragging: Opacity(opacity: 0.4, child: tile()),
      child: tile(),
    );
    if (!pack.editable) return draggable;
    return DragTarget<_Drag>(
      onWillAcceptWithDetails: (d) =>
          d.data.source.sameAs(pack) && !d.data.keys.contains(key) && !busy,
      onAcceptWithDetails: (d) => dropBefore(pack, d.data, key),
      builder: (context, candidates, _) => candidates.isEmpty
          ? draggable
          : _Tile(
              label: key,
              image: provider,
              selected: selected.contains(key),
              dropHere: true,
              onTap: () => toggle(key)),
    );
  }

  Widget gifPane(String? folder, bool wide) {
    final content = store.gifContent;
    final gifs = GifFolders.inFolder(content, folder);
    final shown = gifs.where((e) => matches("${e["body"] ?? ""}")).toList();
    final urls = {for (final e in gifs) e["url"]}.whereType<String>().toSet();
    // A selection left over from GIFs moved away by another device.
    selected.retainAll(urls);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        paneHeader(
          wide: wide,
          title: folder ?? MyGifs.unsorted,
          subtitle: "${MyGifs.title} · ${libraryGifCount(gifs.length)}",
          actions: [
            if (folder != null) ...[
              IconButton(
                  tooltip: promptRenameFolder,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy ? null : () => renameFolder(folder)),
              IconButton(
                  tooltip: promptDeleteFolder,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => deleteFolder(folder)),
            ],
          ],
        ),
        if (selected.isNotEmpty)
          actionBar([
            TextButton.icon(
                icon: const Icon(Icons.drive_file_move_outline, size: 18),
                label: Text(promptMoveToFolder),
                onPressed: busy ? null : () => moveGifs(selected.toSet())),
            TextButton.icon(
                icon: const Icon(Icons.bookmark_remove_outlined, size: 18),
                label: Text(CommonStrings.promptRemove),
                onPressed: busy ? null : () => removeGifs(selected.toSet())),
          ]),
        Expanded(
          child: shown.isEmpty
              ? Center(child: hint(gifs.isEmpty ? labelEmpty : labelNoMatches))
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 140,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8),
                  itemCount: shown.length,
                  itemBuilder: (context, i) {
                    final entry = shown[i];
                    final url = entry["url"];
                    if (url is! String) return const SizedBox.shrink();
                    return _Tile(
                      image: MatrixFavoriteGif(widget.client, entry).image,
                      selected: selected.contains(url),
                      onTap: () => toggle(url),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A grid tile: the image, a check badge and accent outline when selected,
/// the shortcode under it.
class _Tile extends StatelessWidget {
  const _Tile(
      {required this.image,
      required this.selected,
      required this.onTap,
      this.label,
      this.dropHere = false});

  final ImageProvider? image;
  final bool selected;
  final bool dropHere;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: _DropOutline(
        active: dropHere,
        radius: 10,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected && !dropHere
                      ? scheme.primary
                      : Colors.transparent,
                  width: 2),
            ),
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (image != null)
                        Image(
                            image: image!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image_outlined)),
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: scheme.primary,
                            child: Icon(Icons.check,
                                size: 14, color: scheme.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.count, required this.image});

  final int count;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Badge(
        label: Text("$count"),
        isLabelVisible: count > 1,
        child: Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary, width: 2)),
          child:
              image == null ? null : Image(image: image!, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// A pack's avatar, or its first image.
class _PackAvatar extends StatelessWidget {
  const _PackAvatar({required this.pack, required this.mx, this.size = 24});

  final LibraryPack pack;
  final matrix.Client mx;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = (pack.content["pack"] as Map?)?["avatar_url"];
    final url = avatar is String
        ? avatar
        : pack.images.firstOrNull?.value["url"] as String?;
    if (url == null) {
      return Icon(Icons.collections_outlined, size: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image(
        image: MatrixMxcImage(Uri.parse(url), mx,
            fullResHeight: 64,
            doThumbnail: false,
            doFullres: true,
            autoLoadFullRes: true),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.collections_outlined, size: size),
      ),
    );
  }
}

/// The dashed accent outline of a drop target.
class _DropOutline extends StatelessWidget {
  const _DropOutline(
      {required this.active, required this.child, this.radius = 8});

  final bool active;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return CustomPaint(
      foregroundPainter: _DashPainter(
          color: Theme.of(context).colorScheme.primary, radius: radius),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1), Radius.circular(radius)));
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.radius != radius;
}
