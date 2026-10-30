import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';

/// Vommet: one editable color of a theme. [key] is the theme.json name:
/// a `colorScheme` entry, except [foundationKey] (the window behind panels).
/// [optionalKeys] may be unset (automatic): a draft holds them only once
/// picked, so an unset one stays unset in theme.json.
class ThemeSlot {
  const ThemeSlot(this.key, this.group);

  final String key;
  final ThemeSlotGroup group;

  static const foundationKey = "foundation";

  /// Chat bubble backgrounds (Vommet issue 532).
  static const ownBubbleKey = "ownBubble";
  static const otherBubbleKey = "otherBubble";

  /// The open room's highlight in the room list (Vommet issue 573).
  static const selectedRoomKey = "selectedRoom";
  static const optionalKeys = {ownBubbleKey, otherBubbleKey, selectedRoomKey};

  /// In the order the editor lists them.
  static const all = [
    ThemeSlot("primary", ThemeSlotGroup.accent),
    ThemeSlot("onPrimary", ThemeSlotGroup.accent),
    ThemeSlot("links", ThemeSlotGroup.accent),
    ThemeSlot("surface", ThemeSlotGroup.backgrounds),
    ThemeSlot("surfaceContainerLow", ThemeSlotGroup.backgrounds),
    ThemeSlot(selectedRoomKey, ThemeSlotGroup.backgrounds),
    ThemeSlot("surfaceContainerLowest", ThemeSlotGroup.backgrounds),
    ThemeSlot(foundationKey, ThemeSlotGroup.backgrounds),
    ThemeSlot("surfaceContainer", ThemeSlotGroup.backgrounds),
    ThemeSlot("surfaceContainerHigh", ThemeSlotGroup.backgrounds),
    ThemeSlot("surfaceContainerHighest", ThemeSlotGroup.backgrounds),
    ThemeSlot(ownBubbleKey, ThemeSlotGroup.bubbles),
    ThemeSlot(otherBubbleKey, ThemeSlotGroup.bubbles),
    ThemeSlot("onSurface", ThemeSlotGroup.text),
    ThemeSlot("secondary", ThemeSlotGroup.text),
    ThemeSlot("tertiary", ThemeSlotGroup.status),
    ThemeSlot("error", ThemeSlotGroup.status),
    ThemeSlot("outline", ThemeSlotGroup.status),
    ThemeSlot("codeHighlight", ThemeSlotGroup.status),
  ];

  /// Null only for an unset [optionalKeys] color.
  static Color? read(ThemeData theme, String key) {
    var s = theme.colorScheme;
    var extra = theme.extension<ExtraColors>() ?? ExtraColors.fromScheme(s);
    return switch (key) {
      "primary" => s.primary,
      "onPrimary" => s.onPrimary,
      "links" => extra.linkColor,
      "surface" => s.surface,
      "surfaceContainerLow" => s.surfaceContainerLow,
      "surfaceContainerLowest" => s.surfaceContainerLowest,
      foundationKey =>
        theme.extension<FoundationSettings>()?.color ?? s.surfaceDim,
      "surfaceContainer" => s.surfaceContainer,
      "surfaceContainerHigh" => s.surfaceContainerHigh,
      "surfaceContainerHighest" => s.surfaceContainerHighest,
      "onSurface" => s.onSurface,
      "secondary" => s.secondary,
      "tertiary" => s.tertiary,
      "error" => s.error,
      "outline" => s.outline,
      "codeHighlight" => extra.codeHighlight,
      ownBubbleKey => extra.ownBubble,
      otherBubbleKey => extra.otherBubble,
      selectedRoomKey => extra.selectedRoom,
      _ => s.primary,
    };
  }
}

enum ThemeSlotGroup { accent, backgrounds, bubbles, text, status }

/// What sits behind the panels: the Window color, a gradient or an image.
enum ThemeBackground { solid, gradient, image }

String colorToHex(Color c) {
  var argb = c.toARGB32();
  var rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, "0");
  var alpha = argb >> 24;
  return alpha == 0xff
      ? "#$rgb"
      : "#${alpha.toRadixString(16).padLeft(2, "0")}$rgb";
}

Color? colorFromHex(String text) {
  var hex = text.trim().replaceFirst("#", "");
  if (!RegExp(r"^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$").hasMatch(hex)) {
    return null;
  }
  if (hex.length == 6) hex = "ff$hex";
  return Color(int.parse(hex, radix: 16));
}

