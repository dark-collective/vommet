import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'dart:async';
import 'package:commet/diagnostic/diagnostics.dart';
import 'package:commet/telemetry/experiments_telemetry.dart';
import 'package:commet/telemetry/repaint_stats.dart';
import 'package:commet/telemetry/crypto_state_telemetry.dart';
import 'package:commet/telemetry/notify_setup_telemetry.dart';
import 'package:commet/telemetry/init_timings_telemetry.dart';
import 'package:commet/telemetry/main_spans.dart';
import 'package:commet/telemetry/telemetry.dart';
import 'package:commet/telemetry/web_env_telemetry.dart';
import 'package:collection/collection.dart';
import 'package:commet/client/client.dart';
import 'package:commet/client/client_manager.dart';
import 'package:commet/ui/organisms/new_home/new_home_shortcuts.dart';
import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/donation_awards/donation_awards_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/profile/profile_component.dart';
import 'package:commet/client/components/voip/voip_component.dart';
import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/in_app_notification_banner.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/quick_switcher.dart';
import 'package:commet/ui/atoms/room_view_mode.dart';
import 'package:commet/ui/organisms/invitation_view/send_invitation.dart';
import 'package:commet/ui/pages/secure_setup/secure_setup_gate.dart';
import 'package:commet/ui/organisms/update_installed_dialog/update_installed_dialog.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/ui/pages/settings/donation_rewards_confirmation.dart';
import 'package:commet/ui/pages/settings/settings_page.dart';
import 'package:commet/ui/pages/setup/setup_page.dart';
import 'package:commet/ui/pages/setup/menus/welcome_setup.dart';
import 'package:commet/ui/pages/setup/onboarding/onboarding_setup.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:commet/utils/media_spoiler.dart';
import 'package:commet/utils/space_for_room.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/pages/main/last_room_per_space.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/ui/pages/main/main_page_view_mobile.dart';
import 'package:commet/ui/pages/setup/menus/unified_push_distributor_prompt.dart';
import 'package:commet/ui/pages/settings/room_settings_page.dart';
import 'package:commet/utils/first_time_setup.dart';
import 'package:commet/utils/image/lod_image.dart';
import 'package:commet/utils/notifying_list.dart';
import 'package:commet/utils/notifying_list_combiner.dart';
import 'package:commet/utils/notifying_list_filter.dart';
import 'package:commet/utils/custom_uri.dart';
import 'package:commet/utils/links/matrix_link.dart';
import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// Vommet: see the update-installed dialog in MainPageState.
const bool _showUpdateDonationDialog = false;

class MainPage extends StatefulWidget {
  const MainPage(this.clientManager,
      {super.key,
      this.initialClientId,
      this.initialRoom,
      this.wasLoggedInAtStartup = false});
  final ClientManager clientManager;
  final String? initialRoom;
  final String? initialClientId;
  final bool wasLoggedInAtStartup;

  @override
  State<MainPage> createState() => MainPageState();
}

enum MainPageSubView {
  space,
  home,
  rooms,
}

class MainPageState extends State<MainPage> {
  Space? _currentSpace;
  Room? _currentRoom;
  final LastRoomPerSpace _lastRoomInSpace = LastRoomPerSpace(
      saved: preferences.lastRoomPerSpace.value,
      onChanged: (json) => preferences.lastRoomPerSpace.set(json));
  bool showAsTextRoom = false;
  Client? filterClient;

  MainPageSubView _currentView = MainPageSubView.home;

  late INotifyingList<Room> favoriteRooms;

  late INotifyingList<Room> singleRooms;

  late INotifyingList<Room> directMessages;

  StreamSubscription? onSpaceUpdateSubscription;
  StreamSubscription? onRoomUpdateSubscription;
  StreamSubscription? onCallStartedSubscription;
  StreamSubscription? onClientRemovedSubscription;
  StreamSubscription? onRoomRemovedSubscription;
  StreamSubscription? onSpaceRemovedSubscription;
  StreamSubscription? onClientAddedSubscription;
  StreamSubscription? onMatrixLinkSubscription;

  StreamController onFilterClientChanged = StreamController.broadcast();

  MainPageSubView get currentView => _currentView;

  ClientManager get clientManager => widget.clientManager;

