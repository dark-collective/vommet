import 'package:commet/main.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/molecules/room_timeline_widget/message_hover_bar.dart';
import 'package:commet/ui/molecules/room_timeline_widget/room_timeline_overlay_button.dart';
import 'package:commet/ui/molecules/room_timeline_widget/unread_jump_targets.dart';
import 'package:commet/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/atoms/tile.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:flutter/material.dart' as m;

class TimelineOverlay extends StatefulWidget {
  const TimelineOverlay(
      {required this.link,
      this.showMessageMenu = true,
      this.jumpToLatest,
      this.onScrolled,
      this.jumpToTarget,
      this.markTargetsSeen,
      super.key});
  final LayerLink link;

  /// Vommet: the @ and ♥ buttons; true means the reactions one.
  final void Function(bool reactions)? jumpToTarget;
  final void Function(bool reactions)? markTargetsSeen;
  final bool showMessageMenu;
  final Function()? jumpToLatest;
  final Function(PointerScrollEvent)? onScrolled;

  @override
  State<TimelineOverlay> createState() => TimelineOverlayState();
}

class TimelineOverlayState extends State<TimelineOverlay> {
  TimelineEventMenu? currentMenu;
  JustTheController controller = JustTheController();
  PageStorageBucket storage = PageStorageBucket();

  TimelineEventMenuEntry? selectedEntry;
  GlobalKey menuKey = GlobalKey();

  bool? openDownwards;

  final double tooltipHeight = 300;

  bool isAttatchedToBottom = true;

  UnreadJumpTargets jumpTargets = UnreadJumpTargets.empty;

  String get labelJumpToMention => Intl.message("Jump to unread mention",
      desc:
          "Tooltip of the round @ button above the timeline, which jumps to the oldest unread message that mentions you",
      name: "labelJumpToMention");

  String get labelJumpToReaction => Intl.message(
      "Jump to new reaction on your message",
      desc:
          "Tooltip of the round heart button above the timeline, which jumps to the oldest of your messages with new reactions",
      name: "labelJumpToReaction");

  String get promptMarkAllSeen => Intl.message("Mark all as seen",
      desc:
          "Menu item (long press or right click on the @ or heart button above the timeline) that clears its count",
      name: "promptMarkAllSeen");

  String get labelJumpToLatest => Intl.message("Jump to latest",
      desc:
          "Label for the button which jumps the room timeline view to the latest message",
      name: "labelJumpToLatest");

