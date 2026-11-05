import 'package:commet/client/client.dart';
import 'package:commet/client/components/component.dart';
import 'package:commet/client/components/gif/gif_search_result.dart';
import 'package:commet/client/timeline_events/timeline_event.dart';
import 'package:flutter/widgets.dart';

abstract class FavoriteGif {
  ImageProvider get image;

  String get url;

  double get width;

  double get height;
}

abstract class GifComponent<T extends Client> implements Component<T> {
  Future<List<GifSearchResult>> search(String query);

  Future<TimelineEvent?> sendGif(
      Room room, GifSearchResult gif, TimelineEvent? inReplyTo);

  Future<TimelineEvent?> sendFavoriteGif(
      Room room, FavoriteGif gif, TimelineEvent? inReplyTo);

  String get searchPlaceholder;

  bool isGif(TimelineEvent event);

  bool isFavoriteGif(TimelineEvent event);

  Stream get onFavoritesChanged;

  Future<void> setFavoriteFromEvent(TimelineEvent event);

  /// Vommet: whether saving [event] to My GIFs makes an unencrypted copy
  /// (a GIF from an encrypted room).
  bool savesUnencryptedCopy(TimelineEvent event);

  Future<void> removeFavoriteFromEvent(TimelineEvent event);

  Future<void> removeFavorite(FavoriteGif gif);

  List<FavoriteGif> get favorites;

  /// Vommet issue 731: the My GIFs folder names.
  List<String> get folders;

  /// The folder of the saved GIF [event] shows (null: Unsorted or not saved).
  String? folderOfEvent(TimelineEvent event);

  /// Saves the GIF [event] shows to My GIFs in [folder] (null: Unsorted);
  /// a GIF saved already only changes folder.
  Future<void> saveToFolder(TimelineEvent event, String? folder);
}