/// Vommet: a theme being edited. Saved as an ordinary custom theme
/// (`theme/custom/<name>/theme.json`), so it shows in the theme list, can be
/// shared as a .zip, and imports anywhere the + button exists.
class ThemeDraft {
  ThemeDraft(
      {required this.name,
      required this.brightness,
      required this.colors,
      Map<String, dynamic>? raw,
      this.sourceDir,
      this.sourceName,
      this.background = ThemeBackground.solid,
      List<Color>? gradientColors,
      this.gradientStops,
      this.gradientAngle = 135,
      this.imageFile,
      this.imageBytes,
      this.roomListOpacity = 0.85,
      this.chatOpacity = 0.8,
      this.blur = 0,
      this.cornerRadius = 1,
      this.spacing = 0,
      this.borders = true,
      this.chatColors,
      this.chatPattern,
      this.chatPatternStrength = 0.5,
      this.bubbleRadius = ChatStyle.defaultBubbleRadius,
      this.importedFrom})
      : raw = raw ?? {},
        gradientColors = gradientColors ??
            const [Color(0xff2e3440), Color(0xff3b5b6e), Color(0xff8fbcbb)];

  String name;
  Brightness brightness;
  Map<String, Color> colors;

  ThemeBackground background;
  List<Color> gradientColors;

  /// Where each color sits (0..1); null spreads them evenly. Kept so a
  /// gradient theme opens in the editor looking exactly as it did.
  List<double>? gradientStops;

  /// CSS degrees, as gradient themes use them.
  double gradientAngle;

  /// The background image: a file name inside the theme's folder, or a full
  /// path to a newly picked picture, copied in on save.
  String? imageFile;

  /// Web: a newly picked picture (browsers give bytes, not a path), stored
  /// with the theme on save. [imageFile] then holds its file name.
  Uint8List? imageBytes;

  /// See-through amount of the room list and chat over a gradient or image.
  double roomListOpacity;
  double chatOpacity;
  double blur;

  double cornerRadius;
  double spacing;
  bool borders;

  /// Behind the messages (Telegram themes): one color or a gradient; null =
  /// the plain chat color.
  List<Color>? chatColors;

  /// [ChatStyle.telegramPattern] or null.
  String? chatPattern;
  double chatPatternStrength;

  /// Chat bubble corners (Chat bubbles layout only).
  double bubbleRadius;

  /// Set by the Telegram importer ("Telegram Desktop", "Telegram Android"),
  /// so the editor can say where the theme came from. Not saved.
  String? importedFrom;

  /// The theme.json this draft came from; keys the editor doesn't touch
  /// (glass, shadows, a background image) are written back unchanged.
  final Map<String, dynamic> raw;

  /// Set when editing a custom theme, so its other files (a background
  /// image) travel with a save under a new name.
  final Directory? sourceDir;

  /// Web: the name of the custom theme in the browser's storage this draft
  /// edits, so its background image travels with a save.
  String? sourceName;

  /// Web: [sourceName]'s files, read once per draft and its copies.
  Future<Map<String, Uint8List>>? _sourceFiles;

  factory ThemeDraft.fromTheme(ThemeData theme, String name,
      {Map<String, dynamic>? raw, Directory? sourceDir, String? sourceName}) {
    var foundation = theme.extension<FoundationSettings>();
    var glass = theme.extension<GlassSettings>();
    var settings = theme.extension<ThemeSettings>();
    var gradient = foundation?.gradient;
    var image = foundation?.image;
    var chat = theme.extension<ChatStyle>();

    var background = ThemeBackground.solid;
    List<Color>? stops;
    List<double>? positions;
    double angle = 135;
    String? imageFile;
    if (image is FileImage) {
      background = ThemeBackground.image;
      imageFile = path.basename(image.file.path);
    } else if (image is MemoryImage) {
      // Web: a stored theme's picture; its name is in the theme.json.
      var file = ((raw?["foundation"] as Map?)?["image"] as Map?)?["file"];
      if (file is String) {
        background = ThemeBackground.image;
        imageFile = file;
      }
    } else if (gradient is LinearGradient && gradient.colors.length >= 2) {
      background = ThemeBackground.gradient;
      stops = List.of(gradient.colors);
      positions = gradient.stops == null ? null : List.of(gradient.stops!);
      angle = angleOf(gradient);
    }

    return ThemeDraft(
      name: name,
      brightness: theme.brightness,
      colors: {
        for (var slot in ThemeSlot.all)
          if (ThemeSlot.read(theme, slot.key) case var color?) slot.key: color
      },
      raw: raw,
      sourceDir: sourceDir,
      sourceName: sourceName,
      background: background,
      gradientColors: stops,
      gradientStops: positions,
      gradientAngle: angle,
      imageFile: imageFile,
      roomListOpacity: glass?.surfaceContainerLowOpacity ?? 0.85,
      chatOpacity: glass?.surfaceOpacity ?? 0.8,
      blur: glass?.surfaceSigma ?? 0,
      cornerRadius: settings?.caulkBorderRadius ?? 0,
      spacing: settings?.caulkPadding ?? 0,
      borders: settings?.caulkBorders ?? false,
      chatColors: chat?.colors == null ? null : List.of(chat!.colors!),
      chatPattern: chat?.pattern,
      chatPatternStrength: chat?.patternStrength ?? 0.5,
      bubbleRadius: chat?.bubbleRadius ?? ChatStyle.defaultBubbleRadius,
    );
  }

