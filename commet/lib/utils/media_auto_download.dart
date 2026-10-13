import 'dart:async';
import 'dart:convert';

import 'package:commet/config/build_config.dart';
import 'package:commet/debug/log.dart';
import 'package:commet/main.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Vommet: the network media is downloaded over. Roaming counts as mobile
/// data; desktops and web always count as Wi-Fi.
enum MediaNetwork { wifi, mobile }

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
  });

  final bool enabled;
  final bool photos;
  final bool gifs;
  final bool videoPreviews;

  bool allows(AutoMediaKind kind) =>
      enabled &&
      switch (kind) {
        AutoMediaKind.photo => photos,
        AutoMediaKind.gif => gifs,
        AutoMediaKind.videoPreview => videoPreviews,
      };

  AutoDownloadPolicy copyWith(
          {bool? enabled, bool? photos, bool? gifs, bool? videoPreviews}) =>
      AutoDownloadPolicy(
        enabled: enabled ?? this.enabled,
        photos: photos ?? this.photos,
        gifs: gifs ?? this.gifs,
        videoPreviews: videoPreviews ?? this.videoPreviews,
      );

  String toJson() => jsonEncode({
        "enabled": enabled,
        "photos": photos,
        "gifs": gifs,
        "video_previews": videoPreviews,
      });

  /// Unknown or broken values fall back to everything on (Commet's
  /// behaviour before this setting existed).
  static AutoDownloadPolicy fromJson(String? json) {
    if (json == null || json.isEmpty) return const AutoDownloadPolicy();
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      bool flag(String key) => map[key] is bool ? map[key] as bool : true;
      return AutoDownloadPolicy(
        enabled: flag("enabled"),
        photos: flag("photos"),
        gifs: flag("gifs"),
        videoPreviews: flag("video_previews"),
      );
    } catch (_) {
      return const AutoDownloadPolicy();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadPolicy &&
      other.enabled == enabled &&
      other.photos == photos &&
      other.gifs == gifs &&
      other.videoPreviews == videoPreviews;

  @override
  int get hashCode => Object.hash(enabled, photos, gifs, videoPreviews);
}

/// Vommet: holds back event media (pictures, GIFs, stickers, video preview
/// pictures) the current network's [AutoDownloadPolicy] doesn't allow, until
/// it is tapped, opened in the viewer, or the network or policy changes.
/// Avatars, emoji, banners and anything already cached never wait.
class MediaAutoDownload {
  static MediaNetwork _network = MediaNetwork.wifi;
  static MediaNetwork get network => _network;

  static final Set<String> _revealed = {};
  static final Map<String, (AutoMediaKind, Completer<void>)> _waiting = {};

  /// Keys of media currently held back, for the tap-to-load overlay.
  static final ValueNotifier<Set<String>> held = ValueNotifier({});

  static StreamSubscription? _connectivity;
  static bool _started = false;

  /// The kind of an event's media, or null when it always loads.
  static AutoMediaKind? kindOf(
      {required String eventType, String? msgtype, String? mimetype}) {
    if (eventType == "m.sticker") return AutoMediaKind.gif;
    if (eventType != "m.room.message") return null;
    if (msgtype == "m.image") {
      return mimetype == "image/gif" ? AutoMediaKind.gif : AutoMediaKind.photo;
    }
    if (msgtype == "m.video") return AutoMediaKind.videoPreview;
    return null;
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
      AutoDownloadPolicy.fromJson(switch (network) {
        MediaNetwork.wifi => preferences.autoDownloadWifi.value,
        MediaNetwork.mobile => preferences.autoDownloadMobile.value,
      });

  static Future<void> setPolicy(
      MediaNetwork network, AutoDownloadPolicy policy) async {
    switch (network) {
      case MediaNetwork.wifi:
        await preferences.autoDownloadWifi.set(policy.toJson());
      case MediaNetwork.mobile:
        await preferences.autoDownloadMobile.set(policy.toJson());
    }
    _releaseAllowed();
  }

  /// Whether connection type matters here (phones only).
  static bool get tracksNetwork => BuildConfig.MOBILE || _forceTracking;
  static bool _forceTracking = false;

  static void _start() {
    if (_started) return;
    _started = true;
    if (!tracksNetwork) return;
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

  static void _onConnectivity(List<ConnectivityResult> results) {
    _network = networkFrom(results);
    _releaseAllowed();
  }

  /// Waits until media [key] of [kind] may download. Returns at once when
  /// the current policy allows it or it was revealed.
  static Future<void> waitUntilAllowed(String key, AutoMediaKind kind) {
    // Desktops and web always count as Wi-Fi and have no settings for it.
    if (!tracksNetwork) return Future.value();
    _start();
    if (_revealed.contains(key) || policyFor(_network).allows(kind)) {
      return Future.value();
    }
    final existing = _waiting[key];
    if (existing != null) return existing.$2.future;

    final completer = Completer<void>();
    _waiting[key] = (kind, completer);
    held.value = {...held.value, key};
    return completer.future;
  }

  /// Lets media [key] download now (a tap, or opening it in the viewer).
  static void reveal(String key) {
    _revealed.add(key);
    _release(key);
  }

  static void _release(String key) {
    final waiting = _waiting.remove(key);
    if (waiting == null) return;
    waiting.$2.complete();
    held.value = {...held.value}..remove(key);
  }

  static void _releaseAllowed() {
    final policy = policyFor(_network);
    for (final entry in _waiting.entries.toList()) {
      if (policy.allows(entry.value.$1)) _release(entry.key);
    }
  }

  /// Unit tests only: a fresh state with network tracking on.
  static void resetForTest({MediaNetwork network = MediaNetwork.wifi}) {
    _connectivity?.cancel();
    _connectivity = null;
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
