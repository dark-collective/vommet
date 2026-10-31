import 'dart:math';

import 'package:commet/client/components/direct_messages/dm_shape_notifier.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/scrollbar_below_header.dart';
import 'package:commet/ui/layout/scrolling_tab_row.dart';
import 'package:commet/ui/layout/tab_swipe.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/dm_panel.dart';
import 'package:commet/ui/organisms/room_members_list/index_shared_counts.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/ui/organisms/room_widgets/room_widgets_view.dart';
import 'package:commet/ui/organisms/user_profile/user_profile.dart';
import 'package:commet/ui/pages/main/room_chat_layout.dart';
import 'package:commet/ui/pages/room_info/room_info_experiment.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';
import 'package:commet/config/room_layout_options.dart';

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(this.room,
      {this.header = const [], this.nameInHeader = false, super.key});
  final Room room;

  /// Vommet: [header] already shows the room's name (the phone's actions
  /// bar), so a DM's header line only adds the status.
  final bool nameInHeader;

  /// Vommet: slivers above the label (the room banner, the phone's room
  /// actions), scrolling with the list.
  final List<Widget> header;

  /// The list's fixed width on desktop, or null to fill the panel.
  static double? widthFor(BuildContext context, Room room,
      {bool media = false}) {
    if (!MediaQuery.of(context).desktop) return null;
    // Vommet: the resizable right pane (the list pads itself inside it);
    // Vommet issue 747: on the Media tab, its own share of the room's area.
    final width = (media ? PaneWidths.media : PaneWidths.right).effective;
    return isDirectMessage(room) ? max(width, 316) : width;
  }

  // Vommet ("New room info page"): a direct chat with three or more people
  // shows as a room.
  static bool isDirectMessage(Room room) => DmShapes.showsPerson(room);

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

/// Vommet: the member panel's tabs (Discord's channel panel).
enum MemberPanelTab {
  members,
  profile,
  threads,
  media,
  files,
  links,
  pins,
  widgets;

  /// Whether the member list shows the find box: not in direct messages;
  /// with tabs on only on Members, with tabs off always (the list is shown
  /// whatever tab the room remembers from when tabs were on).
  static bool showsFindBox(
          {required bool directMessage,
          required bool tabs,
          required MemberPanelTab tab}) =>
      !directMessage && (!tabs || tab == members);

  /// The tabs in order: a DM's lead with Profile and what was shared (Vommet
  /// issue 602); a room's with Members.
  static List<MemberPanelTab> forRoom({required bool directMessage}) =>
      directMessage
          ? const [profile, media, files, links, threads, pins, widgets]
          : const [members, threads, media, files, links, pins, widgets];

  RoomAttachmentKind? get attachmentKind => switch (this) {
        media => RoomAttachmentKind.media,
        files => RoomAttachmentKind.files,
        links => RoomAttachmentKind.links,
        _ => null,
      };

  static String get memberPanelTabProfile => Intl.message("Profile",
      name: "memberPanelTabProfile",
      desc: "DM side panel: tab with the other person's profile; keep short");

  static String get memberPanelTabLinks => Intl.message("Links",
      name: "memberPanelTabLinks",
      desc: "Room side panel: tab listing the links sent in the room; keep "
          "short");

  static String get memberPanelTabMembers => Intl.message("Members",
      name: "memberPanelTabMembers",
      desc: "Room side panel: tab listing the room's members; keep short");

  static String get memberPanelTabThreads => Intl.message("Threads",
      name: "memberPanelTabThreads",
      desc: "Room side panel: tab listing the room's threads; keep short");

  static String get memberPanelTabMedia => Intl.message("Media",
      name: "memberPanelTabMedia",
      desc:
          "Room side panel: tab listing the room's images and videos; keep short");

  static String get memberPanelTabFiles => Intl.message("Files",
      name: "memberPanelTabFiles",
      desc: "Room side panel: tab listing the room's files; keep short");

  static String get memberPanelTabPins => Intl.message("Pins",
      name: "memberPanelTabPins",
      desc:
          "Room side panel: tab listing the room's pinned messages; keep short");

  static String get memberPanelTabWidgets => Intl.message("Widgets",
      name: "memberPanelTabWidgets",
      desc: "Room side panel: tab listing the room's widgets; keep short");

