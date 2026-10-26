// Vommet: now-playing media controls (premium-free feature batch). On Linux,
// what a music or video app is playing, read over MPRIS (D-Bus), with
// play/pause, previous and next. Shown above your name in the bottom-left
// corner (ui/molecules/now_playing_card.dart). Nothing leaves the device.
import 'dart:async';
import 'dart:io';

import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/bool_preference.dart';
import 'package:commet/debug/log.dart';
import 'package:dbus/dbus.dart';

final BoolPreference experimentNowPlaying =
    BoolPreference("vommet_experiment_now_playing", defaultValue: false);

enum NowPlayingStatus {
  playing,
  paused,
  stopped;

  static NowPlayingStatus parse(String? value) => switch (value) {
        "Playing" => playing,
        "Paused" => paused,
        _ => stopped,
      };
}

/// One media player and what it has loaded.
class NowPlayingPlayer {
  const NowPlayingPlayer({
    required this.busName,
    required this.app,
    this.title,
    this.artists = const [],
    this.art,
    this.length,
    this.position = Duration.zero,
    required this.positionAt,
    this.rate = 1,
    this.status = NowPlayingStatus.stopped,
    this.canPlayPause = false,
    this.canNext = false,
    this.canPrevious = false,
    this.canRaise = false,
    required this.changedAt,
  });

  /// `org.mpris.MediaPlayer2.<name>`.
  final String busName;

  /// The player's name, as it gives it ("Spotify", "Firefox").
  final String app;
  final String? title;
  final List<String> artists;

  /// The cover: a file: or http(s): address.
  final Uri? art;
  final Duration? length;

  /// Where the track was at [positionAt].
  final Duration position;
  final DateTime positionAt;
  final double rate;
  final NowPlayingStatus status;
  final bool canPlayPause;
  final bool canNext;
  final bool canPrevious;
  final bool canRaise;

  /// When the player last changed track or started or stopped playing.
  final DateTime changedAt;

  bool get playing => status == NowPlayingStatus.playing;

  /// Whether there is something to show: a titled track, playing or paused.
  bool get hasTrack =>
      status != NowPlayingStatus.stopped && (title?.isNotEmpty ?? false);

  String get artist => artists.join(", ");

  /// Where the track is at [now], counting on from the last reading while
  /// it plays.
  Duration positionAtTime(DateTime now) {
    var p = position;
    if (playing) {
      p += now.difference(positionAt) * rate;
    }
    if (p.isNegative) return Duration.zero;
    final l = length;
    if (l != null && p > l) return l;
    return p;
  }

  /// The player from its MPRIS properties: [root] on
  /// `org.mpris.MediaPlayer2`, [player] on `org.mpris.MediaPlayer2.Player`.
  /// [previous] keeps [changedAt] when neither the track nor the status
  /// changed.
  static NowPlayingPlayer fromProperties(
    String busName, {
    required Map<String, DBusValue> root,
    required Map<String, DBusValue> player,
    required DateTime now,
    NowPlayingPlayer? previous,
  }) {
    final metadata = _dict(player["Metadata"]);
    final status = NowPlayingStatus.parse(_string(player["PlaybackStatus"]));
    final title = _string(metadata["xesam:title"]);
    final artUrl = _string(metadata["mpris:artUrl"]);
    final lengthUs = _int(metadata["mpris:length"]);
    final positionUs = _int(player["Position"]);
    final controllable = _bool(player["CanControl"]) ?? true;
    final changed = previous == null ||
        previous.title != title ||
        previous.status != status;
    return NowPlayingPlayer(
      busName: busName,
      app: _string(root["Identity"]) ?? _appFromBusName(busName),
      title: title,
      artists: _strings(metadata["xesam:artist"]),
      art: artUrl == null ? null : _artUri(artUrl),
      length: lengthUs == null || lengthUs <= 0
          ? null
          : Duration(microseconds: lengthUs),
      position: positionUs == null
          ? (changed ? Duration.zero : previous.positionAtTime(now))
          : Duration(microseconds: positionUs),
      positionAt: now,
      rate: _double(player["Rate"]) ?? 1,
      status: status,
      canPlayPause: controllable &&
          ((_bool(player["CanPause"]) ?? false) ||
              (_bool(player["CanPlay"]) ?? false)),
      canNext: controllable && (_bool(player["CanGoNext"]) ?? false),
      canPrevious: controllable && (_bool(player["CanGoPrevious"]) ?? false),
      canRaise: _bool(root["CanRaise"]) ?? false,
      changedAt: changed ? now : previous.changedAt,
    );
  }