  /// The CSS angle of a gradient built by [GradientPreset.gradient].
  static double angleOf(LinearGradient gradient) {
    var begin = gradient.begin;
    if (begin is! Alignment) return 180;
    var degrees = math.atan2(-begin.x, begin.y) * 180 / math.pi;
    return (degrees % 360 + 360) % 360;
  }

  ThemeDraft copy() => ThemeDraft(
      name: name,
      brightness: brightness,
      colors: Map.of(colors),
      raw: raw,
      sourceDir: sourceDir,
      sourceName: sourceName,
      background: background,
      gradientColors: List.of(gradientColors),
      gradientStops: gradientStops == null ? null : List.of(gradientStops!),
      gradientAngle: gradientAngle,
      imageFile: imageFile,
      imageBytes: imageBytes,
      roomListOpacity: roomListOpacity,
      chatOpacity: chatOpacity,
      blur: blur,
      cornerRadius: cornerRadius,
      spacing: spacing,
      borders: borders,
      chatColors: chatColors == null ? null : List.of(chatColors!),
      chatPattern: chatPattern,
      chatPatternStrength: chatPatternStrength,
      bubbleRadius: bubbleRadius,
      importedFrom: importedFrom)
    .._sourceFiles = _sourceFiles;

  Map<String, dynamic> toJson() {
    var json = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
    var dark = brightness == Brightness.dark;
    json["base"] = dark ? "dark" : "light";

    var scheme = Map<String, dynamic>.from(
        (json["colorScheme"] as Map?)?.cast<String, dynamic>() ?? {});
    // An explicit color always wins over a seed's generated one.
    scheme.remove("seed");
    for (var entry in colors.entries) {
      if (entry.key == ThemeSlot.foundationKey) continue;
      scheme[entry.key] = colorToHex(entry.value);
    }
    // An automatic optional color must not come back from the old file.
    for (var key in ThemeSlot.optionalKeys) {
      if (!colors.containsKey(key)) scheme.remove(key);
    }
    var secondary = colors["secondary"];
    if (secondary != null) {
      scheme["onSurfaceVariant"] = colorToHex(secondary);
    }
    // Selected rows (the open room, the current settings page) are painted
    // with secondaryContainer; the editor offers them as "Raised".
    var raised = colors["surfaceContainerHigh"];
    if (raised != null) {
      scheme["secondaryContainer"] = colorToHex(raised);
    }
    var foundation = colors[ThemeSlot.foundationKey];
    if (foundation != null) scheme["surfaceDim"] = colorToHex(foundation);
    json["colorScheme"] = scheme;

    var foundationJson = Map<String, dynamic>.from(
        (json["foundation"] as Map?)?.cast<String, dynamic>() ?? {});
    if (foundation != null) foundationJson["color"] = colorToHex(foundation);
    foundationJson.remove("gradient");
    if (background != ThemeBackground.image) foundationJson.remove("image");
    switch (background) {
      case ThemeBackground.solid:
        break;
      case ThemeBackground.gradient:
        foundationJson["gradient"] = {
          "colors": [for (var c in gradientColors) colorToHex(c)],
          if (gradientStops?.length == gradientColors.length)
            "stops": gradientStops,
          "angle": gradientAngle,
        };
      case ThemeBackground.image:
        if (imageFile != null) {
          var image = Map<String, dynamic>.from(
              (foundationJson["image"] as Map?)?.cast<String, dynamic>() ?? {});
          image["file"] = path.basename(imageFile!);
          image["fit"] ??= "cover";
          foundationJson["image"] = image;
        }
    }
    json["foundation"] = foundationJson;

    // Panels let the gradient or image show through, like gradient themes.
    if (background != ThemeBackground.solid) {
      json["glass"] = {
        "surfaceOpacity": chatOpacity,
        "surfaceSigma": blur,
        "surfaceDimOpacity": 0.8,
        "surfaceDimSigma": blur,
        "surfaceContainerLowestOpacity": dark ? 0.5 : 0.3,
        "surfaceContainerLowestSigma": blur,
        "surfaceContainerLowOpacity": roomListOpacity,
        "surfaceContainerLowSigma": blur,
        "surfaceContainerOpacity": 0.7,
        "surfaceContainerSigma": blur,
        "surfaceContainerHighOpacity": dark ? 0.5 : 0.6,
        "surfaceContainerHighSigma": blur,
        "surfaceContainerHighestOpacity": dark ? 0.4 : 0.3,
        "surfaceContainerHighestSigma": blur,
      };
    }

    var settings = Map<String, dynamic>.from(
        (json["settings"] as Map?)?.cast<String, dynamic>() ?? {});
    settings["caulkBorders"] = borders;
    settings["caulkBorderRadius"] = cornerRadius;
    settings["caulkPadding"] = spacing;
    settings["caulkStrokeThickness"] ??= 1;
    json["settings"] = settings;

    var hasChatColors = chatColors?.isNotEmpty ?? false;
    if (hasChatColors ||
        chatPattern != null ||
        bubbleRadius != ChatStyle.defaultBubbleRadius) {
      json["chat"] = ChatStyle.toJson(
          colors: chatColors,
          pattern: chatPattern,
          patternStrength: chatPatternStrength,
          bubbleRadius: bubbleRadius);
    } else {
      json.remove("chat");
    }
    return json;
  }

