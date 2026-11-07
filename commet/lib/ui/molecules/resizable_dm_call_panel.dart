// Vommet: resize the in-room DM call without ending media (Vommet issue 1211).
import 'dart:math' as math;

import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/client/components/voip/voip_stream.dart';
import 'package:commet/ui/molecules/compact_call_strip.dart';
import 'package:commet/ui/organisms/call_view/call.dart';
import 'package:commet/utils/call_duration.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class _CallSize {
  double? expanded;
  bool collapsed = false;
}

/// A live-session preference, not a room setting: room navigation keeps it,
/// another account or a new call cannot inherit it, and no disk cleanup is needed.
class ResizableDmCallPanel extends StatefulWidget {
  const ResizableDmCallPanel(this.session,
      {required this.availableHeight, super.key});
  final VoipSession session;
  final double availableHeight;
  static final _sizes = Expando<_CallSize>();

  static String get resizeLabel => Intl.message('Resize call panel',
      name: 'resizeDmCallPanel', desc: 'Accessible call panel divider label');
  static String get collapseLabel => Intl.message('Collapse call panel',
      name: 'collapseDmCallPanel',
      desc: 'Collapse video to the compact call bar');
  static String get collapsedState => Intl.message('Collapsed',
      name: 'dmCallPanelCollapsed', desc: 'Accessible call panel state');
  static String get expandedState => Intl.message('Expanded',
      name: 'dmCallPanelExpanded', desc: 'Accessible call panel state');

  @override
  State<ResizableDmCallPanel> createState() => _ResizableDmCallPanelState();
}

class _ResizableDmCallPanelState extends State<ResizableDmCallPanel> {
  final _focus = FocusNode();
  double? _dragHeight;
  _CallSize get _size =>
      ResizableDmCallPanel._sizes[widget.session] ??= _CallSize();
  double get _maximum => math.max(64, widget.availableHeight - 160);
  double get _expanded => (_size.expanded ?? widget.availableHeight / 2)
      .clamp(math.min(152, _maximum), _maximum);
  bool get _connected => widget.session.state == VoipState.connected;
  bool get _hasStreams => widget.session.streams
      .any((s) => s.type != VoipStreamType.screenshareAudio);
  bool get _compact =>
      _connected && (_size.collapsed || !_hasStreams || _maximum < 152);

  void _resize(double height) => setState(() {
        if (_size.collapsed ? height >= 152 : height >= 120) {
          _size.collapsed = false;
          _size.expanded = height.clamp(math.min(152, _maximum), _maximum);
        } else {
          _size.collapsed = true;
        }
      });

  void _decrease() {
    if (_compact || _expanded <= 152) {
      _collapse();
    } else {
      _resize(_expanded - 16);
    }
  }

  void _collapse() => setState(() {
        _size.expanded ??= _expanded;
        _size.collapsed = true;
      });
  void _restore() => setState(() => _size.collapsed = false);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Start the existing shared timer while expanded, not only on first collapse.
    CallDuration.connectedSince(widget.session);
    final compact = _compact;
    final expanded = _expanded;
    final scheme = Theme.of(context).colorScheme;
    final canExpand = _hasStreams && _maximum >= 152;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep CallView mounted: disposal can move watched media to the mini-player.
          // This child has its expanded constraints even while the bar is visible.
          ExcludeFocus(
            excluding: compact,
            child: Offstage(
              offstage: compact,
              child: SizedBox(
                height: _connected ? expanded - 12 : widget.availableHeight / 2,
                child: Stack(fit: StackFit.expand, children: [
                  CallWidget(widget.session, key: ObjectKey(widget.session)),
                  if (_connected)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: ResizableDmCallPanel.collapseLabel,
                        onPressed: _collapse,
                        icon: const Icon(Icons.expand_less),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          if (compact)
            CompactCallStrip(widget.session,
                key: ObjectKey(widget.session),
                desktop: true,
                onExpand: canExpand ? _restore : null),
          if (_connected)
            Focus(
              focusNode: _focus,
              onFocusChange: (_) => setState(() {}),
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.home) {
                  _collapse();
                } else if (key == LogicalKeyboardKey.end && canExpand) {
                  _restore();
                } else if (key == LogicalKeyboardKey.arrowUp) {
                  _decrease();
                } else if (key == LogicalKeyboardKey.arrowDown && canExpand) {
                  // A single deliberate keyboard step can leave compact mode.
                  _resize(compact ? 152 : expanded + 16);
                } else {
                  return KeyEventResult.ignored;
                }
                return KeyEventResult.handled;
              },
              child: Semantics(
                label: ResizableDmCallPanel.resizeLabel,
                value: compact
                    ? ResizableDmCallPanel.collapsedState
                    : ResizableDmCallPanel.expandedState,
                increasedValue: ResizableDmCallPanel.expandedState,
                decreasedValue: compact || expanded <= 152
                    ? ResizableDmCallPanel.collapsedState
                    : ResizableDmCallPanel.expandedState,
                onIncrease: canExpand
                    ? () => _resize(compact ? 152 : expanded + 16)
                    : null,
                onDecrease: _decrease,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    key: const ValueKey('dm-call-resize'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      _focus.requestFocus();
                      _dragHeight = compact ? 64 : expanded;
                    },
                    onVerticalDragUpdate: (details) {
                      _dragHeight =
                          (_dragHeight! + details.delta.dy).clamp(64, _maximum);
                      _resize(_dragHeight!);
                    },
                    onVerticalDragEnd: (_) => _dragHeight = null,
                    onVerticalDragCancel: () => _dragHeight = null,
                    child: Container(
                      height: 12,
                      color: _focus.hasFocus
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: Container(
                        width: 48,
                        height: 3,
                        decoration: BoxDecoration(
                            color: scheme.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]);
  }
}