  Profile? get currentUser => getCurrentUser();
  Space? get currentSpace => _currentSpace;
  Room? get currentRoom => _currentRoom;

  VoipSession? get currentCall => currentRoom == null
      ? null
      : widget.clientManager.callManager
          .getCallInRoom(currentRoom!.client, currentRoom!.identifier);

  String get updateInstalledTitle => Intl.message("Update installed",
      desc:
          "Title for the dialog which is shown when an update has been installed",
      name: "updateInstalledTitle");

  @override
  void initState() {
    super.initState();

    Client? client;
    if (preferences.filterClient.value != null) {
      filterClient = clientManager.clients.firstWhereOrNull(
          (i) => i.identifier == preferences.filterClient.value);
    }

    if (widget.initialClientId != null) {
      client = clientManager.getClient(widget.initialClientId!);
    }

    if (client == null && widget.initialRoom != null) {
      client = clientManager.clients
          .where((element) => element.getRoom(widget.initialRoom!) != null)
          .firstOrNull;
    }

    if (client != null && widget.initialRoom != null) {
      var room = client.getRoom(widget.initialRoom!);

      if (filterClient == null || room?.client == filterClient) {
        if (room != null) {
          selectRoom(room);
        }
      }
    }

    var allFavoriteRooms = NotifyingListCombiner(
        clientManager.clients.map((i) => i.favoriteRooms).toList());

    favoriteRooms = NotifyingListFilter(allFavoriteRooms, where: (item) {
      if (filterClient == null) return true;
      return item.client == filterClient;
    }, onFilterParamsChanged: [onFilterClientChanged.stream]);

    directMessages = NotifyingListFilter(
        clientManager.directMessages.directMessageRooms, where: (item) {
      if (item.isFavorite) return false;

      if (filterClient == null) return true;
      return item.client == filterClient;
    }, onFilterParamsChanged: [
      onFilterClientChanged.stream,
      allFavoriteRooms.onListUpdated,
    ]);

    singleRooms = NotifyingListFilter(clientManager.rooms, where: (item) {
      // Vommet: a replaced room goes once you're in its replacement.
      if (isSupersededRoom(item)) return false;

      if (filterClient != null) {
        if (item.client != filterClient) return false;
      }
      var dms = item.client.getComponent<DirectMessagesComponent>();

      if (dms?.isRoomDirectMessage(item) != false) {
        return false;
      }

      if (item.client.spaces
          .any((space) => space.containsRoom(item.identifier))) {
        return false;
      }

      // Vommet: sticker rooms live under Settings › Emoticons.
      if (isStickerRoom(item)) return false;

      return true;
    }, onFilterParamsChanged: [
      onFilterClientChanged.stream,
      clientManager.onSpaceUpdated.stream,
      clientManager.rooms.onListUpdated
    ]);

    ServicesBinding.instance.keyboard.addHandler(_onKeyPressed);

    // backgroundTaskManager.onListUpdate.listen((event) {
    //   setState(() {});
    // });

    onCallStartedSubscription =
        clientManager.callManager.currentSessions.onListUpdated.listen((event) {
      setState(() {});
    });

    EventBus.openRoom.stream.listen(onOpenRoomSignal);

    EventBus.openSpace.stream.listen(onOpenSpaceSignal);

    EventBus.openHomeScreen.stream.listen((_) {
      clearRoomSelection();
      clearSpaceSelection();
    });

    EventBus.setFilterClient.stream.listen(setFilterClient);

    EventBus.openUserProfile.stream.listen(onOpenUserProfileSignal);

    // Vommet (#85): Matrix links opened from outside the app.
    onMatrixLinkSubscription =
        CustomURI.listenMatrixLinks(onExternalMatrixLink);

    onClientRemovedSubscription =
        clientManager.onClientRemoved.stream.listen(onClientRemoved);

    // Vommet: leave the pane of a room that left the list (a dismissed ban)
    onRoomRemovedSubscription = clientManager.onRoomRemoved.listen((room) {
      if (mounted && room == _currentRoom) clearRoomSelection();
    });
    onSpaceRemovedSubscription = clientManager.onSpaceRemoved.listen((space) {
      if (mounted && space == _currentSpace) clearSpaceSelection();
    });

    onClientAddedSubscription = clientManager.onClientAdded.stream.listen((_) {
      if (mounted) setState(() {});
    });

    SchedulerBinding.instance.scheduleFrameCallback(onFirstFrame);

    // Vommet: no resuming upstream's donation check, which polls
    // Commet's Stripe rewards service. Existing badges still display (#86).
  }