  /// A picked picture not yet copied into the theme's folder.
  bool get imageIsNew =>
      imageBytes != null || (imageFile != null && path.isAbsolute(imageFile!));

  Future<Map<String, Uint8List>> _storedFiles() {
    var source = sourceName;
    if (source == null) return Future.value(const {});
    return _sourceFiles ??= ThemeConfig.getWebThemeFiles(source);
  }

  Future<ThemeData> build() async {
    if (PlatformUtils.isWeb) {
      var files = Map.of(await _storedFiles());
      if (imageBytes != null) files[imageFile!] = imageBytes!;
      return await ThemeJsonConverter.fromJson(toJson(), null,
              imageResolver: ThemeConfig.memoryImages(files)) ??
          ThemeData(brightness: brightness);
    }
    var file = sourceDir == null
        ? null
        : File(path.join(sourceDir!.path, "theme.json"));
    var json = toJson();
    // A newly picked picture is still outside the theme's folder.
    if (imageIsNew) {
      file = File(path.join(path.dirname(imageFile!), "theme.json"));
    }
    return await ThemeJsonConverter.fromJson(json, file) ??
        ThemeData(brightness: brightness);
  }

  static String safeName(String name) {
    var cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), "")
        .replaceAll(RegExp(r"^\.+"), "")
        .trim();
    return cleaned.isEmpty ? "My theme" : cleaned;
  }

  /// Writes the theme and returns its theme.json. A name taken by another
  /// theme gets a number, so saving never overwrites someone else's theme.
  Future<File> save() async {
    var root = await ThemeConfig.getCustomThemesDir();
    var base = safeName(name);
    var target = Directory(path.join(root.path, base));
    var editingSelf = sourceDir != null &&
        path.equals(path.normalize(sourceDir!.path), target.path);

    var n = 2;
    while (!editingSelf && await target.exists()) {
      target = Directory(path.join(root.path, "$base $n"));
      n++;
    }
    name = path.basename(target.path);

    await target.create(recursive: true);
    if (sourceDir != null && !editingSelf && await sourceDir!.exists()) {
      await for (var entity in sourceDir!.list()) {
        if (entity is File && path.basename(entity.path) != "theme.json") {
          await entity.copy(path.join(target.path, path.basename(entity.path)));
        }
      }
    }

    if (imageIsNew) {
      var picked = File(imageFile!);
      var copied = path.join(target.path,
          "background${path.extension(picked.path).toLowerCase()}");
      await picked.copy(copied);
      imageFile = path.basename(copied);
    }

    var file = File(path.join(target.path, "theme.json"));
    await file
        .writeAsString(const JsonEncoder.withIndent("  ").convert(toJson()));
    return file;
  }

  /// Web: [save] into the browser's storage. Returns the theme's files.
  Future<Map<String, Uint8List>> saveToBrowser() async {
    var base = safeName(name);
    var taken = await ThemeConfig.getWebThemeNames();
    var target = base;
    var n = 2;
    while (target != sourceName && taken.contains(target)) {
      target = "$base $n";
      n++;
    }
    name = target;

    var files = Map.of(await _storedFiles())..remove("theme.json");
    if (imageBytes != null) {
      var stored = "background${path.extension(imageFile!).toLowerCase()}";
      files[stored] = imageBytes!;
      imageFile = stored;
      imageBytes = null;
    }
    files["theme.json"] = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent("  ").convert(toJson())));

    await ThemeConfig.saveWebTheme(name, files);
    // Saving again (after an export) updates this theme, not a copy.
    sourceName = name;
    _sourceFiles = Future.value(Map.of(files));
    return files;
  }

  /// A .zip of a saved theme's folder, as the + button imports it.
  static Future<Uint8List> zip(Directory dir) async {
    var files = <String, Uint8List>{};
    await for (var entity in dir.list()) {
      if (entity is! File) continue;
      files[path.basename(entity.path)] = await entity.readAsBytes();
    }
    return zipFiles(files);
  }

  static Uint8List zipFiles(Map<String, Uint8List> files) {
    var archive = Archive();
    for (var entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