  String get label => switch (this) {
        MemberPanelTab.members => memberPanelTabMembers,
        MemberPanelTab.profile => memberPanelTabProfile,
        MemberPanelTab.links => memberPanelTabLinks,
        MemberPanelTab.threads => memberPanelTabThreads,
        MemberPanelTab.media => memberPanelTabMedia,
        MemberPanelTab.files => memberPanelTabFiles,
        MemberPanelTab.pins => memberPanelTabPins,
        MemberPanelTab.widgets => memberPanelTabWidgets,
      };
}

class _RoomMembersListWidgetState extends State<RoomMembersListWidget> {
  String get memberPanelWidgetsUnavailable => Intl.message(
      "Widgets aren't available in this room.",
      name: "memberPanelWidgetsUnavailable",
      desc:
          "Room side panel: shown in the Widgets tab when the room can't have widgets");

  String get memberPanelRoomMembers => Intl.message("Room members",
      name: "memberPanelRoomMembers",
      desc: "Room side panel: header above the member list");

  late bool isDirectMessage;
  // Vommet: the open tab per room, so closing a thread opened from the
  // Threads tab comes back to it.
  static final Map<String, MemberPanelTab> _lastTab = {};

  List<MemberPanelTab> get _tabList =>
      MemberPanelTab.forRoom(directMessage: isDirectMessage);

  /// Vommet ("New room info page"): the room's shape, followed live so the
  /// tabs switch between a person's and a room's as people join and leave.
  DmShapeNotifier? _shape;

  late MemberPanelTab tab = switch (_lastTab[widget.room.localId]) {
    final last? when _tabList.contains(last) => last,
    _ => _tabList.first,
  };

  // Vommet: the chip picked over the Media and Files tabs.
  final Map<RoomAttachmentKind, RoomAttachmentFilter> _filters = {};
  SharedContentCounts? _counts;

  // One per tab: while tabs fade, the outgoing and incoming pages both draw
  // their strip.
  final _stripKeys = {for (final t in MemberPanelTab.values) t: GlobalKey()};

  // Vommet: after a click on a tab, the arrow keys (and Home/End) move
  // between tabs while the tab row keeps focus. One node around the whole
  // panel, outside the fade, so only one exists.
  final _tabsFocus = FocusNode(debugLabel: "member-panel-tabs");
  bool _tabsFocused = false;
  RoomAttachmentFeed? feed;

