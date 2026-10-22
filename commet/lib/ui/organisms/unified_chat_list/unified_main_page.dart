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
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:commet/ui/molecules/current_session_panel.dart';
import 'package:commet/ui/molecules/overlapping_panels.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/navigation/navigation_utils.dart';
import 'package:commet/ui/organisms/background_task_view/background_task_view_container.dart';
import 'package:commet/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:commet/ui/organisms/overlay_windows/overlay_window_manager.dart';
import 'package:commet/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_model.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_settings.dart';
import 'package:commet/ui/organisms/unified_chat_list/chat_folders_view.dart';
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
import 'package:commet/utils/room_list_navigation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/foundation.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The open space path, kept per main page so it survives switching between
/// the phone and desktop layouts.
final Expando<SpaceNavigation> _navigations = Expando();

SpaceNavigation _navigationFor(MainPageState state) =>
    _navigations[state] ??= SpaceNavigation();

/// The folder tab picked and whether the archive is open (phase 2), kept
/// per main page like the open space.
class ChatListNavigation extends ChangeNotifier {
  String? _folderId;
  bool _archiveOpen = false;

  /// The folder shown; null for All chats.
  String? get folderId => _folderId;
  bool get archiveOpen => _archiveOpen;

  void selectFolder(String? id) {
    if (_folderId == id && !_archiveOpen) return;
    _folderId = id;
    _archiveOpen = false;
    notifyListeners();
  }

  void openArchive() {
    if (_archiveOpen) return;
    _archiveOpen = true;
    notifyListeners();
  }

  void closeArchive() {
    if (!_archiveOpen) return;
    _archiveOpen = false;
    notifyListeners();
  }
}

final Expando<ChatListNavigation> _listNavigations = Expando();

ChatListNavigation _listNavigationFor(MainPageState state) =>
    _listNavigations[state] ??= ChatListNavigation();

/// What both layouts share: the source, the open space, search, and the
/// actions behind each tap.
/// Whether the keyboard focus ([focused], default the primary focus) is
/// inside [panel].
bool focusIsWithin(BuildContext? panel, [FocusNode? focused]) {
  final focusedContext =
      (focused ?? FocusManager.instance.primaryFocus)?.context;
  if (panel == null || focusedContext == null) return false;
  if (identical(focusedContext, panel)) return true;
  var inside = false;
  focusedContext.visitAncestorElements((element) {
    inside = identical(element, panel);
    return !inside;
  });
  return inside;
}

