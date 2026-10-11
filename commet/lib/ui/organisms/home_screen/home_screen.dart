import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/navigation/quick_switcher.dart';
import 'package:commet/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/ui/organisms/home_screen/home_screen_view.dart';
import 'package:commet/utils/update_checker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HomeScreen extends StatefulWidget {
  final ClientManager clientManager;
  final Client? filterClient;
  final int numRecentRooms;
  final void Function()? onBurgerMenuTap;
  const HomeScreen({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onBurgerMenuTap,
    this.numRecentRooms = 5,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static bool _reportedRoomListOnScreen = false;

  late List<Room> recentActivity;

  Client? filterClient;

  late List<StreamSubscription> subscriptions;

  @override
  void initState() {
    filterClient = widget.filterClient;

    // Vommet: what users feel at startup: the room list on screen (from the
    // local cache). Replaces a "first sync done" timer, which mostly measured
    // the sync long-poll waiting for news.
    if (!_reportedRoomListOnScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_reportedRoomListOnScreen) return;
        if (widget.clientManager.rooms.isEmpty) return;
        _reportedRoomListOnScreen = true;
        Diagnostics.general.addResult(
            "Startup: room list on screen (since launch)",
            startupClock.elapsed);
      });
    }

    subscriptions = [
      widget.clientManager.onSync.stream.listen(onSync),
      widget.clientManager.onClientRemoved.stream.listen((_) {
        setState(() {
          updateRecent();
        });
      }),
      EventBus.setFilterClient.stream.listen(setFilterClient),
    ];

    if (preferences.checkForUpdates.value == true) {
      UpdateChecker.checkForUpdates();
    }

    updateRecent();
    super.initState();
  }

  @override
  void dispose() {
    for (var element in subscriptions) {
      element.cancel();
    }

    super.dispose();
  }

  void onSync(void event) {
    Future.delayed(Duration(seconds: 1)).then((_) {
      // Vommet: the home screen may be gone by now (e.g. a room was opened)
      if (!mounted) return;
      setState(() {
        updateRecent();
      });
    });
  }

  void updateRecent() {
    recentActivity =
        List.from(filterClient?.rooms ?? widget.clientManager.rooms);

    recentActivity.removeWhere((element) => element.lastEvent == null);
    // Vommet: sticker rooms live under Settings › Emoticons.
    recentActivity.removeWhere(isStickerRoom);

    mergeSort(recentActivity, compare: (a, b) {
      return b.lastEventTimestamp.compareTo(a.lastEventTimestamp);
    });

    if (recentActivity.length > widget.numRecentRooms) {
      recentActivity = recentActivity.sublist(0, widget.numRecentRooms);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (MediaQuery.of(context).mobile)
          tiamat.Tile.low(
            caulkClipBottomRight: true,
            caulkClipBottomLeft: true,
            caulkBorderBottom: true,
            child: ScaledSafeArea(
              bottom: false,
              left: false,
              right: false,
              child: SizedBox(
                height: 50,
                child: HeaderView(
                  showBurger: MediaQuery.of(context).mobile,
                  onBurgerMenuTap: widget.onBurgerMenuTap,
                  text: CommonStrings.promptHome,
                  menu: SizedBox(
                      width: 50,
                      height: 50,
                      child: tiamat.IconButton(
                        icon: Icons.search,
                        onPressed: () => QuickSwitcher.show(context),
                      )),
                ),
              ),
            ),
          ),
        // Vommet: "Your messages aren't backed up" (Vommet issue 129).
        const SecureSetupBanner(),
        if (MediaQuery.of(context).desktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(8),
              color: ColorScheme.of(context).surfaceContainerLow,
              child: InkWell(
                onTap: () => QuickSwitcher.show(context),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(spacing: 8, children: [
                        Icon(Icons.search),
                        tiamat.Text.labelLow(CommonStrings.promptSearch),
                      ]),
                      if (MediaQuery.of(context).desktop)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                          child: tiamat.Text.labelLow("Ctrl + K"),
                        )
                    ],
                  ),
                ),
              ),
            ),
          ),
        Flexible(
          // Vommet: HomeScreenView is a CustomScrollView now, so only the
          // room rows on screen get built (see HomeScreenView.build).
          child: HomeScreenView(
            header: IncomingInvitationsWidget(widget.clientManager),
            clientManager: widget.clientManager,
            rooms: widget.clientManager.singleRooms(filterClient: filterClient),
            recentActivity: recentActivity,
            onRoomClicked: (room) => EventBus.doOpenRoom(room.identifier,
                clientId: room.client.identifier),
            joinRoom: joinRoom,
            createRoom: createRoom,
          ),
        ),
      ],
    );
  }

  Future<void> joinRoom(Client client, String address) async {
    await client.joinRoom(address);
  }

  Future<void> createRoom(Client client, CreateRoomArgs args) async {
    await client.createRoom(args);
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;
      updateRecent();
    });
  }
}
