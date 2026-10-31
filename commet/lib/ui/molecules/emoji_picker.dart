import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/layout/reflow_scroll_controller.dart';
import 'package:commet/ui/organisms/room_members_list/grid_columns_zoom.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/atoms/image_button.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';

class EmojiPicker extends StatefulWidget {
  EmojiPicker(this.packs,
      {super.key,
      this.size = BuildConfig.MOBILE ? 48 : 42,
      this.onEmoticonPressed,
      this.packButtonSize = BuildConfig.MOBILE ? 48 : 42,
      this.onlyEmoji = false,
      this.onlyStickers = false,
      this.staggered = false,
      this.previewOnHold = false,
      this.searchDelegate,
      this.focus,
      this.preferredTooltipDirection = AxisDirection.right,
      this.onManagePressed,
      this.manageTooltip = "",
      this.zoom,
      this.menuActions,
      this.sendLabel = "Send",
      this.packListAxis = Axis.vertical});
  final void Function(Emoticon emoticon)? onEmoticonPressed;
  final List<EmoticonPack> packs;
  final double size;
  final Axis packListAxis;
  final FocusNode? focus;
  final double packButtonSize;
  final bool staggered;
  final bool onlyStickers;
  final bool onlyEmoji;

  /// Vommet: press and hold an item to see it large without sending it;
  /// sliding to another item while holding previews that one instead.
  final bool previewOnHold;
  final List<AutofillSearchResultEmoticon> Function(String text)?
      searchDelegate;
  final AxisDirection preferredTooltipDirection;

  /// Vommet issue 731: a Manage button at the end of the pack bar (opens
  /// the Library).
  final VoidCallback? onManagePressed;
  final String manageTooltip;

  /// Vommet issue 790: lets Ctrl + wheel or a pinch resize the grid, which
  /// then uses [GridZoom.size] instead of [size]. Vommet issue 897: one item
  /// per row at a time ([GridColumnsZoom]).
  final GridZoom? zoom;

  /// Vommet issue 890: extra items for an item's menu (right-click, or
  /// lifting the finger after holding one with [previewOnHold]). The menu
  /// always starts with Send ([sendLabel]).
  final List<EmoticonMenuAction> Function(Emoticon emoticon)? menuActions;
  final String sendLabel;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  int crossAxisCount = 12;
  double searchBarSize = 50;
  double headerSize = 40;
  GlobalKey key = GlobalKey();
  ScrollController controller = ReflowScrollController();
  TextEditingController textController = TextEditingController();

  List<AutofillSearchResultEmoticon>? searchResults;

  OverlayEntry? previewEntry;
  final ValueNotifier<Emoticon?> previewed = ValueNotifier(null);
  final ValueNotifier<List<EmoticonMenuAction>?> pinnedActions =
      ValueNotifier(null);
  PointerDeviceKind? holdKind;
  OverlayEntry? menuEntry;

  /// Vommet issue 897: with [EmojiPicker.zoom], the items' size as last
  /// laid out (they fill the width at [zoomColumns] per row); see
  /// [zoomAnchor].
  double? zoomSize;
  double zoomColumns = 1;
  double zoomWidth = 0;
  _ZoomAnchor? zoomAnchor;