  /// The player to show: the one picked with the dots while it has a track,
  /// else the one that most recently started playing, else the most
  /// recently changed paused one.
  static NowPlayingPlayer? pick(
      Iterable<NowPlayingPlayer> players, String? chosen) {
    final shown = players.where((p) => p.hasTrack).toList();
    if (shown.isEmpty) return null;
    final picked = shown.where((p) => p.busName == chosen).firstOrNull;
    if (picked != null) return picked;
    shown.sort((a, b) {
      if (a.playing != b.playing) return a.playing ? -1 : 1;
      return b.changedAt.compareTo(a.changedAt);
    });
    return shown.first;
  }

  static String _appFromBusName(String busName) {
    var name = busName.substring(NowPlaying.busPrefix.length);
    // Players that run more than once add ".instance<pid>".
    final dot = name.indexOf(".");
    if (dot > 0) name = name.substring(0, dot);
    if (name.isEmpty) return busName;
    return name[0].toUpperCase() + name.substring(1);
  }

  static Uri? _artUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    return switch (uri.scheme) {
      "file" || "http" || "https" => uri,
      _ => null,
    };
  }

  static DBusValue? _unwrap(DBusValue? value) {
    var v = value;
    while (v is DBusVariant) {
      v = v.value;
    }
    return v;
  }

  static String? _string(DBusValue? value) => switch (_unwrap(value)) {
        // Object paths (mpris:trackid) are strings too.
        DBusString s => s.value,
        _ => null,
      };

  static bool? _bool(DBusValue? value) => switch (_unwrap(value)) {
        DBusBoolean b => b.value,
        _ => null,
      };

  static double? _double(DBusValue? value) => switch (_unwrap(value)) {
        DBusDouble d => d.value,
        _ => null,
      };

  static int? _int(DBusValue? value) => switch (_unwrap(value)) {
        DBusInt64 i => i.value,
        DBusUint64 i => i.value,
        DBusInt32 i => i.value,
        DBusUint32 i => i.value,
        DBusDouble d => d.value.round(),
        _ => null,
      };

  static List<String> _strings(DBusValue? value) {
    final v = _unwrap(value);
    if (v is DBusString) return v.value.isEmpty ? const [] : [v.value];
    if (v is DBusArray) {
      return [
        for (final c in v.children)
          if (_string(c) case final s? when s.isNotEmpty) s
      ];
    }
    return const [];
  }

  static Map<String, DBusValue> _dict(DBusValue? value) {
    final v = _unwrap(value);
    if (v is! DBusDict) return const {};
    return {
      for (final e in v.children.entries)
        if (e.key is DBusString) (e.key as DBusString).value: e.value
    };
  }
}

/// The media players on the session bus. Runs while the experiment is on.
class NowPlaying {
  NowPlaying._();

  static final NowPlaying instance = NowPlaying._();

  static const busPrefix = "org.mpris.MediaPlayer2.";
  static const _rootInterface = "org.mpris.MediaPlayer2";
  static const _playerInterface = "org.mpris.MediaPlayer2.Player";
  static final _path = DBusObjectPath("/org/mpris/MediaPlayer2");

  /// Whether the controls can show here: Linux, outside the browser.
  static bool get available => PlatformUtils.isLinux && !PlatformUtils.isWeb;

  static bool get enabled => available && experimentNowPlaying.value;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get onChanged => _changes.stream;

  DBusClient? _client;
  final _players = <String, _Player>{};
  final _subs = <StreamSubscription>[];
  Timer? _resync;
  String? _chosen;
  bool _started = false;

  /// Players with a track, in a fixed order (for the dots).
  List<NowPlayingPlayer> get players {
    final list = [
      for (final p in _players.values)
        if (p.state?.hasTrack ?? false) p.state!
    ];
    list.sort((a, b) => a.busName.compareTo(b.busName));
    return list;
  }

  NowPlayingPlayer? get current => NowPlayingPlayer.pick(
      _players.values.map((p) => p.state).nonNulls, _chosen);

  /// Shows [busName]'s player until it has nothing to show.
  void choose(String busName) {
    _chosen = busName;
    _changes.add(null);
  }

  /// Starts watching, if the experiment is on; stops when it goes off.
  void start() {
    if (_started || !available) return;
    _started = true;
    experimentNowPlaying.onChanged.listen((_) => _update());
    _update();
  }

  void _update() {
    if (experimentNowPlaying.value) {
      if (_client == null) unawaited(_watch());
    } else {
      unawaited(_stop());
    }
  }