  void onFirstFrame(Duration timeStamp) async {
    _recordStartup();
    if (widget.clientManager.isLoggedIn()) {
      // Vommet: the welcome screen only until it has been seen once.
      var menus = FirstTimeSetup.postLogin
          .where((m) => m is! WelcomeSetup || !preferences.welcomeShown.value)
          .where((m) => m is! OnboardingMenu || !onboardingShown.value)
          .toList();
      if (menus.isNotEmpty) {
        await NavigationUtils.navigateTo(context, SetupPage(menus));
      }

      // Vommet: secure messaging setup before any room opens (issue 129).
      if (mounted) await SecureSetupGate.run(context, widget.clientManager);

      bool isNewVersion =
          preferences.lastOpenedVersion.value != BuildConfig.VERSION_TAG;

      preferences.lastOpenedVersion.set(BuildConfig.VERSION_TAG);

      // Vommet: upstream shows a "please donate" dialog after each update,
      // whose donation flow goes to commet.chat; the fork doesn't show it.
      if (_showUpdateDonationDialog &&
          !kIsWeb &&
          isNewVersion &&
          widget.wasLoggedInAtStartup) {
        await Future.delayed(Duration(seconds: 2));

        await AdaptiveDialog.show(
          context,
          title: updateInstalledTitle,
          builder: (buildContext) {
            return UpdateInstalledDialog(
              onDonateTapped: () => SettingsPage.onDonateButtonTapped(context),
            );
          },
        );
      }

      // Vommet: ask for a UnifiedPush distributor if none is chosen.
      if (mounted) await UnifiedPushDistributorPrompt.run(context);
    }
  }

  void _recordStartup() {
    final clients = widget.clientManager.clients;
    Telemetry.record("session_start", {
      "first_frame_ms": Telemetry.sinceStart,
      "accounts": clients.length,
      "experiments": ExperimentsTelemetry.enabled(),
    });
    // Vommet: web build only (null elsewhere).
    final webEnv = WebEnvTelemetry.fields();
    if (webEnv != null) Telemetry.record("web_env", webEnv);
    final syncs = clients
        .whereType<MatrixClient>()
        .map((c) => c.firstSync)
        .whereType<Future>()
        .toList();
    // Vommet: recorded from a timer, which runs after LoopLag's overdue
    // tick, so a blocked loop that held up the first sync is broken down in
    // `startup` already (Stall_*).
    Future.wait(syncs).then(
        (_) => Timer.run(() {
              Telemetry.record("app_ready", {
                "ms": Telemetry.sinceStart,
                "accounts": clients.length,
                "rooms": widget.clientManager.rooms.length,
                "spaces": widget.clientManager.spaces.length,
                "db_initial": Telemetry.dbTimers(
                    Diagnostics.initialLoadDatabaseDiagnostics),
                "db_postload":
                    Telemetry.dbTimers(Diagnostics.postLoadDatabaseDiagnostics),
                // Vommet: plus the SDK's Client.init steps (Init_*), then the UI
                // isolate's spans since launch (Stall_*, Main_*, Phase_*).
                "startup": MainSpans.appendSinceLaunch(
                    InitTimingsTelemetry.startupTimers()),
              });
              // Pushers are registered shortly after startup; check them a minute on.
              // The encryption setup (keys loaded, backup) is checked then too.
              Future.delayed(const Duration(minutes: 1), () {
                NotifySetupTelemetry.record(widget.clientManager);
                CryptoStateTelemetry.record(widget.clientManager);
              });
            }),
        onError: (_) {});
  }

