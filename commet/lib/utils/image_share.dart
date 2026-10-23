import 'dart:io' show Directory, File, Platform;

import 'package:commet/config/platform_utils.dart';
import 'package:commet/utils/image_save.dart';
import 'package:commet/utils/mime.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Vommet: "Share" in the image viewer menu hands the picture to the system
/// share sheet. Same bytes as "Save as…" (the original file, decrypted when
/// needed), written to a temporary file first. Only where share_plus opens
/// a real share sheet: Android, iOS and macOS.
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

    // One folder for shares; the previous share's file is dropped here.
    final dir =
        Directory(p.join((await getTemporaryDirectory()).path, "vommet_share"));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, shareFileName(fileName, ext)));
    await file.writeAsBytes(bytes, flush: true);

    final share = await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: Mime.lookupType("", data: bytes))],
      sharePositionOrigin: origin,
    ));
    return share.status != ShareResultStatus.unavailable;
  }

  /// A safe file name for the shared copy: [fileName] without any folders,
  /// "image.<ext>" when there's none, and ".<ext>" added when it has no
  /// extension.
  static String shareFileName(String? fileName, String ext) {
    var name = (fileName ?? "").split(RegExp(r"[/\\]")).last.trim();
    if (name.isEmpty || name == "." || name == "..") name = "image";
    if (!name.contains(".")) name = "$name.$ext";
    return name;
  }
}
