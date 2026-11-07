// Vommet issue 1069: resolve current content under the pointer, not a stale menu.
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:commet/client/timeline.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/message_input.dart';
import 'package:commet/ui/organisms/message_selection/message_selection.dart';
import 'package:commet/utils/hover_reply_binding.dart';
import 'package:commet/utils/timeline_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class HoverReplyTarget extends StatelessWidget {
  const HoverReplyTarget(
      {required this.timeline,
      required this.eventId,
      required this.child,
      super.key});
  final Timeline timeline;
  final String eventId;
  final Widget child;
  @override
  Widget build(BuildContext context) => MetaData(metaData: this, child: child);
}

class HoverReplyPane extends StatefulWidget {
  const HoverReplyPane(
      {required this.blocked,
      required this.reply,
      required this.child,
      super.key});
  final bool Function() blocked;
  final bool Function(HoverReplyTarget target) reply;
  final Widget child;
  @override
  State<HoverReplyPane> createState() => _HoverReplyPaneState();
}

class _HoverReplyPaneState extends State<HoverReplyPane>
    with WidgetsBindingObserver {
  static final _panes = <_HoverReplyPaneState>{};
  Offset? _position;
  int _view = 0;
  bool _current = false;

  @override
  void initState() {
    super.initState();
    _panes.add(this);
    HardwareKeyboard.instance.addHandler(_key);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_pointer);
    WidgetsBinding.instance.addObserver(this);
  }

  void _pointer(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _view = event.viewId;
    _position = _current &&
            event.buttons == 0 &&
            (event is PointerHoverEvent ||
                event is PointerMoveEvent ||
                event is PointerScrollEvent)
        ? event.position
        : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _position = null;
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state == ViewFocusState.unfocused) _position = null;
  }

  bool _key(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !_current ||
        _position == null ||
        HoverReplyBinding.capturing) return false;
    final binding = HoverReplyBinding.saved;
    if (binding == null ||
        !binding.matches(event) ||
        binding.invalidReason != null) return false;
    if (TimelineSelection.current.value != null ||
        MessageSelection.anyActive ||
        clientManager?.callManager.pushToTalk.talking == true ||
        _panes.any((p) => p._current && p.widget.blocked())) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus?.findAncestorStateOfType<EditableTextState>() != null &&
        focus?.findAncestorStateOfType<MessageInputState>() == null)
      return false;
    final hit = HitTestResult();
    RendererBinding.instance.hitTestInView(hit, _position!, _view);
    HoverReplyTarget? target;
    for (final entry in hit.path) {
      final render = entry.target;
      if (render is! RenderMetaData) continue;
      if (render.metaData is HoverReplyTarget)
        target ??= render.metaData as HoverReplyTarget;
      if (render.metaData is _HoverReplyPaneState) {
        return identical(render.metaData, this) &&
            target != null &&
            widget.reply(target);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _current = (ModalRoute.isCurrentOf(context) ?? false) &&
        MediaQuery.of(context).desktop;
    if (!_current) _position = null;
    return MetaData(metaData: this, child: widget.child);
  }

  @override
  void dispose() {
    _panes.remove(this);
    // Closing a thread or switching chats requires a fresh pointer location.
    for (final pane in _panes) {
      pane._position = null;
    }
    HardwareKeyboard.instance.removeHandler(_key);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_pointer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
