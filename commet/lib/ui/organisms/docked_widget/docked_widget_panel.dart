import 'dart:typed_data';

import 'package:commet/client/components/voip_room/voip_room_component.dart';
import 'package:commet/client/components/widgets/docked/macos_widget_dock_backend.dart';
import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:commet/client/room.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vommet: where a docked widget shows (experiment "Docked widgets"): in the
/// room it was opened in, as a side panel beside the room (placement A), or,
/// while you're in the call of a voice room, as a tile above the call
/// (placement B). Wraps the room's primary view.
class DockedWidgetArea extends StatelessWidget {
  const DockedWidgetArea({required this.room, required this.child, super.key});
  final Room room;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WidgetDock.instance,
      builder: (context, _) {
        final docked =
            WidgetDock.instance.inRoom(room.client.identifier, room.identifier);
        if (docked == null) return child;
        if (room.getComponent<VoipRoomComponent>() == null) {
          return _SidePanelSplit(docked: docked, child: child);
        }
        final calls = clientManager?.callManager.currentSessions;
        return StreamBuilder(
          stream: calls?.onListUpdated,
          builder: (context, _) {
            final inCall = clientManager?.callManager
                    .getCallInRoom(room.client, room.identifier) !=
                null;
            if (!inCall) return _SidePanelSplit(docked: docked, child: child);
            return LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: SizedBox(
                      height: constraints.maxHeight * 0.45,
                      child: DockedWidgetCallTile(docked: docked),
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SidePanelSplit extends StatefulWidget {
  const _SidePanelSplit({required this.docked, required this.child});
  final DockedWidget docked;
  final Widget child;

  @override
  State<_SidePanelSplit> createState() => _SidePanelSplitState();
}

class _SidePanelSplitState extends State<_SidePanelSplit> {
  /// Shared by every room, like a pane width should be.
  static double width = 620;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final max = (constraints.maxWidth - 320).clamp(280.0, double.infinity);
      final panelWidth = width.clamp(280.0, max);
      return Row(
        children: [
          Expanded(child: widget.child),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(
                  () => width = (panelWidth - d.delta.dx).clamp(280.0, max)),
              child: SizedBox(
                width: 8,
                child: Center(
                  child: Container(
                    width: 3,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: panelWidth,
            child: DockedWidgetSidePanel(docked: widget.docked),
          ),
        ],
      );
    });
  }
}

/// The widget's icon in a small rounded square, as on its tile.
class _WidgetBadge extends StatelessWidget {
  const _WidgetBadge({required this.docked, this.size = 28});
  final DockedWidget docked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = docked.icon?.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: SizedBox(
        width: size,
        height: size,
        child: image != null
            ? Image(image: image, fit: BoxFit.cover)
            : ColoredBox(
                color: scheme.primaryContainer,
                child: Icon(docked.icon?.icon ?? Icons.widgets_rounded,
                    size: size * 0.6, color: scheme.onPrimaryContainer),
              ),
      ),
    );
  }
}

/// Placement A: a panel beside the room.
class DockedWidgetSidePanel extends StatelessWidget {
  const DockedWidgetSidePanel({required this.docked, super.key});
  final DockedWidget docked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 50,
            child: Row(
              children: [
                const SizedBox(width: 10),
                _WidgetBadge(docked: docked),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(docked.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall),
                ),
                if (docked.poppedOut)
                  Text(" · in its own window",
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (docked.poppedOut)
                  TextButton.icon(
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text("Dock back"),
                    onPressed: () => WidgetDock.instance.dockBack(docked.id),
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text("Pop out"),
                    onPressed: () => WidgetDock.instance.popOut(docked.id),
                  ),
                IconButton(
                  tooltip: "Close",
                  icon: const Icon(Icons.close_rounded),
                  onPressed: docked.onCloseRequested,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: docked.poppedOut
                ? DockedWidgetPoppedPlaceholder(docked: docked)
                : DockedWidgetViewport(id: docked.id),
          ),
        ],
      ),
    );
  }
}

