import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:commet/config/app_icon_design.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
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

  /// The window icon for [design] as PNG bytes.
  static Future<Uint8List> windowIconPng(AppIconDesign design) async {
    if (design == AppIconDesign.original) {
      final data = await rootBundle.load(_originalWindowPng);
      return data.buffer.asUint8List();
    }
    final image = await renderSvg(design.svgAsset, 256);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError("Could not encode the window icon");
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
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
