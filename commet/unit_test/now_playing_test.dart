// Vommet: now-playing media controls. Reading a player's MPRIS properties,
// picking which player to show, and counting the position on while a track
// plays.
import 'package:commet/utils/now_playing/now_playing.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

DBusVariant _v(DBusValue value) => DBusVariant(value);

Map<String, DBusValue> _player({
  String status = "Playing",
  String? title = "Song",
  DBusValue? artist,
  int? lengthUs = 200000000,
  int? positionUs = 30000000,
  bool canNext = true,
}) =>
    {
      "PlaybackStatus": _v(DBusString(status)),
      "Metadata": _v(DBusDict.stringVariant({
        if (title != null) "xesam:title": DBusString(title),
        "xesam:artist": artist ?? DBusArray.string(["Band", "Guest"]),
        if (lengthUs != null) "mpris:length": DBusInt64(lengthUs),
        "mpris:artUrl": DBusString("file:///home/u/.cache/cover.png"),
        "mpris:trackid": DBusObjectPath("/org/mpris/track/1"),
      })),
      if (positionUs != null) "Position": _v(DBusInt64(positionUs)),
      "Rate": _v(const DBusDouble(1)),
      "CanPlay": _v(const DBusBoolean(true)),
      "CanPause": _v(const DBusBoolean(true)),
      "CanGoNext": _v(DBusBoolean(canNext)),
      "CanGoPrevious": _v(const DBusBoolean(false)),
      "CanControl": _v(const DBusBoolean(true)),
    };

final _root = <String, DBusValue>{
  "Identity": _v(DBusString("Spotify")),
  "CanRaise": _v(const DBusBoolean(true)),
};

void main() {
  final t0 = DateTime(2026, 10, 26, 12);

  test("reads a player's track and controls", () {
    final p = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.spotify",
        root: _root, player: _player(), now: t0);
    expect(p.app, "Spotify");
    expect(p.title, "Song");
    expect(p.artist, "Band, Guest");
    expect(p.art, Uri.parse("file:///home/u/.cache/cover.png"));
    expect(p.length, const Duration(seconds: 200));
    expect(p.position, const Duration(seconds: 30));
    expect(p.playing, isTrue);
    expect(p.hasTrack, isTrue);
    expect(p.canPlayPause, isTrue);
    expect(p.canNext, isTrue);
    expect(p.canPrevious, isFalse);
    expect(p.canRaise, isTrue);
  });

  test("a single artist string, uint64 length, no Identity", () {
    final p = NowPlayingPlayer.fromProperties(
        "org.mpris.MediaPlayer2.vlc.instance1234",
        root: const {},
        player: {
          ..._player(artist: DBusString("Solo")),
          "Metadata": _v(DBusDict.stringVariant({
            "xesam:title": DBusString("Film"),
            "xesam:artist": DBusString("Solo"),
            "mpris:length": DBusUint64(5000000),
          })),
        },
        now: t0);
    expect(p.app, "Vlc");
    expect(p.artist, "Solo");
    expect(p.length, const Duration(seconds: 5));
    expect(p.art, isNull);
  });

  test("stopped or untitled players have nothing to show", () {
    expect(
        NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
                root: _root, player: _player(status: "Stopped"), now: t0)
            .hasTrack,
        isFalse);
    expect(
        NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
                root: _root, player: _player(title: null), now: t0)
            .hasTrack,
        isFalse);
    expect(
        NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
                root: _root, player: _player(status: "Paused"), now: t0)
            .hasTrack,
        isTrue,
        reason: "a paused track can be resumed");
  });

  test("CanControl false hides every button", () {
    final p = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root,
        player: {..._player(), "CanControl": _v(const DBusBoolean(false))},
        now: t0);
    expect(p.canPlayPause || p.canNext || p.canPrevious, isFalse);
  });

  test("the position counts on while playing, up to the length", () {
    final p = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root, player: _player(), now: t0);
    expect(p.positionAtTime(t0.add(const Duration(seconds: 10))),
        const Duration(seconds: 40));
    expect(p.positionAtTime(t0.add(const Duration(hours: 1))),
        const Duration(seconds: 200));
    final paused = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root, player: _player(status: "Paused"), now: t0);
    expect(paused.positionAtTime(t0.add(const Duration(seconds: 10))),
        const Duration(seconds: 30));
  });

  test("a change without a position keeps counting from the last one", () {
    final first = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root, player: _player(), now: t0);
    final later = t0.add(const Duration(seconds: 5));
    final same = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root,
        player: _player(positionUs: null, canNext: false),
        now: later,
        previous: first);
    expect(same.position, const Duration(seconds: 35));
    expect(same.changedAt, t0, reason: "same track, same status");
    final next = NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.a",
        root: _root,
        player: _player(title: "Next song", positionUs: null),
        now: later,
        previous: first);
    expect(next.position, Duration.zero);
    expect(next.changedAt, later);
  });

  test("picks the chosen player, else the latest playing, else paused", () {
    NowPlayingPlayer make(String name, String status, int minute) =>
        NowPlayingPlayer.fromProperties("org.mpris.MediaPlayer2.$name",
            root: _root,
            player: _player(status: status),
            now: t0.add(Duration(minutes: minute)));
    final pausedNew = make("paused", "Paused", 9);
    final playingOld = make("old", "Playing", 1);
    final playingNew = make("new", "Playing", 5);
    final stopped = make("stopped", "Stopped", 10);
    final all = [pausedNew, playingOld, playingNew, stopped];

    expect(NowPlayingPlayer.pick(all, null), playingNew);
    expect(NowPlayingPlayer.pick(all, pausedNew.busName), pausedNew);
    expect(NowPlayingPlayer.pick(all, stopped.busName), playingNew,
        reason: "a chosen player with nothing loaded isn't shown");
    expect(NowPlayingPlayer.pick([pausedNew, stopped], null), pausedNew);
    expect(NowPlayingPlayer.pick([stopped], null), isNull);
    expect(NowPlayingPlayer.pick(const [], null), isNull);
  });
}
