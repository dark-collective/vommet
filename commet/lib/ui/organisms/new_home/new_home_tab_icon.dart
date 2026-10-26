import 'package:commet/client/components/emoticon/emoji_pack.dart';
import 'package:commet/client/components/emoticon/emoticon_component.dart';
import 'package:commet/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:commet/client/matrix/matrix_client.dart';
import 'package:commet/client/matrix/matrix_mxc_image_provider.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/atoms/emoji_widget.dart';
import 'package:commet/ui/molecules/emoji_picker.dart';
import 'package:commet/ui/navigation/adaptive_dialog.dart';
import 'package:commet/ui/organisms/new_home/new_home.dart';
import 'package:commet/ui/organisms/new_home/new_home_icon_catalog.dart';
import 'package:commet/utils/emoji/unicode_emoji.dart';
import 'package:commet/utils/picker_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tiamat/tiamat.dart' as tiamat;

// A tab's icon (Vommet issue 698) is one of:
// - a built-in name from [HomeTabs.icons] ("gamepad"),
// - `m:<name>`, an icon from [homeIconCatalog] ("m:casino"),
// - `e:<emoji>`, a Unicode emoji ("e:🎲"),
// - an `mxc://` image: an uploaded picture or a custom emoji.
// Builds that don't know a kind draw the default icon.

/// The icon of catalog entry [name], as a tab saves it.
String catalogTabIcon(String name) => "m:$name";

/// The emoji [emoji], as a tab saves it.
String emojiTabIcon(String emoji) => "e:$emoji";

bool isImageTabIcon(String icon) => icon.startsWith("mxc://");

/// The emoji of an `e:` icon, else null.
String? tabIconEmoji(String icon) =>
    icon.startsWith("e:") && icon.length > 2 ? icon.substring(2) : null;

final Map<String, IconData> _catalogIcons = {
  for (final entry in homeIconCatalog) entry.name: entry.icon,
};

/// The glyph of a built-in or `m:` icon, else null.
IconData? catalogIconData(String icon) =>
    icon.startsWith("m:") ? _catalogIcons[icon.substring(2)] : null;

/// The catalog icons for [query] in [category] (an index into
/// [homeIconCategories], or null for all), best matches first: a name
/// starting with the query, then a name containing it, then a keyword.
List<HomeIconEntry> searchHomeIcons(String query, {int? category}) {
  final inCategory = [
    for (final entry in homeIconCatalog)
      if (category == null || entry.categories & (1 << category) != 0) entry,
  ];
  final words = query.trim().toLowerCase().split(RegExp(r"\s+"))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return inCategory;
  int rank(HomeIconEntry entry) {
    final label = entry.label.toLowerCase();
    var worst = 0;
    for (final word in words) {
      final int score;
      if (label.startsWith(word)) {
        score = 1;
      } else if (label.split(" ").any((w) => w.startsWith(word))) {
        score = 2;
      } else if (label.contains(word)) {
        score = 3;
      } else if (entry.keywords.split(" ").any((k) => k.startsWith(word))) {
        score = 4;
      } else {
        return 0;
      }
      if (score > worst) worst = score;
    }
    return worst;
  }

  final ranked = [
    for (final entry in inCategory)
      if (rank(entry) case final r when r > 0) (r, entry),
  ];
  // List.sort isn't stable; break ties by catalog order.
  final order = {for (final (i, e) in inCategory.indexed) e.name: i};
  ranked.sort((a, b) => a.$1 != b.$1
      ? a.$1.compareTo(b.$1)
      : order[a.$2.name]!.compareTo(order[b.$2.name]!));
  return [for (final (_, entry) in ranked) entry];
}

/// The account tab icon images are uploaded to and listed on: the one
/// Home's layout is saved on, else the first.
MatrixClient? tabIconClient() =>
    HomeLayoutStore.instance.account.value ??
    clientManager?.clients.whereType<MatrixClient>().firstOrNull;

/// A tab's icon, whatever kind it is (see the top of this file).
class HomeTabIcon extends StatelessWidget {
  const HomeTabIcon(this.icon,
      {super.key, this.size = 20, this.color, this.semanticLabel});
  final String icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(homeTabIcon(icon),
        size: size, color: color, semanticLabel: semanticLabel);
    final emoji = tabIconEmoji(icon);
    if (emoji != null) {
      return Semantics(
        label: semanticLabel,
        child: SizedBox.square(
          dimension: size,
          child: EmojiWidget(UnicodeEmoticon(emoji), height: size),
        ),
      );
    }
    final uri = isImageTabIcon(icon) ? Uri.tryParse(icon) : null;
    final client = uri == null ? null : tabIconClient();
    if (uri == null || client == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image(
        image: MatrixMxcImage(uri, client.matrixClient, scaledThumbnail: true),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: semanticLabel,
        errorBuilder: (context, _, __) => fallback,
      ),
    );
  }
}

