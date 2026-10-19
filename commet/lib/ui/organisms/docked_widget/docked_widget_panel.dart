import 'dart:typed_data';

import 'package:commet/client/components/widgets/docked/widget_dock.dart';
import 'package:flutter/material.dart';

/// Vommet: PLACEHOLDER placement for docked widgets (experiment): a panel
/// on the right of the main window. The final placement is still being
/// picked; whatever it is only needs to put a [DockedWidgetViewport]
/// somewhere.
class DockedWidgetSurface extends StatelessWidget {
  const DockedWidgetSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WidgetDock.instance,
      builder: (context, _) {
        final docked = WidgetDock.instance.current;
        if (docked == null) return const SizedBox.shrink();
        return Positioned(
          top: 0,
          right: 0,
          bottom: 0,
          width: 480,
          child: DockedWidgetPanel(widget: docked),
        );
      },
    );
  }
}

class DockedWidgetPanel extends StatelessWidget {
  const DockedWidgetPanel({required this.widget, super.key});
  final DockedWidget widget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (widget.poppedOut)
                  IconButton(
                    tooltip: "Dock back",
                    icon: const Icon(Icons.login_rounded),
                    onPressed: () => WidgetDock.instance.dockBack(widget.id),
                  )
                else
                  IconButton(
                    tooltip: "Pop out",
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => WidgetDock.instance.popOut(widget.id),
                  ),
                IconButton(
                  tooltip: "Close",
                  icon: const Icon(Icons.close_rounded),
                  onPressed: widget.onCloseRequested,
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.poppedOut
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Open in its own window"),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              WidgetDock.instance.dockBack(widget.id),
                          child: const Text("Dock back"),
                        ),
                      ],
                    ),
                  )
                : DockedWidgetViewport(id: widget.id),
          ),
        ],
      ),
    );
  }
}

/// Where a docked widget's native view is drawn: keeps the native view on
/// this widget's rect, and while other Flutter UI (a dialog, a menu, another
/// page) covers it, swaps it for a still picture, since native views always
/// draw above Flutter.
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

  WidgetDockBackend? get _backend => WidgetDock.instance.backend;

  void _sync(bool uncovered) {
    if (!mounted) return;
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
    final uncovered = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(uncovered));
    return LayoutBuilder(builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(uncovered));
      return ColoredBox(
        color: Colors.black,
        child: _cover == null
            ? const SizedBox.expand()
            : Image.memory(_cover!, fit: BoxFit.fill, gaplessPlayback: true),
      );
    });
  }
}
