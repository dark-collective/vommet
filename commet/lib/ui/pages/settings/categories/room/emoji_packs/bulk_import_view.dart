import 'dart:convert';
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:signal_sticker_api/signal_sticker_api.dart';
import 'package:tiamat/atoms/panel.dart';

import 'package:path/path.dart' as p;
import 'package:tiamat/tiamat.dart' as tiamat;

class EmoticonBulkImportDialog extends StatefulWidget {
  const EmoticonBulkImportDialog(
      {super.key, this.importPack, this.destinations});
  final Function(String name, int avatarIndex, List<String> names,
      List<Uint8List> imageDatas,
      {EmoticonUsage? usage})? importPack;

  /// Vommet: when set, the dialog asks where the images go (a new pack or
  /// an existing one) and performs the import itself; [importPack] is
  /// ignored.
  final List<EmoticonImportDestination>? destinations;

  @override
  State<EmoticonBulkImportDialog> createState() =>
      _EmoticonBulkImportDialogState();
}

class _EmoticonBulkImportDialogState extends State<EmoticonBulkImportDialog> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _packNameEditor = TextEditingController();
  final TextEditingController _emotePrefixEditor = TextEditingController();
  final TextEditingController _overrideNameEditor = TextEditingController();
  Debouncer debouncer = Debouncer(delay: const Duration(milliseconds: 500));

  List<String>? names;
  List<Uint8List?>? datas;
  List<ImageProvider?>? images;

  int? avatarIndex;

  // Indices whose image could not be downloaded; left out of the import.
  Set<int> failed = {};

  // Shown under the URL field: load errors and skipped-sticker notes.
  String? sourceMessage;

  // Bumped on every new URL so late responses for an old one are ignored.
  int _loadGeneration = 0;

  // Telegram custom-emoji sets import as emoji; everything else unset.
  EmoticonUsage? importUsage;

  String? prefix;
  String? overrideName;
  bool loading = false;

  bool useAsEmoji = false;
  bool useAsSticker = true;

  EmoticonImportDestination? destination;

  final TextEditingController _stickerRoomNameEditor =
      TextEditingController(text: "Sticker packs");

  bool get addingToExisting =>
      destination?.kind == EmoticonImportKind.addToPack;

  @override
  void initState() {
    destination = widget.destinations?.firstOrNull;
    _controller.addListener(onTextChanged);
    _emotePrefixEditor.addListener(onPrefixChanged);
    _overrideNameEditor.addListener(onOverrideChanged);
    super.initState();
  }

  void onTextChanged() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        loading = true;
      });
      debouncer.run(fetchUrl);
    } else {
      debouncer.cancel();
      setState(() {
        loading = false;
        reset();
      });
    }
  }

  void onPrefixChanged() {
    setState(() {
      prefix = _emotePrefixEditor.text;
    });
  }

  void onOverrideChanged() {
    setState(() {
      overrideName = _overrideNameEditor.text;
    });
  }

  List<String> ensureNoConflictingNames(List<String> names) {
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      if (names.where((element) => element == name).length > 1) {
        names[i] = "${name}_$i";
      }
    }

    return names;
  }

  String getFinalName(int index) {
    String name = names![index];
    if (overrideName != null && overrideName!.isNotEmpty) {
      name = overrideName!;
    }

    if (prefix != null) {
      name = "$prefix$name";
    }

    if (overrideName != null && overrideName!.isNotEmpty) {
      name = "${name}_$index";
    }

    return name;
  }

  void reset() {
    setState(() {
      _packNameEditor.text = "";
      _overrideNameEditor.text = "";
      _emotePrefixEditor.text = "";
      avatarIndex = null;
      names = null;
      datas = null;
      images = null;
      failed = {};
      sourceMessage = null;
      importUsage = null;
    });
  }

  Future<void> fetchUrl() async {
    var text = _controller.text;
    await UnicodeEmojis.loadShortcodeData();

    reset();
    final generation = ++_loadGeneration;

    final telegram = TelegramStickerLink.parse(text);
    if (telegram != null) {
      await loadTelegramPack(telegram, generation);
      return;
    }

    var uri = Uri.parse(text);
    if (["https", "http", "sgnl"].contains(uri.scheme)) {
      await loadSignalPack(uri);
    }
  }

  String _shortcodeFor(String? emoji, int index) {
    if (emoji != null && emoji.isNotEmpty) {
      final code = UnicodeEmojis.findShortcode(emoji);
      if (code != null && code.isNotEmpty) return code;
    }
    return "sticker_$index";
  }

  /// Telegram sticker and custom-emoji sets, fetched through the proxy (the
  /// Bot API needs a bot token, which only the proxy has). With conversion
  /// enabled on the proxy, animated stickers arrive as animated WebP.
  Future<void> loadTelegramPack(
      TelegramStickerLink link, int generation) async {
    final proxy = preferences.proxyUrl.value;

    Map<String, dynamic> set;
    try {
      final response = await http
          .get(Uri.https(proxy, "/proxy/telegram/stickers/${link.setName}"));
      final body = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(body is Map
            ? (body["error"] ?? response.statusCode)
            : response.statusCode);
      }
      set = body as Map<String, dynamic>;
    } catch (e) {
      Log.w("Could not load Telegram pack ${link.setName}: $e");
      if (generation != _loadGeneration || !mounted) return;
      setState(() {
        loading = false;
        sourceMessage = "Could not load this Telegram pack ($e).";
      });
      return;
    }

    if (generation != _loadGeneration || !mounted) return;

    final all = (set["stickers"] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // A proxy without conversion lists animated stickers as tgs/webm, which
    // Matrix clients can't display. Skip those and say how many.
    final usable = all.where((s) => s["format"] == "webp").toList();
    final skipped = all.length - usable.length;

    if (usable.isEmpty) {
      setState(() {
        loading = false;
        sourceMessage = all.isEmpty
            ? "This Telegram pack is empty."
            : "All ${all.length} stickers in this pack are animated, and $proxy can't convert them.";
      });
      return;
    }

    _packNameEditor.text = (set["title"] as String?) ?? link.setName;
    importUsage = link.isEmojiSet || set["sticker_type"] == "custom_emoji"
        ? EmoticonUsage.emoji
        : null;
    names = ensureNoConflictingNames([
      for (var i = 0; i < usable.length; i++)
        _shortcodeFor(usable[i]["emoji"] as String?, i)
    ]);
    datas = List.generate(usable.length, (index) => null);
    images = List.generate(usable.length, (index) => null);
    avatarIndex = 0;

    setState(() {
      loading = false;
      if (skipped > 0) {
        sourceMessage =
            "$skipped animated stickers were skipped because $proxy can't convert them.";
      }
    });

    for (var i = 0; i < usable.length; i++) {
      _downloadTelegramSticker(
          Uri.parse("https://$proxy${usable[i]["url"]}"), i, generation);
    }
  }

  Future<void> _downloadTelegramSticker(
      Uri url, int index, int generation) async {
    // Converted stickers can take a few seconds on first request; retry once.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http.get(url);
        if (generation != _loadGeneration || !mounted) return;
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          setState(() {
            datas![index] = response.bodyBytes;
            images![index] = Image.memory(response.bodyBytes).image;
          });
          return;
        }
        Log.w("Sticker download $url failed: HTTP ${response.statusCode}");
      } catch (e) {
        Log.w("Sticker download $url failed: $e");
      }
    }

    if (generation != _loadGeneration || !mounted) return;
    setState(() {
      failed.add(index);
      sourceMessage = "${failed.length} stickers could not be downloaded "
          "and will be left out.";
    });
  }

  Future<void> loadSignalPack(Uri uri) async {
    var client = SignalStickerClient(
        host: preferences.proxyUrl.value, rootPath: "/proxy/signal");

    var packInfo = client.getPackFromUri(uri);
    var pack = await client.getPack(packInfo!);
    _packNameEditor.text = pack!.name;

    names = ensureNoConflictingNames(pack.stickers
        .map((e) => e.emoji)
        .toList()
        .map((e) => UnicodeEmojis.findShortcode(e)!)
        .toList());
    datas = List.generate(names!.length, (index) => null);
    images = List.generate(names!.length, (index) => null);

    setState(() {
      loading = false;
    });

    var coverId = pack.cover;

    if (!pack.stickers.any((element) => element.id == pack.cover)) {
      coverId = pack.stickers.first.id;
    }

    for (var i = 0; i < pack.stickers.length; i++) {
      var sticker = pack.stickers[i];
      sticker.getData().then((value) {
        setState(() {
          var bytes = Uint8List.fromList(value!);
          datas![i] = bytes;
          images![i] = Image.memory(bytes).image;

          if (coverId == sticker.id) {
            avatarIndex = i;
          }
        });
      });
    }
  }

  Future<void> pickFolder() async {
    var files = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true, allowMultiple: true);

    setState(() {
      reset();
      datas = files!.files.map((e) => e.bytes!).toList();
      images = files.files.map((e) => Image.memory(e.bytes!).image).toList();
      names =
          files.files.map((e) => p.basenameWithoutExtension(e.name)).toList();
      avatarIndex = 0;
      _controller.text = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    bool loadingFinished = images != null &&
        List.generate(images!.length, (i) => i)
            .every((i) => images![i] != null || failed.contains(i));
    final keep = names == null || datas == null
        ? <int>[]
        : [
            for (var i = 0; i < names!.length; i++)
              if (datas![i] != null && !failed.contains(i)) i
          ];
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(width: 800, height: 800),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          sourceSelection(),
          if (loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          if (loading == false && names != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: MasonryGridView.extent(
                      itemCount: names!.length,
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      itemBuilder: entryBuilder),
                ),
              ),
            ),
          if (loading == false && names != null) packEdit(),
          if (images != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: tiamat.Button(
                isLoading: !loadingFinished,
                text:
                    "Import ${loadingFinished ? keep.length : names!.length} Emoticons!",
                onTap: () {
                  if (canCreatePack() && keep.isNotEmpty) {
                    var finalNames = keep.map((i) => getFinalName(i)).toList();
                    var avatar = keep.indexOf(avatarIndex ?? 0);
                    if (destination != null) {
                      importTo(
                          destination!,
                          _packNameEditor.text,
                          avatar < 0 ? 0 : avatar,
                          finalNames,
                          keep.map((i) => datas![i]!).toList());
                      return;
                    }
                    widget.importPack?.call(
                        _packNameEditor.text,
                        avatar < 0 ? 0 : avatar,
                        finalNames,
                        keep.map((i) => datas![i]!).toList(),
                        usage: importUsage);
                  }
                },
              ),
            )
        ],
      ),
    );
  }

  bool canCreatePack() {
    return addingToExisting || _packNameEditor.text.isNotEmpty;
  }

  void importTo(EmoticonImportDestination dest, String name, int avatarIndex,
      List<String> names, List<Uint8List> imageDatas) {
    final roomName = _stickerRoomNameEditor.text.trim();
    final work = switch (dest.kind) {
      EmoticonImportKind.addToPack => dest.component
          .addToPack(dest.pack!, names, imageDatas, usage: importUsage),
      EmoticonImportKind.newPack => dest.component.importEmoticonPack(
          name, avatarIndex, names, imageDatas,
          usage: importUsage),
      EmoticonImportKind.newStickerRoom => dest.component
          .importIntoNewStickerRoom(
              roomName.isEmpty ? "Sticker packs" : roomName,
              name,
              avatarIndex,
              names,
              imageDatas,
              usage: importUsage),
    };
    work.catchError((Object e) => Log.e("Emoticon import failed: $e"));
    Navigator.pop(context);
  }

  Widget destinationSelector() {
    final destinations = widget.destinations!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow("Import into"),
          ),
          SizedBox(
            height: 44,
            child: tiamat.DropdownSelector<EmoticonImportDestination>(
              itemHeight: 44,
              items: destinations,
              value: destination!,
              onItemSelected: (item) => setState(() => destination = item),
              itemBuilder: (item) => Row(
                children: [
                  Icon(switch (item.kind) {
                    EmoticonImportKind.newPack => Icons.add,
                    EmoticonImportKind.addToPack => Icons.library_add,
                    EmoticonImportKind.newStickerRoom => Icons.add_home_work,
                  }),
                  const SizedBox(width: 8),
                  Flexible(
                      child: tiamat.Text.label(item.label,
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          if (destination?.kind == EmoticonImportKind.newStickerRoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: tiamat.TextInput(
                controller: _stickerRoomNameEditor,
                label: "Sticker room name",
                maxLines: 1,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: tiamat.Text.labelLow(
                EmoticonImportDestinations.explainStickerRooms),
          ),
        ],
      ),
    );
  }

  Widget packEdit() {
    return Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: avatarIndex != null && images?[avatarIndex!] != null
                  ? tiamat.Avatar(
                      image: images![avatarIndex!],
                      radius: 50,
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.destinations != null &&
                      widget.destinations!.length > 1)
                    destinationSelector(),
                  if (!addingToExisting)
                    tiamat.TextInput(
                      controller: _packNameEditor,
                      label: "Pack Name",
                      maxLines: 1,
                    ),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: tiamat.Text.labelLow("Optional:"),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: tiamat.TextInput(
                          controller: _emotePrefixEditor,
                          label: "Prefix",
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(
                        width: 10,
                      ),
                      Flexible(
                        child: tiamat.TextInput(
                          controller: _overrideNameEditor,
                          label: "Override Name",
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sourceSelection() {
    return Panel(
        header: "Select pack source",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.TextInput(
              placeholder: "Enter URL",
              controller: _controller,
              maxLines: 1,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                    child: tiamat.Text.labelLow(
                        "Supports: Signal (sgnl://, signal.art) and Telegram (t.me/addstickers)")),
                Flexible(
                  child: tiamat.Text.labelLow(
                      "Request will be proxied via ${preferences.proxyUrl.value}"),
                ),
              ],
            ),
            if (sourceMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                child: tiamat.Text.labelLow(sourceMessage!),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 100,
                    height: 10,
                    child: tiamat.Seperator(),
                  ),
                  tiamat.Text.labelLow(CommonStrings.labelOr),
                  const SizedBox(
                    width: 100,
                    height: 10,
                    child: tiamat.Seperator(),
                  ),
                ],
              ),
            ),
            tiamat.Button(
              text: "Select Files",
              onTap: pickFolder,
            ),
          ],
        ));
  }

  Widget entryBuilder(BuildContext context, int index) {
    var background = index % 2 == 0
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : Theme.of(context).colorScheme.surfaceContainerHigh;

    var loading = images?[index] != null;

    return DecoratedBox(
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(5)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 150, minWidth: 150),
          child: failed.contains(index)
              ? const Center(child: Icon(Icons.broken_image_outlined))
              : loading
                  ? Column(
                      children: [
                        Image(
                          filterQuality: FilterQuality.medium,
                          fit: BoxFit.fill,
                          image: images![index]!,
                        ),
                        tiamat.Text.tiny(getFinalName(index))
                      ],
                    )
                  : const SizedBox(
                      width: 15,
                      height: 15,
                      child: Center(child: CircularProgressIndicator())),
        ),
      ),
    );
  }
}
