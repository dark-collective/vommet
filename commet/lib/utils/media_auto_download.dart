import 'dart:async';
import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:commet/utils/mime.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Vommet: the network media is downloaded over. Roaming is only told apart
/// from mobile data on Android (elsewhere it counts as mobile data). On Linux
/// and Windows a connection the system marks as metered counts as mobile
/// data; other desktops and web always count as Wi-Fi.
enum MediaNetwork { wifi, mobile, roaming }

/// Vommet: what an event's media is, for the automatic download choices.
/// Videos themselves only ever download when played; only their preview
/// picture is automatic.
enum AutoMediaKind { photo, gif, videoPreview }

/// Vommet: which media downloads by itself on one network.
class AutoDownloadPolicy {
  const AutoDownloadPolicy({
    this.enabled = true,
    this.photos = true,
    this.gifs = true,
    this.videoPreviews = true,
    this.maxMb = 0,
  });

  final bool enabled;
  final bool photos;
  final bool gifs;
  final bool videoPreviews;

  /// Photos and GIFs bigger than this many MB wait for a tap; 0 means no
  /// limit. Video previews are small pictures and never wait for size.
  final int maxMb;

  /// The size limit steps the settings offer; 0 is "No limit".
  static const maxMbSteps = [1, 2, 5, 10, 0];

  /// The defaults per network: everything on Wi-Fi, photos and GIFs up to
  /// 2 MB on mobile data, nothing by itself when roaming.
  static AutoDownloadPolicy defaultFor(MediaNetwork network) =>
      switch (network) {
        MediaNetwork.wifi => const AutoDownloadPolicy(),
        MediaNetwork.mobile => const AutoDownloadPolicy(maxMb: 2),
        MediaNetwork.roaming => const AutoDownloadPolicy(enabled: false),
      };

  /// Whether media of [kind] downloads by itself; [bytes] is the size of
  /// what would be downloaded, when known.
  bool allows(AutoMediaKind kind, {int? bytes}) =>
      enabled &&
      switch (kind) {
        AutoMediaKind.photo => photos && _fits(bytes),
        AutoMediaKind.gif => gifs && _fits(bytes),
        AutoMediaKind.videoPreview => videoPreviews,
      };

  bool _fits(int? bytes) =>
      maxMb <= 0 || bytes == null || bytes <= maxMb * 1024 * 1024;

  AutoDownloadPolicy copyWith(
          {bool? enabled,
          bool? photos,
          bool? gifs,
          bool? videoPreviews,
          int? maxMb}) =>
      AutoDownloadPolicy(
        enabled: enabled ?? this.enabled,
        photos: photos ?? this.photos,
        gifs: gifs ?? this.gifs,
        videoPreviews: videoPreviews ?? this.videoPreviews,
        maxMb: maxMb ?? this.maxMb,
      );

  String toJson() => jsonEncode({
        "enabled": enabled,
        "photos": photos,
        "gifs": gifs,
        "video_previews": videoPreviews,
        "max_mb": maxMb,
      });

  /// Missing, unknown or broken values fall back to [fallback] (everything
  /// on unless given: Commet's behaviour before this setting existed).
  static AutoDownloadPolicy fromJson(String? json,
      {AutoDownloadPolicy fallback = const AutoDownloadPolicy()}) {
    if (json == null || json.isEmpty) return fallback;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      bool flag(String key, bool otherwise) =>
          map[key] is bool ? map[key] as bool : otherwise;
      final max = map["max_mb"];
      return AutoDownloadPolicy(
        enabled: flag("enabled", fallback.enabled),
        photos: flag("photos", fallback.photos),
        gifs: flag("gifs", fallback.gifs),
        videoPreviews: flag("video_previews", fallback.videoPreviews),
        maxMb: max is int && max >= 0 ? max : fallback.maxMb,
      );
    } catch (_) {
      return fallback;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadPolicy &&
      other.enabled == enabled &&
      other.photos == photos &&
      other.gifs == gifs &&
      other.videoPreviews == videoPreviews &&
      other.maxMb == maxMb;

  @override
  int get hashCode => Object.hash(enabled, photos, gifs, videoPreviews, maxMb);
}

/// Vommet: holds back event media (pictures, GIFs, stickers, video preview
/// pictures) the current network's [AutoDownloadPolicy] doesn't allow, until
/// it is tapped, opened in the viewer, or the network or policy changes.
/// Avatars, emoji, banners and anything already cached never wait.
class MediaAutoDownload {
  /// The current network, updated as it changes (also for "Use less data
  /// for calls", Vommet issue 776).
  static final ValueNotifier<MediaNetwork> networkChanges =
      ValueNotifier(MediaNetwork.wifi);
  static MediaNetwork get _network => networkChanges.value;
  static set _network(MediaNetwork network) => networkChanges.value = network;
  static MediaNetwork get network => _network;

