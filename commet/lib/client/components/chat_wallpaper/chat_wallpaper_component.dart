import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Vommet issue 746 (experiment): a chat wallpaper shared by both people in
/// a 1:1 chat, or by everyone in a group. Each person can hide it in their
/// own app, or pick one only they see.
final BoolPreference experimentChatWallpapers =
    BoolPreference("vommet_experiment_chat_wallpapers", defaultValue: false);

/// Settings › Appearance: show chat wallpapers at all (on this device).
final BoolPreference showChatWallpapers =
    BoolPreference("vommet_show_chat_wallpapers", defaultValue: true);

/// A wallpaper made of colors instead of a picture: one color, a two-color
/// gradient, or a four-point gradient of 3 or 4 colors that can shift when
/// messages come and go.
class WallpaperFill {
  const WallpaperFill(this.colors, {this.animate = false});

  /// 1 to [maxColors] colors.
  final List<Color> colors;

  /// Shift the gradient on new messages (only with 3 or more colors).
  final bool animate;

  static const int maxColors = 4;

  bool get canAnimate => colors.length >= 3;

  /// Reads `{"colors": ["#rrggbb", ...], "animate": bool}`; null when it
  /// holds no valid color.
  static WallpaperFill? fromJson(Object? json) {
    if (json is! Map) return null;
    final list = json["colors"];
    if (list is! List) return null;
    final colors = <Color>[];
    for (final entry in list.take(maxColors)) {
      final color = colorFromJson(entry);
      if (color != null) colors.add(color);
    }
    if (colors.isEmpty) return null;
    return WallpaperFill(colors,
        animate: json["animate"] == true && colors.length >= 3);
  }

  Map<String, Object?> toJson() => {
        "colors": [for (final c in colors) colorToJson(c)],
        if (canAnimate) "animate": animate,
      };

  /// The same value for the same colors, so Recent keeps one entry each.
  String get source => "fill:${colors.map(colorToJson).join(",")}";

  /// `#rrggbb` (opaque) or null.
  static Color? colorFromJson(Object? value) {
    if (value is! String) return null;
    final match = RegExp(r"^#([0-9a-fA-F]{6})$").firstMatch(value.trim());
    if (match == null) return null;
    return Color(0xff000000 | int.parse(match.group(1)!, radix: 16));
  }

  static String colorToJson(Color c) =>
      "#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, "0")}";

  @override
  bool operator ==(Object other) =>
      other is WallpaperFill &&
      other.animate == animate &&
      listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(animate, Object.hashAll(colors));
}

/// One applied wallpaper: a picture plus how it was adjusted, or a [fill].
class ChatWallpaper {
  const ChatWallpaper({
    required this.id,
    this.bytes,
    this.fill,
    this.dim = 0,
    this.blur = 0,
    this.source,
    this.own = false,
  }) : assert(bytes != null || fill != null);

  /// Identifies this applied wallpaper (on Matrix, its event id).
  final String id;

  /// The picture, as uploaded (already scaled down, metadata removed), or
  /// null for a [fill].
  final Uint8List? bytes;

  /// The colors, when this isn't a picture.
  final WallpaperFill? fill;

  /// -1 (darkest) to 1 (lightest), 0 = unchanged.
  final double dim;

  /// 0 (sharp) to 1 (most blurred).
  final double blur;

  /// The same value for every wallpaper made from one picture (or one set
  /// of colors), so Recent keeps one entry per picture.
  final String? source;

  /// Our own wallpaper for this chat, which only we see.
  final bool own;
}

abstract class ChatWallpaperComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// The experiment is on (in any chat: 1:1 or group).
  bool get isAvailable;

  /// A chat between two people (for wording: "both of us" or "everyone").
  bool get isOneToOne;

  /// We may set or remove the wallpaper everyone sees here.
  bool get canChange;

  /// We hid the wallpaper in this chat (our own choice, synced to our
  /// devices; no one else is told).
  bool get hiddenHere;

  Future<void> setHiddenHere(bool hidden);

  /// Fires when a wallpaper, Recent or [hiddenHere] changes.
  Stream<void> get onChanged;

  /// The wallpaper shown in this chat: our own one, else the shared one,
  /// or null when there is none.
  Future<ChatWallpaper?> current();

  /// The wallpaper everyone sees here, or null.
  Future<ChatWallpaper?> shared();

  /// The wallpaper only we see here, or null.
  Future<ChatWallpaper?> own();

  /// We set a wallpaper only we see here.
  bool get hasOwn;

  /// Recently applied wallpapers in this chat, newest first.
  Future<List<ChatWallpaper>> recent();

  /// Applies [image] (a picture just picked), [fill] (colors), or, without
  /// either, the picture or colors of [from] (a current wallpaper or one
  /// from Recent) with [dim] and [blur]. For everyone, or with [onlyForMe]
  /// for us alone (synced to our devices).
  Future<void> apply(
      {Uint8List? image,
      WallpaperFill? fill,
      ChatWallpaper? from,
      required double dim,
      required double blur,
      bool onlyForMe = false});

  /// Back to no wallpaper, for everyone.
  Future<void> remove();

  /// Drops our own wallpaper, so the shared one shows again.
  Future<void> removeOwn();

  /// Removes entries from our Recent list only.
  Future<void> removeRecent(Set<String> ids);
}
