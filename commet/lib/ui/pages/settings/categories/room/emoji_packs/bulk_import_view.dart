import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:commet/debug/log.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/common_strings.dart';
import 'package:commet/utils/debounce.dart';
import 'package:commet/utils/background_tasks/pack_import_queue_task.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/sticker_pack_links.dart';
import 'package:commet/utils/sticker_pack_source.dart';
import 'package:commet/utils/telegram_sticker_link.dart';
import 'package:commet/ui/pages/settings/categories/room/emoji_packs/import_destinations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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

  // Vommet: what the imported images become. Stickers unless the user picks
  // otherwise (packs imported as both kept being sent as emoji by mistake);
  // Telegram custom-emoji sets preselect Emoji.
  EmoticonUsage importUsage = EmoticonUsage.sticker;

  String? prefix;
  String? overrideName;
  bool loading = false;

  bool useAsEmoji = false;
  bool useAsSticker = true;

  EmoticonImportDestination? destination;

  final TextEditingController _stickerRoomNameEditor =
      TextEditingController(text: bulkImportDefaultStickerRoomName);

  bool get addingToExisting =>
      destination?.kind == EmoticonImportKind.addToPack;

  // Vommet: multi-link import. Set while the box holds two or more links;
  // each becomes its own pack, imported one at a time in the background.
  StickerPackLinkList? multi;
  List<_MultiPackRow> multiRows = [];
  late final List<EmoticonImportDestination> multiDestinations =
      EmoticonImportDestinations.forMultiImport(widget.destinations ?? []);
  EmoticonImportDestination? multiDestination;

  // Keeps the link box (and its focus) when the dialog switches between
  // the single-pack and the multi-pack layout.
  final GlobalKey _linkFieldKey = GlobalKey();
  final ScrollController _multiListScroll = ScrollController();

  @override
  void initState() {
    destination = widget.destinations?.firstOrNull;
    multiDestination = multiDestinations.firstOrNull;
    _controller.addListener(onTextChanged);
    _emotePrefixEditor.addListener(onPrefixChanged);
    _overrideNameEditor.addListener(onOverrideChanged);
    super.initState();
  }

  // The controller also notifies on cursor moves; only new text reloads.
  String _lastText = "";

  void onTextChanged() {
    if (_controller.text == _lastText) return;
    _lastText = _controller.text;
    if (_controller.text.isNotEmpty) {
      setState(() {
        loading = true;
      });
      debouncer.run(fetchUrl);
    } else {
      debouncer.cancel();
      _loadGeneration++;
      setState(() {
        loading = false;
        multi = null;
        multiRows = [];
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
      importUsage = EmoticonUsage.sticker;
    });
  }

  Future<void> fetchUrl() async {
    var text = _controller.text;
    final parsed = StickerPackLinkList.parse(text);
    if (parsed.links.length > 1) {
      fetchMulti(parsed);
      return;
    }
    if (multi != null) setState(() => multi = null);
    if (parsed.links.length == 1) text = parsed.links.first.raw;

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
        sourceMessage = bulkImportTelegramLoadFailed(e.toString());
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
            ? bulkImportTelegramEmpty
            : bulkImportTelegramAllAnimated(all.length, proxy);
      });
      return;
    }

    _packNameEditor.text = (set["title"] as String?) ?? link.setName;
    importUsage = link.isEmojiSet || set["sticker_type"] == "custom_emoji"
        ? EmoticonUsage.emoji
        : EmoticonUsage.sticker;
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
        sourceMessage = bulkImportTelegramSkippedAnimated(skipped, proxy);
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
      sourceMessage = bulkImportDownloadsFailed(failed.length);
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
  void dispose() {
    _loadGeneration++;
    debouncer.cancel();
    _multiListScroll.dispose();
    super.dispose();
  }

  String labelFoundStickerPacks(int packs, int images, int failed) =>
      Intl.message("Found $packs packs · $images images · $failed failed",
          args: [packs, images, failed],
          name: "labelFoundStickerPacks",
          desc: "Summary of a multi-link sticker pack import");

  String labelLookingUpStickerPacks(int left) => Intl.message(
      "Looking up $left more…",
      args: [left],
      name: "labelLookingUpStickerPacks",
      desc: "Multi-link sticker import: links whose packs are still loading");

  String labelStickerLinksLeftOut(int max, int count) => Intl.message(
      "Only the first $max links are used; $count more were left out.",
      args: [max, count],
      name: "labelStickerLinksLeftOut",
      desc: "Multi-link sticker import: more links were pasted than allowed");

  String labelStickerPackImageCount(int count) => Intl.plural(count,
      one: "$count image",
      other: "$count images",
      args: [count],
      name: "labelStickerPackImageCount",
      desc: "Number of images in a sticker pack");

  String labelStickerPackCouldNotLoad(String reason) =>
      Intl.message("Couldn't load: $reason",
          args: [reason],
          name: "labelStickerPackCouldNotLoad",
          desc: "A pasted sticker pack link that failed to load");

  String get labelStickerPackLinks =>
      Intl.message("Pack links: one per line, or paste a whole list",
          name: "labelStickerPackLinks",
          desc: "Label of the link box in the sticker pack import dialog");

  String get labelSupportedStickerLinks => Intl.message(
      "Supports Telegram (t.me/addstickers, t.me/addemoji) and Signal links.",
      name: "labelSupportedStickerLinks",
      desc: "Which links the sticker pack import understands");

  String get labelStickerImportRunsInBackground => Intl.message(
      "Runs in the background. Packs import one at a time.",
      name: "labelStickerImportRunsInBackground",
      desc: "Multi-link sticker import: the import continues after closing");

  String promptImportStickerPacks(int count) => Intl.plural(count,
      one: "Import $count pack",
      other: "Import $count packs",
      args: [count],
      name: "promptImportStickerPacks",
      desc: "Button that starts a multi-link sticker pack import");

  String get promptSelectAllStickerPacks => Intl.message("Select all",
      name: "promptSelectAllStickerPacks",
      desc: "Ticks every pack in the multi-link sticker import");

  String get promptSelectNoStickerPacks => Intl.message("Select none",
      name: "promptSelectNoStickerPacks",
      desc: "Unticks every pack in the multi-link sticker import");

  String get labelStickerPackKindStickers => Intl.message("Stickers",
      name: "labelStickerPackKindStickers",
      desc: "Chip on a sticker pack that holds stickers");

  String get labelStickerPackKindEmoji => Intl.message("Emoji",
      name: "labelStickerPackKindEmoji",
      desc: "Chip on a sticker pack that holds custom emoji");

  String get labelImportUseAs => Intl.message("Use as",
      name: "labelImportUseAs",
      desc:
          "Label above the choice of whether imported images become stickers, emoji, or both");

  String get labelImportUsageBoth => Intl.message("Both",
      name: "labelImportUsageBoth",
      desc:
          "Choice in the pack import: the images can be used as stickers and as emoji");

  String get explainImportUsage => Intl.message(
      "Stickers are sent as their own message. Emoji go inside your text and reactions.",
      name: "explainImportUsage",
      desc: "Explains the Stickers / Emoji / Both choice in the pack import");

  String promptImportStickers(int count) => Intl.plural(count,
      one: "Import $count sticker",
      other: "Import $count stickers",
      args: [count],
      name: "promptImportStickers",
      desc: "Button that imports a pack's images as stickers");

  String promptImportEmoji(int count) => Intl.plural(count,
      one: "Import $count emoji",
      other: "Import $count emoji",
      args: [count],
      name: "promptImportEmoji",
      desc: "Button that imports a pack's images as custom emoji");

  String promptImportStickersAndEmoji(int count) => Intl.plural(count,
      one: "Import $count sticker & emoji",
      other: "Import $count stickers & emoji",
      args: [count],
      name: "promptImportStickersAndEmoji",
      desc:
          "Button that imports a pack's images as both stickers and custom emoji");

  void fetchMulti(StickerPackLinkList parsed) {
    final generation = ++_loadGeneration;
    final previous = {
      for (final row in multiRows)
        if (row.source != null) row.link.key: row
    };
    setState(() {
      loading = false;
      multi = parsed;
      multiRows = [
        for (final link in parsed.links)
          previous[link.key] ?? _MultiPackRow(link),
      ];
    });

    final todo = multiRows.where((r) => r.source == null).toList();
    StickerPackSource.fetchAll(
      [for (final r in todo) r.link],
      proxy: preferences.proxyUrl.value,
      isCancelled: () => generation != _loadGeneration || !mounted,
      onEach: (i, source) {
        setState(() {
          todo[i].source = source;
          todo[i].selected = source.ok;
          todo[i].usage = source.usage ?? EmoticonUsage.sticker;
        });
      },
    );
  }

  Widget linkField({required bool multiLine}) {
    return tiamat.TextInput(
      key: _linkFieldKey,
      label: labelStickerPackLinks,
      controller: _controller,
      minLines: 1,
      maxLines: multiLine ? 5 : 3,
    );
  }

  Widget buildMulti(BuildContext context) {
    final rows = multiRows;
    final loaded = rows.where((r) => r.source != null);
    final ok = loaded.where((r) => r.source!.ok);
    final failedCount = loaded.length - ok.length;
    final images = ok.fold<int>(0, (sum, r) => sum + r.source!.imageCount);
    final selected = rows.where((r) => r.selected && r.source?.ok == true);
    final pending = rows.length - loaded.length;
    final height = math.min(800.0, MediaQuery.of(context).size.height * 0.75);

    return SizedBox(
      width: 800,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
            child: linkField(multiLine: true),
          ),
          tiamat.Text.labelLow(labelSupportedStickerLinks),
          if ((multi?.leftOut ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: tiamat.Text.labelLow(labelStickerLinksLeftOut(
                  StickerPackLinkList.maxLinks, multi!.leftOut)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                tiamat.Text.labelEmphasised(
                    labelFoundStickerPacks(ok.length, images, failedCount) +
                        (pending > 0
                            ? " · ${labelLookingUpStickerPacks(pending)}"
                            : "")),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    tiamat.Button.secondary(
                        text: promptSelectAllStickerPacks,
                        onTap: () => setState(() {
                              for (final r in rows) {
                                r.selected = r.source?.ok == true;
                              }
                            })),
                    const SizedBox(width: 8),
                    tiamat.Button.secondary(
                        text: promptSelectNoStickerPacks,
                        onTap: () => setState(() {
                              for (final r in rows) {
                                r.selected = false;
                              }
                            })),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Scrollbar(
                  controller: _multiListScroll,
                  child: ListView.builder(
                    controller: _multiListScroll,
                    itemCount: rows.length,
                    itemBuilder: (context, i) => multiRow(context, rows[i]),
                  ),
                ),
              ),
            ),
          ),
          if (multiDestinations.isNotEmpty) multiDestinationSelector(),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
            child: Row(
              children: [
                Expanded(
                    child: tiamat.Text.labelLow(
                        labelStickerImportRunsInBackground)),
                const SizedBox(width: 8),
                tiamat.Button(
                  text: promptImportStickerPacks(selected.length),
                  onTap: selected.isEmpty || multiDestination == null
                      ? null
                      : () => startMultiImport(selected.toList()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget multiRow(BuildContext context, _MultiPackRow row) {
    final source = row.source;
    final colors = Theme.of(context).colorScheme;
    final failed = source != null && !source.ok;

    Widget thumbnail;
    if (source?.thumbnail != null) {
      thumbnail = Image.memory(source!.thumbnail!,
          fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    } else if (source == null) {
      thumbnail = const Padding(
        padding: EdgeInsets.all(10),
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      thumbnail = Icon(failed ? Icons.help_outline : Icons.image_outlined,
          color: colors.onSurfaceVariant);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          Checkbox(
            value: row.selected,
            onChanged: source?.ok == true
                ? (v) => setState(() => row.selected = v ?? false)
                : null,
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              color: colors.surfaceContainerHighest,
              alignment: Alignment.center,
              child: thumbnail,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text.labelEmphasised(
                    source?.displayName ??
                        row.link.telegram?.setName ??
                        row.link.raw,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                if (source == null)
                  tiamat.Text.labelLow(row.link.raw,
                      overflow: TextOverflow.ellipsis, maxLines: 1)
                else if (failed)
                  tiamat.Text.labelLow(
                      labelStickerPackCouldNotLoad(source.error!),
                      color: colors.error,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1)
                else
                  tiamat.Text.labelLow(
                      labelStickerPackImageCount(source.imageCount)),
              ],
            ),
          ),
          if (source != null && source.ok) multiRowUsage(context, row),
        ],
      ),
    );
  }

  // Tappable chip on a pack row: what that pack imports as.
  Widget multiRowUsage(BuildContext context, _MultiPackRow row) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<EmoticonUsage>(
      tooltip: labelImportUseAs,
      initialValue: row.usage,
      onSelected: (usage) => setState(() => row.usage = usage),
      itemBuilder: (context) => [
        for (final usage in importUsageChoices)
          PopupMenuItem(
            value: usage,
            child: Row(
              children: [
                Icon(importUsageIcon(usage), size: 20),
                const SizedBox(width: 8),
                Text(importUsageLabel(usage)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.Text.labelLow(importUsageLabel(row.usage)),
            Icon(Icons.arrow_drop_down,
                size: 18, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static const importUsageChoices = [
    EmoticonUsage.sticker,
    EmoticonUsage.emoji,
    EmoticonUsage.all,
  ];

  static IconData importUsageIcon(EmoticonUsage usage) => switch (usage) {
        EmoticonUsage.emoji => Icons.emoji_emotions,
        EmoticonUsage.all => Icons.star,
        _ => Icons.sticky_note_2,
      };

  String importUsageLabel(EmoticonUsage usage) => switch (usage) {
        EmoticonUsage.emoji => labelStickerPackKindEmoji,
        EmoticonUsage.all => labelImportUsageBoth,
        _ => labelStickerPackKindStickers,
      };

  String importButtonLabel(int count) => switch (importUsage) {
        EmoticonUsage.emoji => promptImportEmoji(count),
        EmoticonUsage.all => promptImportStickersAndEmoji(count),
        _ => promptImportStickers(count),
      };

  // Single-pack import: Stickers / Emoji / Both, under the pack details.
  Widget usageSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow(labelImportUseAs),
          ),
          // Icons only when there's room, so labels never wrap on phones.
          LayoutBuilder(
            builder: (context, constraints) => SegmentedButton<EmoticonUsage>(
              showSelectedIcon: false,
              segments: [
                for (final usage in importUsageChoices)
                  ButtonSegment(
                      value: usage,
                      icon: constraints.maxWidth < 340
                          ? null
                          : Icon(importUsageIcon(usage)),
                      label: Text(importUsageLabel(usage))),
              ],
              selected: {importUsage},
              onSelectionChanged: (selected) =>
                  setState(() => importUsage = selected.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: tiamat.Text.labelLow(explainImportUsage),
          ),
        ],
      ),
    );
  }

  Widget multiDestinationSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow(bulkImportImportInto),
          ),
          SizedBox(
            height: 44,
            child: tiamat.DropdownSelector<EmoticonImportDestination>(
              itemHeight: 44,
              items: multiDestinations,
              value: multiDestination!,
              onItemSelected: (item) => setState(() => multiDestination = item),
              itemBuilder: (item) => Row(
                children: [
                  Icon(item.kind == EmoticonImportKind.newStickerRoom
                      ? Icons.add_home_work
                      : Icons.add),
                  const SizedBox(width: 8),
                  Flexible(
                      child: tiamat.Text.label(item.label,
                          overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ),
          if (multiDestination?.kind == EmoticonImportKind.newStickerRoom)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
              child: tiamat.TextInput(
                controller: _stickerRoomNameEditor,
                label: bulkImportStickerRoomName,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  /// Closes the dialog and imports [sources] one after the other in the
  /// background; each pack is written (and usable) as soon as it's done.
  void startMultiImport(List<_MultiPackRow> rows) {
    final dest = multiDestination!;
    final roomName = _stickerRoomNameEditor.text.trim();
    Future<EmoticonComponent>? target;

    final jobs = [
      for (final (source, usage) in rows.map((r) => (r.source!, r.usage)))
        PackImportJob(
          name: source.displayName,
          imageCount: source.imageCount,
          thumbnail: source.thumbnail,
          run: (progress) async {
            final component = await (target ??= _resolveMultiTarget(
                dest,
                roomName.isEmpty
                    ? bulkImportDefaultStickerRoomName
                    : roomName));
            final images = await source
                .loadImages((done, total) => progress(done / (2 * total), 0));
            await component.importEmoticonPack(source.displayName,
                images.avatarIndex, images.names, images.datas,
                usage: usage,
                onProgress: (done, total) =>
                    progress(0.5 + done / (2 * total), done));
          },
        ),
    ];

    final task = PackImportQueueTask(jobs);
    backgroundTaskManager.addTask(task);
    unawaited(task.start());
    Navigator.pop(context);
  }

  /// The component new packs go to; creates the sticker room for a
  /// "new sticker room" destination (once, for all packs).
  static Future<EmoticonComponent> _resolveMultiTarget(
      EmoticonImportDestination dest, String roomName) async {
    if (dest.kind != EmoticonImportKind.newStickerRoom) return dest.component;

    final account = dest.component;
    final roomId = await account.createStickerRoom(roomName);
    for (var i = 0; i < 120; i++) {
      for (final c in account.stickerRoomComponents) {
        if (c is RoomEmoticonComponent && c.room.identifier == roomId) {
          return c;
        }
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }
    throw Exception("the new sticker room didn't appear");
  }

  @override
  Widget build(BuildContext context) {
    if (multi != null) return buildMulti(context);

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
                text: importButtonLabel(
                    loadingFinished ? keep.length : names!.length),
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
              roomName.isEmpty ? bulkImportDefaultStickerRoomName : roomName,
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
          Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: tiamat.Text.labelLow(bulkImportImportInto),
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
                label: bulkImportStickerRoomName,
                maxLines: 1,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: tiamat.Text.labelLow(
                EmoticonImportDestinations.explainStickerRoomsV2),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            usageSelector(),
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
            // Vommet: takes a list of links too (multi-pack import).
            linkField(multiLine: false),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                    child: tiamat.Text.labelLow(labelSupportedStickerLinks)),
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

/// Vommet: one pasted link in the multi-link import.
class _MultiPackRow {
  _MultiPackRow(this.link);
  final StickerPackLink link;

  /// Null while the pack is being looked up.
  StickerPackSource? source;
  bool selected = false;

  /// What the pack imports as; stickers unless it's an emoji set.
  EmoticonUsage usage = EmoticonUsage.sticker;
}

String get bulkImportDefaultStickerRoomName => Intl.message("Sticker packs",
    name: "bulkImportDefaultStickerRoomName",
    desc: "Default name of a new sticker room created by a pack import");

String bulkImportTelegramLoadFailed(String error) => Intl.message(
    "Could not load this Telegram pack ($error).",
    args: [error],
    name: "bulkImportTelegramLoadFailed",
    desc:
        "Error when a Telegram sticker pack could not be loaded; error is the technical error text");

String get bulkImportTelegramEmpty =>
    Intl.message("This Telegram pack is empty.",
        name: "bulkImportTelegramEmpty",
        desc: "Shown when a Telegram sticker pack has no stickers");

String bulkImportTelegramAllAnimated(int count, String proxy) => Intl.message(
    "All $count stickers in this pack are animated, and $proxy can't convert them.",
    args: [count, proxy],
    name: "bulkImportTelegramAllAnimated",
    desc:
        "Shown when every sticker in a Telegram pack is animated and the proxy cannot convert them; proxy is a host name");

String bulkImportTelegramSkippedAnimated(int count, String proxy) => Intl.message(
    "$count animated stickers were skipped because $proxy can't convert them.",
    args: [count, proxy],
    name: "bulkImportTelegramSkippedAnimated",
    desc:
        "Shown when some animated stickers were skipped; proxy is a host name");

String bulkImportDownloadsFailed(int count) => Intl.message(
    "$count stickers could not be downloaded and will be left out.",
    args: [count],
    name: "bulkImportDownloadsFailed",
    desc: "Shown when some stickers could not be downloaded");

String get bulkImportImportInto => Intl.message("Import into",
    name: "bulkImportImportInto",
    desc: "Label above the import destination picker");

String get bulkImportStickerRoomName => Intl.message("Sticker room name",
    name: "bulkImportStickerRoomName",
    desc: "Label of the field naming a new sticker room");
