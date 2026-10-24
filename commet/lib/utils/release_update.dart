import 'dart:convert';
import 'dart:io';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/experiment_registry.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/file_utils.dart';
import 'package:commet/utils/minisign.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// How this copy of Vommet was installed (Vommet issue 593).
enum InstallKind {
  apk,
  flatpak,
  appImage,
  deb,
  rpm,
  tarball,
  nix,
  guix,
  macos,
  windows,
  ios,
  web,
  unknown,
}

/// What the release bar's button does for an install kind.
enum UpdateAction {
  /// Download, verify, open the file with the system installer.
  install,

  /// Download, verify, swap the AppImage in place, then restart.
  replace,

  /// Download, verify, show the file in the file manager.
  reveal,

  /// Download, verify, then show the command that installs the file. A
  /// Flatpak can't install itself from inside its sandbox, and many desktops
  /// have no app that opens .flatpak files (Hyprland, sway, a bare Guix
  /// session), so opening the file would do nothing.
  installCommand,

  /// A package manager owns the install: show its update command.
  command,

  /// Reload the page (web).
  reload,

  /// Open the download page.
  page,
}

enum UpdatePhase { idle, downloading, ready, failed }

class UpdateState {
  const UpdateState(this.phase,
      {this.received = 0, this.total, this.file, this.error});
  final UpdatePhase phase;
  final int received;
  final int? total;
  final String? file;
  final UpdateError? error;

  static const idle = UpdateState(UpdatePhase.idle);
}

enum UpdateError {
  /// The download failed (network, disk).
  download,

  /// The file didn't match the signed SHA256SUMS, or the signature is missing
  /// or wrong. Nothing was installed.
  verify,

  /// The new file couldn't be put in place or opened.
  install,
}

/// Vommet: gets the newer release's file for this install, checks it against
/// the release's signed SHA256SUMS and hands it to the system (Vommet issue
/// 593). Package-manager installs get a command instead of a download.
class ReleaseUpdate {
  /// minisign public key of the release signing key (publish.sh signs each
  /// release's SHA256SUMS into SHA256SUMS.minisig).
  static const String publicKey =
      "RWQ99Qbe/vM2/KxFh19QhHL00+tb0Fre2krWPT5CTgak/7506vbteI8k";

  static const int _maxSize = 1024 * 1024 * 1024;

  static const MethodChannel _android = MethodChannel("im.nether.chat/updates");

  static final ValueNotifier<UpdateState> state =
      ValueNotifier(UpdateState.idle);

  static InstallKind? _kind;
  static InstallKind get kind => _kind ??= _detectCurrent();

  /// Tests pick the install kind (null: detect it again).
  static set kindForTest(InstallKind? kind) => _kind = kind;

  static UpdateAction get action => actionFor(kind);

  static http.Client? _client;
  static bool _cancelled = false;

  static InstallKind _detectCurrent() {
    if (kIsWeb || BuildConfig.WEB) return InstallKind.web;
    return detect(
      android: BuildConfig.ANDROID,
      ios: BuildConfig.IOS,
      mac: Platform.isMacOS,
      windows: Platform.isWindows,
      linux: Platform.isLinux,
      environment: Platform.environment,
      executable: Platform.resolvedExecutable,
      exists: (path) => File(path).existsSync(),
    );
  }

  /// Linux packages share one Flutter build (BUILD_DETAIL says "guix" for
  /// all of them), so the kind comes from where the binary runs from.
  static InstallKind detect(
      {required bool android,
      required bool ios,
      required bool mac,
      required bool windows,
      required bool linux,
      required Map<String, String> environment,
      required String executable,
      required bool Function(String path) exists}) {
    if (android) return InstallKind.apk;
    if (ios) return InstallKind.ios;
    if (mac) return InstallKind.macos;
    if (windows) return InstallKind.windows;
    if (!linux) return InstallKind.unknown;
    if (environment.containsKey("FLATPAK_ID")) return InstallKind.flatpak;
    if ((environment["APPIMAGE"] ?? "").isNotEmpty) {
      return InstallKind.appImage;
    }
    if (executable.startsWith("/nix/store/")) return InstallKind.nix;
    if (executable.startsWith("/gnu/store/")) return InstallKind.guix;
    if (executable.startsWith("/opt/vommet/")) {
      if (exists("/var/lib/dpkg/info/vommet.list")) return InstallKind.deb;
      return InstallKind.rpm;
    }
    return InstallKind.tarball;
  }

