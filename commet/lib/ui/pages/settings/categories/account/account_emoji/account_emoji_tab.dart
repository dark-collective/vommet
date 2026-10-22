import 'dart:async';
import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/pages/settings/categories/account/account_emoji/account_emoji_view.dart';
import 'package:commet/ui/pages/settings/categories/account/account_emoji/personal_pack_settings.dart';
import 'package:commet/ui/pages/settings/categories/account/account_emoji/sticker_rooms_panel.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:commet/utils/current_account.dart';
import 'package:flutter/widgets.dart';

import '../../../../../molecules/account_selector.dart';

class AccountEmojiTab extends StatefulWidget {
  const AccountEmojiTab(
      {required this.clientManager, this.selectedClientIndex, super.key});
  final ClientManager clientManager;

  /// Account to open on; the current account (see [currentAccount]) if null.
  final int? selectedClientIndex;
  @override
  State<AccountEmojiTab> createState() => _AccountEmojiTabState();
}

class _AccountEmojiTabState extends State<AccountEmojiTab> {
  Client? selectedClient;
  EmoticonComponent? component;

  // Vommet: rebuild when packs change, so the personal packs room's section
  // appears as soon as the first extra personal pack is created.
  StreamSubscription? sub;

  @override
  void initState() {
    final index = widget.selectedClientIndex;
    selectedClient = index != null
        ? widget.clientManager.clients[index]
        : currentAccount(
            widget.clientManager.clients, preferences.filterClient.value);
    component = selectedClient!.getComponent<EmoticonComponent>();
    listen();
    super.initState();
  }

  void listen() {
    sub?.cancel();
    sub = component?.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.clientManager.clients.length > 1)
          AccountSelector(
            widget.clientManager.clients,
            initialClient: selectedClient,
            onClientSelected: (client) {
              setState(() {
                selectedClient = client;
                component = selectedClient!.getComponent<EmoticonComponent>();
                listen();
              });
            },
          ),
        const SizedBox(
          height: 10,
        ),
        buildEmojiView(context)
      ],
    );
  }

  Widget buildEmojiView(BuildContext context) {
    if (component == null) {
      return const Placeholder();
    }

    return Column(
      // I dont love using a key here, is there a better way to do this? i dont know
      key: ValueKey("account_emoji_editor_key_${selectedClient!.identifier}"),
      children: [
        // Vommet: Import pack / New pack. New packs go to a sticker room
        // unless "Use a personal pack" (Advanced) is on and there's none.
        RoomEmojiPackSettingsView(
          component: component!,
          editable: true,
          showPacks: false,
        ),
        // Vommet: sticker rooms, where packs live.
        StickerRoomsPanel(
          key: ValueKey("sticker_rooms_${selectedClient!.identifier}"),
          account: component!,
        ),
        // Vommet: an existing personal pack always shows, switch or not.
        if (component!.ownedPacks.isNotEmpty)
          PersonalPackPanel(
            key: ValueKey("personal_pack_${selectedClient!.identifier}"),
            account: component!,
          ),
        const SizedBox(
          height: 5,
        ),
        if (AccountEmojiView.favouritesOutsideStickerRooms(component!)
            .isNotEmpty)
          AccountEmojiView(component!),
        const EmoticonAdvancedSettings(),
      ],
    );
  }

  Future<void> createPack(String name, Uint8List? avatarData) {
    return component!.createEmoticonPack(name, avatarData);
  }

  Future<void> deleteEmoticon(EmoticonPack pack, Emoticon emoticon) {
    return pack.deleteEmoticon(emoticon);
  }

  Future<void> deletePack(EmoticonPack pack) {
    return component!.deleteEmoticonPack(pack);
  }
}
