import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:commet/cache/file_provider.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/utils/image_save.dart';
import 'package:commet/utils/mime.dart';
import 'package:commet/utils/private_files/private_media_files.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Vommet: "Share" in the image viewer menu hands the picture to the system
/// share sheet. Same bytes as "Save as…" (the original file, decrypted when
/// needed), written to a private file first ([PrivateMediaFiles], never the
/// shared temporary directory) that is deleted afterwards. Only where
/// share_plus opens a real share sheet: Android, iOS and macOS.
class ImageShare {
  static bool get supported =>
      PlatformUtils.isAndroid ||
      (!kIsWeb && (Platform.isIOS || Platform.isMacOS));

  /// True when the share sheet was opened. [origin] is where the menu was
  /// opened, for the iPad and macOS share popover.
  static Future<bool> share(ImageProvider image,
      {String? fileName, Rect? origin}) async {
    if (!supported) return false;
    final result = await ImageSave.bytesOf(image);
    if (result == null) return false;
    final (bytes, ext) = result;
    return _shareBytes(bytes, shareFileName(fileName, ext), origin);
  }

  /// Vommet issue 766: "Share" for a video (or any file) in the media
  /// viewer. The whole file, decrypted when needed; [fallbackName] names it
  /// when [fileName] is missing.
  static Future<bool> shareFile(FileProvider file,
      {String? fileName,
      String fallbackName = "video",
      String fallbackExt = "mp4",
      Rect? origin}) async {
    if (!supported) return false;
    final bytes = await file.getFileData();
    if (bytes == null || bytes.isEmpty) return false;
    final mime = Mime.lookupType(fileName ?? "", data: bytes);
    final ext =
        (mime == null ? null : Mime.extensionFromMime(mime)) ?? fallbackExt;
    return _shareBytes(
        bytes, shareFileName(fileName, ext, fallback: fallbackName), origin);
  }

  /// How long a shared copy is kept on iOS and macOS.
  static const Duration shareCopyLifetime = Duration(minutes: 5);

  static Future<bool> _shareBytes(
      Uint8List bytes, String name, Rect? origin) async {
    final File file;
    try {
      file = await PrivateMediaFiles.writeNamed(bytes, name);
    } on PrivateFilesUnavailable catch (error) {
      Log.w("Not sharing: $error");
      return false;
    }
    try {
      final share = await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: Mime.lookupType("", data: bytes))],
        sharePositionOrigin: origin,
      ));
      return share.status != ShareResultStatus.unavailable;
    } finally {
      // Android's share_plus hands apps its own copy, so ours can go now.
      // On iOS and macOS the receiving app may still be reading the file
      // when the sheet reports back, so it goes a little later (or with the
      // start-up sweep if the app is closed first).
      if (PlatformUtils.isAndroid) {
        await PrivateMediaFiles.release(file.uri);
      } else {
        Future.delayed(shareCopyLifetime, () {
          PrivateMediaFiles.release(file.uri);
        });
      }
    }
  }

  /// A safe file name for the shared copy: [fileName] without any folders,
  /// "<fallback>.<ext>" ("image" unless given) when there's none, and
  /// ".<ext>" added when it has no extension.
  static String shareFileName(String? fileName, String ext,
      {String fallback = "image"}) {
    var name = (fileName ?? "").split(RegExp(r"[/\\]")).last.trim();
    if (name.isEmpty || name == "." || name == "..") name = fallback;
    if (!name.contains(".")) name = "$name.$ext";
    return name;
  }
}