  static UpdateAction actionFor(InstallKind kind) => switch (kind) {
        InstallKind.flatpak => UpdateAction.installCommand,
        InstallKind.apk ||
        InstallKind.deb ||
        InstallKind.rpm =>
          UpdateAction.install,
        InstallKind.appImage => UpdateAction.replace,
        InstallKind.tarball ||
        InstallKind.macos ||
        InstallKind.windows =>
          UpdateAction.reveal,
        InstallKind.nix || InstallKind.guix => UpdateAction.command,
        InstallKind.web => UpdateAction.reload,
        InstallKind.ios || InstallKind.unknown => UpdateAction.page,
      };

  /// The command that updates a package-manager install.
  static String? commandFor(InstallKind kind) => switch (kind) {
        InstallKind.nix => "nix profile upgrade vommet-packaging",
        InstallKind.guix => "guix pull && guix upgrade vommet",
        _ => null,
      };

  /// The command that installs the downloaded [file] over this Flatpak.
  /// `flatpak install` of a bundle updates an app already installed from
  /// one. [flatpakInfo] is the sandbox's /.flatpak-info: its app-path says
  /// whether Vommet is a per-user or a system-wide install.
  static String flatpakInstallCommand(String file, String flatpakInfo) {
    final system = RegExp(r"^app-path=/var/lib/flatpak/", multiLine: true)
        .hasMatch(flatpakInfo);
    final quoted = RegExp(r"^[\w@%+=:,./-]+$").hasMatch(file)
        ? file
        : "'${file.replaceAll("'", "'\\''")}'";
    return "flatpak install ${system ? "--system" : "--user"} -y $quoted";
  }

  /// The install command for the downloaded update, or null when there is
  /// none (not a Flatpak, or nothing downloaded yet).
  static String? get installCommand {
    final file = state.value.file;
    if (action != UpdateAction.installCommand ||
        state.value.phase != UpdatePhase.ready ||
        file == null) {
      return null;
    }
    String info = "";
    try {
      info = File("/.flatpak-info").readAsStringSync();
    } catch (_) {}
    return flatpakInstallCommand(file, info);
  }

  /// "x64" or "arm64", as the release files name them.
  static String get arch =>
      Platform.version.contains("arm64") ? "arm64" : "x64";

