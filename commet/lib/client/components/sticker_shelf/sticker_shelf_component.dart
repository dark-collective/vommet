import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/emoticon/emoticon.dart';

/// Vommet issue 890: the sticker tab's Favorites and Recent rows. Both
/// lists are newest first and saved to the account, so they follow you to
/// your other devices.
abstract class StickerShelfComponent<T extends Client> implements Component<T> {
  static const int maxFavorites = 10;
  static const int maxRecent = 25;

  List<Emoticon> get favorites;

  List<Emoticon> get recent;

  /// Fires when either list changes, here or on another device.
  Stream<void> get onChanged;

  bool isFavorite(Emoticon sticker);

  bool isRecent(Emoticon sticker);

  /// Adds or removes [sticker] from Favorites. Returns true when adding it
  /// replaced the oldest favorite because the list was full.
  Future<bool> setFavorite(Emoticon sticker, bool favorite);

  /// Records a sent sticker at the front of Recent.
  Future<void> stickerSent(Emoticon sticker);

  Future<void> removeRecent(Emoticon sticker);

  /// The sticker at [url] (e.g. one tapped in the timeline), or null when
  /// it can't be kept on the shelf.
  Emoticon? stickerFor(String url, {required String shortcode});
}