  /// Starts following the network (no-op where it isn't tracked).
  static void watchNetwork() => _start();

  static final Set<String> _revealed = {};
  static final Map<String, (AutoMediaKind, int?, Completer<void>)> _waiting =
      {};

  /// Keys of media currently held back, for the tap-to-load overlay.
  static final ValueNotifier<Set<String>> held = ValueNotifier({});

  static StreamSubscription? _connectivity;
  static bool _started = false;

  /// The kind of an event's media, or null when it always loads.
  ///
  /// Decided by the attachment's resolved type, not only its msgtype: the
  /// timeline shows any message with an image or video mimetype as a
  /// picture or video (`m.file`, but also `m.text`, `m.audio` or none), so
  /// it waits like one; otherwise a sender could get past the setting just
  /// by picking the msgtype. [fileName] (`filename`, else `body`) is the
  /// fallback when the mimetype is missing or generic, as for the
  /// picture/file choice in the timeline. Other files never wait.
  static AutoMediaKind? kindOf(
      {required String eventType,
      String? msgtype,
      String? mimetype,
      String? fileName}) {
    if (eventType == "m.sticker") return AutoMediaKind.gif;
    if (eventType != "m.room.message") return null;
    final mime = mediaMimetype(mimetype ?? "", fileName);
    if (msgtype == "m.image") {
      return mime == "image/gif" ? AutoMediaKind.gif : AutoMediaKind.photo;
    }
    if (msgtype == "m.video") return AutoMediaKind.videoPreview;
    if (mime == "image/gif") return AutoMediaKind.gif;
    if (mime.startsWith("image/")) return AutoMediaKind.photo;
    if (mime.startsWith("video/")) return AutoMediaKind.videoPreview;
    return null;
  }

  static const _genericMimetypes = {
    "",
    "application/octet-stream",
    "binary/octet-stream",
    "application/binary",
    "application/unknown",
  };

  /// [mimetype] lowercased without parameters; a missing or generic one
  /// falls back to [fileName]'s extension (same rule as `AttachmentMime`).
  @visibleForTesting
  static String mediaMimetype(String mimetype, String? fileName) {
    final mime = mimetype.split(";").first.trim().toLowerCase();
    if (!_genericMimetypes.contains(mime) || fileName == null) return mime;
    final name = fileName.trim();
    final dot = name.lastIndexOf(".");
    if (dot < 0 || dot == name.length - 1) return mime;
    final ext = name.substring(dot + 1).toLowerCase();
    if (ext.contains(RegExp(r"[\s/\\]"))) return mime;
    return Mime.fromExtenstion(ext) ?? mime;
  }

  /// The file name an attachment event declares: `filename`, else `body`.
  static String? fileNameOf(Map<String, dynamic> content) {
    final filename = content["filename"];
    if (filename is String && filename.trim().isNotEmpty) return filename;
    final body = content["body"];
    return body is String ? body : null;
  }