mixin _UnifiedChatPage<T extends StatefulWidget> on State<T> {
  MainPageState get page;

  late final UnifiedChatSource source;
  late final SpaceNavigation nav;
  late final ChatListNavigation listNav;
  final TextEditingController search = TextEditingController();

  void onRoomOpened() {}

  @override
  void initState() {
    super.initState();
    source =
        UnifiedChatSource(page.clientManager, filterClient: page.filterClient);
    nav = _navigationFor(page);
    listNav = _listNavigationFor(page);
    source.addListener(_onSourceChanged);
    nav.addListener(_onNavChanged);
    listNav.addListener(_onNavChanged);
    RoomListNavigation.registerMover(this, moveToRoom);
    _onSourceChanged();
  }

  @override
  void dispose() {
    RoomListNavigation.unregister(this);
    source.removeListener(_onSourceChanged);
    nav.removeListener(_onNavChanged);
    listNav.removeListener(_onNavChanged);
    source.dispose();
    search.dispose();
    super.dispose();
  }

  void _onSourceChanged() {
    // Archived spaces can be open too.
    nav.prune((path) => isValidSpacePath(source.allRows, path));
    // A deleted folder's tab goes back to All chats.
    if (listNav.folderId != null &&
        source.folders.folder(listNav.folderId) == null) {
      listNav.selectFolder(null);
    }
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

  bool get hasFolders => source.folders.folders.isNotEmpty;

  /// The rows on screen: the archive, or the picked folder (All chats).
  List<TopRow> get currentRows =>
      listNav.archiveOpen ? source.archived : source.rowsFor(listNav.folderId);

  List<FolderTab> get tabs => hasFolders
      ? folderTabs(source.folders, source.unreadFor)
      : const <FolderTab>[];

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, s) {
      Log.onError(e, s);
      if (mounted) AdaptiveDialog.showError(context, e, s);
    }
  }

  Future<void> toggleArchive(TopRow row) => _guard(() => source.isArchived(row)
      ? source.unarchive([row.roomId])
      : source.archive(row));

  /// Archive and "Add to folder" go into every top-level row's menu.
  List<tiamat.ContextMenuItem> rowMenuItems(TopRow row) {
    final archived = source.isArchived(row);
    final extra = [
      tiamat.ContextMenuItem(
          text: archived ? "Unarchive" : "Archive",
          icon: archived ? Icons.unarchive_outlined : Icons.archive_outlined,
          onPressed: () => toggleArchive(row)),
      tiamat.ContextMenuItem(
          text: "Add to folder…",
          icon: Icons.create_new_folder_outlined,
          onPressed: () => showAddToFolder(context, row, archived: archived)),
    ];
    switch (row) {
      case ChatTopRow(:final chat):
        final room = chat.source;
        if (room is! Room) return extra;
        final items = RoomTextButton.createRoomContextMenuItems(context, room);
        return [...items.take(1), ...extra, ...items.skip(1)];
      case SpaceTopRow(:final space):
        final spaceObject = space.source;
        return [
          tiamat.ContextMenuItem(
              text: "Mark as Read",
              icon: Icons.visibility,
              onPressed: () => markRowsRead([row])),
          ...extra,
          if (spaceObject is Space)
            tiamat.ContextMenuItem(
                text: "Space settings",
                icon: Icons.settings,
                onPressed: () => NavigationUtils.navigateTo(
                    context, SpaceSettingsPage(space: spaceObject))),
        ];
    }
  }

  /// A tab's menu: Edit folder, Mark all as read, Delete (All chats: Edit
  /// folders, Mark all as read).
  Widget wrapTab(FolderTab tab, Widget child) {
    final folder = source.folders.folder(tab.id);
    return AdaptiveContextMenu(
      items: [
        if (folder == null)
          tiamat.ContextMenuItem(
              text: "Edit folders",
              icon: Icons.tune,
              onPressed: () => openChatFoldersSettings(context))
        else
          tiamat.ContextMenuItem(
              text: "Edit folder",
              icon: Icons.edit_outlined,
              onPressed: () => openFolderEditor(context, folder: folder)),
        tiamat.ContextMenuItem(
            text: "Mark all as read",
            icon: Icons.done_all,
            onPressed: () => markRowsRead(source.rowsFor(tab.id))),
        if (folder != null)
          tiamat.ContextMenuItem(
              text: "Delete",
              icon: Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
              onPressed: () => confirmDeleteFolder(context, folder)),
      ],
      child: child,
    );
  }

  Widget folderTabBar() => FolderTabBar(
      tabs: tabs,
      selected: listNav.folderId,
      onSelect: selectFolder,
      wrapTab: wrapTab);

  Widget folderStrip() => FolderStrip(
      tabs: tabs,
      selected: listNav.folderId,
      onSelect: selectFolder,
      onEdit: () => openChatFoldersSettings(context),
      wrapTab: wrapTab);

  void selectFolder(String? id) {
    nav.close();
    listNav.selectFolder(id);
  }

  Widget archivePane() => ArchivePane(
        rows: source.archived,
        now: DateTime.now(),
        selectedKey: selectedKey,
        onBack: listNav.closeArchive,
        onRowTap: openRow,
        wrapRow: wrapChatRow,
      );

  void openRow(TopRow row) {
    switch (row) {
      case ChatTopRow(:final chat):
        nav.close();
        openChat(chat);
      case SpaceTopRow(:final space):
        nav.openRoot(space.key);
    }
  }

  /// Alt+Up/Down (Vommet issue 549), in the order the list shows: a space
  /// row opens the space at the room it lists first and goes through its
  /// rooms; past either end of them, back to the list.
  void moveToRoom(Room? current,
      {required bool forward,
      bool Function(Room room)? where,
      required void Function(Room room) open}) {
    final query = search.text;
    final rows = filterTopRows(
        query.trim().isNotEmpty ? source.allRows : currentRows, query);
    final stop = stepChatList(chatListStops(rows), current?.localId, nav.root,
        forward: forward,
        where: where == null
            ? null
            : (chat) => chat.source is Room && where(chat.source as Room));
    final room = stop?.chat.source;
    if (stop == null || room is! Room) return;
    final space = stop.spaceKey;
    if (space == null) {
      nav.close();
    } else {
      nav.openTop(space);
    }
    open(room);
    onRoomOpened();
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

  Widget wrapChatRow(TopRow row, Widget child) =>
      AdaptiveContextMenu(items: rowMenuItems(row), child: child);

  Widget wrapRoom(ChatEntry chat, Widget child) {
    final room = chat.source;
    if (room is! Room) return child;
    return AdaptiveContextMenu(
        items: RoomTextButton.createRoomContextMenuItems(context, room),
        child: child);
  }

  Widget chatListPane({bool withTabs = false}) => ChatListPane(
        rows: currentRows,
        searchRows: source.allRows,
        tabs: withTabs && hasFolders ? folderTabBar() : null,
        archive: listNav.folderId == null
            ? ArchiveSummary.of(source.archived)
            : null,
        onArchive: listNav.openArchive,
        emptyText: listNav.folderId == null
            ? "No chats yet"
            : "No chats in this folder yet",
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

  /// Vommet issue 539: the list's width (without the folder strip) when
  /// [window] is that wide: the dragged one, less whatever would squeeze the
  /// chat under [ResponsiveDesktop.minChatWidth], never under the narrowest.
  static double paneWidthFor(double window, double folderStrip) {
    final pane = PaneWidths.chatList;
    final fits = window - folderStrip - ResponsiveDesktop.minChatWidth;
    return pane.effective.clamp(pane.min, fits < pane.min ? pane.min : fits);
  }

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
        LayoutBuilder(
          builder: (context, constraints) => ListenableBuilder(
            listenable: PaneWidths.chatList,
            builder: (context, _) =>
                layout(context, constraints.maxWidth, room),
          ),
        ),
        if (room != null)
          DragDropFileTarget(
              onDropComplete: (details) => EventBus.onFileDropped.add(details)),
        const BackgroundTaskViewContainer(),
        const OverlayWindowsSurface(),
      ]),
    );
  }

  Widget layout(BuildContext context, double width, Room? room) {
    final strip = hasFolders ? FolderStrip.width + 1 : 0.0;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: UnifiedMainPageDesktop.paneWidthFor(width, strip) + strip,
        child: Stack(children: [
          Positioned.fill(
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
          // Vommet issue 539: drag the edge to resize, double-click to reset.
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: PaneResizeHandle(PaneWidths.chatList),
          ),
        ]),
      ),
      if (room != null)
        MainPageViewDesktop(page).roomChatView()
      else
        Expanded(child: emptyChat(context)),
    ]);
  }

  Widget leftPane() {
    final pane = listPane();
    if (!hasFolders) return pane;
    // Telegram Desktop's folder strip at the far left.
    return Row(children: [
      folderStrip(),
      VerticalDivider(
          width: 1,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant),
      Expanded(child: pane),
    ]);
  }

  Widget listPane() {
    final space = openSpace;
    if (space == null) {
      return listNav.archiveOpen ? archivePane() : chatListPane();
    }

    return Row(children: [
      FoldedChatColumn(
        rows: currentRows,
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
  final GlobalKey leftPanelKey = GlobalKey();
  final GlobalKey rightPanelKey = GlobalKey();
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

  bool canPop() =>
      (side == RevealSide.left || side == null) &&
      !nav.isOpen &&
      !listNav.archiveOpen;

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
        if (nav.isOpen) {
          nav.back();
        } else {
          listNav.closeArchive();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final right = rightPanel();
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
              // Vommet issue 322: drop the focus left behind in the chat, but
              // keep focus that is already inside the panel just revealed
              // (Reply in Thread puts the cursor in the thread's box).
              final revealed = switch (side) {
                RevealSide.left => leftPanelKey.currentContext,
                RevealSide.right => rightPanelKey.currentContext,
                RevealSide.main => null,
              };
              if (side != RevealSide.main && !focusIsWithin(revealed)) {
                FocusManager.instance.primaryFocus?.unfocus();
              }
              setState(() => shouldMainIgnoreInput = side != RevealSide.main);
            },
            left: KeyedSubtree(key: leftPanelKey, child: navigation()),
            main: Foundation(
              child: IgnorePointer(
                ignoring: shouldMainIgnoreInput,
                child: mainPanel(),
              ),
            ),
            right: right == null
                ? null
                : KeyedSubtree(key: rightPanelKey, child: right),
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
              child: space != null
                  ? spacePane(space)
                  : listNav.archiveOpen
                      ? archivePane()
                      : chatListPane(withTabs: true),
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