  double get size => zoomSize ?? widget.size;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vommet: a tab page can be built and dropped in one frame (the
      // emoticon picker's tabs change while it is open).
      if (!mounted) return;
      if (MediaQuery.of(context).focusPickerSearch) {
        widget.focus?.requestFocus();
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    endPreview();
    closeMenu();
    previewed.dispose();
    pinnedActions.dispose();
    super.dispose();
  }

  void startPreview(Emoticon emoticon) {
    HapticFeedback.selectionClick();
    previewed.value = emoticon;
    if (previewEntry != null) return;
    previewEntry = OverlayEntry(
        builder: (context) =>
            _EmoticonPreview(previewed, pinnedActions, onDismiss: endPreview));
    Overlay.of(context, rootOverlay: true).insert(previewEntry!);
  }

  void movePreview(Offset globalPosition) {
    final emoticon = emoticonAt(globalPosition);
    if (emoticon == null || emoticon == previewed.value) return;
    HapticFeedback.selectionClick();
    previewed.value = emoticon;
  }

  void endPreview() {
    previewEntry?.remove();
    previewEntry = null;
    previewed.value = null;
    pinnedActions.value = null;
  }

  List<EmoticonMenuAction> menuFor(Emoticon emoticon) => [
        EmoticonMenuAction(widget.sendLabel, Icons.send,
            () => widget.onEmoticonPressed?.call(emoticon)),
        ...widget.menuActions!(emoticon),
      ];

  /// Vommet issue 890: a touch hold that ends keeps the preview open with
  /// the item's menu (Telegram-style); a mouse hold just closes it.
  void releasePreview() {
    final emoticon = previewed.value;
    if (emoticon == null ||
        widget.menuActions == null ||
        holdKind == PointerDeviceKind.mouse) {
      endPreview();
      return;
    }
    pinnedActions.value = menuFor(emoticon);
  }

  /// Vommet issue 890: the right-click menu. An overlay entry rather than a
  /// route, so it shows above the desktop picker's modal tooltip.
  void openMenu(Emoticon emoticon, Offset globalPosition) {
    closeMenu();
    final actions = menuFor(emoticon);
    menuEntry = OverlayEntry(
        builder: (context) => _EmoticonMenuOverlay(
            position: globalPosition, actions: actions, onDismiss: closeMenu));
    Overlay.of(context, rootOverlay: true).insert(menuEntry!);
  }

  void closeMenu() {
    menuEntry?.remove();
    menuEntry = null;
  }

  Emoticon? emoticonAt(Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance
        .hitTestInView(result, globalPosition, View.of(context).viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderMetaData && target.metaData is Emoticon) {
        return target.metaData as Emoticon;
      }
    }
    return null;
  }

  List<Emoticon> getEmoticonList(EmoticonPack pack) {
    if (widget.onlyEmoji) {
      return pack.emoji;
    }

    if (widget.onlyStickers) {
      return pack.stickers;
    }

    return pack.emotes;
  }

  void onSearchTextChanged(String value) {
    setState(() {
      if (value == "") {
        searchResults = null;
      } else {
        searchResults = widget.searchDelegate?.call(value);
      }
    });
  }

  void jumpToPack(int packIndex) {
    if (packIndex == 0) {
      controller.jumpTo(0);
      return;
    }

    if (key.currentContext?.findRenderObject() != null) {
      var renderBox = key.currentContext!.findRenderObject() as RenderBox;
      var boxSize = renderBox.size.width / crossAxisCount.toDouble();

      double offset = 0;
      if (widget.searchDelegate != null) {
        offset += searchBarSize.toDouble();
      }

      for (int i = 0; i < packIndex; i++) {
        offset += headerSize;

        var numEmotes = getEmoticonList(widget.packs[i]).length;
        var numRows = (numEmotes / crossAxisCount).ceil();

        offset += numRows.toDouble() * boxSize;
      }

      controller.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        color: Colors.transparent,
        child: widget.packListAxis == Axis.vertical
            ? buildWithVerticalList(context)
            : buildWithHorizontalList(context));
  }