  /// Vommet: hides [child] while messages are being selected.
  Widget hideWhileSelecting(Widget child) {
    final selection = MessageSelectionScope.maybeOf(context);
    if (selection == null) return child;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, child) =>
          selection.active ? const SizedBox.shrink() : child!,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Vommet: the hover bar can be compact or off (Settings › Appearance).
        if (widget.showMessageMenu &&
            MessageHoverBar.current != MessageHoverBar.off)
          Positioned(
              right: 0,
              top: 0,
              child: CompositedTransformFollower(
                  targetAnchor: Alignment.topRight,
                  followerAnchor: compactFollowerAnchor ??
                      (openDownwards == true
                          ? Alignment.topRight
                          : Alignment.bottomRight),
                  showWhenUnlinked: false,
                  offset: compactOffset ??
                      Offset(-20, openDownwards == true ? -50 : 0),
                  link: widget.link,
                  // Vommet: no hover menu while selecting messages.
                  child: hideWhileSelecting(MouseRegion(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: buildTooltipMenu(
                          child: Listener(
                              onPointerSignal: (event) {
                                if (event is PointerScrollEvent) {
                                  widget.onScrolled?.call(event);
                                }
                              },
                              child: buildPrimaryMenu(context))),
                    ),
                  )))),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            offset: Offset(0, !isAttatchedToBottom ? 0 : 1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            child: RoomTimelineOverlayButton(
              text: labelJumpToLatest,
              onTap: widget.jumpToLatest,
            ),
          ),
        ),
        if (!jumpTargets.isEmpty)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              // Vommet: clear of the Jump to latest pill when it shows.
              padding: EdgeInsets.only(
                  right: 8, bottom: isAttatchedToBottom ? 8 : 52),
              child: hideWhileSelecting(Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (jumpTargets.mentions.isNotEmpty)
                    buildJumpTargetButton(
                        icon: m.Icons.alternate_email,
                        tooltip: labelJumpToMention,
                        count: jumpTargets.mentions.length,
                        reactions: false),
                  if (jumpTargets.reactions.isNotEmpty)
                    buildJumpTargetButton(
                        icon: m.Icons.favorite,
                        tooltip: labelJumpToReaction,
                        count: jumpTargets.reactions.length,
                        reactions: true),
                ],
              )),
            ),
          ),
      ],
    );
  }

  Widget buildTooltipMenu({required Widget child}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        verticalDirection: openDownwards == true
            ? VerticalDirection.up
            : VerticalDirection.down,
        children: [
          if (selectedEntry != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Tile.surfaceContainer(
                  child: SizedBox(
                      width: tooltipHeight,
                      height: tooltipHeight,
                      child: MouseRegion(
                          child: selectedEntry!.secondaryMenuBuilder
                              ?.call(context, clearSelection))),
                ),
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }

  Widget buildPrimaryMenu(BuildContext context) {
    if (compact) return buildCompactMenu(context);
    var reactions = currentMenu?.recentReactions;
    if (reactions != null) {
      if (reactions.length > 4) {
        reactions = reactions.sublist(0, 4);
      }
    }
    const double size = 30;

    return MouseRegion(
      child: DecoratedBox(
          key: menuKey,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: m.Theme.of(context).colorScheme.surfaceDim,
              border: Border.all(
                  color:
                      m.Theme.of(context).colorScheme.surfaceContainerHighest,
                  width: 1)),
          child: currentMenu != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: Row(children: [
                    for (var e in reactions!)
                      buildAction(
                          name: e.shortcode,
                          maxWidth: e.image == null ? size * 2.5 : null,
                          child: EmojiWidget(
                            e,
                            height: size / 1.5,
                            maxWidth: size * 2.5 - 4,
                            padding: const EdgeInsetsGeometry.all(2),
                          ),
                          onTap: () {
                            currentMenu?.timeline.room
                                .addReaction(currentMenu!.event, e);
                          }),
                    if (currentMenu!.addReactionAction != null)
                      buildAction(
                          name: currentMenu!.addReactionAction!.name,
                          child: m.Icon(
                            currentMenu!.addReactionAction!.icon,
                            color: Theme.of(context).colorScheme.secondary,
                            size: size / 1.5,
                          ),
                          onTap: () =>
                              togglePopupMenu(currentMenu!.addReactionAction!)),
                    if (currentMenu!.addReactionAction != null)
                      SizedBox(height: 10, child: VerticalDivider()),
                    for (var e in withHoverForward(
                        currentMenu!.hoverForwardAction,
                        currentMenu!.primaryActions))
                      buildAction(
                          name: e.name,
                          child: m.Icon(
                            e.icon,
                            color: Theme.of(context).colorScheme.secondary,
                            size: size / 1.5,
                          ),
                          size: size,
                          onTap: e.secondaryMenuBuilder != null
                              ? () => togglePopupMenu(e)
                              : () => e.action?.call(context)),
                    buildAction(
                        name: "Options",
                        child: Icon(m.Icons.more_vert),
                        size: size,
                        contextMenuItems: currentMenu!.secondaryActions
                            .map((e) => ContextMenuItem(
                                text: e.name,
                                icon: e.icon,
                                onPressed: () => e.action?.call(context)))
                            .toList())
                  ]),
                )
              : Container()),
    );
  }

  /// Vommet: [actions] with [forward] right after Reply (first when there is
  /// no Reply) on a picture, video or file.
  static List<TimelineEventMenuEntry> withHoverForward(
      TimelineEventMenuEntry? forward, List<TimelineEventMenuEntry> actions) {
    if (forward == null) return actions;
    final reply = actions.indexWhere((e) => e.icon == m.Icons.reply);
    return [...actions]..insert(reply + 1, forward);
  }

  /// Vommet: the Compact hover bar (see [MessageHoverBar]).
  bool get compact => MessageHoverBar.current == MessageHoverBar.compact;

  static const double compactSize = 26;

  /// Vommet: the Compact bar sits inside the message's top-right corner
  /// (the follower's 20 px hover margin above it reaches up 16 px), and
  /// stays there when a reaction picker opens above or below it.
  Alignment? get compactFollowerAnchor => !compact
      ? null
      : openDownwards == false
          ? Alignment.bottomRight
          : Alignment.topRight;

  Offset? get compactOffset => !compact
      ? null
      : Offset(-20, openDownwards == false ? 4 + compactSize + 2 : -16);

  /// Vommet: add reaction, edit (own messages), reply (and retry/cancel on a
  /// failed send) and "more"; the other actions move into "more". Nothing
  /// floats over the message above.
  Widget buildCompactMenu(BuildContext context) {
    final menu = currentMenu;
    final colors = m.Theme.of(context).colorScheme;
    Widget icon(IconData i) =>
        m.Icon(i, color: colors.secondary, size: compactSize / 1.5);
    final kept = [m.Icons.edit, m.Icons.reply, m.Icons.refresh, m.Icons.cancel];
    final shown = menu?.primaryActions
            .where(
                (e) => kept.contains(e.icon) || e.secondaryMenuBuilder != null)
            .toList() ??
        [];
    final moved = menu?.primaryActions
            .where((e) => !shown.contains(e) && e.action != null)
            .toList() ??
        [];

    return MouseRegion(
      child: DecoratedBox(
          key: menuKey,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: colors.surfaceDim,
              border: Border.all(color: colors.surfaceContainerHighest)),
          child: menu == null
              ? Container()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (menu.addReactionAction != null)
                      buildAction(
                          name: menu.addReactionAction!.name,
                          child: icon(m.Icons.add_reaction_outlined),
                          size: compactSize,
                          onTap: () =>
                              togglePopupMenu(menu.addReactionAction!)),
                    for (var e
                        in withHoverForward(menu.hoverForwardAction, shown))
                      buildAction(
                          name: e.name,
                          child: icon(e.icon),
                          size: compactSize,
                          onTap: e.secondaryMenuBuilder != null
                              ? () => togglePopupMenu(e)
                              : () => e.action?.call(context)),
                    buildAction(
                        name: "Options",
                        child: icon(m.Icons.more_vert),
                        size: compactSize,
                        contextMenuItems: [...moved, ...menu.secondaryActions]
                            .map((e) => ContextMenuItem(
                                text: e.name,
                                icon: e.icon,
                                onPressed: () => e.action?.call(context)))
                            .toList())
                  ]),
                )),
    );
  }

  void clearSelection() {
    setState(() {
      openDownwards = null;
      selectedEntry = null;
    });
  }

  void togglePopupMenu(TimelineEventMenuEntry entry) {
    if (selectedEntry == entry) {
      setState(() {
        selectedEntry = null;
      });
    } else {
      var obj = menuKey.currentContext?.findRenderObject() as RenderBox;
      var pos = obj.localToGlobal(Offset.zero) * preferences.appScale.value;
      openDownwards = pos.dy < (tooltipHeight + 100);
      setState(() {
        selectedEntry = entry;
      });
    }
  }

  void setMenu(TimelineEventMenu menu) {
    setState(() {
      currentMenu = menu;
      selectedEntry = null;
    });
  }

  void setJumpTargets(UnreadJumpTargets value) {
    if (value.mentions.length == jumpTargets.mentions.length &&
        value.reactions.length == jumpTargets.reactions.length) {
      jumpTargets = value;
      return;
    }
    setState(() {
      jumpTargets = value;
    });
  }

  /// Vommet: a round @ or ♥ button with its count; long press or right
  /// click offers "Mark all as seen".
  Widget buildJumpTargetButton(
      {required IconData icon,
      required String tooltip,
      required int count,
      required bool reactions}) {
    final colors = Theme.of(context).colorScheme;
    const double size = 40;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: tiamat.Tooltip(
        text: tooltip,
        child: Badge(
          label: Text(count > 99 ? "99+" : "$count"),
          child: DecoratedBox(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Theme.of(context).shadowColor, blurRadius: 5)
                ],
                border: Border.all(color: colors.surfaceContainerHigh),
                color: colors.surfaceContainer),
            child: ClipOval(
              child: Material(
                color: Colors.transparent,
                child: ContextMenu(
                  items: [
                    ContextMenuItem(
                        text: promptMarkAllSeen,
                        icon: m.Icons.done_all,
                        onPressed: () =>
                            widget.markTargetsSeen?.call(reactions)),
                  ],
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: () => widget.jumpToTarget?.call(reactions),
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: m.Icon(icon, size: 20, color: colors.onSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void setAttachedToBottom(bool value) {
    if (value != isAttatchedToBottom) {
      setState(() {
        isAttatchedToBottom = value;
      });
    }
  }

  Widget buildAction(
      {required Widget child,
      String? name,
      Function()? onTap,
      double size = 30,
      double? maxWidth,
      List<ContextMenuItem>? contextMenuItems}) {
    var pad = const EdgeInsets.all(2);

    var result = m.Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Material(
          color: Colors.transparent,
          child: m.ConstrainedBox(
            // A text reaction may be wider than an icon, up to [maxWidth]
            // (Vommet issue 643).
            constraints: BoxConstraints(
                minWidth: size,
                maxWidth: maxWidth ?? size,
                minHeight: size,
                maxHeight: size),
            child: contextMenuItems != null
                ? ContextMenu(
                    modal: true,
                    items: contextMenuItems,
                    child: Padding(
                      padding: pad,
                      child: child,
                    ),
                  )
                : InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: onTap,
                    child: Padding(
                      padding: pad,
                      child: child,
                    )),
          ),
        ),
      ),
    );
    if (name != null) return tiamat.Tooltip(text: name, child: result);

    return result;
  }
}
