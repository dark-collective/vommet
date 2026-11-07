// Vommet issue 1065: a media_kit Player stand-in that behaves like the real
// one around open(). media_kit 1.2.6 NativePlayer.open
// (lib/src/player/native/player/real.dart ~140-235) sends mpv `loadfile`
// and returns at once; whether the file loads only shows on the player's
// streams afterwards: a duration (and for video a size, buffered data) once
// it has loaded, a message on `error` when mpv fails, nothing at all while
// mpv's own fetch hangs.
// unit_test/ isn't a recognised test directory for the analyzer.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:media_kit/media_kit.dart';

import 'telemetry_v45_test.dart' show FakePlayer;

class LoadingFakePlayer extends FakePlayer {
  final volumeC = StreamController<double>.broadcast();
  final bufferingC = StreamController<bool>.broadcast();
  final bufferC = StreamController<Duration>.broadcast();
  final widthC = StreamController<int?>.broadcast();
  final errorC = StreamController<String>.broadcast();

  /// What mpv reports after open(): null loads the file (a duration), a
  /// string is an mpv error. [openHangs]: mpv never loads it and reports
  /// nothing (open() still returns, as the real one does).
  String? loadError;

  /// mpv's error was non-fatal: the file loads 200 ms after it.
  bool loadsAfterError = false;

  bool disposed = false;

  @override
  late final PlayerStream stream = PlayerStream(
    const Stream.empty(),
    playingC.stream,
    completedC.stream,
    positionC.stream,
    durationC.stream,
    volumeC.stream,
    const Stream.empty(),
    const Stream.empty(),
    bufferingC.stream,
    const Stream.empty(),
    bufferC.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    widthC.stream,
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    errorC.stream,
  );

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (openError != null) throw openError!;
    if (openHangs) return;
    final error = loadError;
    Timer(const Duration(milliseconds: 300), () {
      if (disposed) return;
      if (error != null) {
        errorC.add(error);
        if (loadsAfterError) {
          Timer(const Duration(milliseconds: 200), () {
            if (!disposed) durationC.add(const Duration(milliseconds: 2300));
          });
        }
      } else {
        durationC.add(const Duration(milliseconds: 2300));
      }
    });
  }

  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => disposed = true;
}
