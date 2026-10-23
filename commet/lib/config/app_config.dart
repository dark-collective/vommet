library;

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  /// Vommet: the single-instance pipe on Windows. It must not be Commet's
  /// (`chat.commet.commetapp`), or with both running a new Vommet hands its
  /// arguments to Commet and quits (Vommet issue 355).
  static const String windowsPipeName = r"\\.\pipe\im.nether.chat";

  static Future<String> getDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "db");
  }

  static Future<String> getSocketPath() async {
    if (PlatformUtils.isWindows) {
      return windowsPipeName;
    }

    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "socket");
  }

  static Future<String> getWidgetSocketPath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "widget_rx");
  }

  static Future<String> getDriftDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final dir = await getDatabasePath();
    return join(dir, "account", "drift");
  }
}
