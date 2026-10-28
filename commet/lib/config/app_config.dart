library;

import 'package:commet/config/build_config.dart';
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/xdg_config_dirs.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static Future<XdgConfigDirs?>? _xdgConfigDirs;

  /// Vommet issue 836: the Linux config folder, or null elsewhere (and
  /// when there is no usable `$XDG_CONFIG_HOME`/`$HOME`).
  static Future<XdgConfigDirs?> _linuxConfigDirs() =>
      _xdgConfigDirs ??= () async {
        if (BuildConfig.WEB || !PlatformUtils.isLinux) return null;
        final data = (await getApplicationSupportDirectory()).path;
        final config = XdgConfigDirs.configDirFor(data, Platform.environment);
        if (config == null) return null;
        return XdgConfigDirs(dataDir: data, configDir: config);
      }();

  /// Where the user's customization [folder] lives ("theme", "fonts",
  /// "sounds", "app_icon"): `$XDG_CONFIG_HOME/<app>/<folder>` on Linux
  /// (Vommet issue 836), the app support folder elsewhere.
  static Future<String> getConfigFolderPath(String folder) async {
    final xdg = await _linuxConfigDirs();
    if (xdg != null) return xdg.folderPath(folder);
    return join((await getApplicationSupportDirectory()).path, folder);
  }

  /// Moves those folders out of the data folder once on Linux (Vommet
  /// issue 836); runs before anything reads them. Never throws.
  static Future<void> moveConfigFolders(SharedPreferences prefs) async {
    try {
      final xdg = await _linuxConfigDirs();
      if (xdg == null) return;
      await xdg.migrate(
        readStrings: () => {
          for (final key in prefs.getKeys())
            if (prefs.get(key) case final Object v
                when v is String || v is List<String>)
              key: v,
        },
        writeString: prefs.setString,
        writeStringList: prefs.setStringList,
      );
    } catch (_) {}
  }

  static Future<String> getDriftDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final dir = await getDatabasePath();
    return join(dir, "account", "drift");
  }
}
