import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';

class SystemProcessesUtils {
  static Future<List<ProcessInfo>> getProcessList() async {
    if (PlatformUtils.isWeb) {
      return [];
    }

    if (BuildConfig.IS_FLATPAK) {
      var result = await Process.run(
          "flatpak-spawn", ["--host", "ps", "-e", "-o", "pid,command"]);
      return parseLinuxPS(result.stdout);
    }

    if (BuildConfig.LINUX) {
      var result = await Process.run("ps", ["-e", "-o", "pid,command"]);
      return parseLinuxPS(result.stdout);
    }

    return [];
  }

  static Future<Process> spawnSubprocess(String name, List<String> args) async {
    if (BuildConfig.IS_FLATPAK) {
      // Vommet: the host's own display names, not the sandbox's. Inside the
      // Flatpak the Wayland socket is always renamed to wayland-0 (and X11
      // to :0), so passing those to a host process breaks on desktops that
      // use wayland-1 or :1.
      var display = await hostDisplayEnv();

      if (PlatformUtils.isDisplayServer(DisplayServer.Wayland)) {
        args = [
          "WAYLAND_DISPLAY=${display["WAYLAND_DISPLAY"] ?? "wayland-0"}",
          name,
          ...args
        ];
        name = "env";
      }

      if (PlatformUtils.isDisplayServer(DisplayServer.X11)) {
        args = ["DISPLAY=${display["DISPLAY"] ?? ":0"}", name, ...args];
        name = "env";
      }

      Log.i("Spawning subprocess: ${name} ${args}");
      var result =
          await Process.start("flatpak-spawn", ["--host", name, ...args]);

      return result;
    }

    Log.i("Spawning subprocess: ${name} ${args}");

    return Process.start(name, args);
  }

  static Future<ProcessResult> runSubprocess(
      String name, List<String> args) async {
    Log.i("Spawning subprocess: ${name} ${args}");

    if (BuildConfig.IS_FLATPAK) {
      var result =
          await Process.run("flatpak-spawn", ["--host", name, ...args]);
      return result;
    }

    return Process.run(name, args);
  }

  static Future<Map<String, String>>? _hostDisplayEnv;

  /// Vommet: WAYLAND_DISPLAY and DISPLAY of the host session, read once.
  /// First from the user session's environment (desktops publish both
  /// there), else the host's only wayland-N socket. Keys are missing when
  /// neither works; callers then keep the old default.
  static Future<Map<String, String>> hostDisplayEnv() =>
      _hostDisplayEnv ??= _readHostDisplayEnv();

  static Future<Map<String, String>> _readHostDisplayEnv() async {
    var env = <String, String>{};
    try {
      var result = await Process.run("flatpak-spawn",
          ["--host", "systemctl", "--user", "show-environment"]);
      if (result.exitCode == 0) {
        env = parseDisplayEnvironment(result.stdout as String);
      }
    } catch (e) {
      Log.w("Couldn't read the host session environment: $e");
    }

    if (!env.containsKey("WAYLAND_DISPLAY")) {
      try {
        var result = await Process.run("flatpak-spawn",
            ["--host", "sh", "-c", r'ls -1 "$XDG_RUNTIME_DIR"']);
        var socket = singleWaylandSocket(result.stdout as String);
        if (result.exitCode == 0 && socket != null) {
          env["WAYLAND_DISPLAY"] = socket;
        }
      } catch (e) {
        Log.w("Couldn't list the host Wayland sockets: $e");
      }
    }

    Log.i("Host display: $env");
    return env;
  }

  /// WAYLAND_DISPLAY and DISPLAY from `systemctl --user show-environment`
  /// output. Values systemd had to quote are skipped.
  static Map<String, String> parseDisplayEnvironment(String output) {
    var env = <String, String>{};
    for (var line in output.split("\n")) {
      for (var key in const ["WAYLAND_DISPLAY", "DISPLAY"]) {
        if (!line.startsWith("$key=")) continue;
        var value = line.substring(key.length + 1).trim();
        if (value.isNotEmpty && !value.startsWith(r"$'")) env[key] = value;
      }
    }
    return env;
  }

  /// The one `wayland-N` socket in a directory listing, or null when there
  /// are none or several.
  static String? singleWaylandSocket(String listing) {
    var sockets = listing
        .split("\n")
        .map((e) => e.trim())
        .where((e) => RegExp(r"^wayland-\d+$").hasMatch(e))
        .toList();
    return sockets.length == 1 ? sockets.first : null;
  }

  static List<ProcessInfo> parseLinuxPS(String output) {
    // Skip first line
    var lines = output.trim().split("\n").sublist(1);

    var result = List<ProcessInfo>.empty(growable: true);

    for (var line in lines) {
      var split = line.trim().split(" ");
      if (split.isEmpty) continue;

      var pid = int.parse(split[0]);
      var command = split[1];

      if (command.startsWith("[")) command = command.substring(1);

      if (command.endsWith("]"))
        command = command.substring(0, command.length - 1);

      List<String> args = [];
      if (split.length > 2) {
        args = split.sublist(2);
      }

      result.add(ProcessInfo(processId: pid, command: command, args: args));
    }

    return result;
  }
}

class ProcessInfo {
  final int processId;
  final String command;
  final List<String> args;

  ProcessInfo(
      {required this.processId, required this.command, this.args = const []});
}
