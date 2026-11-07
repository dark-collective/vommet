import 'dart:math' as math;

import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/ui/atoms/room_list_collapse_button.dart';
import 'package:commet/ui/layout/pane_widths.dart';
import 'package:commet/ui/layout/responsive_desktop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Separate from the classic room list's choice; automatic changes never
/// write it. Keeping it here also avoids editing the shared preferences file.
final unifiedListCollapsed =
    BoolPreference('vommet_unified_list_collapsed', defaultValue: false);

/// The unified list keeps the existing minimum useful chat width, but first
/// fits the named list down to its own minimum. Recovery has a small margin
/// so crossing a pixel boundary repeatedly does not alternate whole layouts.
class UnifiedDesktopFit {
  static const avatarWidth = 72.0;
  static const recoveryMargin = 24.0;

  static DesktopSideColumn column(double width, double folderWidth,
      {required double minimumListWidth,
      required bool collapsed,
      DesktopSideColumn? previous}) {
    final compactAt =
        folderWidth + avatarWidth + ResponsiveDesktop.minChatWidth;
    final fullAt =
        folderWidth + minimumListWidth + ResponsiveDesktop.minChatWidth;
    final compactMargin =
        previous == DesktopSideColumn.hidden ? recoveryMargin : 0;
    if (width < compactAt + compactMargin) return DesktopSideColumn.hidden;
    final fullMargin = previous != null && previous != DesktopSideColumn.full
        ? recoveryMargin
        : 0;
    if (!collapsed && width >= fullAt + fullMargin)
      return DesktopSideColumn.full;
    return DesktopSideColumn.compact;
  }

  /// Vommet issue 539: the list's width (without the folder strip) in a
  /// [width] wide window: the dragged one, less whatever would squeeze the
  /// chat under [ResponsiveDesktop.minChatWidth], never under the narrowest.
  static double paneWidth(PaneWidth pane, double width, double folderWidth) {
    final available =
        math.max(0.0, width - folderWidth - ResponsiveDesktop.minChatWidth);
    return pane.effective
        .clamp(pane.min, math.max(pane.min, available))
        .toDouble();
  }
}

/// Desktop-only responsive navigation. The full pane stays mounted when
/// folded/hidden and moves into an overlay when opened, retaining search,
/// space navigation and scroll state without duplicate pane instances.
class UnifiedDesktopLayout extends StatefulWidget {
  const UnifiedDesktopLayout(
      {super.key,
      required this.pane,
      required this.folderWidth,
      required this.hasRoom,
      required this.navigation,
      required this.compactNavigation,
      required this.chatBuilder});

  final PaneWidth pane;
  final double folderWidth;
  final bool hasRoom;
  final Widget navigation;
  final Widget compactNavigation;
  final Widget Function(bool hidden, VoidCallback openNavigation) chatBuilder;

  @override
  State<UnifiedDesktopLayout> createState() => UnifiedDesktopLayoutState();
}

class UnifiedDesktopLayoutState extends State<UnifiedDesktopLayout> {
  late bool _collapsed = unifiedListCollapsed.value;
  bool get collapsed => _collapsed;
  bool _drawer = false;
  bool get drawerOpen => _drawer;
  DesktopSideColumn? _column;
  double _width = 0;
  final _navigationFocus = FocusScopeNode(debugLabel: 'Unified navigation');
  final _compactFocus = FocusScopeNode(debugLabel: 'Unified avatars');
  final _chatFocus = FocusScopeNode(debugLabel: 'Unified conversation');
  FocusNode? _returnFocus;

