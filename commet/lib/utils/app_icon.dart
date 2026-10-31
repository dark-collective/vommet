import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// Vommet: draws the app's icons from their SVGs, and puts the picked
/// design on the window (Vommet issue 591). The tray icon follows the same
/// setting (AppTray).
class AppIcon {
  static const _linuxChannel = MethodChannel("im.nether.vommet/window_icon");

  /// The PNG the window used before this setting existed; the window starts
  /// with it (my_application.cc, the Windows resource).
  static const _originalWindowPng =
      "assets/images/app_icon/app_icon_rounded.png";

  /// Whether the window icon can be changed while the app runs.
  static bool get windowIconSupported =>
      PlatformUtils.isLinux || PlatformUtils.isWindows;

  /// Puts the picked icon on the window and follows changes to it.
  static Future<void> init() async {
    if (!windowIconSupported) return;
    appIconDesignPreference.onChanged.listen((_) => applyWindowIcon());
    appIconCustomPathPreference.onChanged.listen((_) => applyWindowIcon());
    // The window already starts with the original icon.
    if (appIconDesign != AppIconDesign.original) await applyWindowIcon();
  }

  /// [asset] drawn into a [size]×[size] square, kept centred at its aspect
  /// ratio. With [argb], every painted pixel takes that colour (for the
  /// one-colour silhouettes).
  static Future<ui.Image> renderSvg(String asset, int size, {int? argb}) async {
    final info = await vg.loadPicture(SvgAssetLoader(asset), null);
    try {
      final s = size.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
      if (argb != null) {
        canvas.saveLayer(
            null,
            Paint()
              ..colorFilter = ColorFilter.mode(Color(argb), BlendMode.srcIn));
      }
      final scale = s / max(info.size.width, info.size.height);
      canvas.translate((s - info.size.width * scale) / 2,
          (s - info.size.height * scale) / 2);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      if (argb != null) canvas.restore();
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(size, size);
      } finally {
        picture.dispose();
      }
    } finally {
      info.picture.dispose();
    }
  }

  /// [file] (an uploaded icon) drawn into a [size]×[size] square. With
  /// [argb], every painted pixel takes that colour, as in [renderSvg].
  static Future<ui.Image> renderFile(File file, int size, {int? argb}) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final ui.Image source;
    try {
      source = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    try {
      final s = size.toDouble();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, s, s));
      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (argb != null) {
        paint.colorFilter = ColorFilter.mode(Color(argb), BlendMode.srcIn);
      }
      canvas.drawImageRect(
          source,
          Rect.fromLTWH(
              0, 0, source.width.toDouble(), source.height.toDouble()),
          Rect.fromLTWH(0, 0, s, s),
          paint);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(size, size);
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// [place]'s icon for [design] drawn at [size]: the uploaded image for
  /// [AppIconDesign.custom], else the design's SVG.
  static Future<ui.Image> renderIcon(
      AppIconPlace place, AppIconDesign design, int size,
      {int? argb}) async {
    final file = design == AppIconDesign.custom ? place.customFile : null;
    if (file != null) return renderFile(file, size, argb: argb);
    return renderSvg(argb == null ? design.svgAsset : design.monoSvgAsset, size,
        argb: argb);
  }

  /// [place]'s icon for [design] as a [size]×[size] PNG.
  static Future<Uint8List> iconPng(
      AppIconPlace place, AppIconDesign design, int size) async {
    final image = await renderIcon(place, design, size);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError("Could not encode the icon");
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// The window icon for [design] as PNG bytes.
  static Future<Uint8List> windowIconPng(AppIconDesign design) async {
    if (design == AppIconDesign.original) {
      final data = await rootBundle.load(_originalWindowPng);
      return data.buffer.asUint8List();
    }
    return iconPng(AppIconPlace.window, design, 256);
  }

  /// Saves [bytes] (an image the user picked) as [place]'s own icon and
  /// shows it there (Vommet issue 681). Cut to a centred square.
  static Future<void> setCustomIcon(AppIconPlace place, Uint8List bytes) async {
    final png = await compute(squareIconPng, bytes);
    final dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, "app_icon"));
    await dir.create(recursive: true);
    // A new name each time, so nothing shows a cached copy of the old one.
    final file = File(p.join(dir.path,
        "${place.name}-${DateTime.now().millisecondsSinceEpoch}.png"));
    await file.writeAsBytes(png, flush: true);
    final old = place.customPathPreference.value;
    await place.customPathPreference.set(file.path);
    await place.preference.set(AppIconDesign.custom.name);
    await _deleteQuietly(old);
  }

  /// Forgets [place]'s own icon; the place goes back to its default.
  static Future<void> removeCustomIcon(AppIconPlace place) async {
    final old = place.customPathPreference.value;
    if (place.preference.value == AppIconDesign.custom.name) {
      await place.preference.set(place.defaultDesign.name);
    }
    await place.customPathPreference.set("");
    await _deleteQuietly(old);
  }

  static Future<void> _deleteQuietly(String path) async {
    if (path.isEmpty) return;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static Future<void> applyWindowIcon() async {
    try {
      final design = appIconDesign;
      final png = await windowIconPng(design);
      if (PlatformUtils.isLinux) {
        await _linuxChannel.invokeMethod("setIcon", png);
      } else if (PlatformUtils.isWindows) {
        await windowManager.setIcon(await _writeIco(design, png));
      }
    } catch (e, s) {
      Log.onError(e, s, content: "Failed to set the window icon");
    }
  }

  /// Windows takes the window icon from an .ico file.
  static Future<String> _writeIco(AppIconDesign design, Uint8List png) async {
    final source = img.decodePng(png);
    if (source == null) throw StateError("Could not decode the window icon");
    img.Image? ico;
    for (final size in const [256, 48, 32, 24, 16]) {
      final frame = img.copyResize(source,
          width: size, height: size, interpolation: img.Interpolation.average);
      if (ico == null) {
        ico = frame;
      } else {
        ico.addFrame(frame);
      }
    }
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, "window_icon_${design.name}.ico"));
    await file.writeAsBytes(img.encodeIco(ico!), flush: true);
    return file.path;
  }
}

/// [bytes] (any image format the app reads) as a PNG of its centred square,
/// at most 512 px. Throws when it isn't an image.
Uint8List squareIconPng(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // The decoders can throw (RangeError, ...) on files that aren't images.
  }
  if (decoded == null) throw const FormatException("Not an image");
  // Phone photos are often stored sideways with an EXIF rotation.
  final source = img.bakeOrientation(decoded);
  final side = min(source.width, source.height);
  var square = img.copyCrop(source,
      x: (source.width - side) ~/ 2,
      y: (source.height - side) ~/ 2,
      width: side,
      height: side);
  if (side > 512) {
    square = img.copyResize(square,
        width: 512, height: 512, interpolation: img.Interpolation.average);
  }
  return img.encodePng(square);
}