  /// The release file for [kind] on [arch], from the releases API's
  /// `assets`, or null when the release has none (the bar then falls back to
  /// the download page).
  static Map<String, dynamic>? assetFor(
      InstallKind kind, String arch, List<dynamic> assets) {
    final (String prefix, String suffix)? match = switch (kind) {
      InstallKind.apk => ("vommet-", ".apk"),
      InstallKind.flatpak => (
          "vommet-",
          arch == "arm64" ? "-aarch64.flatpak" : "-x86_64.flatpak"
        ),
      InstallKind.appImage => ("vommet-linux-$arch-", ".AppImage"),
      InstallKind.deb => ("vommet-linux-$arch-", ".deb"),
      InstallKind.rpm => ("vommet-linux-$arch-", ".rpm"),
      InstallKind.tarball => ("vommet-linux-$arch-", ".tar.gz"),
      InstallKind.macos => ("vommet-macos-", ".zip"),
      InstallKind.windows => ("vommet-", "-windows-x64.zip"),
      _ => null,
    };
    if (match == null) return null;
    for (final a in assets.whereType<Map<String, dynamic>>()) {
      final name = a["name"];
      if (name is String &&
          name.startsWith(match.$1) &&
          name.endsWith(match.$2) &&
          a["browser_download_url"] is String) {
        return a;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _named(List<dynamic> assets, String name) {
    for (final a in assets.whereType<Map<String, dynamic>>()) {
      if (a["name"] == name && a["browser_download_url"] is String) return a;
    }
    return null;
  }

  /// The SHA-256 SHA256SUMS lists for [file] (`sha256sum` output).
  static String? checksumFor(String sums, String file) {
    for (final line in const LineSplitter().convert(sums)) {
      final m = RegExp(r"^([0-9a-fA-F]{64}) [ *](.+)$").firstMatch(line.trim());
      if (m != null && m.group(2) == file) return m.group(1)!.toLowerCase();
    }
    return null;
  }

  /// The newer release has a file this install can use.
  static bool canDownload(Map<String, dynamic>? release) {
    final a = action;
    if (a != UpdateAction.install &&
        a != UpdateAction.installCommand &&
        a != UpdateAction.replace &&
        a != UpdateAction.reveal) {
      return false;
    }
    final assets = release?["assets"];
    // Releases from before signing have no SHA256SUMS.minisig: those keep
    // the download page rather than an Update button that can only fail.
    return assets is List &&
        assetFor(kind, arch, assets) != null &&
        _named(assets, "SHA256SUMS") != null &&
        _named(assets, "SHA256SUMS.minisig") != null;
  }

  static void cancel() {
    _cancelled = true;
    _client?.close();
  }

  /// Downloads and verifies [release]'s file for this install. On success
  /// the state is [UpdatePhase.ready] with the verified file.
  static Future<void> download(Map<String, dynamic> release,
      {http.Client? client}) async {
    if (state.value.phase == UpdatePhase.downloading) return;
    final assets = release["assets"];
    if (assets is! List) return;
    final asset = assetFor(kind, arch, assets);
    if (asset == null) return;
    final name = asset["name"] as String;

    _cancelled = false;
    state.value = const UpdateState(UpdatePhase.downloading);
    final c = _client = client ?? http.Client();
    File? part;
    try {
      final sumsAsset = _named(assets, "SHA256SUMS");
      final sigAsset = _named(assets, "SHA256SUMS.minisig");
      if (sumsAsset == null || sigAsset == null) {
        Log.w("Update: release has no signed SHA256SUMS");
        state.value =
            const UpdateState(UpdatePhase.failed, error: UpdateError.verify);
        return;
      }
      final sums = await _get(c, sumsAsset["browser_download_url"]);
      final sig = await _get(c, sigAsset["browser_download_url"]);
      if (!await Minisign.verify(
          publicKey: publicKey, message: sums, signature: utf8.decode(sig))) {
        Log.w("Update: SHA256SUMS signature doesn't verify");
        state.value =
            const UpdateState(UpdatePhase.failed, error: UpdateError.verify);
        return;
      }
      final want = checksumFor(utf8.decode(sums), name);
      if (want == null) {
        Log.w("Update: $name isn't in SHA256SUMS");
        state.value =
            const UpdateState(UpdatePhase.failed, error: UpdateError.verify);
        return;
      }

      final target = await _targetFor(name);
      part = File("$target.part");
      final request =
          http.Request("GET", Uri.parse(asset["browser_download_url"]));
      final response = await c.send(request);
      if (response.statusCode != 200) {
        throw HttpException("HTTP ${response.statusCode}");
      }
      final total = response.contentLength ?? (asset["size"] as int?);
      if (total != null && total > _maxSize) {
        throw const HttpException("file too large");
      }
      final sink = part.openWrite();
      var received = 0;
      var lastShown = 0;
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 60))) {
          if (_cancelled) break;
          received += chunk.length;
          if (received > _maxSize) {
            throw const HttpException("file too large");
          }
          sink.add(chunk);
          if (received - lastShown > 256 * 1024) {
            lastShown = received;
            state.value = UpdateState(UpdatePhase.downloading,
                received: received, total: total);
          }
        }
      } finally {
        await sink.close();
      }
      if (_cancelled) {
        await part.delete();
        state.value = UpdateState.idle;
        return;
      }

      final got = (await crypto.sha256.bind(part.openRead()).first).toString();
      if (got != want) {
        Log.w("Update: $name doesn't match SHA256SUMS");
        await part.delete();
        state.value =
            const UpdateState(UpdatePhase.failed, error: UpdateError.verify);
        return;
      }
      await part.rename(target);
      Log.i("Update: $name downloaded and verified");
      state.value =
          UpdateState(UpdatePhase.ready, received: received, file: target);
    } catch (e) {
      if (_cancelled) {
        state.value = UpdateState.idle;
      } else {
        Log.w("Update: download failed: $e");
        state.value =
            const UpdateState(UpdatePhase.failed, error: UpdateError.download);
      }
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
    } finally {
      if (client == null) c.close();
      _client = null;
    }
  }

  static Future<List<int>> _get(http.Client c, String url) async {
    final r = await c.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw HttpException("HTTP ${r.statusCode}");
    return r.bodyBytes;
  }

  /// Where the download goes: next to the AppImage it replaces (so the swap
  /// is one rename), the app's cache on Android (shared with the installer
  /// through VommetUpdateProvider), the app's cache folder in a Flatpak
  /// (~/.var/app/<id>/cache: the same path inside and outside the sandbox,
  /// so the install command works in a host terminal; Downloads isn't
  /// mounted in the sandbox when the desktop sets no XDG user dirs),
  /// otherwise the Downloads folder.
  static Future<String> _targetFor(String name) async {
    if (action == UpdateAction.replace) {
      final appImage = Platform.environment["APPIMAGE"]!;
      final dir = p.dirname(appImage);
      // A read-only folder can't take the new AppImage: fall back to
      // Downloads (the bar then shows the file instead).
      try {
        final probe = File(p.join(dir, ".vommet-update-probe"));
        await probe.writeAsString("");
        await probe.delete();
        return p.join(dir, ".$name.vommet-update");
      } catch (_) {
        _kind = InstallKind.tarball;
      }
    }
    Directory dir;
    final flatpakCache = Platform.environment["XDG_CACHE_HOME"];
    if (Platform.isAndroid) {
      dir = Directory(p.join((await getTemporaryDirectory()).path, "updates"));
    } else if (action == UpdateAction.installCommand && flatpakCache != null) {
      dir = Directory(p.join(flatpakCache, "updates"));
    } else {
      dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    }
    await dir.create(recursive: true);
    return p.join(dir.path, name);
  }

  /// Hands the verified file to the system. Returns false when it couldn't.
  static Future<bool> apply() async {
    final file = state.value.file;
    if (state.value.phase != UpdatePhase.ready || file == null) return false;
    try {
      switch (action) {
        case UpdateAction.install:
          if (Platform.isAndroid) {
            // Opens Android's installer, or first the "install unknown apps"
            // switch for Vommet when it's off.
            await _android.invokeMethod("installApk", {"path": file});
          } else {
            await Process.start("xdg-open", [file],
                mode: ProcessStartMode.detached);
          }
          return true;
        case UpdateAction.replace:
          final appImage = Platform.environment["APPIMAGE"]!;
          await Process.run("chmod", ["755", file]);
          await File(file).rename(appImage);
          for (final client in [...?clientManager?.clients]) {
            await client.close();
          }
          await ExperimentRegistry.restart();
          return true;
        case UpdateAction.reveal:
          if (Platform.isMacOS) {
            await Process.start("open", ["-R", file],
                mode: ProcessStartMode.detached);
          } else if (Platform.isWindows) {
            await Process.start("explorer.exe", ["/select,$file"],
                mode: ProcessStartMode.detached);
          } else {
            FileUtils.navigateToFile(file);
          }
          return true;
        default:
          return false;
      }
    } catch (e) {
      Log.w("Update: couldn't hand over $file: $e");
      state.value =
          const UpdateState(UpdatePhase.failed, error: UpdateError.install);
      return false;
    }
  }
}
