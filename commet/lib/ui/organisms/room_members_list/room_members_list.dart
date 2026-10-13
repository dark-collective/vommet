import 'dart:math';

import 'package:commet/client/components/direct_messages/direct_message_component.dart';
import 'package:commet/client/components/invitation/invitation_component.dart';
import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/widgets/widget_component.dart';
import 'package:commet/client/room.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/layout/collapsing_header.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/scrollbar_below_header.dart';
import 'package:commet/ui/layout/scrolling_tab_row.dart';
import 'package:commet/ui/layout/tab_swipe.dart';
import 'package:commet/ui/molecules/space_menu.dart';
import 'package:commet/ui/molecules/user_list.dart';
import 'package:commet/ui/organisms/room_members_list/room_attachments.dart';
import 'package:commet/ui/organisms/room_pinned_messages/room_pinned_messages_widget.dart';
import 'package:commet/ui/organisms/room_threads_list/room_threads_list_widget.dart';
import 'package:commet/ui/organisms/room_widgets/room_widgets_view.dart';
import 'package:commet/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intl/intl.dart';

class RoomMembersListWidget extends StatefulWidget {
  const RoomMembersListWidget(this.room, {this.header = const [], super.key});
  final Room room;

  /// Vommet: slivers above the label (the room banner, the phone's room
  /// actions), scrolling with the list.
  final List<Widget> header;

  /// The list's fixed width on desktop, or null to fill the panel.
  static double? widthFor(BuildContext context, Room room) {
    if (!MediaQuery.of(context).desktop) return null;
    // Vommet: the resizable right pane (the list pads itself inside it).
    final width = PaneWidths.right.effective;
    return isDirectMessage(room) ? max(width, 316) : width;
  }

  static bool isDirectMessage(Room room) =>
      room.client
          .getComponent<DirectMessagesComponent>()
          ?.isRoomDirectMessage(room) ??
      false;

  @override
  State<RoomMembersListWidget> createState() => _RoomMembersListWidgetState();
}

/// Vommet: the member panel's tabs (Discord's channel panel).
enum MemberPanelTab {
  members,
  threads,
  media,
  files,
  pins,
  widgets;

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

  String get memberPanelInviteMembers => Intl.message("Invite members",
      name: "memberPanelInviteMembers",
      desc:
          "Room side panel: card at the top of the Members tab that opens the invite dialog");

  String get memberPanelRoomMembers => Intl.message("Room Members",
      name: "memberPanelRoomMembers",
      desc: "Room side panel: header above the member list");

  late bool isDirectMessage;
  // Vommet: the open tab per room, so closing a thread opened from the
  // Threads tab comes back to it.
  static final Map<String, MemberPanelTab> _lastTab = {};

  late MemberPanelTab tab =
      _lastTab[widget.room.localId] ?? MemberPanelTab.members;

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
    super.initState();
    if (tab == MemberPanelTab.media || tab == MemberPanelTab.files) {
      feed = RoomAttachmentFeed(widget.room)..addListener(_onFeed);
      feed!.start();
    }
  }

  @override
  void dispose() {
    _tabsFocus.dispose();
    feed?.removeListener(_onFeed);
    feed?.dispose();
    super.dispose();
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  // The tabs are part of the Discord-style layout experiment.
  bool get _tabs =>
      preferences.experimentBannerLayout.value && !isDirectMessage;

  void _select(MemberPanelTab value) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
    if (value == MemberPanelTab.media || value == MemberPanelTab.files) {
      if (feed == null) {
        feed = RoomAttachmentFeed(widget.room)..addListener(_onFeed);
        feed!.start();
      }
    }
    setState(() => tab = value);
    _lastTab[widget.room.localId] = value;
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
    return ScrollingTabRow(
      key: _stripKeys[tab],
      background: scheme.surfaceContainer,
      children: [
        for (final value in MemberPanelTab.values)
          InkWell(
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
  }

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
    const tabs = MemberPanelTab.values;
    final MemberPanelTab? next = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight =>
        tab.index + 1 < tabs.length ? tabs[tab.index + 1] : null,
      LogicalKeyboardKey.arrowLeft =>
        tab.index > 0 ? tabs[tab.index - 1] : null,
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
    final available = !PlatformUtils.isWeb &&
        room.client.getComponent<WidgetComponent>() != null &&
        room.getComponent<VoipRoomComponent>() == null;
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

  /// Vommet: "Invite members", first in the Members tab (it scrolls away
  /// with the list), for people allowed to invite.
  Widget _inviteCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Material(
        key: const ValueKey("member-panel-invite-card"),
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => RoomMenu.invite(context, widget.room),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(children: [
              Icon(Icons.person_add_alt_1, size: 22, color: scheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Text(memberPanelInviteMembers,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.onSurface)),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ]),
          ),
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
    const tabs = MemberPanelTab.values;
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
            final next = tab.index + direction;
            return next >= 0 && next < tabs.length;
          },
          onSwipe: (direction) => _select(tabs[tab.index + direction]),
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
      if (_tabs)
        SliverPersistentHeader(
          pinned: true,
          delegate: CollapsingHeaderDelegate(
              minHeight: 44,
              maxHeight: 44,
              builder: (context, _) => _tabStrip(context)),
        ),
    ];
    final width = RoomMembersListWidget.widthFor(context, widget.room);

    if (_tabs && tab != MemberPanelTab.members) {
      final feed = this.feed;
      return _swipeable(
        width,
        (controller, behavior) => CustomScrollView(
          key: ValueKey("member-panel-${tab.name}-${widget.room.localId}"),
          controller: controller,
          scrollBehavior: behavior,
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
            else if (feed != null) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                sliver: tab == MemberPanelTab.media
                    ? RoomMediaGrid(feed)
                    : RoomFilesList(feed),
              ),
              SliverToBoxAdapter(
                child: RoomAttachmentsFooter(
                    feed,
                    tab == MemberPanelTab.media
                        ? RoomAttachmentKind.media
                        : RoomAttachmentKind.files),
              ),
            ],
          ],
        ),
      );
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
        leading: [
          ...leading,
          if (_tabs && _canInvite)
            SliverToBoxAdapter(child: _inviteCard(context)),
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
        listPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}