/// A tab's button in the sidebar: [tiamat.ImageButton] with its glyph or
/// picture, or the same outlined square holding its emoji.
Widget homeTabRailButton(
    {Key? key,
    required String icon,
    required double size,
    required String semanticsLabel,
    VoidCallback? onTap}) {
  final emoji = tabIconEmoji(icon);
  if (emoji == null) {
    final uri = isImageTabIcon(icon) ? Uri.tryParse(icon) : null;
    final client = uri == null ? null : tabIconClient();
    return tiamat.ImageButton(
      key: key,
      size: size,
      icon: homeTabIcon(icon),
      image: client == null
          ? null
          : MatrixMxcImage(uri!, client.matrixClient, scaledThumbnail: true),
      semanticsLabel: semanticsLabel,
      onTap: onTap,
    );
  }
  return Builder(builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(size / 3.4 + 2);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox.square(
        key: key,
        dimension: size,
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: scheme.outline, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: Center(
              child: ExcludeSemantics(
                  child:
                      EmojiWidget(UnicodeEmoticon(emoji), height: size / 2.2)),
            ),
          ),
        ),
      ),
    );
  });
}

/// Uploaded tab icons are this many pixels square.
const int tabIconPixels = 128;

/// Pictures larger than this aren't read (decoding them would stall).
const int maxTabIconSourceBytes = 15 * 1024 * 1024;

/// [bytes] (PNG, JPEG, WebP, GIF…) cropped to a centred square and shrunk
/// to [tabIconPixels], as PNG; only a GIF's first frame. Null if they
/// aren't a picture.
Uint8List? squareTabIconPng(Uint8List bytes) {
  final img.Image? picture;
  try {
    picture = img.decodeImage(bytes, frame: 0);
  } catch (_) {
    return null; // Not a picture (the decoders throw on some garbage).
  }
  if (picture == null) return null;
  final square = img.copyResizeCropSquare(picture,
      size: tabIconPixels, interpolation: img.Interpolation.average);
  return img.encodePng(square);
}

/// Account data listing the images used as tab icons, newest first.
const String tabIconImagesKey = "im.nether.vommet.home_tab_icons";

/// How many used images [tabIconImagesKey] keeps.
const int maxRecentTabImages = 12;

/// The images in [content] (that account data's content), newest first.
List<String> recentTabImagesFrom(Map<String, Object?>? content) {
  final list = content?["recent"];
  if (list is! List) return [];
  return list
      .whereType<String>()
      .where(isImageTabIcon)
      .toSet()
      .take(maxRecentTabImages)
      .toList();
}

List<String> recentTabImages(MatrixClient client) => recentTabImagesFrom(
    client.matrixClient.accountData[tabIconImagesKey]?.content);

/// [uri] first in the used images, the oldest beyond the limit dropped.
List<String> withRecentTabImage(List<String> recent, String uri) =>
    [uri, ...recent.where((u) => u != uri)].take(maxRecentTabImages).toList();

Future<void> _rememberTabImage(MatrixClient client, String uri) async {
  final userId = client.matrixClient.userID;
  if (userId == null) return;
  await client.matrixClient.setAccountData(userId, tabIconImagesKey, {
    "recent": withRecentTabImage(recentTabImages(client), uri),
  });
}

/// Picks a picture, makes it a [tabIconPixels] square and uploads it to
/// [tabIconClient]'s homeserver. Returns its `mxc://` link, or null when
/// nothing was picked or it failed (the error is shown).
Future<String?> uploadTabIconImage(BuildContext context) async {
  final client = tabIconClient();
  if (client == null) return null;
  final picked = await PickerUtils.pickImage();
  if (picked == null || !context.mounted) return null;
  try {
    final bytes = await picked.readAsBytes();
    if (bytes.length > maxTabIconSourceBytes) {
      throw const _TabIconError("That picture is too big (15 MB at most).");
    }
    final png = await compute(squareTabIconPng, bytes);
    if (png == null) {
      throw const _TabIconError("That file isn't a picture Vommet can read.");
    }
    final uri = (await client.matrixClient.uploadContent(png,
            filename: "tab-icon.png", contentType: "image/png"))
        .toString();
    await _rememberTabImage(client, uri);
    return uri;
  } catch (e, s) {
    if (context.mounted) {
      await AdaptiveDialog.showError(context, e, s,
          title: "Couldn’t upload the picture");
    }
    return null;
  }
}

class _TabIconError implements Exception {
  const _TabIconError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Opens the large icon picker; returns the picked icon, or null.
Future<String?> showHomeIconPicker(BuildContext context,
        {required String current}) =>
    showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: HomeIconPicker(current: current),
        ),
      ),
    );

/// Choose an icon: Icons (search + categories), Emoji (with the account's
/// emoji packs) and Your images (upload, or one used before).
class HomeIconPicker extends StatefulWidget {
  const HomeIconPicker({super.key, required this.current});

