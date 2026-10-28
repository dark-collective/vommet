import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/chat_wallpaper/chat_wallpaper_component.dart';
import 'package:commet/main.dart';
import 'package:commet/ui/organisms/chat_wallpaper/wallpaper_gradient.dart';
import 'package:flutter/material.dart';

/// Vommet issue 746: a wallpaper picture with its darken/lighten and blur,
/// or a color wallpaper ([fill]).
class ChatWallpaperView extends StatelessWidget {
  const ChatWallpaperView({
    this.bytes,
    this.fill,
    this.dim = 0,
    this.blur = 0,
    this.blurScale = 1,
    this.decodeWidth,
    this.shifts,
    this.flat = false,
    super.key,
  }) : assert(bytes != null || fill != null);

  ChatWallpaperView.of(ChatWallpaper wallpaper,
      {this.blurScale = 1,
      this.decodeWidth,
      this.shifts,
      this.flat = false,
      super.key})
      : bytes = wallpaper.bytes,
        fill = wallpaper.fill,
        dim = wallpaper.dim,
        blur = wallpaper.blur;

  final Uint8List? bytes;
  final WallpaperFill? fill;
  final double dim;
  final double blur;

  /// Moves an animated color wallpaper a step each time.
  final Stream<void>? shifts;

  /// Messages are drawn without bubbles (Discord style), so a color
  /// wallpaper is washed with the chat's background to keep text readable.
  final bool flat;

  /// How much of the chat's background covers a color wallpaper when
  /// [flat].
  static const double flatWash = 0.6;

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
    final fill = this.fill;
    if (fill != null) {
      return WallpaperFillView(
        fill: fill,
        shifts: shifts,
        wash: flat
            ? Theme.of(context).colorScheme.surface.withValues(alpha: flatWash)
            : null,
      );
    }
    final ImageProvider image = decodeWidth != null
        ? ResizeImage(MemoryImage(bytes!), width: decodeWidth)
        : MemoryImage(bytes!);
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

/// The wallpaper behind a chat's timeline, or nothing.
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
  bool _flat = false;

  /// New messages in this room (they move an animated color wallpaper).
  late final Stream<void> _messages = widget.room.client.onTimelineEvent
      .where((e) => e.$1.identifier == widget.room.identifier);

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
    final flat = !preferences.chatBubbleLayout.value;
    if (!mounted ||
        load != _loads ||
        (wallpaper?.id == _wallpaper?.id && flat == _flat)) {
      return;
    }
    setState(() {
      _wallpaper = wallpaper;
      _flat = flat;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = _wallpaper;
    if (wallpaper == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ChatWallpaperView.of(
        wallpaper,
        key: ValueKey(wallpaper.id),
        shifts: _messages,
        flat: _flat,
      ),
    );
  }
}
