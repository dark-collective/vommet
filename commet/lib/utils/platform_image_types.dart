import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/image/heif_decode.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show compute;

/// Vommet: picture types Flutter itself can't decode, but this device's
/// platform decoder can (Vommet issue 778).
///
/// Flutter hands formats it doesn't know to the platform, but only Android
/// has such a decoder (`android.graphics.ImageDecoder`, API 28+): HEIC/HEIF
/// from Android 9, AVIF from Android 12. On Linux and Windows HEIC/HEIF are
/// decoded by the system's own decoder and handed to the engine as a BMP
/// (Vommet issue 813, see [decodeHeifToBmp]) where a test picture decodes at
/// startup. iOS, macOS and web have none, so there these stay thumbnail-only
/// (AttachmentMime.showsThumbnailOnly) or a file tile.
class PlatformImageTypes {
  static Set<String> _types = const {};
  static bool _transcodesHeif = false;

  /// Whether HEIC/HEIF bytes must go through [decodeHeifToBmp] before the
  /// engine can decode them (Linux, Windows).
  static bool get transcodesHeif => _transcodesHeif;

  /// The types decodable here; empty until [init] has run.
  static Set<String> get types => _types;

  static bool canDecode(String mimetype) => _types.contains(mimetype);

  /// Reads the Android API level once at startup, or on Linux and Windows
  /// tries the system's HEIC decoder; a no-op elsewhere.
  static Future<void> init() async {
    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      try {
        if (await compute(_probeHeif, null)) {
          _types = const {"image/heic", "image/heif"};
          _transcodesHeif = true;
        }
      } catch (e) {
        Log.w("Could not probe the system HEIC decoder: $e");
      }
      return;
    }
    if (!PlatformUtils.isAndroid) return;
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      _types = forAndroidSdk(sdk);
    } catch (e) {
      Log.w("Could not read the Android API level: $e");
    }
  }

  static Set<String> forAndroidSdk(int sdk) => {
        if (sdk >= 28) ...{"image/heic", "image/heif"},
        if (sdk >= 31) "image/avif",
      };

  static void setForTesting(Set<String> types, {bool transcodesHeif = false}) {
    _types = types;
    _transcodesHeif = transcodesHeif;
  }
}

bool _probeHeif(void _) => decodeHeifToBmp(heifProbeSample) != null;
