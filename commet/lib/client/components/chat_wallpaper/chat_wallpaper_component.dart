import 'dart:typed_data';

import 'package:commet/client/client.dart';
import 'package:commet/client/components/room_component.dart';
import 'package:commet/config/preferences/bool_preference.dart';

/// Vommet issue 746 (experiment): a chat wallpaper shared by both people in
/// a 1:1 chat. Each person can hide it in their own app.
final BoolPreference experimentChatWallpapers =
    BoolPreference("vommet_experiment_chat_wallpapers", defaultValue: false);

/// Settings › Appearance: show chat wallpapers at all (on this device).
final BoolPreference showChatWallpapers =
    BoolPreference("vommet_show_chat_wallpapers", defaultValue: true);

/// One applied wallpaper: the picture plus how it was adjusted.
class ChatWallpaper {
  const ChatWallpaper({
    required this.id,
    required this.bytes,
    required this.dim,
    required this.blur,
    this.source,
  });

  /// Identifies this applied wallpaper (on Matrix, its event id).
  final String id;

  /// The picture, as uploaded (already scaled down, metadata removed).
  final Uint8List bytes;

  /// -1 (darkest) to 1 (lightest), 0 = unchanged.
  final double dim;

  /// 0 (sharp) to 1 (most blurred).
  final double blur;

  /// The same value for every wallpaper made from one picture, so Recent
  /// keeps one entry per picture.
  final String? source;
}

abstract class ChatWallpaperComponent<R extends Client, T extends Room>
    implements RoomComponent<R, T> {
  /// The experiment is on and this is a chat between two people.
  bool get isAvailable;

  /// We may set or remove the wallpaper here.
  bool get canChange;

  /// We hid the wallpaper in this chat (our own choice, synced to our
  /// devices; the other person isn't told).
  bool get hiddenHere;

  Future<void> setHiddenHere(bool hidden);

  /// Fires when the wallpaper, Recent or [hiddenHere] changes.
  Stream<void> get onChanged;

  /// The wallpaper shown in this chat, or null when there is none.
  Future<ChatWallpaper?> current();

  /// Recently applied wallpapers in this chat, newest first.
  Future<List<ChatWallpaper>> recent();

  /// Applies [image] (a picture just picked) or, without one, the picture of
  /// [from] (the current wallpaper or one from Recent) with [dim] and [blur],
  /// for both people.
  Future<void> apply(
      {Uint8List? image,
      ChatWallpaper? from,
      required double dim,
      required double blur});

  /// Back to no wallpaper, for both people.
  Future<void> remove();

  /// Removes entries from our Recent list only.
  Future<void> removeRecent(Set<String> ids);
}