  @override
  void dispose() {
    onSpaceUpdateSubscription?.cancel();
    onMatrixLinkSubscription?.cancel();
    onRoomUpdateSubscription?.cancel();
    onCallStartedSubscription?.cancel();
    onClientRemovedSubscription?.cancel();
    onRoomRemovedSubscription?.cancel();
    onSpaceRemovedSubscription?.cancel();
    onClientAddedSubscription?.cancel();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyPressed);
    super.dispose();
  }

  void onClientRemoved(dynamic event) {
    if (!mounted) return;

    setState(() {
      if (_currentRoom != null && !clientManager.rooms.contains(_currentRoom)) {
        _currentRoom = null;
      }

      if (_currentSpace != null &&
          !clientManager.spaces.contains(_currentSpace)) {
        _currentSpace = null;
        _currentView = MainPageSubView.home;
      }

      if (filterClient != null &&
          !clientManager.clients.contains(filterClient)) {
        filterClient = null;
        EventBus.setFilterClient.add(null);
        onFilterClientChanged.add(null);
      }
    });
  }

  Profile? getCurrentUser() {
    if (currentRoom != null) return currentRoom!.client.self!;

    if (currentSpace != null) return currentSpace!.client.self!;

    if (filterClient != null) return filterClient!.self!;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Vommet: which view the frame counter files frames under (names only).
    RepaintStats.mainView = _currentRoom != null
        ? RepaintView.room
        : _currentView == MainPageSubView.space
            ? RepaintView.space
            : RepaintView.home;
    // Vommet: listens for in-app notification banners while logged in.
    return InAppNotificationBannerHost(
      child: MediaQuery.of(context).mobile
          // Vommet: on iOS keep the mobile layout clear of side insets, e.g.
          // the iPhone Duo's status bar on the side of its closed screen.
          // Other platforms keep Commet's edge-to-edge mobile layout.
          ? ScaledSafeArea(
              top: false,
              bottom: false,
              left: PlatformUtils.isIOS,
              right: PlatformUtils.isIOS,
              child: MainPageViewMobile(this))
          : MainPageViewDesktop(this),
    );
  }

  void selectSpace(Space? space) {
    if (space == currentSpace) return;

    _rememberRoomInSpace();

    if (space != null && !space.fullyLoaded) space.loadExtra();
    clearRoomSelection();

    if (space?.avatar is LODImageProvider) {
      (space!.avatar as LODImageProvider).fetchFullRes();
    }

    onSpaceUpdateSubscription?.cancel();
    setState(() {
      _currentSpace = space;
      _currentView = MainPageSubView.space;
    });

    EventBus.onSelectedSpaceChanged.add(space);
  }

  /// Vommet: a space icon in the rail. Clicking the space you're already in
  /// goes back to its main page (selectSpace ignored it, so you stayed in
  /// the room).
  ///
  /// [restoreLastRoom]: switching to another space reopens the room you were
  /// in when you left it (Vommet issue 35).
  void openSpaceHome(Space space, {bool restoreLastRoom = false}) {
    if (space == currentSpace) {
      if (currentRoom != null) clearRoomSelection();
      return;
    }
    selectSpace(space);
    if (restoreLastRoom) _restoreRoomInSpace(space);
  }

  static bool _spaceHasRoom(Space space, String roomId) =>
      space.roomsWithChildren.any((r) => r.identifier == roomId);

  /// Vommet: note where you were in the space you're leaving.
  void _rememberRoomInSpace() {
    if (!preferences.experimentLastRoomPerSpace.value) return;
    final space = currentSpace;
    if (space == null) return;
    final room = currentRoom;
    _lastRoomInSpace.leave(space.client.identifier, space.identifier,
        roomId: room?.identifier,
        roomInSpace: room != null && _spaceHasRoom(space, room.identifier),
        textView: showAsTextRoom);
  }

  void _restoreRoomInSpace(Space space) {
    if (!preferences.experimentLastRoomPerSpace.value) return;
    final last =
        _lastRoomInSpace.lookup(space.client.identifier, space.identifier);
    // The room may have been left or moved out of the space since.
    if (last == null || !_spaceHasRoom(space, last.roomId)) return;
    final room = space.client.getRoom(last.roomId);
    if (room == null) return;
    selectRoom(room, bypassSpecialRoomType: last.textView);
  }

  void selectRoom(Room room, {bool bypassSpecialRoomType = false}) {
    if (room == currentRoom && bypassSpecialRoomType == showAsTextRoom) return;

    onRoomUpdateSubscription?.cancel();

    // Vommet: switching rooms (not just call/chat view) covers revealed
    // media spoilers again, like Telegram.
    if (room != currentRoom) {
      MediaSpoilerReveal.leftRoom(
          rehide: preferences.rehideMediaSpoilers.value);
    }

    setState(() {
      _currentRoom = room;
      showAsTextRoom = bypassSpecialRoomType;
    });
    // Vommet: for the room header's call/chat switch.
    RoomViewMode.showingText.value = bypassSpecialRoomType;

    EventBus.selectedRoom = room;
    EventBus.onSelectedRoomChanged.add(room);
    EventBus.onSelectedSpaceChanged.add(currentSpace);
  }

  void clearRoomSelection() {
    onRoomUpdateSubscription?.cancel();
    MediaSpoilerReveal.leftRoom(rehide: preferences.rehideMediaSpoilers.value);
    setState(() {
      _currentRoom = null;
    });

    EventBus.selectedRoom = null;
    EventBus.onSelectedRoomChanged.add(null);
  }

  void clearSpaceSelection() {
    _rememberRoomInSpace();
    setState(() {
      clearRoomSelection();

      _currentSpace = null;
      _currentView = MainPageSubView.home;
    });

    EventBus.onSelectedSpaceChanged.add(null);
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;

      if (event != null) {
        if (_currentRoom?.client != event) {
          clearRoomSelection();
        }

        if (_currentSpace != null && _currentSpace?.client != event) {
          clearSpaceSelection();
        }
      }
    });

    onFilterClientChanged.add(null);
  }

  void callRoom(Room room) {
    var component = room.client.getComponent<VoipComponent>();
    if (component == null) {
      return;
    }

    var direct = room.client.getComponent<DirectMessagesComponent>();
    if (direct == null) {
      Log.w("VOIP Only supports direct messages!!");
      return;
    }

    var partner = direct.getDirectMessagePartnerId(room);

    component.startCall(room.identifier, CallType.voice, userId: partner);
  }

  void selectHome() {
    setState(() {
      _currentView = MainPageSubView.home;
      clearSpaceSelection();
    });
  }

  void selectRoomsView() {
    if (newHomeOpenRooms(this)) return;
    setState(() {
      clearSpaceSelection();
      _currentView = MainPageSubView.rooms;
    });
  }

  // Vommet: open a space from elsewhere (mutual spaces on a profile).
  void onOpenSpaceSignal((String, String) args) {
    final client = clientManager.getClient(args.$2);
    final space = client?.getSpace(args.$1);
    if (client == null || space == null) return;

    if (filterClient != null && client != filterClient) {
      EventBus.setFilterClient.add(client);
      preferences.filterClient.set(client.identifier);
    }

    selectSpace(space);
  }

  void onOpenRoomSignal(RoomOpenArgs args) async {
    var roomId = args.roomId;
    var clientId = args.clientId;
    var bypassSpecialRoomType = args.bypassSpecialRoomTypes;

    var originalId = roomId;

    Client? client;

    if (clientId != null) {
      client = clientManager.getClient(clientId);

      if (client is MatrixClient) {
        var info = client.parseAddressToIdAndVia(roomId);
        if (info != null) {
          roomId = info.$1;
        }
      }
    } else {
      client = clientManager.clients
          .where((element) => element.hasRoom(roomId))
          .firstOrNull;
    }

    if (client == null) {
      return;
    }

    if (filterClient != null && client != filterClient) {
      askSwitchAccount(client, (args.roomId, args.clientId));
      return;
    }

    var room = client.getRoom(roomId);

    if (room == null) {
      room = client.getRoomByAlias(roomId);
    }

    if (room != null) {
      if (preferences.automaticallyOpenSpace.value && args.openInSpace) {
        // Vommet: by the room's id; roomId may still be an alias here.
        // Vommet (issue 307): the top-level space, not a subspace.
        var roomSpace =
            spaceForRoom(client.spaces, room.identifier, current: currentSpace);

        if (roomSpace != null) {
          selectSpace(roomSpace);
        }
      }

      selectRoom(room, bypassSpecialRoomType: bypassSpecialRoomType);
      return;
    }

    // Vommet: a link to a space you're already in opens that space.
    var space = client.getSpace(roomId);
    if (space == null && client is MatrixClient) {
      space = client.getSpaceByAlias(roomId);
    }

    if (space != null) {
      if (space == currentSpace) {
        clearRoomSelection();
      } else {
        selectSpace(space);
      }
    } else {
      GetOrCreateRoom.show(client, context,
          pickExisting: false,
          showAllRoomTypes: false,
          initialRoomAddress: originalId);
    }
  }

  Future<void> askSwitchAccount(
      Client newClient, (String, String?) strings) async {
    var confirm = await AdaptiveDialog.confirmation(context,
        prompt:
            "You tried to open a room for another account (${newClient.self?.identifier}), would you like to switch?",
        title: "Switch Account");
    if (confirm != true) return;

    EventBus.setFilterClient.add(newClient);
    preferences.filterClient.set(newClient.identifier);
    EventBus.doOpenRoom(strings.$1, clientId: strings.$2);
  }

  void navigateRoomSettings() {
    if (currentRoom != null) {
      NavigationUtils.navigateTo(
          context,
          RoomSettingsPage(
            room: currentRoom!,
            contextSpace: currentSpace,
            onLeaveRoom: clearRoomSelection,
          ));
    }
  }

  Future<void> onExternalMatrixLink(Uri uri) async {
    final target = MatrixLinkTarget.parse(uri);
    if (target == null || clientManager.clients.isEmpty) return;

    // Let the accounts finish their first sync, so a room you're already in
    // opens instead of the join dialog.
    try {
      await Future.wait(clientManager.clients
              .whereType<MatrixClient>()
              .map((c) => c.firstSync)
              .whereType<Future>())
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
    if (!mounted) return;

    Client? client;
    if (target.kind != MatrixLinkKind.user) {
      client = clientManager.clients.firstWhereOrNull((c) =>
          c.getRoom(target.identifier) != null ||
          c.getRoomByAlias(target.identifier) != null);
    }
    client ??= filterClient;
    client ??= await AdaptiveDialog.pickClient(context);
    if (client == null || !mounted) return;

    Log.i("Opening Matrix link for ${client.identifier}: $uri");
    if (target.kind == MatrixLinkKind.user) {
      EventBus.openUserProfile
          .add((target.identifier, client.identifier, null));
    } else {
      EventBus.doOpenRoom(target.roomAddress, clientId: client.identifier);
    }
  }

  void onOpenUserProfileSignal((String, String, String?) event) {
    var userId = event.$1;
    var clientId = event.$2;

    var client = clientManager.getClient(clientId);
    if (client != null) {
      UserProfile.show(context, client: client, userId: userId);
    }
  }

  void checkDonationFlow() async {
    var donationCheck = preferences.runningDonationCheckFlow;
    if (donationCheck != null) {
      var client = clientManager.getClient(donationCheck.$1);

      Log.i(
        "Resuming donation flow for user: ${client?.self?.identifier}",
      );

      if (client != null) {
        var secret = await client
            .getComponent<DonationAwardsComponent>()
            ?.getClientSecret();
        if (secret != null) {
          AdaptiveDialog.show(context,
              builder: (context) => DonationRewardsConfirmation(
                    client: client,
                    identifier: secret,
                    didOpenDonationWindow: true,
                    since: donationCheck.$2,
                  ),
              dismissible: false);
        }
      }
    }
  }

  void searchUserToDm() async {
    var client = filterClient;
    if (client == null) client = await AdaptiveDialog.pickClient(context);

    if (client == null) {
      return;
    }

    final invitation = client.getComponent<InvitationComponent>();
    if (invitation == null) return;

    AdaptiveDialog.show(context,
        builder: (context) => SendInvitationWidget(
              client!,
              invitation,
              showSuggestions: false,
              onUserPicked: (userId) async {
                final confirm = await AdaptiveDialog.confirmation(context,
                    prompt: "Are you sure you want to invite $userId to chat?",
                    title: "Invitation");
                if (confirm != true) {
                  return;
                }

                var comp = client!.getComponent<DirectMessagesComponent>();
                await comp?.createDirectMessage(userId);
              },
            ),
        title: "Start Direct Message");
  }

  bool _onKeyPressed(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyK &&
          ServicesBinding.instance.keyboard.isControlPressed) {
        QuickSwitcher.show(context);
      }
    }

    // Vommet issues 290/499/606: Alt+Up/Down, Alt+Shift+Up/Down and
    // Ctrl+PgUp/PgDown switch rooms.
    if (RoomListNavigation.handleKey(event, currentRoom, selectRoom)) {
      return true;
    }

    return false;
  }
}