/// Placement B: a tile above the call in a voice room.
class DockedWidgetCallTile extends StatelessWidget {
  const DockedWidgetCallTile({required this.docked, super.key});
  final DockedWidget docked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The web view draws above Flutter, so the controls sit in a bar above
    // it rather than over the picture.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: scheme.surfaceContainerLowest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  _WidgetBadge(docked: docked, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(docked.title,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  if (!docked.poppedOut)
                    TextButton.icon(
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text("Pop out"),
                      onPressed: () => WidgetDock.instance.popOut(docked.id),
                    ),
                  IconButton(
                    tooltip: "Close",
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: docked.onCloseRequested,
                  ),
                ],
              ),
            ),
            Expanded(
              child: docked.poppedOut
                  ? DockedWidgetPoppedPlaceholder(docked: docked)
                  : DockedWidgetViewport(id: docked.id),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for a popped out widget (mockups D2/D3).
class DockedWidgetPoppedPlaceholder extends StatelessWidget {
  const DockedWidgetPoppedPlaceholder({required this.docked, super.key});
  final DockedWidget docked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WidgetBadge(docked: docked, size: 56),
            const SizedBox(height: 16),
            Text("${docked.title} is open in its own window",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text("It keeps playing there. Dock it back to watch here.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: () => WidgetDock.instance.dockBack(docked.id),
                  child: const Text("Dock back"),
                ),
                FilledButton.tonal(
                  onPressed: () => WidgetDock.instance.showWindow(docked.id),
                  child: const Text("Show window"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a docked widget's native view is drawn: keeps the native view on
/// this widget's rect, and while other Flutter UI (a dialog, a menu, another
/// page) covers it, swaps it for a still picture, since native views always
/// draw above Flutter. Hidden while no viewport shows it (another room).
class DockedWidgetViewport extends StatefulWidget {
  const DockedWidgetViewport({required this.id, super.key});
  final String id;

  @override
  State<DockedWidgetViewport> createState() => _DockedWidgetViewportState();
}

class _DockedWidgetViewportState extends State<DockedWidgetViewport> {
  Rect? _sentRect;
  bool? _sentVisible;
  Uint8List? _cover;

  bool _uncovered = true;

  WidgetDockBackend? get _backend => WidgetDock.instance.backend;

  // Every drawn frame re-checks where the viewports ended up, since a
  // viewport can move without being rebuilt (a pane beside it opens).
  static final Set<_DockedWidgetViewportState> _live = {};
  static bool _hooked = false;

  static void _onFrame(Duration _) {
    if (_live.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final state in _live.toList()) {
        state._sync();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _live.add(this);
    if (!_hooked) {
      _hooked = true;
      WidgetsBinding.instance.addPersistentFrameCallback(_onFrame);
    }
  }

  @override
  void dispose() {
    _live.remove(this);
    // Left the room (or popped out, where the native side ignores this).
    if (_sentVisible == true) _backend?.setVisible(widget.id, false);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    // macOS: a platform view, placed and covered by Flutter itself.
    if (MacosWidgetDockBackend.isMacOS) return;
    final uncovered = _uncovered;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final dpr = WidgetsBinding
        .instance.renderViews.first.configuration.devicePixelRatio;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    final physical = Rect.fromLTWH(
        rect.left * dpr, rect.top * dpr, rect.width * dpr, rect.height * dpr);
    if (physical != _sentRect) {
      _sentRect = physical;
      _backend?.setRect(widget.id, physical);
    }
    if (uncovered != _sentVisible) {
      _sentVisible = uncovered;
      if (uncovered) {
        _backend?.setVisible(widget.id, true);
        setState(() => _cover = null);
      } else {
        _hideBehindSnapshot();
      }
    }
  }

  Future<void> _hideBehindSnapshot() async {
    final picture = await _backend?.snapshot(widget.id);
    if (!mounted || _sentVisible == true) return;
    setState(() => _cover = picture);
    _backend?.setVisible(widget.id, false);
  }

  @override
  Widget build(BuildContext context) {
    if (MacosWidgetDockBackend.isMacOS) {
      return AppKitView(
        key: ValueKey(widget.id),
        viewType: MacosWidgetDockBackend.viewType,
        creationParams: {"id": widget.id},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    _uncovered = ModalRoute.of(context)?.isCurrent ?? true;
    return ColoredBox(
      color: Colors.black,
      child: _cover == null
          ? const SizedBox.expand()
          : Image.memory(_cover!, fit: BoxFit.fill, gaplessPlayback: true),
    );
  }
}
