// Vommet: the main page with the Telegram-style unified chat list instead of
// the space rail and Home (Vommet issue 291, experiment
// experiment_unified_chat_list). MainPageViewDesktop/-Mobile hand over to
// these when the experiment is on; the room view itself is unchanged.
import 'dart:async';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/room_preview.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:commet/ui/atoms/drag_drop_file_target.dart';
import 'package:commet/ui/atoms/room_header.dart';
import 'package:commet/ui/atoms/room_text_button.dart';
import 'package:commet/ui/atoms/scaled_safe_area.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:commet/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_list_view.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/unified_chat_source.dart';
import 'package:commet/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:commet/ui/pages/main/main_page.dart';
import 'package:commet/ui/pages/main/main_page_view_desktop.dart';
import 'package:commet/ui/pages/main/room_primary_view.dart';
import 'package:commet/ui/pages/settings/app_settings_page.dart';
import 'package:commet/ui/pages/settings/space_settings_page.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The open space path, kept per main page so it survives switching between
/// the phone and desktop layouts.
final Expando<SpaceNavigation> _navigations = Expando();

SpaceNavigation _navigationFor(MainPageState state) =>
    _navigations[state] ??= SpaceNavigation();

/// What both layouts share: the source, the open space, search, and the
/// actions behind each tap.
mixin _UnifiedChatPage<T extends StatefulWidget> on State<T> {
  MainPageState get page;

  late final UnifiedChatSource source;
  late final SpaceNavigation nav;
  final TextEditingController search = TextEditingController();

  void onRoomOpened() {}

  @override
  void initState() {
    super.initState();
    source =
        UnifiedChatSource(page.clientManager, filterClient: page.filterClient);
    nav = _navigationFor(page);
    source.addListener(_onSourceChanged);
    nav.addListener(_onNavChanged);
    _onSourceChanged();
  }

  @override
  void dispose() {
    source.removeListener(_onSourceChanged);
    nav.removeListener(_onNavChanged);
    source.dispose();
    search.dispose();
    super.dispose();
  }

  void _onSourceChanged() {
    nav.prune((path) => isValidSpacePath(source.rows, path));
    if (mounted) setState(() {});
  }

  void _onNavChanged() {
    final key = nav.current;
    if (key != null) source.ensureSpaceLoaded(key);
    if (mounted) setState(() {});
  }

  SpaceEntry? get openSpace {
    final key = nav.current;
    return key == null ? null : source.spaces[key];
  }

  String? get openSpaceParentName {
    final key = nav.parent;
    return key == null ? null : source.spaces[key]?.name;
  }

  String? get selectedKey => page.currentRoom?.localId;

  void openRow(TopRow row) {
    switch (row) {
      case ChatTopRow(:final chat):
        nav.close();
        openChat(chat);
      case SpaceTopRow(:final space):
        nav.openRoot(space.key);
    }
  }

  void openChat(ChatEntry chat) {
    final room = chat.source;
    if (room is! Room) return;
    page.selectRoom(room);
    onRoomOpened();
  }

  Future<void> joinVoice(ChatEntry chat) async {
    final room = chat.source;
    if (room is! Room) return;
    openChat(chat);
    final voip = room.getComponent<VoipRoomComponent>();
    if (voip == null || !voip.canJoinCall || voip.currentSession != null) {
      return;
    }
    try {
      await voip.joinCall();
    } catch (e, s) {
      Log.onError(e, s);
      if (mounted) AdaptiveDialog.showError(context, e, s);
    }
  }

  Future<void> joinPreview(ChatPreviewEntry entry) async {
    final preview = entry.source;
    final space = openSpace?.source;
    if (preview is! RoomPreview || space is! Space) return;

    final confirm = await AdaptiveDialog.confirmation(context,
        prompt: "Are you sure you want to join the room '${entry.name}' ?");
    if (confirm != true) return;

    try {
      final room = await space.client.joinRoomFromPreview(preview);
      page.selectRoom(room);
      onRoomOpened();
    } catch (e, s) {
      Log.onError(e, s);
      if (mounted) AdaptiveDialog.showError(context, e, s);
    }
  }

  void openSubspace(SpaceEntry sub) => nav.drillInto(sub.key);

  void openMenu() =>
      NavigationUtils.navigateTo(context, const AppSettingsPage());

  void openSpaceSettings() {
    final space = openSpace?.source;
    if (space is Space) {
      NavigationUtils.navigateTo(context, SpaceSettingsPage(space: space));
    }
  }

  void openInvitations() {
    AdaptiveDialog.show(context,
        title: "Invitations",
        builder: (_) => IncomingInvitationsWidget(page.clientManager));
  }

  Future<void> compose() async {
    final action = await AdaptiveDialog.show<String>(context,
        title: "New chat",
        builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (key, icon, text) in const [
                ("dm", Icons.person_add_alt_1, "New direct message"),
                ("room", Icons.tag, "New room"),
                ("space", Icons.workspaces_outline, "New space"),
              ])
                ListTile(
                    leading: Icon(icon),
                    title: Text(text),
                    onTap: () => Navigator.of(context).pop(key)),
            ]));
    if (!mounted) return;

    switch (action) {
      case "dm":
        page.searchUserToDm();
      case "room":
        GetOrCreateRoom.show(null, context,
            pickExisting: false, showAllRoomTypes: true);
      case "space":
        GetOrCreateRoom.show(null, context,
            pickExisting: false, createSpace: true);
    }
  }

  String? get invitationSubtitle {
    final invites = source.invitations;
    if (invites.isEmpty) return null;
    final first = invites.first.$2;
    final name = first.displayName ?? first.roomId;
    return invites.length == 1 ? name : "$name and ${invites.length - 1} more";
  }

  Widget wrapChatRow(TopRow row, Widget child) {
    if (row case ChatTopRow(:final chat)) return wrapRoom(chat, child);
    return child;
  }

  Widget wrapRoom(ChatEntry chat, Widget child) {
    final room = chat.source;
    if (room is! Room) return child;
    return AdaptiveContextMenu(
        items: RoomTextButton.createRoomContextMenuItems(context, room),
        child: child);
  }

  Widget chatListPane() => ChatListPane(
        rows: source.rows,
        search: search,
        now: DateTime.now(),
        selectedKey: selectedKey,
        alerts: source.alerts,
        invitationCount: source.invitations.length,
        invitationSubtitle: invitationSubtitle,
        onMenu: openMenu,
        onCompose: compose,
        onInvitations: openInvitations,
        onDismissAlert: source.dismissAlert,
        onRowTap: openRow,
        wrapRow: wrapChatRow,
      );

  Widget spacePane(SpaceEntry space) => SpacePane(
        key: ValueKey("unified-space-pane-${space.key}"),
        space: space,
        now: DateTime.now(),
        parentName: openSpaceParentName,
        selectedKey: selectedKey,
        onBack: nav.back,
        onMenu: openSpaceSettings,
        onRoomTap: openChat,
        onJoinVoice: joinVoice,
        onPreviewTap: joinPreview,
        onSubspaceTap: openSubspace,
        wrapRoom: wrapRoom,
      );
}

