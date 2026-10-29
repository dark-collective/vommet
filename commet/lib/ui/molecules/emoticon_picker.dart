import 'dart:async';

import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/molecules/gif_picker.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/utils/autofill_utils.dart';
import 'package:commet/ui/organisms/room_members_list/media_grid_zoom.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../client/components/emoticon/emoji_pack.dart';
import '../../client/components/emoticon/emoticon.dart';

class EmoticonPicker extends StatefulWidget {
  const EmoticonPicker({
    super.key,
    required this.emoji,
    required this.stickers,
    this.allowGifSearch = false,
    this.showGifs = false,
    this.onEmojiPressed,
    this.onStickerPressed,
    this.onGifPressed,
    this.onFavoritePicked,
    this.gifComponent,
    this.emojiSearchFocus,
    this.stickerSearchFocus,
    this.gifSearchFocus,
    this.searchDelegate,
    this.packListAxis = Axis.vertical,
    this.onImportPressed,
    this.onManagePressed,
    this.manageTooltip = "",
  });
  final List<EmoticonPack> emoji;
  final List<EmoticonPack> stickers;
  final GifComponent? gifComponent;
  final FocusNode? emojiSearchFocus;
  final FocusNode? stickerSearchFocus;
  final FocusNode? gifSearchFocus;
  final bool allowGifSearch;

  /// Vommet: shows the GIF tab (with My GIFs) even while GIF search is off.
  final bool showGifs;
  final void Function(Emoticon emoticon)? onEmojiPressed;
  final void Function(Emoticon emoticon)? onStickerPressed;

  final List<AutofillSearchResultEmoticon> Function(String text)?
      searchDelegate;
  final Future<void> Function(GifSearchResult emoticon)? onGifPressed;
  final Future<void> Function(FavoriteGif gif)? onFavoritePicked;
  final Axis packListAxis;

  /// Vommet: shows an import button next to the tabs (upstream only offered
  /// import deep in settings).
  final VoidCallback? onImportPressed;

  /// Vommet issue 731: a Manage button at the end of the emoji and sticker
  /// pack bars, opening the Library.
  final VoidCallback? onManagePressed;
  final String manageTooltip;

  @override
  State<EmoticonPicker> createState() => _EmoticonPickerState();
}

