import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Vommet: the theme's [ChatStyle] behind the messages (Telegram themes): a
/// color or gradient with Telegram's doodle pattern over it. Draws nothing
/// for themes without one. A room's own wallpaper is drawn above it.
class ChatBackdrop extends StatelessWidget {
  const ChatBackdrop({this.style, super.key});

  /// Overrides the theme's (the theme editor's preview).
  final ChatStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = this.style ?? theme.extension<ChatStyle>();
    if (style == null || !style.hasBackdrop) return const SizedBox.shrink();
    final colors = style.colors ?? [theme.colorScheme.surface];
    final dark = theme.brightness == Brightness.dark;
    return RepaintBoundary(
      child: style.pattern == ChatStyle.telegramPattern
          ? FutureBuilder<ui.Picture?>(
              future: TelegramPattern.load(),
              builder: (context, snapshot) => CustomPaint(
                  painter: _BackdropPainter(colors,
                      pattern: snapshot.data,
                      patternColor: TelegramPattern.colorFor(
                          dark, style.patternStrength))))
          : CustomPaint(painter: _BackdropPainter(colors)),
    );
  }
}

/// Telegram Desktop's chat pattern (assets/images/telegram, GPLv3+): a
/// gzipped SVG of black doodles, parsed once.
class TelegramPattern {
  static const asset = "assets/images/telegram/pattern.svg.gz";

  /// Size of the art; it tiles at half size.
  static const size = Size(1440, 2960);
  static const scale = 0.5;

  static Future<ui.Picture?>? _picture;

  static Future<ui.Picture?> load() => _picture ??= _load();

  static Future<ui.Picture?> _load() async {
    try {
      final data = await rootBundle.load(asset);
      final svg = utf8.decode(GZipDecoder().decodeBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      final info = await vg.loadPicture(SvgStringLoader(svg), null);
      return info.picture;
    } catch (e) {
      Log.w("Could not load the Telegram pattern: $e");
      return null;
    }
  }

  /// Doodles darken a light background and lighten a dark one.
  static Color colorFor(bool dark, double strength) {
    final s = strength.clamp(0.0, 1.0);
    return dark
        ? Colors.white.withValues(alpha: s * 0.18)
        : Colors.black.withValues(alpha: s * 0.35);
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.colors, {this.pattern, this.patternColor});

  final List<Color> colors;
  final ui.Picture? pattern;
  final Color? patternColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    if (colors.length == 1) {
      paint.color = colors.first;
    } else {
      paint.shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors)
          .createShader(rect);
    }
    canvas.drawRect(rect, paint);

    final pattern = this.pattern;
    final color = patternColor;
    if (pattern == null || color == null || color.a == 0) return;
    canvas.save();
    canvas.clipRect(rect);
    canvas.saveLayer(rect,
        Paint()..colorFilter = ui.ColorFilter.mode(color, ui.BlendMode.srcIn));
    final tile = TelegramPattern.size * TelegramPattern.scale;
    for (var y = 0.0; y < size.height; y += tile.height) {
      for (var x = 0.0; x < size.width; x += tile.width) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(TelegramPattern.scale);
        canvas.drawPicture(pattern);
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.pattern != pattern ||
      old.patternColor != patternColor ||
      !_sameColors(old.colors, colors);

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