  Future<void> _watch() async {
    try {
      final client = _client = DBusClient.session();
      _subs.add(client.nameOwnerChanged
          .where((e) => e.name.startsWith(busPrefix))
          .listen((e) {
        _remove(e.name);
        if (e.newOwner?.isNotEmpty ?? false) unawaited(_add(e.name));
      }));
      for (final name in await client.listNames()) {
        if (name.startsWith(busPrefix)) await _add(name);
      }
      // Players that don't say when they seek: read where they are now and
      // then.
      _resync = Timer.periodic(
          const Duration(seconds: 10), (_) => unawaited(_resyncPlaying()));
    } catch (e) {
      Log.w("Now playing: could not watch media players: $e");
    }
  }

  Future<void> _stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final name in _players.keys.toList()) {
      _remove(name);
    }
    _resync?.cancel();
    _resync = null;
    final client = _client;
    _client = null;
    await client?.close();
    _changes.add(null);
  }

  Future<void> _add(String name) async {
    final client = _client;
    if (client == null || _players.containsKey(name)) return;
    try {
      // Vommet's own videos and calls aren't "now playing".
      if (await client.getConnectionUnixProcessId(name) == pid) return;
    } catch (_) {}
    final object = DBusRemoteObject(client, name: name, path: _path);
    final player = _players[name] = _Player(object);
    try {
      player.root = await object.getAllProperties(_rootInterface);
      player.props = await object.getAllProperties(_playerInterface);
    } catch (e) {
      Log.w("Now playing: could not read $name: $e");
      _remove(name);
      return;
    }
    if (_players[name] != player) return;
    player.subs.add(object.propertiesChanged.listen((signal) {
      if (signal.propertiesInterface == _rootInterface) {
        player.root = {...player.root, ...signal.changedProperties};
        _refresh(name);
      } else if (signal.propertiesInterface == _playerInterface) {
        final changed = signal.changedProperties;
        player.props = {...player.props, ...changed}..remove("Position");
        _refresh(name);
        // The position isn't sent on changes; read it when the track or
        // status changes, or when the player doesn't send values.
        if (changed.containsKey("Metadata") ||
            changed.containsKey("PlaybackStatus") ||
            signal.invalidatedProperties.isNotEmpty) {
          unawaited(_reread(name));
        }
      }
    }));
    player.subs.add(DBusSignalStream(client,
            sender: name,
            interface: _playerInterface,
            name: "Seeked",
            path: _path,
            signature: DBusSignature("x"))
        .listen((signal) {
      player.props = {...player.props, "Position": signal.values.first};
      _refresh(name);
      player.props.remove("Position");
    }));
    _refresh(name);
    player.props.remove("Position");
  }

  void _remove(String name) {
    final player = _players.remove(name);
    if (player == null) return;
    for (final sub in player.subs) {
      sub.cancel();
    }
    _changes.add(null);
  }

  void _refresh(String name) {
    final player = _players[name];
    if (player == null) return;
    player.state = NowPlayingPlayer.fromProperties(name,
        root: player.root,
        player: player.props,
        now: DateTime.now(),
        previous: player.state);
    _changes.add(null);
  }

  Future<void> _reread(String name) async {
    final player = _players[name];
    if (player == null) return;
    try {
      player.props = await player.object.getAllProperties(_playerInterface);
    } catch (_) {
      return;
    }
    if (_players[name] != player) return;
    _refresh(name);
    player.props.remove("Position");
  }

  Future<void> _resyncPlaying() async {
    final shown = current;
    if (shown == null || !shown.playing) return;
    await _reread(shown.busName);
  }

  Future<void> playPause(String busName) => _call(busName, "PlayPause");
  Future<void> next(String busName) => _call(busName, "Next");
  Future<void> previous(String busName) => _call(busName, "Previous");

  /// Brings the player's window to the front.
  Future<void> raise(String busName) =>
      _call(busName, "Raise", interface: _rootInterface);

  Future<void> _call(String busName, String method,
      {String interface = _playerInterface}) async {
    final player = _players[busName];
    if (player == null) return;
    try {
      await player.object.callMethod(interface, method, const [],
          replySignature: DBusSignature.empty);
    } catch (e) {
      Log.w("Now playing: $method on $busName failed: $e");
    }
  }
}

class _Player {
  _Player(this.object);

  final DBusRemoteObject object;
  final subs = <StreamSubscription>[];
  Map<String, DBusValue> root = const {};
  Map<String, DBusValue> props = const {};
  NowPlayingPlayer? state;
}
