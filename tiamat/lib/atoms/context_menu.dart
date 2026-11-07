import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/atoms/seperator.dart';
import 'package:tiamat/atoms/text.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(name: "Context Menu", type: ContextMenu)
Widget wbContextMenu(BuildContext context) {
  return Tile.low1(
    child: Center(
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: ContextMenu(
              items: [
                ContextMenuItem(
                    text: "Copy Text",
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      print("Copying text");
                    }),
                ContextMenuItem(
                  text: "Delete Message",
                  icon: Icons.delete,
                  color: Theme.of(context).colorScheme.error,
                ),
              ],
              child: const Tile.low3(
                child: SizedBox(
                    width: 500,
                    height: 500,
                    child: Center(
                        child:
                            const tiamat.Text.label("Right Click Somewhere"))),
              ),
            ))),
  );
}

@UseCase(name: "Modal", type: ContextMenu)
Widget wbContextMenuModal(BuildContext context) {
  return Tile.low1(
    child: Center(
        child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          child: ContextMenu(
            modal: true,
            items: [
              ContextMenuItem(
                  text: "Copy Text",
                  icon: Icons.copy_rounded,
                  onPressed: () {
                    print("Copying text");
                  }),
              ContextMenuItem(
                text: "Delete Message",
                icon: Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
            ],
            child: Padding(
                padding: EdgeInsets.all(8), child: const Icon(Icons.mouse)),
          ),
        ),
      ),
    )),
  );
}

class ContextMenuOverlay extends StatefulWidget {
  const ContextMenuOverlay(
      {super.key, required this.globalOffset, required this.items, this.close});
  // Vommet issue 1213: in-app hotkeys defer while a menu owns typing.
  static int _acceleratedMenus = 0;
  static bool get acceleratedMenuOpen => _acceleratedMenus > 0;

  final Offset globalOffset;
  final List<ContextMenuItem> items;
  final Function()? close;

