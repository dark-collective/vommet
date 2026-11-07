import 'package:commet/utils/mime.dart';
import 'package:commet/utils/platform_image_types.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Vommet: the mimetype an event's attachment is shown by.
///
/// The picture/video/file decision is mimetype-based whatever the msgtype, so
/// an `m.file` with `info.mimetype: image/jpeg` shows as a picture. Pictures
/// sent through some clients' generic "attach file" path arrive as `m.file`
/// with a missing or generic (`application/octet-stream`) mimetype, or a
/// non-standard one (`image/jpg`); those are normalised, and a missing or
/// generic one falls back to the file name's extension, so `file_63458.jpg`
/// still shows as a picture. Anything else keeps its declared mimetype, so
/// other files are unchanged.
class AttachmentMime {
  static const _aliases = {
    "image/jpg": "image/jpeg",
    "image/pjpeg": "image/jpeg",
    "image/x-ms-bmp": "image/bmp",
    "image/x-bmp": "image/bmp",
  };

  static const _generic = {
    "",
    "application/octet-stream",
    "binary/octet-stream",
    "application/binary",
    "application/unknown",
  };

  /// [mimetype] as declared by the event (may be empty), [name] its file
  /// name (`filename`, or `body` when there is none).
  static String effective({required String mimetype, String? name}) {
    var mime = mimetype.split(";").first.trim().toLowerCase();
    mime = _aliases[mime] ?? mime;
    if (!_generic.contains(mime)) return mime;

    final ext = _extension(name);
    if (ext == null) return mime;
    return Mime.fromExtenstion(ext) ?? mime;
  }

  /// The file name an attachment event declares: `filename`, else `body`.
  static String? nameOf(matrix.Event event) {
    final filename = event.content["filename"];
    if (filename is String && filename.trim().isNotEmpty) return filename;
    final body = event.content["body"];
    return body is String ? body : null;
  }

  static String ofEvent(matrix.Event event) =>
      effective(mimetype: event.attachmentMimetype, name: nameOf(event));

  /// Vommet: whether a picture of a type Flutter can't decode
  /// ([Mime.thumbnailOnlyImageTypes], e.g. AVIF) is shown as a picture
  /// through the thumbnail its sender attached (Vommet issue 329). The
  /// thumbnail must be a type Flutter decodes; an unknown (empty) thumbnail
  /// mimetype is sniffed when it loads. Servers can't help: Synapse only
  /// thumbnails JPEG, PNG, WebP and GIF.
  static bool showsThumbnailOnly(
      {required String mimetype,
      required bool hasThumbnail,
      required String thumbnailMimetype}) {
    if (!Mime.thumbnailOnlyImageTypes.contains(mimetype)) return false;
    // Vommet issue 778: shown in full where the platform decodes it.
    if (PlatformImageTypes.canDecode(mimetype)) return false;
    if (!hasThumbnail) return false;
    final thumbnail = effective(mimetype: thumbnailMimetype);
    return thumbnail.isEmpty || Mime.imageTypes.contains(thumbnail);
  }

  /// Vommet: whether [mimetype] is shown as a full picture: a type Flutter
  /// decodes, or HEIC/AVIF where the platform decodes them (Vommet issue
  /// 778, see [PlatformImageTypes]).
  static bool isFullPicture(String mimetype) =>
      Mime.imageTypes.contains(mimetype) ||
      PlatformImageTypes.canDecode(mimetype);

  static bool showsThumbnailOnlyEvent(matrix.Event event) => showsThumbnailOnly(
      mimetype: ofEvent(event),
      hasThumbnail: event.hasThumbnail,
      thumbnailMimetype: event.thumbnailMimetype);

  static String? _extension(String? name) {
    if (name == null) return null;
    final trimmed = name.trim();
    final dot = trimmed.lastIndexOf(".");
    if (dot < 0 || dot == trimmed.length - 1) return null;
    final ext = trimmed.substring(dot + 1).toLowerCase();
    if (ext.contains(RegExp(r"[\s/\\]"))) return null;
    return ext;
  }
}