  /// The tab's icon now; selected when it's in the shown list.
  final String current;

  @override
  State<HomeIconPicker> createState() => _HomeIconPickerState();
}

class _HomeIconPickerState extends State<HomeIconPicker> {
  final TextEditingController search = TextEditingController();
  late String selected = widget.current;
  late int page = tabIconEmoji(widget.current) != null
      ? 1
      : isImageTabIcon(widget.current)
          ? 2
          : 0;
  int? category;
  bool uploading = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void use([String? icon]) => Navigator.of(context).pop(icon ?? selected);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Choose an icon",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (page == 0) ...[
            TextField(
              key: const ValueKey("NewHomeIconSearch"),
              controller: search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                final first = searchHomeIcons(search.text, category: category)
                    .firstOrNull;
                if (first != null) use(catalogTabIcon(first.name));
              },
              decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: "Search icons",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
          ],
          SegmentedButton<int>(
            key: const ValueKey("NewHomeIconPages"),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text("Icons")),
              ButtonSegment(value: 1, label: Text("Emoji")),
              ButtonSegment(value: 2, label: Text("Your images")),
            ],
            selected: {page},
            onSelectionChanged: (s) => setState(() => page = s.first),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: switch (page) {
              1 => _emojiPage(),
              2 => _imagesPage(scheme),
              _ => _iconsPage(scheme),
            },
          ),
          const SizedBox(height: 12),
          Row(spacing: 8, children: [
            HomeTabIcon(selected, size: 24, color: scheme.onSurface),
            const Spacer(),
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel")),
            FilledButton(
              key: const ValueKey("NewHomeIconUse"),
              onPressed: selected == widget.current ? null : use,
              child: const Text("Use icon"),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _iconsPage(ColorScheme scheme) {
    final results = searchHomeIcons(search.text, category: category);
    Widget chip(int? index, String label) => ChoiceChip(
          key: ValueKey("NewHomeIconCategory-${index ?? "all"}"),
          label: Text(label),
          selected: category == index,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => category = index),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          chip(null, "All"),
          for (final (i, name) in homeIconCategories.indexed) chip(i, name),
        ]),
        const SizedBox(height: 10),
        Flexible(
          child: results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text("No icons match “${search.text.trim()}”.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                )
              : GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 76,
                      mainAxisExtent: 64,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6),
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final entry = results[i];
                    final value = catalogTabIcon(entry.name);
                    final on = selected == value;
                    return Tooltip(
                      message: entry.label,
                      child: Material(
                        color: on
                            ? scheme.primary.withAlpha(60)
                            : scheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: on
                                ? BorderSide(color: scheme.primary, width: 1.5)
                                : BorderSide.none),
                        child: InkWell(
                          key: ValueKey("NewHomeIcon-${entry.name}"),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => selected = value),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 4,
                            children: [
                              Icon(entry.icon, size: 22),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(entry.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: scheme.onSurfaceVariant)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emojiPage() {
    final client = tabIconClient();
    List<EmoticonPack> packs;
    try {
      packs =
          client?.getComponent<EmoticonComponent>()?.availablePacks ?? const [];
    } catch (_) {
      // A broken pack (as in the message menu): fall back to Unicode.
      packs = UnicodeEmojis.packs ?? const [];
    }
    return SizedBox(
      height: 380,
      child: EmojiPicker(packs, onlyEmoji: true, packListAxis: Axis.horizontal,
          onEmoticonPressed: (emoticon) {
        final value = switch (emoticon) {
          MatrixEmoticon e => e.emojiUrl.toString(),
          _ => emojiTabIcon(emoticon.slug),
        };
        setState(() => selected = value);
      }),
    );
  }

  Widget _imagesPage(ColorScheme scheme) {
    final client = tabIconClient();
    final recent = client == null ? const <String>[] : recentTabImages(client);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          OutlinedButton.icon(
            key: const ValueKey("NewHomeIconUpload"),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18)),
            onPressed: uploading || client == null
                ? null
                : () async {
                    setState(() => uploading = true);
                    final uri = await uploadTabIconImage(context);
                    if (!mounted) return;
                    setState(() => uploading = false);
                    if (uri != null) use(uri);
                  },
            icon: uploading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_photo_alternate_rounded),
            label: const Text("Upload an image"),
          ),
          Text(
              "Cropped to a square and shrunk to $tabIconPixels px. Pictures "
              "are stored on your homeserver and aren’t end-to-end encrypted.",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          if (recent.isNotEmpty) ...[
            Text("Used before",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final uri in recent)
                InkWell(
                  key: ValueKey("NewHomeIconImage-$uri"),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => selected = uri),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: selected == uri
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2),
                    ),
                    child: HomeTabIcon(uri, size: 44),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}