/// Desktop: the list on the left (folding into an avatar column beside an
/// open space), the chat on the right.
class UnifiedMainPageDesktop extends StatefulWidget {
  const UnifiedMainPageDesktop(this.state, {super.key});
  final MainPageState state;

  static const double paneWidth = 400;

  @override
  State<UnifiedMainPageDesktop> createState() => _UnifiedMainPageDesktopState();
}

class _UnifiedMainPageDesktopState extends State<UnifiedMainPageDesktop>
    with _UnifiedChatPage {
  @override
  MainPageState get page => widget.state;

  @override
  Widget build(BuildContext context) {
    final room = page.currentRoom;
    return tiamat.Foundation(
      child: Stack(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: UnifiedMainPageDesktop.paneWidth,
            child: Column(children: [
              Expanded(
                child: Tile.surfaceContainer(
                  caulkPadTop: true,
                  caulkClipTopRight: true,
                  caulkClipBottomRight: true,
                  child: ScaledSafeArea(
                      top: true, bottom: false, child: leftPane()),
                ),
              ),
              Tile.low(
                caulkPadTop: true,
                caulkClipTopRight: true,
                caulkBorderTop: true,
                child: ScaledSafeArea(
                  top: false,
                  child: CurrentSessionPanel(currentUser: page.currentUser),
                ),
              ),
            ]),
          ),
          if (room != null)
            MainPageViewDesktop(page).roomChatView()
          else
            Expanded(child: emptyChat(context)),
        ]),
        if (room != null)
          DragDropFileTarget(
              onDropComplete: (details) => EventBus.onFileDropped.add(details)),
        const BackgroundTaskViewContainer(),
        const OverlayWindowsSurface(),
      ]),
    );
  }

  Widget leftPane() {
    final space = openSpace;
    if (space == null) return chatListPane();

    return Row(children: [
      FoldedChatColumn(
        rows: source.rows,
        selectedKey: nav.root,
        onMenu: openMenu,
        onRowTap: openRow,
      ),
      VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant),
      Expanded(child: spacePane(space)),
    ]);
  }
}

Widget emptyChat(BuildContext context) => Tile(
      caulkPadLeft: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      caulkPadTop: true,
      caulkPadBottom: true,
      child: Center(
        child: tiamat.Text.labelLow("Pick a chat to start talking"),
      ),
    );

/// Phone: the list (or an open space) fills the screen; a chat slides over
/// it, and Back returns to the list.
class UnifiedMainPageMobile extends StatefulWidget {
  const UnifiedMainPageMobile(this.state, {super.key});
  final MainPageState state;

  @override
  State<UnifiedMainPageMobile> createState() => _UnifiedMainPageMobileState();
}

