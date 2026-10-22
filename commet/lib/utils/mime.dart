import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import 'package:mime/mime.dart' as mime;

class Mime {
  static const displayableImageTypes = {
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/bmp",
    "image/webp"
  };

  static const imageTypes = {
    "image/jpeg",
    "image/png",
    "image/gif",
    "image/webp",
    "image/bmp",
  };

  /// Vommet: pictures Flutter has no decoder for (Vommet issue 329). They
  /// show through the JPEG/PNG thumbnail their sender attached (Element
  /// always attaches one to AVIF), never at full size; without a usable
  /// thumbnail they show as a file. See AttachmentMime.showsThumbnailOnly.
  static const thumbnailOnlyImageTypes = {
    "image/avif",
    "image/heic",
    "image/heif",
  };

  static const gifTypes = {
    "image/gif",
    "image/webp",
  };

  static const playableAudioTypes = {
    "audio/x-wav",
    "audio/ogg",
    "audio/opus",
    "audio/wav",
    "audio/mp3",
    "audio/mpeg",
    // Vommet: voice messages (Ogg/Opus from most clients, AAC/MP4 from some;
    // upstream lists audio/opus itself)
    "audio/mp4",
    "audio/aac",
    "audio/x-m4a",
    "audio/webm",
  };

  static bool isText(String mime) => mime.startsWith("text/");

  // Vommet: types that say nothing about the content (some bridges send these)
  static const genericTypes = {
    "application/octet-stream",
    "binary/octet-stream",
  };

  // Vommet: audio file extensions the mime package doesn't know
  static const audioExtensionToMime = {
    "opus": "audio/ogg",
  };

  /// The type without its parameters, in lower case:
  /// `audio/ogg; codecs=opus` becomes `audio/ogg`.
  static String? essence(String? mimeType) {
    if (mimeType == null) return null;
    final type = mimeType.split(";").first.trim().toLowerCase();
    return type.isEmpty ? null : type;
  }

  /// Whether the inline audio player can play a file: by its type, ignoring
  /// parameters, or by its file name when the type is missing or generic.
  static bool isPlayableAudio(String? mimeType, {String? name}) {
    final type = essence(mimeType);
    if (type != null && !genericTypes.contains(type)) {
      return playableAudioTypes.contains(type);
    }

    if (name == null || name.isEmpty) return false;
    final dot = name.lastIndexOf(".");
    final extension = dot < 0 ? "" : name.substring(dot + 1).toLowerCase();
    final byName = audioExtensionToMime[extension] ?? lookupType(name);
    return playableAudioTypes.contains(essence(byName));
  }

  static const videoTypes = {
    "video/x-matroska",
    "video/mp4",
    "video/mpeg",
    "video/webm",
    "video/quicktime"
  };

  static const videoStreamTypes = {"application/vnd.apple.mpegurl"};

  static const archiveTypes = {
    "application/x-7z-compressed",
    "application/x-bzip",
    "application/x-bzip2",
    "application/gzip"
  };

  static const extensionToMime = {
    "jpeg": "image/jpeg",
    "jpg": "image/jpeg",
    "png": "image/png",
    "gif": "image/gif",
    "webp": "image/webp",
    "bmp": "image/bmp",
    "avif": "image/avif",
    "heic": "image/heic",
    "heif": "image/heif"
  };

  static String? fromExtenstion(String extension) {
    return extensionToMime.tryGet(extension);
  }

  static String? extensionFromMime(String mimeType) {
    for (var pair in extensionToMime.entries) {
      if (pair.value == mimeType) {
        return pair.key;
      }
    }

    return null;
  }

  static IconData toIcon(String? mimeType) {
    mimeType = essence(mimeType);
    if (imageTypes.contains(mimeType)) return Icons.image;
    if (thumbnailOnlyImageTypes.contains(mimeType)) return Icons.image;
    if (videoTypes.contains(mimeType)) return Icons.video_file_rounded;
    if (archiveTypes.contains(mimeType)) return Icons.folder_zip;
    if (playableAudioTypes.contains(mimeType)) return Icons.audio_file;
    return Icons.file_present;
  }

  static String? lookupType(String filepath, {Uint8List? data}) {
    var resolver = mime.MimeTypeResolver();
    resolver.addMagicNumber([0x42, 0x4d], "image/bmp");
    resolver.addMagicNumber([0x3c, 0x73, 0x76, 0x67], "image/svg+xml"); // '<svg
    resolver.addMagicNumber([0x4F, 0x67, 0x67, 0x53], "audio/ogg"); // 'OggS
    var type = resolver.lookup(filepath);
    type ??= resolver.lookup(filepath, headerBytes: data);
    return type;
  }
}
