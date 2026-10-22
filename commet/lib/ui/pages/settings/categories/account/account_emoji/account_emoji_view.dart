import 'dart:async';

import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountEmojiView extends StatefulWidget {
  const AccountEmojiView(this.component, {super.key});
  final EmoticonComponent component;

  /// Vommet: favourites minus the packs in your sticker rooms, which are
  /// listed (with their heart) under Sticker rooms already. Vommet
  /// favourites every pack it creates there.
  static List<EmoticonPack> favouritesOutsideStickerRooms(
      EmoticonComponent account) {
    final rooms = account.stickerRoomComponents;
    return account
        .globalPacks()
        .where((p) => !rooms.any((r) => r.ownedPacks.contains(p)))
        .toList();
  }

  @override
  State<AccountEmojiView> createState() => _AccountEmojiViewState();
}

class _AccountEmojiViewState extends State<AccountEmojiView> {
  late List<EmoticonPack> globalPacks;
  StreamSubscription? sub;

  @override
  void initState() {
    sub = widget.component.onStateChanged.listen((_) => updateState());
    updateState();
    super.initState();
  }

  void updateState() {
    // Vommet: the component can change after this page closed.
    if (!mounted) return;
    setState(() {
      globalPacks =
          AccountEmojiView.favouritesOutsideStickerRooms(widget.component);
    });
  }

  // Vommet: upstream never cancelled this subscription.
  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        tiamat.Panel(
          header: "Favorite Packs",
          mode: tiamat.TileType.surfaceContainerLow,
          child:
              Column(children: globalPacks.map((e) => packSummary(e)).toList()),
        ),
      ],
    );
  }

  Widget packSummary(EmoticonPack pack) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (pack.image != null)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Image(
                      image: pack.image!,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(pack.displayName),
                      tiamat.Text.labelLow(preferences.developerMode.value
                          ? "${pack.ownerDisplayName} - (${pack.ownerId})"
                          : pack.ownerDisplayName),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: tiamat.IconButton(
                icon: Icons.heart_broken,
                onPressed: () => pack.markAsGlobal(false),
              ),
            )
          ],
        ),
      ),
    );
  }
}