  /// The network from connectivity_plus's results: Wi-Fi or ethernet wins;
  /// anything else on a phone counts as mobile data.
  static MediaNetwork networkFrom(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return MediaNetwork.wifi;
    }
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return MediaNetwork.wifi;
    }
    return MediaNetwork.mobile;
  }

  static AutoDownloadPolicy policyFor(MediaNetwork network) =>
      AutoDownloadPolicy.fromJson(
          switch (network) {
            MediaNetwork.wifi => preferences.autoDownloadWifi.value,
            MediaNetwork.mobile => preferences.autoDownloadMobile.value,
            MediaNetwork.roaming => preferences.autoDownloadRoaming.value,
          },
          fallback: AutoDownloadPolicy.defaultFor(network));

  static Future<void> setPolicy(
      MediaNetwork network, AutoDownloadPolicy policy) async {
    switch (network) {
      case MediaNetwork.wifi:
        await preferences.autoDownloadWifi.set(policy.toJson());
      case MediaNetwork.mobile:
        await preferences.autoDownloadMobile.set(policy.toJson());
      case MediaNetwork.roaming:
        await preferences.autoDownloadRoaming.set(policy.toJson());
    }
    _releaseAllowed();
  }

  /// Whether connection type matters here (phones only).
  static bool get tracksNetwork => BuildConfig.MOBILE || _forceTracking;
  static bool _forceTracking = false;

  /// Whether this desktop asks the system if the connection is metered
  /// (Linux NetworkManager, Windows); a metered one uses the mobile data
  /// choices for automatic download (not for Send smaller).
  static bool get watchesMetered =>
      !BuildConfig.MOBILE &&
      !_forceTracking &&
      (PlatformUtils.isLinux || PlatformUtils.isWindows);

  /// Whether the automatic download choices apply here.
  static bool get hasSettings => tracksNetwork || watchesMetered;

  /// Whether roaming is told apart from mobile data (Android only).
  static bool get detectsRoaming => PlatformUtils.isAndroid || _forceTracking;

  static const _channel = MethodChannel("im.nether.vommet/network");

  /// Android: whether the active network is roaming. Errors count as not
  /// roaming.
  static Future<bool> _isRoaming() async {
    if (!PlatformUtils.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>("isRoaming") ?? false;
    } catch (e) {
      Log.w("Roaming check failed: $e");
      return false;
    }
  }

  static DBusClient? _systemBus;
  static StreamSubscription? _meteredChanges;
  static List<ConnectivityResult> _lastResults = const [];

  static DBusRemoteObject _networkManager() =>
      DBusRemoteObject(_systemBus ??= DBusClient.system(),
          name: "org.freedesktop.NetworkManager",
          path: DBusObjectPath("/org/freedesktop/NetworkManager"));

  /// Linux and Windows: whether the system marks the connection as
  /// metered. Errors and "unknown" count as not metered.
  static Future<bool> _isMetered() async {
    try {
      if (PlatformUtils.isWindows) {
        return await _channel.invokeMethod<bool>("isMetered") ?? false;
      }
      if (PlatformUtils.isLinux) {
        final value = await _networkManager().getProperty(
            "org.freedesktop.NetworkManager", "Metered",
            signature: DBusSignature("u"));
        // NMMetered: 1 = yes, 3 = guessed yes (e.g. a phone hotspot).
        final metered = value.asUint32();
        return metered == 1 || metered == 3;
      }
    } catch (e) {
      Log.w("Metered check failed: $e");
    }
    return false;
  }

  /// Linux: NetworkManager says when the connection becomes (un)metered
  /// without the connection itself changing.
  static void _watchMetered() {
    if (!PlatformUtils.isLinux) return;
    try {
      _meteredChanges = _networkManager().propertiesChanged.listen((signal) {
        if (signal.changedProperties.containsKey("Metered")) {
          _onConnectivity(_lastResults);
        }
      }, onError: (Object e) => Log.w("Metered updates failed: $e"));
    } catch (e) {
      Log.w("Metered updates unavailable: $e");
    }
  }

  /// [networkFrom], then roaming told apart from mobile data, or on a
  /// desktop a metered connection counted as mobile data.
  static Future<MediaNetwork> _resolve(List<ConnectivityResult> results) async {
    if (!tracksNetwork) {
      if (results.isEmpty ||
          results.every((r) => r == ConnectivityResult.none)) {
        return MediaNetwork.wifi;
      }
      return await _isMetered() ? MediaNetwork.mobile : MediaNetwork.wifi;
    }
    final network = networkFrom(results);
    if (network != MediaNetwork.mobile) return network;
    return await _isRoaming() ? MediaNetwork.roaming : network;
  }

  static int _resolving = 0;

  static void _start() {
    if (_started) return;
    _started = true;
    if (!hasSettings) return;
    if (watchesMetered) _watchMetered();
    try {
      final connectivity = Connectivity();
      connectivity.checkConnectivity().then(_onConnectivity,
          onError: (Object e) => Log.w("Connectivity check failed: $e"));
      _connectivity = connectivity.onConnectivityChanged.listen(_onConnectivity,
          onError: (Object e) {
        Log.w("Connectivity updates failed: $e");
      });
    } catch (e) {
      Log.w("Connectivity unavailable, treating as Wi-Fi: $e");
    }
  }

  static Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    _lastResults = results;
    final run = ++_resolving;
    final network = await _resolve(results);
    // A newer change came in while asking about roaming.
    if (run != _resolving) return;
    _network = network;
    _releaseAllowed();
  }

  /// The network right now, asking the system when it may not be known
  /// yet (Vommet issue 128: pictures are sent smaller on mobile data).
  static Future<MediaNetwork> currentNetwork() async {
    if (!tracksNetwork) return MediaNetwork.wifi;
    // Unit tests set the network and have no platform channels.
    if (_forceTracking) return _network;
    _start();
    try {
      return await _resolve(await Connectivity().checkConnectivity());
    } catch (e) {
      Log.w("Connectivity check failed: $e");
      return _network;
    }
  }

  /// Waits until media [key] of [kind] may download. Returns at once when
  /// the current policy allows it or it was revealed. [bytes] is the size
  /// of what would be downloaded, when known, for the size limit.
  static Future<void> waitUntilAllowed(String key, AutoMediaKind kind,
      {int? bytes}) {
    // Web and macOS always count as Wi-Fi and have no settings for it.
    if (!hasSettings) return Future.value();
    _start();
    if (_revealed.contains(key) ||
        policyFor(_network).allows(kind, bytes: bytes)) {
      return Future.value();
    }
    final existing = _waiting[key];
    if (existing != null) return existing.$3.future;

    final completer = Completer<void>();
    _waiting[key] = (kind, bytes, completer);
    held.value = {...held.value, key};
    return completer.future;
  }

  /// Whether media of [kind] may download by itself right now (without
  /// waiting), e.g. to decide whether a GIF video starts on its own.
  static bool allowsNow(AutoMediaKind kind) {
    if (!hasSettings) return true;
    _start();
    return policyFor(_network).allows(kind);
  }

  /// Lets media [key] download now (a tap, or opening it in the viewer).
  static void reveal(String key) {
    _revealed.add(key);
    _release(key);
  }

  static void _release(String key) {
    final waiting = _waiting.remove(key);
    if (waiting == null) return;
    waiting.$3.complete();
    held.value = {...held.value}..remove(key);
  }

  static void _releaseAllowed() {
    final policy = policyFor(_network);
    for (final entry in _waiting.entries.toList()) {
      if (policy.allows(entry.value.$1, bytes: entry.value.$2)) {
        _release(entry.key);
      }
    }
  }

  /// Unit tests only: a fresh state with network tracking on.
  static void resetForTest({MediaNetwork network = MediaNetwork.wifi}) {
    _connectivity?.cancel();
    _connectivity = null;
    _meteredChanges?.cancel();
    _meteredChanges = null;
    _started = true; // no platform channels in unit tests
    _forceTracking = true;
    _network = network;
    _revealed.clear();
    _waiting.clear();
    held.value = {};
  }

  /// Unit tests only.
  static void setNetworkForTest(MediaNetwork network) {
    _network = network;
    _releaseAllowed();
  }
}
