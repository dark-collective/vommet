import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/subplatforms/subplatforms.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/utils/system_processes_utils.dart';
import 'package:window_manager/window_manager.dart';

class SteamdeckSubplatform implements Subplatform {
  @override
  Future<void> init() async {
    Log.i(
        "Initializing steamdeck subplatform: ${_isSteamDeck} is gamemode: ${_isGameMode}");

    if (_isGameMode) {
      await windowManager.setFullScreen(true);
      ensureFullscreen();
    }
  }

  Future<void> ensureFullscreen() async {
    for (int i = 0; i < 10; i++) {
      if (await windowManager.isFullScreen()) {
        return;
      }

      Log.i("Window is still not fullscreen, waiting and trying again");

      await Future.delayed(Duration(seconds: 1));
      await windowManager.setFullScreen(true);
    }
  }

  @override
  String get name => _isGameMode ? "steamdeck_gamemode" : "steamdeck_desktop";

  static bool _isSteamDeck = false;

  static bool _isGameMode = false;

  static Future<bool> isSteamdeck() async {
    if (!PlatformUtils.isLinux) {
      return false;
    }

    // Vommet: the Flatpak can't list host processes. A Deck's board is
    // named Jupiter (LCD) or Galileo (OLED); Steam's game mode runs apps in
    // a gamescope session.
    if (BuildConfig.IS_FLATPAK) {
      final env = Platform.environment;
      var board = "";
      try {
        board =
            (await File("/sys/class/dmi/id/board_name").readAsString()).trim();
      } catch (_) {}
      _isSteamDeck =
          board == "Jupiter" || board == "Galileo" || env["SteamDeck"] == "1";
      _isGameMode = _isSteamDeck &&
          (env["SteamGamepadUI"] == "1" ||
              (env["XDG_CURRENT_DESKTOP"] ?? "")
                  .toLowerCase()
                  .contains("gamescope"));
      Log.i("Is running on steamdeck: ${_isSteamDeck} is gamemode: "
          "${_isGameMode} (board $board)");
      return _isSteamDeck;
    }

    var processes = await SystemProcessesUtils.getProcessList();

    var steamProceses = processes.where((i) => i.command.endsWith("/steam"));

    _isSteamDeck = steamProceses.any((i) => i.args.contains("-steamdeck"));

    _isGameMode =
        _isSteamDeck && steamProceses.any((i) => i.args.contains("-gamepadui"));

    Log.i(
        "Is running on steamdeck: ${_isSteamDeck} is gamemode: ${_isGameMode}");

    return _isSteamDeck;
  }
}