  @override
  void dispose() {
    _navigationFocus.dispose();
    _compactFocus.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  void showNavigation() {
    if (_drawer || _column == DesktopSideColumn.full || !widget.hasRoom) return;
    _returnFocus = FocusManager.instance.primaryFocus;
    setState(() => _drawer = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _drawer) _navigationFocus.requestFocus();
    });
  }

  void closeNavigation({bool roomOpened = false}) {
    if (!_drawer) return;
    setState(() => _drawer = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final previous = _returnFocus;
      _returnFocus = null;
      if (!roomOpened &&
          previous?.context != null &&
          previous!.canRequestFocus) {
        previous.requestFocus();
      } else {
        _chatFocus.requestFocus();
      }
    });
  }

  void toggleCollapsed() {
    if (_column == DesktopSideColumn.hidden) {
      _drawer ? closeNavigation() : showNavigation();
      return;
    }
    if (_column == DesktopSideColumn.compact) {
      if (_collapsed) setCollapsed(false);
      if (_width <
          widget.folderWidth +
              widget.pane.min +
              ResponsiveDesktop.minChatWidth) {
        showNavigation();
      }
    } else {
      setCollapsed(true);
    }
  }

  void setCollapsed(bool value) {
    setState(() {
      _collapsed = value;
      // A deliberate expansion need not wait out automatic recovery.
      _column = null;
      _drawer = false;
    });
    unifiedListCollapsed.set(value);
  }

  void resetWidth() {
    widget.pane.reset();
    setCollapsed(false);
  }

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyB,
            shift: true, control: !mac, meta: mac): toggleCollapsed,
        if (_drawer)
          const SingleActivator(LogicalKeyboardKey.escape): closeNavigation,
      },
      child: Focus(
          autofocus: true,
          child: LayoutBuilder(builder: (context, constraints) {
            return ListenableBuilder(
                listenable: widget.pane,
                builder: (context, _) {
                  final old = _column;
                  final widthChanged = _width != constraints.maxWidth;
                  _width = constraints.maxWidth;
                  final fit = UnifiedDesktopFit.column(
                      _width, widget.folderWidth,
                      minimumListWidth: widget.pane.min,
                      collapsed: _collapsed,
                      previous: _column);
                  _column = fit;
                  // Widening returns navigation to its fitted place. Merely opening
                  // search or browsing a space in a compact layout keeps the overlay.
                  final closeOnResize = _drawer &&
                      (!widget.hasRoom ||
                          fit == DesktopSideColumn.full ||
                          (widthChanged &&
                              old == DesktopSideColumn.hidden &&
                              fit != DesktopSideColumn.hidden));
                  if (closeOnResize) {
                    // Rebuild the shortcut scope too, so Escape stops being
                    // captured once the overlay is gone. Mutating _drawer
                    // only inside this builder leaves the outer binding stale.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _drawer) closeNavigation();
                    });
                  }
                  final full = fit == DesktopSideColumn.full || !widget.hasRoom;
                  final compact = !full && fit == DesktopSideColumn.compact;
                  final overlay = _drawer && !full && !closeOnResize;
                  final shown = full || overlay;
                  _navigationFocus.traversalEdgeBehavior = overlay
                      ? TraversalEdgeBehavior.closedLoop
                      : TraversalEdgeBehavior.parentScope;
                  final fittedWidth = UnifiedDesktopFit.paneWidth(
                      widget.pane, _width, widget.folderWidth);
                  final fullWidth =
                      !widget.hasRoom && fit != DesktopSideColumn.full
                          ? _width
                          : overlay
                              ? math.min(
                                  widget.pane.effective + widget.folderWidth,
                                  math.max(0.0, _width - 48))
                              : fittedWidth + widget.folderWidth;
                  final navWidth = full
                      ? fullWidth
                      : compact
                          ? widget.folderWidth + UnifiedDesktopFit.avatarWidth
                          : 0.0;
                  // ExcludeFocus immediately moves focus out before a pane disappears.
                  // Keep conversation focus intact if the user was typing there.
                  if (!shown && _navigationFocus.hasFocus ||
                      !compact && _compactFocus.hasFocus) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_drawer) _chatFocus.requestFocus();
                    });
                  }
                  return Stack(children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                              width: navWidth,
                              child: compact
                                  ? FocusScope(
                                      node: _compactFocus,
                                      child: Stack(children: [
                                        Positioned.fill(
                                            child: ExcludeFocus(
                                                excluding: overlay,
                                                child:
                                                    widget.compactNavigation)),
                                        Positioned(
                                            right: 0,
                                            top: 0,
                                            bottom: 0,
                                            child: GestureDetector(
                                                onDoubleTap: resetWidth,
                                                child: CollapsedPaneHandle(
                                                    onExpand: () {
                                                  if (_width >=
                                                      widget.folderWidth +
                                                          widget.pane.min +
                                                          ResponsiveDesktop
                                                              .minChatWidth) {
                                                    setCollapsed(false);
                                                  } else {
                                                    showNavigation();
                                                  }
                                                }))),
                                      ]))
                                  : null),
                          Expanded(
                              child: ExcludeFocus(
                                  excluding: overlay,
                                  child: FocusScope(
                                      node: _chatFocus,
                                      child: widget.chatBuilder(
                                          !full && !compact, showNavigation)))),
                        ]),
                    if (overlay)
                      Positioned.fill(
                          child: ModalBarrier(
                              color: Colors.black54,
                              dismissible: true,
                              onDismiss: closeNavigation,
                              semanticsLabel: MaterialLocalizations.of(context)
                                  .modalBarrierDismissLabel)),
                    Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: fullWidth,
                        child: Offstage(
                            offstage: !shown,
                            child: TickerMode(
                                enabled: shown,
                                child: ExcludeFocus(
                                    excluding: !shown,
                                    child: FocusScope(
                                        node: _navigationFocus,
                                        child: Material(
                                            elevation: overlay ? 8 : 0,
                                            child: Stack(children: [
                                              Positioned.fill(
                                                  child: widget.navigation),
                                              if (full && widget.hasRoom) ...[
                                                Positioned.fill(
                                                    left: widget.folderWidth,
                                                    child: ValueListenableBuilder(
                                                        valueListenable: widget
                                                            .pane.pulledPastMin,
                                                        builder: (context,
                                                                pulled, _) =>
                                                            pulled
                                                                ? const RoomListCollapseHint()
                                                                : const SizedBox
                                                                    .shrink())),
                                                Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    bottom: 0,
                                                    child: PaneResizeHandle(
                                                        widget.pane,
                                                        visibleWidth:
                                                            fittedWidth,
                                                        onReset: resetWidth,
                                                        onCollapse: () =>
                                                            setCollapsed(
                                                                true))),
                                              ],
                                            ]))))))),
                  ]);
                });
          })),
    );
  }
}