class _EmoticonPickerState extends State<EmoticonPicker>
    with TickerProviderStateMixin {
  late TabController controller;
  PageStorageBucket bucket = PageStorageBucket();
  String get labelEmojiPickerEmojiTab => Intl.message("Emoji",
      desc: "Label for the emoji tab in emoji picker",
      name: "labelEmojiPickerEmojiTab");

  String get labelEmojiPickerStickerTab => Intl.message("Sticker",
      desc: "Label for the sticker tab in the emoji picker",
      name: "labelEmojiPickerStickerTab");

  String get labelEmojiPickerGifTab => Intl.message("Gif",
      desc: "Label for the gif search tab in the emoji picker",
      name: "labelEmojiPickerGifTab");

  String get tooltipEmojiPickerImport =>
      Intl.message("Import or create sticker packs",
          desc: "Tooltip for the import button in the emoji picker",
          name: "tooltipEmojiPickerImport");

  List<FavoriteGif> favorites = [];
  StreamSubscription? sub;

  bool get showStickerTab => widget.stickers.isNotEmpty;

  bool get showGifTab =>
      (widget.allowGifSearch || widget.showGifs) && widget.gifComponent != null;

  /// The tabs shown, in order. Vommet: the tab bar, the pages and the
  /// controller all follow this one list.
  List<_PickerTab> get tabs => [
        _PickerTab.emoji,
        if (showStickerTab) _PickerTab.sticker,
        if (showGifTab) _PickerTab.gif,
      ];

  late List<_PickerTab> currentTabs;

  @override
  void initState() {
    currentTabs = tabs;
    controller = TabController(length: currentTabs.length, vsync: this);

    favorites = widget.gifComponent?.favorites ?? [];

    sub = widget.gifComponent?.onFavoritesChanged.listen((i) {
      setState(() {
        favorites = widget.gifComponent!.favorites;
      });
    });

    super.initState();
  }

  // Vommet: the picker stays open while packs are imported from it, so the
  // Sticker tab has to appear when the first sticker pack arrives (upstream
  // fixed the tab count in initState until the app restarted).
  @override
  void didUpdateWidget(covariant EmoticonPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = tabs;
    if (next.length == currentTabs.length &&
        next.indexed.every((e) => currentTabs[e.$1] == e.$2)) {
      return;
    }

    final selected = currentTabs[controller.index];
    var index = next.indexOf(selected);
    if (index < 0) index = controller.index.clamp(0, next.length - 1);

    // The tab bar and pages still hold the old controller until they
    // rebuild; dispose it once they have let go.
    final old = controller;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    currentTabs = next;
    controller = TabController(
        length: currentTabs.length, initialIndex: index, vsync: this);
  }

  @override
  void dispose() {
    sub?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: PageStorage(
        bucket: bucket,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: TabBarView(controller: controller, children: [
                Tab(
                  child: EmojiPicker(
                    widget.emoji,
                    // Vommet: phones get the horizontal pack bar the caller asks for.
                    packListAxis: widget.packListAxis,
                    preferredTooltipDirection:
                        widget.packListAxis == Axis.vertical
                            ? AxisDirection.right
                            : AxisDirection.down,
                    focus: widget.emojiSearchFocus,
                    searchDelegate: (value) => widget.searchDelegate!
                        .call(value)
                        .where((i) => i.emoticon.isEmoji)
                        .toList(),
                    onlyEmoji: true,
                    onManagePressed: widget.onManagePressed,
                    manageTooltip: widget.manageTooltip,
                    onEmoticonPressed: (emoticon) =>
                        widget.onEmojiPressed?.call(emoticon),
                  ),
                ),
                if (currentTabs.contains(_PickerTab.sticker))
                  Tab(
                    child: EmojiPicker(
                      widget.stickers,
                      // Vommet: phones get the horizontal pack bar the caller asks for.
                      packListAxis: widget.packListAxis,
                      preferredTooltipDirection:
                          widget.packListAxis == Axis.vertical
                              ? AxisDirection.right
                              : AxisDirection.down,
                      focus: widget.stickerSearchFocus,
                      searchDelegate: (value) => widget.searchDelegate!
                          .call(value)
                          .where((i) => i.emoticon.isSticker)
                          .toList(),
                      onlyStickers: true,
                      onManagePressed: widget.onManagePressed,
                      manageTooltip: widget.manageTooltip,
                      previewOnHold: true,
                      // Vommet issue 790: Ctrl + wheel or a pinch resizes.
                      zoom: GridZoom.stickers,
                      onEmoticonPressed: (emoticon) =>
                          widget.onStickerPressed?.call(emoticon),
                    ),
                  ),
                if (currentTabs.contains(_PickerTab.gif))
                  Tab(
                    child: GifPicker(
                      focus: widget.gifSearchFocus,
                      favorites: widget.gifComponent?.favorites ?? [],
                      search: widget.gifComponent!.search,
                      placeholderText: widget.gifComponent!.searchPlaceholder,
                      favoritePicked: widget.onFavoritePicked,
                      gifPicked: widget.onGifPressed,
                      onUnfavoriteGif: (gif) async {
                        widget.gifComponent?.removeFavorite(gif);
                      },
                      searchEnabled: widget.allowGifSearch,
                      onTurnOnSearch: () =>
                          preferences.tenorGifSearchEnabled.set(true),
                    ),
                  )
              ]),
            ),
            if (controller.length > 1 || widget.onImportPressed != null)
              tiamat.Tile.low(
                child: SizedBox(
                  height: 40,
                  child: Row(children: [
                    Expanded(child: tabBar()),
                    if (widget.onImportPressed != null)
                      Tooltip(
                        message: tooltipEmojiPickerImport,
                        child: tiamat.IconButton(
                          icon: Icons.add_photo_alternate_outlined,
                          size: 20,
                          onPressed: widget.onImportPressed,
                        ),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget tabBar() {
    if (controller.length <= 1) return const SizedBox.shrink();
    return TabBar(
        controller: controller,
        dividerColor: Colors.transparent,
        dividerHeight: 0,
        tabs: [
          Tab(
            text: labelEmojiPickerEmojiTab,
          ),
          if (currentTabs.contains(_PickerTab.sticker))
            Tab(text: labelEmojiPickerStickerTab),
          if (currentTabs.contains(_PickerTab.gif))
            Tab(text: labelEmojiPickerGifTab)
        ]);
  }
}

enum _PickerTab { emoji, sticker, gif }