  @override
  State<ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<ContextMenuOverlay>
    with TickerProviderStateMixin {
  Offset? calculatedOffset;
  Size? size;
  GlobalKey sizeGetKey = GlobalKey();
  bool leftAlign = false;
  bool topAlign = false;

  // Vommet issue 1213: focus belongs to the open menu, never the composer.
  final _keyFocus = FocusScopeNode();
  late final bool _accelerated = widget.items.any((i) => i.accelerator != null);
  bool _activated = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _activated) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.close?.call();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.handled;
    }
    final letter = event.logicalKey.keyLabel.toUpperCase();
    final matches = widget.items
        .where((i) =>
            i.onPressed != null &&
            i.accelerator?.call()?.toUpperCase() == letter)
        .toList();
    // Fail closed for malformed duplicate bindings; never cycle or guess.
    if (matches.length == 1) {
      _activated = true;
      final action = matches.single.onPressed;
      widget.close?.call();
      action?.call();
    }
    return KeyEventResult.handled;
  }

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );

  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );

  @override
  void initState() {
    if (_accelerated) ContextMenuOverlay._acceleratedMenus++;
    SchedulerBinding.instance.scheduleFrameCallback(onFirstFrame);
    if (_accelerated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyFocus.requestFocus();
      });
    }

    var view = WidgetsBinding.instance.platformDispatcher.views.first;
    var size = view.physicalSize;
    var position = widget.globalOffset * view.devicePixelRatio;

    leftAlign = position.dx > size.width / 2;
    topAlign = position.dy > size.height / 2;

    super.initState();
  }

  @override
  void dispose() {
    if (_accelerated) ContextMenuOverlay._acceleratedMenus--;
    _keyFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Vommet issue 1213: include the measuring frame so typing cannot leak.
    final menu = _buildPositioned(context);
    return _accelerated
        ? Positioned.fill(
            child: FocusScope(
                node: _keyFocus,
                autofocus: true,
                onKeyEvent: _onKey,
                child: Stack(children: [menu])))
        : menu;
  }

  Widget _buildPositioned(BuildContext context) {
    var view = WidgetsBinding.instance.platformDispatcher.views.first;
    var viewSize = view.physicalSize;

    var scale = (tiamat.getAppScale?.call() ?? 1.0) * view.devicePixelRatio;

    if (calculatedOffset == null) {
      return Container(
        child: Offstage(
          child: buildMenu(context, key: sizeGetKey),
        ),
      );
    }

    // Vommet: keep the whole menu inside the window. It moves back in when
    // it would cross an edge, and a menu taller than the window scrolls (see
    // buildMenu), so every item stays reachable.
    var area = viewSize / scale;
    var local = calculatedOffset!;

    var bottom = !topAlign
        ? null
        : _fitInWindow(area.height - local.dy, size!.height, area.height);

    var top =
        topAlign ? null : _fitInWindow(local.dy, size!.height, area.height);

    var left = _fitInWindow(
        local.dx - (leftAlign ? size!.width : 0), size!.width, area.width);

    return Positioned(
        left: left,
        top: top,
        bottom: bottom,
        child: SizeTransition(
          sizeFactor: _animation,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            // Vommet: always opaque. A glass tile takes the theme's panel
            // opacity (50 % in gradient themes, meant for the app frame), so
            // the menu showed the message and image under it.
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: buildMenu(context),
            ),
          ),
        ));
  }

  /// Vommet: space kept free between the menu and the window edges.
  static const double _windowMargin = 8;

  /// Vommet: the window size in the overlay's coordinates.
  static Size _windowArea() {
    var view = WidgetsBinding.instance.platformDispatcher.views.first;
    var scale = (tiamat.getAppScale?.call() ?? 1.0) * view.devicePixelRatio;
    return view.physicalSize / scale;
  }

  /// Vommet: [start] moved just enough that [length] fits inside [extent],
  /// [_windowMargin] from both ends.
  static double _fitInWindow(double start, double length, double extent) {
    var end = extent - _windowMargin - length;
    if (start > end) start = end;
    return start < _windowMargin ? _windowMargin : start;
  }

  Widget buildMenu(BuildContext context, {GlobalKey? key}) {
    var maxHeight = _windowArea().height - 2 * _windowMargin;
    // Vommet: never taller than the window; the rest of the items scroll.
    return ConstrainedBox(
      key: key,
      constraints: BoxConstraints(maxHeight: maxHeight > 0 ? maxHeight : 0),
      child: SingleChildScrollView(
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.items
                .map(
                  (e) => e.build(
                    context,
                    () {
                      // Vommet issue 1213: restore focus before Reply/Edit
                      // requests its destination, for mouse and keyboard alike.
                      if (_accelerated) {
                        widget.close?.call();
                        e.onPressed?.call();
                        return;
                      }
                      e.onPressed?.call();
                      _controller
                          .animateTo(0)
                          .then((value) => widget.close?.call());
                    },
                    closeMenu: () {
                      _controller
                          .animateTo(0)
                          .then((value) => widget.close?.call());
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  void onFirstFrame(Duration timeStamp) {
    RenderBox getBox = context.findRenderObject() as RenderBox;
    var local = getBox.globalToLocal(widget.globalOffset);

    print("Local position: $local");
    print("Size: ${getBox.size}");

    var menuBox = sizeGetKey.currentContext!.findRenderObject() as RenderBox;
    print(menuBox);
    print(menuBox.size);

    setState(() {
      size = menuBox.size;
      calculatedOffset = local;
      _controller.animateTo(1);
    });
  }
}

class ContextMenu extends StatefulWidget {
  const ContextMenu(
      {super.key,
      required this.child,
      this.separator,
      required this.items,
      this.itemsBuilder,
      this.onLongPress,
      this.touchTapOpens = false,
      this.excludeFromSemantics = false,
      this.modal = false});

  final Seperator? separator;
  final List<ContextMenuItem> items;

  /// Vommet: builds the items when the menu opens; null means [items].
  final List<ContextMenuItem>? Function()? itemsBuilder;

  /// Vommet: runs on a long press instead of opening the menu; returning
  /// false opens the menu after all.
  final bool Function()? onLongPress;

  /// Vommet: a touch (or stylus) tap opens the menu, for when [onLongPress]
  /// took the long press and there is no right click.
  final bool touchTapOpens;

  /// Vommet issue 1012: leaves the right-click and long press out of the
  /// accessibility tree. A secondary-tap detector still counts as tappable
  /// there, so a menu over a large area (a whole chat) took the clicks meant
  /// for other menus drawn over it, while the accessibility tree was on.
  final bool excludeFromSemantics;
  final Widget child;
  final bool modal;

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  // Vommet issue 1213: a second menu replaces the first, including its focus.
  static _ContextMenuState? _active;
  FocusNode? _previousFocus;
  bool _ownsKeys = false;
  List<ContextMenuItem> _openItems = const [];

  @override
  void dispose() {
    removeOverlay();
    super.dispose();
  }

  Offset mousePosition = Offset.zero;
  OverlayEntry? entry;

  void addOverlay() {
    // Vommet issue 1213: preserve the original focus when replacing a menu;
    // requestFocus is deferred, so primaryFocus can still be the old menu.
    final previous =
        _active?._previousFocus ?? FocusManager.instance.primaryFocus;
    _active?.removeOverlay();
    _active = this;
    _openItems = widget.itemsBuilder?.call() ?? widget.items;
    _ownsKeys = _openItems.any((i) => i.accelerator != null);
    _previousFocus = _ownsKeys ? previous : null;
    entry = OverlayEntry(builder: buildOverlay);
    Overlay.of(context).insert(entry!);
  }

  void removeOverlay() {
    if (entry == null) return;
    entry!.remove();
    entry!.dispose();
    entry = null;
    if (_active == this) _active = null;
    final previous = _previousFocus;
    _previousFocus = null;
    if (previous?.context != null) previous!.requestFocus();
  }

  Widget buildOverlay(BuildContext overlayContext) {
    if (mounted)
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: removeOverlay,
        child: Stack(
          children: [
            Theme(
              data: Theme.of(context),
              child: ContextMenuOverlay(
                globalOffset: mousePosition,
                items: _openItems,
                close: removeOverlay,
              ),
            ),
          ],
        ),
      );
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        mousePosition = event.position;
      },
      child: widget.modal
          ? InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              child: widget.child,
              onTap: () => _showMenu(context, mousePosition),
            )
          : GestureDetector(
              excludeFromSemantics: widget.excludeFromSemantics,
              onLongPress: () {
                if (widget.onLongPress?.call() == true) return;
                _showMenu(context, mousePosition);
              },
              onSecondaryTap: () => _showMenu(context, mousePosition),
              child: widget.touchTapOpens
                  ? GestureDetector(
                      supportedDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.stylus,
                      },
                      onTap: () => _showMenu(context, mousePosition),
                      child: widget.child,
                    )
                  : widget.child,
            ),
    );
  }

  void _showMenu(BuildContext context, Offset mousePosition) {
    addOverlay();
  }
}

