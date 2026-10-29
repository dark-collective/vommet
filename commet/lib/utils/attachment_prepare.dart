import 'dart:io';

import 'package:commet/client/attachment.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/picture_shrink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

/// Vommet issue 838: the slow work on a picture (removing hidden info,
/// making it smaller) done when it is sent, not while it is being picked.
/// A file asks for it with [PendingFileAttachment.removeHiddenInfo] and
/// [PendingFileAttachment.shrinkLongestEdge]; files that ask for nothing
/// are returned as they are.
class AttachmentPrepare {
  /// Whether [prepare] would change [file].
  static bool wanted(PendingFileAttachment file) =>
      (file.shrinkLongestEdge != null &&
          PictureShrink.canShrink(file.mimeType)) ||
      (file.removeHiddenInfo && canRemoveHiddenInfo(file.mimeType));

  /// Pictures whose hidden info Vommet can remove. GIFs are left alone
  /// (re-saving would lose the animation).
  static bool canRemoveHiddenInfo(String? mimeType) =>
      Mime.imageTypes.contains(mimeType) && mimeType != "image/gif";

  /// [file] made smaller and/or without its hidden info, off the UI thread.
  /// Keeps the spoiler marking. On any failure the original file is sent
  /// (as the dialog did when a picture couldn't be read).
  static Future<PendingFileAttachment> prepare(
      PendingFileAttachment file) async {
    if (!wanted(file)) return file;
    try {
      final data = file.data ?? await File(file.path!).readAsBytes();
      PendingFileAttachment? result;

      final longestEdge = file.shrinkLongestEdge;
      if (longestEdge != null && PictureShrink.canShrink(file.mimeType)) {
        final small = await compute(_shrink, (data, longestEdge, file.name));
        if (small != null) {
          result = PendingFileAttachment(
              name: small.name,
              data: small.data,
              size: small.data.lengthInBytes,
              mimeType: small.mimeType)
            ..dimensions =
                Size(small.width.toDouble(), small.height.toDouble());
        }
      }

      if (result == null &&
          file.removeHiddenInfo &&
          canRemoveHiddenInfo(file.mimeType)) {
        final stripped = await compute(
            _strip, (data, file.name, file.mimeType ?? "image/png"));
        if (stripped != null) {
          result = PendingFileAttachment(
              name: stripped.$1,
              data: stripped.$2,
              size: stripped.$2.lengthInBytes,
              mimeType: stripped.$3);
        }
      }

      if (result == null) return file;
      result.spoiler = file.spoiler;
      result.spoilerReason = file.spoilerReason;
      result.telemetryMs.addAll(file.telemetryMs);
      return result;
    } catch (_) {
      return file;
    }
  }

  static ShrunkPicture? _shrink((Uint8List, int, String?) args) {
    try {
      return PictureShrink.shrink(args.$1, longestEdge: args.$2, name: args.$3);
    } catch (_) {
      return null;
    }
  }

  static (String, Uint8List, String)? _strip(
      (Uint8List, String?, String) args) {
    try {
      return stripHiddenInfo(args.$1, name: args.$2, mimeType: args.$3);
    } catch (_) {
      return null;
    }
  }

  /// [data] re-saved without EXIF or PNG text: (name, bytes, mime type).
  /// Kept in its own format when the name says which; PNG otherwise.
  static (String, Uint8List, String)? stripHiddenInfo(Uint8List data,
      {String? name, required String mimeType}) {
    final decoder = img.findDecoderForData(data);
    final image = decoder?.decode(data);
    if (image == null) return null;

    image.exif.clear();
    image.textData = null;

    var trimmed = name?.trim();
    if (trimmed?.isEmpty == true) trimmed = null;
    Uint8List? encoded;
    if (trimmed != null) encoded = img.encodeNamedImage(trimmed, image);
    if (encoded != null) return (trimmed!, encoded, mimeType);

    final rawName = path.basenameWithoutExtension(trimmed ?? "untitled.png");
    return ("$rawName.png", img.encodePng(image), "image/png");
  }
}
