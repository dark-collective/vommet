import 'package:matrix/matrix.dart';

/// Vommet: which media the file cache must keep sealed (see
/// [FileCache.writeFile]): anything from an encrypted room, including an
/// unencrypted attachment sent there and thumbnails, and any encrypted
/// attachment wherever it was sent. Avatars, emoji, banners and media from
/// unencrypted rooms stay plain.
class MatrixMediaPrivacy {
  static bool isSensitive(Event? event) {
    if (event == null) return false;
    return event.room.encrypted ||
        event.isAttachmentEncrypted ||
        event.isThumbnailEncrypted;
  }
}