class ContextMenuItem {
  const ContextMenuItem(
      {required this.text,
      this.onPressed,
      this.icon,
      this.color,
      this.tooltip,
      this.accelerator,
      this.customBuilder});

  final String text;

  // Vommet issue 1213: read at menu-open time so rebinding applies immediately.
  final String? Function()? accelerator;

  Widget _acceleratorLabel(BuildContext context, Color color) {
    final key = accelerator?.call();
    if (key == null) {
      return tiamat.Text(text, type: TextType.body, maxLines: 1, color: color);
    }
    final characters = text.characters.toList();
    final index =
        characters.indexWhere((c) => c.toUpperCase() == key.toUpperCase());
    final before = index < 0 ? '$text (' : characters.take(index).join();
    final marked = index < 0 ? key : characters[index];
    final after = index < 0 ? ')' : characters.skip(index + 1).join();
    return material.Text.rich(
        TextSpan(children: [
          TextSpan(text: before),
          TextSpan(
              text: marked,
              style: const TextStyle(decoration: TextDecoration.underline)),
          TextSpan(text: after),
        ]),
        maxLines: 1,
        style: Theme.of(context)
            .textTheme
            .bodyMedium!
            .copyWith(fontWeight: FontWeight.w300, color: color));
  }

  /// Vommet: explains what the item does (hover on desktop; shown under the
  /// item in the mobile bottom sheet). Not used with [customBuilder].
  final String? tooltip;
  final Function? onPressed;
  final IconData? icon;
  final Color? color;
  final Widget Function(BuildContext context, Function() onClicked,
      {Function()? closeMenu})? customBuilder;

  Widget build(BuildContext context, Function() onClicked,
      {Function()? closeMenu}) {
    var c = color ?? Theme.of(context).colorScheme.onSurface;

    if (customBuilder != null) {
      return Material(
          color: Colors.transparent,
          child: customBuilder!.call(context, onClicked, closeMenu: closeMenu));
    }

    final item = Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onClicked,
            borderRadius: BorderRadius.circular(8),
            child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _acceleratorLabel(context, c),
                    if (icon != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                        child: Icon(
                          icon,
                          color: c,
                          size: 20,
                        ),
                      )
                  ],
                ))),
      ),
    );

    if (tooltip == null) return item;
    return tiamat.Tooltip(text: tooltip!, child: item);
  }
}
