import 'dart:ui';

import 'package:commet/client/components/gif/gif_component.dart';
import 'package:commet/config/build_config.dart';
import 'package:commet/config/layout_config.dart';
import 'package:commet/ui/atoms/adaptive_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:commet/ui/molecules/my_gifs.dart';
import '../../utils/debounce.dart';
import '../../client/components/gif/gif_search_result.dart';

class GifPicker extends StatefulWidget {
  const GifPicker(
      {super.key,
      this.gifPicked,
      this.search,
      this.focus,
      this.favorites = const [],
      this.favoritePicked,
      this.onUnfavoriteGif,
      this.searchEnabled = true,
      this.onTurnOnSearch,
      this.placeholderText = "Search Gif"});
  final List<FavoriteGif> favorites;
  final Future<void> Function(GifSearchResult gif)? gifPicked;
  final Future<void> Function(FavoriteGif gif)? favoritePicked;
  final Future<void> Function(FavoriteGif gif)? onUnfavoriteGif;
  final Future<List<GifSearchResult>> Function(String query)? search;
  final FocusNode? focus;

  /// Vommet: while GIF search is off, the picker shows My GIFs with a
  /// "Turn on" button where the search box would be.
  final bool searchEnabled;
  final Future<void> Function()? onTurnOnSearch;

  final String placeholderText;

  @override
  State<GifPicker> createState() => _GifPickerState();

  static String get promptUnfavoriteGif => Intl.message(
        "Unfavorite GIF",
        desc: "Prompt the user remove a gif from favorites",
        name: "promptUnfavoriteGif",
      );
}

class _GifPickerState extends State<GifPicker> {
  List<GifSearchResult>? searchResult;
  bool searching = false;
  bool sending = false;
  late bool searchOn = widget.searchEnabled;

  final TextEditingController _textController = TextEditingController();
  Debouncer debouce = Debouncer(delay: const Duration(milliseconds: 500));

  @override
  void initState() {
    _textController.addListener(onTextChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vommet: as in EmojiPicker, a tab page can be gone by now.
      if (!mounted) return;
      if (MediaQuery.of(context).focusPickerSearch) {
        widget.focus?.requestFocus();
      }
    });

    super.initState();
  }

  String prevText = "";
  void onTextChanged() {
    if (_textController.text == prevText) {
      return;
    }

    prevText = _textController.text;

    if (_textController.text.isNotEmpty) {
      setState(() {
        searching = true;
        searchResult = null;
      });
      debouce.run(() => doSearch(_textController.text));
    } else {
      debouce.cancel();
      setState(() {
        searching = false;
      });
    }
  }

  void doSearch(String query) {
    setState(() {
      searching = true;
    });

    widget.search?.call(query).then((value) {
      setState(() {
        searchResult = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      buildContent(context),
      IgnorePointer(
        ignoring: !sending,
        child: AnimatedOpacity(
          opacity: sending ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: 2, sigmaY: 2, tileMode: TileMode.repeated),
            child: Container(
              color: Colors.black.withAlpha(100),
              child: const Center(
                  child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(),
              )),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget buildContent(BuildContext context) {
    if (BuildConfig.MOBILE) {
      return Column(children: [
        buildSearchBar(),
        ...buildMyGifsTitle(),
        buildSearch(context)
      ]);
    } else {
      return Column(children: [
        ...buildMyGifsTitle(),
        buildSearch(context),
        buildSearchBar()
      ]);
    }
  }

  Widget buildSearchBar() {
    if (!searchOn) return buildSearchOff();
    return tiamat.Tile.low(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
            height: BuildConfig.DESKTOP ? 30 : null,
            child: TextField(
              controller: _textController,
              focusNode: widget.focus,
              decoration: InputDecoration(
                  icon: const Icon(Icons.search),
                  isDense: true,
                  border: InputBorder.none,
                  hintText: widget.placeholderText),
            )),
      ),
    );
  }

  /// Vommet: the "My GIFs" heading above the saved GIFs.
  List<Widget> buildMyGifsTitle() {
    if (searching || widget.favorites.isEmpty) return [];
    final colors = ColorScheme.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Row(children: [
          Icon(Icons.bookmark, size: 16, color: colors.primary),
          const SizedBox(width: 6),
          Text(MyGifs.title,
              style: TextStyle(
                  color: colors.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ]),
      ),
    ];
  }

  Widget buildSearchOff() {
    final colors = ColorScheme.of(context);
    return tiamat.Tile.low(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(children: [
          Icon(Icons.search_off, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
              child: Text(MyGifs.searchOff,
                  style: TextStyle(color: colors.onSurfaceVariant))),
          tiamat.Button.secondary(
            text: MyGifs.promptTurnOnSearch,
            onTap: () async {
              await widget.onTurnOnSearch?.call();
              if (!mounted) return;
              setState(() => searchOn = true);
              widget.focus?.requestFocus();
            },
          ),
        ]),
      ),
    );
  }

  Widget buildMyGifsEmpty() {
    final colors = ColorScheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bookmark_add_outlined,
              size: 40, color: colors.onSurfaceVariant),
          const SizedBox(height: 12),
          tiamat.Text.labelEmphasised(MyGifs.emptyTitle),
          const SizedBox(height: 6),
          Text(MyGifs.emptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant)),
        ]),
      ),
    );
  }

  Widget buildSearch(BuildContext context) {
    if (!searching && widget.favorites.isEmpty) {
      return Expanded(child: buildMyGifsEmpty());
    }

    if (!searching) {
      return Expanded(
          child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: MasonryGridView.extent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 8,
          padding: EdgeInsetsGeometry.all(0),
          crossAxisSpacing: 8,
          itemCount: widget.favorites.length,
          itemBuilder: (context, index) {
            var result = widget.favorites.elementAt(index);
            return AdaptiveContextMenu(
              items: [
                tiamat.ContextMenuItem(
                  text: MyGifs.promptRemove,
                  icon: Icons.bookmark_remove_outlined,
                  onPressed: () {
                    widget.onUnfavoriteGif?.call(result);
                  },
                ),
              ],
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => sendFavoriteGif(result),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: ColorScheme.of(context).surfaceContainerLowest,
                      child: AspectRatio(
                        aspectRatio: result.width / result.height,
                        child: SizedBox(
                          child: Image(
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            image: result.image,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ));
    }

    if (searchResult == null)
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );

    return Expanded(
        child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: MasonryGridView.extent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 8,
        padding: EdgeInsetsGeometry.all(0),
        crossAxisSpacing: 8,
        itemCount: searchResult!.length,
        itemBuilder: (context, index) {
          var result = searchResult!.elementAt(index);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => sendGif(result),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  color: ColorScheme.of(context).surfaceContainerLowest,
                  child: AspectRatio(
                    aspectRatio: result.x / result.y,
                    child: SizedBox(
                      child: Image(
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        image: NetworkImage(result.previewUrl.toString()),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ));
  }

  void sendGif(GifSearchResult gif) {
    setState(() {
      sending = true;
    });

    widget.gifPicked?.call(gif).then((value) => setState(() {
          sending = false;
        }));
  }

  void sendFavoriteGif(FavoriteGif gif) {
    widget.favoritePicked?.call(gif);
  }
}
