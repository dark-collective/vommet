import 'dart:async';

import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:flutter/foundation.dart';
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
  /// then uses [GridZoom.size] instead of [size].
  final GridZoom? zoom;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  int crossAxisCount = 12;
  double searchBarSize = 50;
  double headerSize = 40;
  GlobalKey key = GlobalKey();
  ScrollController controller = ScrollController();
  TextEditingController textController = TextEditingController();

  List<AutofillSearchResultEmoticon>? searchResults;

  OverlayEntry? previewEntry;
  final ValueNotifier<Emoticon?> previewed = ValueNotifier(null);
  StreamSubscription? zoomSubscription;

  double get size => widget.zoom?.size ?? widget.size;

  @override
  void initState() {
    zoomSubscription = widget.zoom?.preference.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vommet: a tab page can be built and dropped in one frame (the
      // emoticon picker's tabs change while it is open).
      if (!mounted) return;
      if (MediaQuery.of(context).desktop) {
        widget.focus?.requestFocus();
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    endPreview();
    previewed.dispose();
    zoomSubscription?.cancel();
    super.dispose();
  }

  void startPreview(Emoticon emoticon) {
    HapticFeedback.selectionClick();
    previewed.value = emoticon;
    if (previewEntry != null) return;
    previewEntry =
        OverlayEntry(builder: (context) => _EmoticonPreview(previewed));
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
        child: LayoutBuilder(builder: (context, constraints) {
          // Vommet issue 790: laid out in the same frame, so a resize
          // (GridZoom) reflows at once; at least one per row.
          crossAxisCount = (constraints.maxWidth / size).floor().clamp(1, 1000);

          final view = CustomScrollView(
            controller: controller,
            physics: widget.zoom != null
                ? const NoWheelWhileCtrlScrollPhysics()
                : null,
            slivers: [
              if (widget.searchDelegate != null)
                SliverList(
                    delegate: SliverChildListDelegate([
                  SizedBox(
                      height: searchBarSize,
                      child: Container(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                            child: TextField(
                              focusNode: widget.focus,
                              autofocus: MediaQuery.of(context).desktop,
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
                    child: Center(
                        child: tiamat.Text.labelLow("No results found :(")),
                  ),
                ])),
              if (searchResults?.isNotEmpty == true)
                SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount),
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
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount),
                    itemCount: getEmoticonList(pack).length,
                    itemBuilder: (context, index) {
                      var emote = getEmoticonList(pack)[index];
                      return buildEmoticon(emote);
                    },
                  )
                ],
            ],
          );
          final zoom = widget.zoom;
          if (zoom == null) return view;
          return MediaGridZoomDetector(
              zoom: zoom, controller: controller, padding: 0, child: view);
        }));
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
          onLongPressStart: (_) => startPreview(emoticon),
          onLongPressMoveUpdate: (details) =>
              movePreview(details.globalPosition),
          onLongPressEnd: (_) => endPreview(),
          onLongPressCancel: endPreview,
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
  const _EmoticonPreview(this.emoticon);
  final ValueListenable<Emoticon?> emoticon;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final extent = (size.shortestSide * 0.6).clamp(96.0, 320.0);
    final colors = Theme.of(context).colorScheme;

    return IgnorePointer(
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
