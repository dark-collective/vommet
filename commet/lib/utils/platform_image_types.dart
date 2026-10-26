import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Vommet: picture types Flutter itself can't decode, but this device's
/// platform decoder can (Vommet issue 778).
///
/// Flutter hands formats it doesn't know to the platform, but only Android
/// has such a decoder (`android.graphics.ImageDecoder`, API 28+): HEIC/HEIF
/// from Android 9, AVIF from Android 12. iOS, macOS, Windows, Linux and web
/// have none in the engine, so there these stay thumbnail-only
/// (AttachmentMime.showsThumbnailOnly) or a file tile.
class PlatformImageTypes {
  static Set<String> _types = const {};

  /// The types decodable here; empty until [init] has run.
  static Set<String> get types => _types;

  static bool canDecode(String mimetype) => _types.contains(mimetype);

  /// Reads the Android API level once at startup; a no-op elsewhere.
  static Future<void> init() async {
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

  static void setForTesting(Set<String> types) => _types = types;
}