  @override
  void initState() {
    isDirectMessage = RoomMembersListWidget.isDirectMessage(widget.room);
    if (roomInfoPageEnabled) {
      _shape = DmShapeNotifier.of(widget.room)..addListener(_onShapeChanged);
    }
    super.initState();
    _prepare(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportMediaTab(tab);
    });
    // Vommet issue 897: in the same frame as the resize.
    MediaGridZoom.zoom.changes.addListener(_onFeed);
  }

  /// Starts what [value]'s tab shows: the feed for Media, Files and Links;
  /// the DM Profile tab's counts, from the encrypted-chat search index where
  /// there is one, else from what the feed finds.
  void _prepare(MemberPanelTab value) {
    if (value.attachmentKind != null) _startFeed();
    if (value == MemberPanelTab.profile && isDirectMessage && _counts == null) {
      _counts = IndexSharedContentCounts.maybeFor(widget.room) ??
          FeedSharedContentCounts(_startFeed());
    }
  }

  RoomAttachmentFeed _startFeed() {
    if (feed case final feed?) return feed;
    final started = RoomAttachmentFeed(widget.room)..addListener(_onFeed);
    started.start();
    return feed = started;
  }

  void _onShapeChanged() {
    if (!mounted) return;
    setState(() {
      isDirectMessage = RoomMembersListWidget.isDirectMessage(widget.room);
      if (!_tabList.contains(tab)) tab = _tabList.first;
    });
    _prepare(tab);
  }

  @override
  void dispose() {
    _shape?.removeListener(_onShapeChanged);
    MediaGridZoom.zoom.changes.removeListener(_onFeed);
    _tabsFocus.dispose();
    _counts?.dispose();
    feed?.removeListener(_onFeed);
    feed?.dispose();
    super.dispose();
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  // The tabs are the Member panel tabs setting (Layout settings); DMs always
  // have them (Vommet issue 602).
  bool get _tabs => memberPanelTabs.value || isDirectMessage;

  void _select(MemberPanelTab value) {
    // Vommet issue 622: only Media, Files and Links fill the room's area.
    if (value.attachmentKind == null &&
        RoomChatLayout.panelExpandedOf(context) == true) {
      RoomChatLayout.setPanelExpanded(context, false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
    _prepare(value);
    _reportMediaTab(value);
    setState(() => tab = value);
    _lastTab[widget.room.localId] = value;
  }

  // Vommet issue 747: the Media tab keeps its own width.
  void _reportMediaTab(MemberPanelTab value) => RoomChatLayout.setMediaTab(
      context, _tabs && value == MemberPanelTab.media);

  /// A "Shared in this chat" row: its tab, with the matching chip picked.
  void _openShared(SharedCategory category) {
    final (value, kind, filter) = switch (category) {
      SharedCategory.photosAndVideos => (
          MemberPanelTab.media,
          RoomAttachmentKind.media,
          RoomAttachmentFilter.all
        ),
      SharedCategory.gifs => (
          MemberPanelTab.media,
          RoomAttachmentKind.media,
          RoomAttachmentFilter.gifs
        ),
      SharedCategory.files => (
          MemberPanelTab.files,
          RoomAttachmentKind.files,
          RoomAttachmentFilter.files
        ),
      SharedCategory.voice => (
          MemberPanelTab.files,
          RoomAttachmentKind.files,
          RoomAttachmentFilter.voice
        ),
      SharedCategory.links => (
          MemberPanelTab.links,
          RoomAttachmentKind.links,
          RoomAttachmentFilter.all
        ),
    };
    _filters[kind] = filter;
    _select(value);
  }

  Widget _tabStrip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Vommet: more tabs than fit a narrow panel scroll, with arrows at the
    // clipped edges (ScrollingTabRow).
    // While the row has keyboard focus (arrows switch tabs), the selected
    // tab's underline is thicker and brighter. Keyboard use only, as
    // Flutter's own buttons do: touch or mouse taps leave it as is.
    final keyboard = _tabsFocused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final underline = keyboard
        ? Color.lerp(scheme.primary, scheme.onSurface, 0.3)!
        : scheme.primary;
    final strip = ScrollingTabRow(
      key: _stripKeys[tab],
      background: scheme.surfaceContainer,
      children: [
        for (final value in _tabList)
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            key: ValueKey("member-panel-tab-${value.name}"),
            onTap: () {
              _tabsFocus.requestFocus();
              _select(value);
            },
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      width: keyboard && value == tab ? 3 : 2,
                      color: value == tab ? underline : Colors.transparent),
                ),
              ),
              child: Text(value.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: value == tab
                          ? scheme.primary
                          : scheme.onSurfaceVariant)),
            ),
          ),
      ],
    );

    // Vommet issue 622: on Media, Files and Links, a button that makes the
    // panel fill the room's area (desktop, inside a RoomChatLayout).
    final expanded = RoomChatLayout.panelExpandedOf(context);
    if (expanded == null || tab.attachmentKind == null) return strip;
    return ColoredBox(
      color: scheme.surfaceContainer,
      child: Row(children: [
        Expanded(child: strip),
        IconButton(
          key: const ValueKey("member-panel-expand"),
          tooltip: expanded ? memberPanelCollapse : memberPanelExpand,
          iconSize: 20,
          icon: Icon(expanded ? Icons.close_fullscreen : Icons.open_in_full),
          onPressed: () {
            // Escape collapses it again from anywhere in the panel.
            _tabsFocus.requestFocus();
            RoomChatLayout.setPanelExpanded(context, !expanded);
          },
        ),
      ]),
    );
  }

  static String get memberPanelExpand => Intl.message("Expand",
      name: "memberPanelExpand",
      desc: "Room side panel: tooltip of the button that makes the Media, "
          "Files and Links tabs fill the window");

  static String get memberPanelCollapse => Intl.message("Back to the side",
      name: "memberPanelCollapse",
      desc: "Room side panel: tooltip of the button that puts the expanded "
          "Media, Files and Links tabs back at the side of the chat");

  /// Vommet: scrolls the tab strip so the selected tab shows (more tabs than
  /// fit a narrow panel, and a swipe can select one off-screen).
  void _revealSelectedTab() {
    final strip = _stripKeys[tab]?.currentContext;
    if (strip == null || !strip.mounted) return;
    final key = ValueKey("member-panel-tab-${tab.name}");
    BuildContext? item;
    void visit(Element e) {
      if (item != null) return;
      if (e.widget.key == key) {
        item = e;
        return;
      }
      e.visitChildren(visit);
    }

    (strip as Element).visitChildren(visit);
    final found = item;
    if (found == null) return;
    Scrollable.ensureVisible(found,
        alignment: 0.5, duration: const Duration(milliseconds: 200));
  }

  KeyEventResult _onTabKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final tabs = _tabList;
    final index = tabs.indexOf(tab);
    final MemberPanelTab? next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight =>
        index + 1 < tabs.length ? tabs[index + 1] : null,
      LogicalKeyboardKey.arrowLeft => index > 0 ? tabs[index - 1] : null,
      LogicalKeyboardKey.home => tabs.first,
      LogicalKeyboardKey.end => tabs.last,
      _ => null,
    };
    if (next == null) {
      final arrow = event.logicalKey == LogicalKeyboardKey.arrowLeft ||
          event.logicalKey == LogicalKeyboardKey.arrowRight;
      // At the first or last tab an arrow does nothing, but stays ours.
      return arrow ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    if (next != tab) _select(next);
    return KeyEventResult.handled;
  }

  /// Vommet: the room's widgets, as a tab (the ▾ menu no longer has them).
  Widget _widgetsTab(BuildContext context) {
    final room = widget.room;
    // Vommet: the web app has widgets too (framed in the page).
    final available = room.client.getComponent<WidgetComponent>() != null;
    if (!available) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: tiamat.Text.labelLow(memberPanelWidgetsUnavailable),
      );
    }
    return RoomWidgetsView(room,
        key: ValueKey("room-widgets-tab-${room.localId}"));
  }

  bool get _canInvite =>
      widget.room.permissions.canInviteUser &&
      widget.room.client.getComponent<InvitationComponent>() != null;

  /// Vommet ("New room info page"): the person who left a direct chat isn't
  /// a member any more, so the Profile tab shows them faded.
  Widget _leftPartnerProfile(BuildContext context) {
    final partner = _shape?.value.partnerId;
    if (partner == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey("dm-left-partner-profile"),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Opacity(
        opacity: 0.5,
        child: UserProfile(
          maxBioHeight: double.infinity,
          doSafeArea: false,
          userId: partner,
          bannerHeight: MediaQuery.of(context).mobile ? 200 : 120,
          client: widget.room.client,
          showMessageButton: false,
          showContactButton: true,
        ),
      ),
    );
  }

  /// Swipes change tabs only on the tab's content: below the tab strip and
  /// clear of the panel's left edge. On the banner, the actions, the strip
  /// or the edge they always move the panel itself.
  bool _inTabContent(Offset global) {
    final strip = _stripKeys[tab]?.currentContext?.findRenderObject();
    if (strip is! RenderBox || !strip.attached) return false;
    final topLeft = strip.localToGlobal(Offset.zero);
    return global.dy > topLeft.dy + strip.size.height &&
        global.dx > topLeft.dx + 24;
  }

  /// Vommet: with tabs, swipe between them (see TabSwipeDetector) and fade
  /// from one to the next. Every tab draws the same banner and tab strip
  /// over its own scroll view, so a fade keeps them still where a slide
  /// would move them.
  ///
  /// [page] builds the tab's scroll view with [ScrollbarBelowHeader]'s
  /// controller and behaviour, so its scrollbar starts under the tab strip.
  Widget _swipeable(
      double? width,
      Widget Function(ScrollController? controller, ScrollBehavior? behavior)
          build) {
    if (!_tabs) return SizedBox(width: width, child: build(null, null));
    final tabs = _tabList;
    final index = tabs.indexOf(tab);
    final page = ScrollbarBelowHeader(
      headerKey: _stripKeys[tab]!,
      builder: (context, controller, behavior) => build(controller, behavior),
    );
    return SizedBox(
      width: width,
      child: Focus(
        focusNode: _tabsFocus,
        onFocusChange: (focused) => setState(() => _tabsFocused = focused),
        onKeyEvent: (node, event) => _onTabKey(event),
        child: TabSwipeDetector(
          canSwipe: (direction) {
            final next = index + direction;
            return next >= 0 && next < tabs.length;
          },
          onSwipe: (direction) => _select(tabs[index + direction]),
          startsHere: _inTabContent,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: KeyedSubtree(key: ValueKey(tab), child: page),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leading = [
      ...widget.header,
      if (isDirectMessage)
        SliverToBoxAdapter(
          child: DmPanelHeader(widget.room,
              showName: !widget.nameInHeader,
              partnerLeft: _shape?.value.partnerLeft ?? false,
              key: ValueKey("dm-panel-header-${widget.room.localId}")),
        ),
      if (_tabs)
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
              minHeight: 44,
              maxHeight: 44,
              builder: (context, _) => _tabStrip(context)),
        ),
    ];
    // Vommet issue 622: expanded, the panel fills the room's area.
    final width = RoomChatLayout.panelExpandedOf(context) == true
        ? null
        : RoomMembersListWidget.widthFor(context, widget.room,
            media: _tabs && tab == MemberPanelTab.media);

    final kind = tab.attachmentKind;
    final filter = _filters[kind] ?? RoomAttachmentFilter.all;
    if (_tabs &&
        tab != MemberPanelTab.members &&
        tab != MemberPanelTab.profile) {
      final feed = this.feed;
      final media = kind == RoomAttachmentKind.media;
      return _swipeable(width, (controller, behavior) {
        final view = CustomScrollView(
          key: ValueKey("member-panel-${tab.name}-${widget.room.localId}"),
          controller: controller,
          scrollBehavior: behavior,
          // Vommet issue 622: Ctrl + wheel resizes the Media thumbnails
          // instead of scrolling.
          physics: media ? const NoWheelWhileCtrlScrollPhysics() : null,
          slivers: [
            ...leading,
            if (tab == MemberPanelTab.threads)
              SliverFillRemaining(
                child: RoomThreadsListWidget(
                  room: widget.room,
                  key: ValueKey("room-threads-tab-${widget.room.localId}"),
                ),
              )
            else if (tab == MemberPanelTab.pins)
              SliverFillRemaining(
                child: RoomPinnedMessagesWidget(
                  room: widget.room,
                  onEventClicked: (eventId) {
                    EventBus.jumpToEvent.add(eventId);
                    EventBus.focusTimeline.add(null);
                  },
                ),
              )
            else if (tab == MemberPanelTab.widgets)
              SliverFillRemaining(child: _widgetsTab(context))
            else if (feed != null && kind != null) ...[
              if (kind != RoomAttachmentKind.links)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  sliver: SliverToBoxAdapter(
                    child: RoomAttachmentChips(
                      kind: kind,
                      selected: filter,
                      onSelected: (value) =>
                          setState(() => _filters[kind] = value),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    8, kind == RoomAttachmentKind.links ? 0 : 4, 8, 0),
                sliver: switch (kind) {
                  RoomAttachmentKind.media =>
                    RoomMediaGrid(feed, filter: filter),
                  RoomAttachmentKind.files =>
                    RoomFilesList(feed, filter: filter),
                  RoomAttachmentKind.links => RoomLinksList(feed),
                },
              ),
              SliverToBoxAdapter(
                child: RoomAttachmentsFooter(feed, kind, filter: filter),
              ),
            ],
          ],
        );
        return media
            ? MediaGridZoomDetector(controller: controller, child: view)
            : view;
      });
    }

    // Vommet: header, label and members share one scroll view so the banner
    // can collapse (desktop) or scroll away (phone) as the list scrolls.
    return _swipeable(
      width,
      (controller, behavior) => RoomMemberList(
        key: ValueKey("room-participant-list-key-${widget.room.localId}"),
        widget.room,
        controller: controller,
        scrollBehavior: behavior,
        directMessage: _shape != null ? isDirectMessage : null,
        // Vommet: the find box and invite button, pinned under the tabs
        // (or the "Room members" label); not in direct messages.
        findBox: MemberPanelTab.showsFindBox(
            directMessage: isDirectMessage, tabs: _tabs, tab: tab),
        onInvite: _canInvite && !isDirectMessage
            ? (query) =>
                RoomMenu.invite(context, widget.room, initialQuery: query)
            : null,
        leading: [
          ...leading,
          if (tab == MemberPanelTab.profile &&
              _shape?.value.partnerLeft == true)
            SliverToBoxAdapter(child: _leftPartnerProfile(context)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              // Styled like the space list's section headers opposite.
              child: isDirectMessage || _tabs
                  ? null
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                      child:
                          tiamat.Text.labelEmphasised(memberPanelRoomMembers),
                    ),
            ),
          ),
        ],
        trailing: [
          if (tab == MemberPanelTab.profile && _counts != null)
            SliverToBoxAdapter(
              child: DmSharedCounts(_counts!, onOpen: _openShared),
            ),
        ],
        listPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