  Row buildWithVerticalList(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Tile.low(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: SizedBox(
              width: widget.packButtonSize,
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView.builder(
                  itemCount: packBarLength,
                  padding: EdgeInsets.all(0),
                  itemBuilder: (context, index) {
                    if (index == widget.packs.length) {
                      return Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                          child: buildManageButton());
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                      child: buildPackButton(index, () {
                        jumpToPack(index);
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Container(child: buildEmojiList()),
      ],
    );
  }

  Widget buildWithHorizontalList(BuildContext context) {
    return Column(
      children: [
        tiamat.Tile.low(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.packButtonSize),
              child: ScrollConfiguration(
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView.builder(
                  padding: EdgeInsets.all(0),
                  scrollDirection: Axis.horizontal,
                  itemCount: packBarLength,
                  itemBuilder: (context, index) {
                    if (index == widget.packs.length) {
                      return Padding(
                          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                          child: buildManageButton());
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                      child: buildPackButton(index, () {
                        jumpToPack(index);
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Container(child: buildEmojiList()),
      ],
    );
  }

  int get packBarLength =>
      widget.packs.length + (widget.onManagePressed != null ? 1 : 0);

  Widget buildManageButton() {
    return tiamat.Tooltip(
      text: widget.manageTooltip,
      preferredDirection: widget.preferredTooltipDirection,
      child: ImageButton(
        size: widget.packButtonSize,
        iconSize: widget.packButtonSize - 16,
        icon: Icons.tune,
        semanticsLabel: widget.manageTooltip,
        onTap: widget.onManagePressed,
      ),
    );
  }

  Widget buildPackButton(int index, void Function()? onTap) {
    return SizedBox(
      child: tiamat.Tooltip(
        text: widget.packs[index].displayName,
        preferredDirection: widget.preferredTooltipDirection,
        child: ImageButton(
          size: widget.packButtonSize,
          iconSize: widget.packButtonSize - 8,
          icon: widget.packs[index].icon,
          image: widget.packs[index].image,
          onTap: onTap,
        ),
      ),
    );
  }

  Expanded buildEmojiList() {
    return Expanded(
        key: key,
        child: switch (widget.zoom) {
          null => LayoutBuilder(builder: (context, constraints) {
              crossAxisCount =
                  (constraints.maxWidth / size).floor().clamp(1, 1000);
              return buildScrollView(SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount));
            }),
          // Vommet issue 897: resized one per row at a time, the stickers
          // sliding between layouts, the one under the fingers (or the
          // pointer) kept in place.
          final zoom => GridColumnsZoom(
              zoom: zoom,
              onFocus: focusZoom,
              builder: (context, constraints, columns) {
                keepZoomAnchor(columns, constraints.maxWidth);
                zoomColumns = columns;
                zoomWidth = constraints.maxWidth;
                zoomSize = constraints.maxWidth / columns;
                crossAxisCount = columns.round();
                return buildScrollView(SliverGridDelegateWithColumns(columns));
              }),
        });
  }

  /// The picker's scroll view, its grids laid out by [gridDelegate].
  Widget buildScrollView(SliverGridDelegate gridDelegate) {
    return CustomScrollView(
      controller: controller,
      physics:
          widget.zoom != null ? const NoWheelWhileCtrlScrollPhysics() : null,
      slivers: [
        if (widget.searchDelegate != null)
          SliverList(
              delegate: SliverChildListDelegate([
            SizedBox(
                height: searchBarSize,
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                      child: TextField(
                        focusNode: widget.focus,
                        autofocus: MediaQuery.of(context).focusPickerSearch,
                        controller: textController,
                        onChanged: onSearchTextChanged,
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: CommonStrings.promptSearch,
                            icon: Icon(Icons.search)),
                      ),
                    ),
                  ),
                ))
          ])),
        if (searchResults?.isEmpty == true)
          SliverList(
              delegate: SliverChildListDelegate([
            SizedBox(
              height: 50,
              child: Center(child: tiamat.Text.labelLow("No results found :(")),
            ),
          ])),
        if (searchResults?.isNotEmpty == true)
          SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: searchResults!.length,
            itemBuilder: (context, index) {
              var emote = searchResults![index].emoticon;
              return buildEmoticon(emote);
            },
          ),
        if (searchResults == null)
          for (var pack in widget.packs) ...[
            SliverList(
                delegate: SliverChildListDelegate([
              SizedBox(
                height: headerSize,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Align(
                      alignment: AlignmentGeometry.centerLeft,
                      child: Text(pack.displayName)),
                ),
              ),
            ])),
            SliverGrid.builder(
              gridDelegate: gridDelegate,
              itemCount: getEmoticonList(pack).length,
              itemBuilder: (context, index) {
                var emote = getEmoticonList(pack)[index];
                return buildEmoticon(emote);
              },
            )
          ],
      ],
    );
  }

  /// Vommet issue 897: what the scroll view holds, top to bottom, as
  /// [buildScrollView] lays it out: rows of a fixed height and grids.
  List<_ZoomBlock> zoomBlocks() => [
        if (widget.searchDelegate != null) _ZoomBlock.fixed(searchBarSize),
        if (searchResults?.isEmpty == true) _ZoomBlock.fixed(50),
        if (searchResults?.isNotEmpty == true)
          _ZoomBlock.grid(searchResults!.length),
        if (searchResults == null)
          for (var pack in widget.packs) ...[
            _ZoomBlock.fixed(headerSize),
            _ZoomBlock.grid(getEmoticonList(pack).length),
          ],
      ];

  /// A pinch or a Ctrl + wheel step starts at [focal] (null: it settled):
  /// remembers what is there, as laid out now, to keep it in place.
  void focusZoom(Offset? focal) {
    if (focal == null || !controller.hasClients || zoomWidth <= 0) {
      zoomAnchor = null;
      return;
    }
    final y = controller.position.pixels + focal.dy;
    final layout = ColumnsGridLayout(zoomColumns, zoomWidth);
    final blocks = zoomBlocks();
    var top = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final height = block.height(layout);
      if (y < top + height || i == blocks.length - 1) {
        final items = block.items;
        if (items == null || items == 0) {
          zoomAnchor = _ZoomAnchor(i, null, y - top, focal.dy);
          return;
        }
        final index = layout.indexAt(Offset(focal.dx, y - top), items);
        final g = layout.getGeometryForChildIndex(index);
        final share = g.mainAxisExtent > 0
            ? (y - top - g.scrollOffset) / g.mainAxisExtent
            : 0.0;
        zoomAnchor = _ZoomAnchor(i, index, share, focal.dy);
        return;
      }
      top += height;
    }
    zoomAnchor = null;
  }

  /// While a pinch or a step is under way, scrolls so that what was under
  /// it stays there at [columns] per row, in the same frame (on every
  /// build, so a finger dragging the list doesn't move it either).
  void keepZoomAnchor(double columns, double width) {
    final anchor = zoomAnchor;
    final reflow = controller;
    if (anchor == null || reflow is! ReflowScrollController) return;
    final layout = ColumnsGridLayout(columns, width);
    final blocks = zoomBlocks();
    if (anchor.block >= blocks.length) return;
    var y = 0.0;
    for (var i = 0; i < anchor.block; i++) {
      y += blocks[i].height(layout);
    }
    final index = anchor.index;
    if (index == null) {
      y += anchor.offset;
    } else {
      final items = blocks[anchor.block].items ?? 0;
      if (index >= items) return;
      final g = layout.getGeometryForChildIndex(index);
      y += g.scrollOffset + anchor.offset * g.mainAxisExtent;
    }
    final target = y - anchor.focalY;
    reflow.anchor((_) => target);
  }

  Widget buildEmoticon(Emoticon emoticon) {
    Widget child = InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () => widget.onEmoticonPressed?.call(emoticon),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Center(
                child: EmojiWidget(
              emoticon,
              height: size,
            ))));

    if (widget.previewOnHold) {
      child = MetaData(
        metaData: emoticon,
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          onLongPressDown: (details) => holdKind = details.kind,
          onLongPressStart: (_) => startPreview(emoticon),
          onLongPressMoveUpdate: (details) =>
              movePreview(details.globalPosition),
          onLongPressEnd: (_) => releasePreview(),
          onLongPressCancel: endPreview,
          onSecondaryTapUp: widget.menuActions == null
              ? null
              : (details) => openMenu(emoticon, details.globalPosition),
          child: child,
        ),
      );
    }