class _UnifiedMainPageMobileState extends State<UnifiedMainPageMobile>
    with _UnifiedChatPage {
  @override
  MainPageState get page => widget.state;

  final GlobalKey<OverlappingPanelsState> panelsKey = GlobalKey();
  bool shouldMainIgnoreInput = false;
  final List<StreamSubscription> subs = [];

  RevealSide? get side => panelsKey.currentState?.currentSide;

  @override
  void initState() {
    super.initState();
    subs.addAll([
      EventBus.openThread.stream
          .listen((_) => panelsKey.currentState?.reveal(RevealSide.right)),
      EventBus.closeThread.stream
          .listen((_) => panelsKey.currentState?.reveal(RevealSide.main)),
      EventBus.focusTimeline.stream
          .listen((_) => panelsKey.currentState?.reveal(RevealSide.main)),
      EventBus.openRoom.stream.listen((a) => panelsKey.currentState
          ?.reveal(a.threadId == null ? RevealSide.main : RevealSide.right)),
    ]);

    // Start on the list, like Telegram, unless a chat is already open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && page.currentRoom == null) {
        panelsKey.currentState?.reveal(RevealSide.left);
      }
    });
  }

  @override
  void dispose() {
    for (final sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void onRoomOpened() {
    panelsKey.currentState?.reveal(RevealSide.main);
    setState(() => shouldMainIgnoreInput = false);
  }

  bool canPop() => (side == RevealSide.left || side == null) && !nav.isOpen;

  void onPop() {
    final event = ScopePopped()..currentMobileSide = side;
    EventBus.onPopInvoked.add(event);
    if (event.handled) return;

    switch (side) {
      case RevealSide.right:
        panelsKey.currentState?.reveal(RevealSide.main);
      case RevealSide.main:
        panelsKey.currentState?.reveal(RevealSide.left);
      case RevealSide.left:
      case null:
        nav.back();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onPop();
      },
      child: Foundation(
        child: Stack(children: [
          OverlappingPanels(
            key: panelsKey,
            onSideChange: (side) {
              if (side != RevealSide.main) {
                FocusManager.instance.primaryFocus?.unfocus();
              }
              setState(() => shouldMainIgnoreInput = side != RevealSide.main);
            },
            left: navigation(),
            main: Foundation(
              child: IgnorePointer(
                ignoring: shouldMainIgnoreInput,
                child: mainPanel(),
              ),
            ),
            right: rightPanel(),
          ),
          const OverlayWindowsSurface(),
        ]),
      ),
    );
  }

  Widget navigation() {
    final space = openSpace;
    return Material(
      color: Colors.transparent,
      child: Column(children: [
        Expanded(
          child: Tile.surfaceContainer(
            caulkClipTopRight: true,
            caulkClipBottomRight: true,
            caulkPadRight: true,
            child: ScaledSafeArea(
              top: true,
              bottom: false,
              child: space == null ? chatListPane() : spacePane(space),
            ),
          ),
        ),
        const BackgroundTaskViewContainer(),
        tiamat.Tile.low(
          caulkPadTop: true,
          caulkClipTopRight: true,
          caulkBorderTop: true,
          caulkPadRight: true,
          child: ScaledSafeArea(
            bottom: true,
            top: false,
            child: CurrentSessionPanel(currentUser: page.currentUser),
          ),
        ),
      ]),
    );
  }

  Widget mainPanel() {
    final room = page.currentRoom;
    if (room == null) {
      return Tile(
        child: ScaledSafeArea(
          child: Center(
              child: tiamat.Text.labelLow("Pick a chat to start talking")),
        ),
      );
    }

    return Tile(
      key: ValueKey("room-chat-view-${room.localId}"),
      child: Column(children: [
        Tile.low(
          caulkClipBottomRight: true,
          caulkClipBottomLeft: true,
          caulkBorderBottom: true,
          child: ScaledSafeArea(
            bottom: false,
            left: false,
            right: false,
            child: SizedBox(
              height: 50,
              child: RoomHeader(
                room,
                onTap: room.permissions.canEditAnything
                    ? () => page.navigateRoomSettings()
                    : null,
                menu: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: tiamat.IconButton(
                      icon: Icons.chevron_right,
                      onPressed: () =>
                          panelsKey.currentState?.reveal(RevealSide.right),
                    ),
                  ),
                ),
                onBurgerMenuTap: () =>
                    panelsKey.currentState?.reveal(RevealSide.left),
              ),
            ),
          ),
        ),
        Expanded(
          child: RoomPrimaryView(room,
              bypassSpecialRoomTypes: page.showAsTextRoom),
        ),
      ]),
    );
  }

  Widget? rightPanel() {
    final room = page.currentRoom;
    if (room == null) return null;
    return Tile(
      caulkPadLeft: true,
      caulkClipTopLeft: true,
      caulkClipBottomLeft: true,
      child: Column(children: [
        Tile.low(
          child: ScaledSafeArea(
              bottom: false,
              top: true,
              left: false,
              right: false,
              child: Container()),
        ),
        Expanded(
          child: RoomSidePanel(
              key: ValueKey("room-side-panel-${room.localId}"), state: page),
        ),
      ]),
    );
  }
}
