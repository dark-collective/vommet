import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/main.dart';
import 'package:flutter/material.dart';

/// Vommet issue 746: a wallpaper picture with its darken/lighten and blur.
class ChatWallpaperView extends StatelessWidget {
  const ChatWallpaperView({
    required this.bytes,
    required this.dim,
    required this.blur,
    this.blurScale = 1,
    this.decodeWidth,
    super.key,
  });

  final Uint8List bytes;
  final double dim;
  final double blur;

  /// Smaller previews blur less, so they look like the full-size chat.
  final double blurScale;

  /// Decode no wider than this (thumbnails).
  final int? decodeWidth;

  /// Strongest blur, as a Gaussian sigma in logical pixels.
  static const double maxBlurSigma = 24;

  /// Strongest darkening or lightening (the overlay's opacity).
  static const double maxTint = 0.85;

  /// The overlay over the picture for [dim], or null for none.
  static Color? tintFor(double dim) {
    if (dim == 0) return null;
    final base = dim < 0 ? Colors.black : Colors.white;
    return base.withValues(alpha: dim.abs().clamp(0.0, 1.0) * maxTint);
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider image = decodeWidth != null
        ? ResizeImage(MemoryImage(bytes), width: decodeWidth)
        : MemoryImage(bytes);
    Widget picture = Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    final sigma = blur.clamp(0.0, 1.0) * maxBlurSigma * blurScale;
    if (sigma > 0) {
      picture = ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror),
          child: picture);
    }
    final tint = tintFor(dim);
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        picture,
        if (tint != null) ColoredBox(color: tint),
      ]),
    );
  }
}

/// The wallpaper behind a 1:1 chat's timeline, or nothing.
class ChatWallpaperBackground extends StatefulWidget {
  const ChatWallpaperBackground({required this.room, super.key});
  final Room room;

  @override
  State<ChatWallpaperBackground> createState() =>
      _ChatWallpaperBackgroundState();
}

class _ChatWallpaperBackgroundState extends State<ChatWallpaperBackground> {
  final List<StreamSubscription> _subs = [];
  ChatWallpaper? _wallpaper;
  int _loads = 0;

  ChatWallpaperComponent? get _component =>
      widget.room.getComponent<ChatWallpaperComponent>();

  @override
  void initState() {
    super.initState();
    final component = _component;
    if (component != null) _subs.add(component.onChanged.listen(_load));
    _subs.add(widget.room.onUpdate.listen(_load));
    _subs.add(preferences.onSettingChanged.listen(_load));
    _load(null);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _load(_) async {
    final load = ++_loads;
    final component = _component;
    ChatWallpaper? wallpaper;
    if (component != null &&
        showChatWallpapers.value &&
        component.isAvailable &&
        !component.hiddenHere) {
      wallpaper = await component.current();
    }
    if (!mounted || load != _loads || wallpaper?.id == _wallpaper?.id) return;
    setState(() => _wallpaper = wallpaper);
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = _wallpaper;
    if (wallpaper == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ChatWallpaperView(
        key: ValueKey(wallpaper.id),
        bytes: wallpaper.bytes,
        dim: wallpaper.dim,
        blur: wallpaper.blur,
      ),
    );
  }
}