    return SizedBox(width: size, height: size, child: child);
  }
}

/// Vommet: the enlarged item shown while one is held in the picker. It
/// ignores the pointer so the held gesture keeps reaching the picker.
class _EmoticonPreview extends StatelessWidget {
  const _EmoticonPreview(this.emoticon, this.actions,
      {required this.onDismiss});
  final ValueListenable<Emoticon?> emoticon;

  /// Vommet issue 890: set once the hold ends; the preview then takes
  /// taps, shows this menu, and a tap outside it closes both.
  final ValueListenable<List<EmoticonMenuAction>?> actions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final extent = (size.shortestSide * 0.6).clamp(96.0, 320.0);
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<List<EmoticonMenuAction>?>(
      valueListenable: actions,
      builder: (context, menu, _) => IgnorePointer(
        ignoring: menu == null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          onSecondaryTap: onDismiss,
          child: ColoredBox(
            color: Colors.black.withAlpha(110),
            child: Center(
              child: ValueListenableBuilder<Emoticon?>(
                valueListenable: emoticon,
                builder: (context, value, _) {
                  if (value == null) return const SizedBox.shrink();
                  return TweenAnimationBuilder<double>(
                    key: ValueKey(value.key),
                    tween: Tween(begin: 0.85, end: 1),
                    duration: Durations.short3,
                    curve: Curves.easeOutBack,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EmojiWidget(value, height: extent),
                        if (value.shortcode != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                child: Text(value.shortcode!,
                                    style: TextStyle(color: colors.onSurface)),
                              ),
                            ),
                          ),
                        if (menu != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: _EmoticonMenuCard(menu, onDone: onDismiss),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vommet issue 890: one item of a sticker's menu.
class EmoticonMenuAction {
  const EmoticonMenuAction(this.label, this.icon, this.onPressed);
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

class _EmoticonMenuCard extends StatelessWidget {
  const _EmoticonMenuCard(this.actions, {required this.onDone});
  final List<EmoticonMenuAction> actions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions)
              InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () {
                  onDone();
                  action.onPressed();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.icon, size: 20, color: colors.onSurface),
                      const SizedBox(width: 12),
                      Text(action.label,
                          style: TextStyle(color: colors.onSurface)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vommet issue 890: the right-click menu, placed at the pointer and kept
/// on screen; a click anywhere else closes it.
class _EmoticonMenuOverlay extends StatelessWidget {
  const _EmoticonMenuOverlay(
      {required this.position, required this.actions, required this.onDismiss});
  final Offset position;
  final List<EmoticonMenuAction> actions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
          ),
        ),
        CustomSingleChildLayout(
          delegate: _MenuLayout(position),
          child: _EmoticonMenuCard(actions, onDone: onDismiss),
        ),
      ],
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.position);
  final Offset position;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = position.dx + childSize.width > size.width
        ? position.dx - childSize.width
        : position.dx;
    final y = position.dy + childSize.height > size.height
        ? position.dy - childSize.height
        : position.dy;
    return Offset(x.clamp(0.0, size.width), y.clamp(0.0, size.height));
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) =>
      oldDelegate.position != position;
}

/// Vommet issue 897: a row of a fixed [fixedHeight] in the picker's scroll
/// view, or a grid of [items].
class _ZoomBlock {
  const _ZoomBlock.fixed(double this.fixedHeight) : items = null;
  const _ZoomBlock.grid(int this.items) : fixedHeight = null;

  final double? fixedHeight;
  final int? items;

  double height(ColumnsGridLayout layout) =>
      fixedHeight ?? layout.computeMaxScrollOffset(items ?? 0);
}

/// Vommet issue 897: what a pinch or a Ctrl + wheel step started over, kept
/// at [focalY] down the picker while the grid reflows: [offset] pixels into
/// [block] of [_EmojiPickerState.zoomBlocks], or with [index], that item and
/// [offset] (a share of its height) down it.
class _ZoomAnchor {
  const _ZoomAnchor(this.block, this.index, this.offset, this.focalY);

  final int block;
  final int? index;
  final double offset;
  final double focalY;
}
