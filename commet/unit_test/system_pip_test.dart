import 'package:commet/ui/molecules/video_player/system_pip.dart';
import 'package:commet/ui/molecules/video_player/video_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// Vommet issue 1081: only a playing video in the viewer goes to the
// system's picture in picture.

SystemPipCandidate _candidate({bool playing = false}) {
  final controller = VideoPlayerController();
  controller.setPlaying(playing);
  return SystemPipCandidate(controller);
}

void main() {
  test('a paused video never goes to the system window', () {
    expect(SystemPip.pick([_candidate(), _candidate()]), isNull);
    expect(SystemPip.pick([]), isNull);
  });

  test('the newest playing video goes', () {
    final older = _candidate(playing: true);
    final paused = _candidate();
    final newer = _candidate(playing: true);
    expect(SystemPip.pick([older, paused]), same(older));
    expect(SystemPip.pick([older, paused, newer]), same(newer));
  });

  test('a player that is disposed stops counting as playing', () {
    final candidate = _candidate(playing: true);
    final owner = Object();
    candidate.controller.attach(
        pause: () async {},
        play: () async {},
        replay: () async {},
        getLength: () async => Duration.zero,
        getSize: () async => null,
        getVolume: () async => 1,
        seekTo: (_) async {},
        setVolume: (_) async {},
        owner: owner);
    candidate.controller.detach(owner);
    expect(SystemPip.pick([candidate]), isNull);
  });

  test('aspect ratios stay inside what Android takes', () {
    expect(SystemPip.aspectRatioFor(null), 16 / 9);
    expect(SystemPip.aspectRatioFor(0), 16 / 9);
    expect(SystemPip.aspectRatioFor(double.nan), 16 / 9);
    expect(SystemPip.aspectRatioFor(1.5), 1.5);
    expect(SystemPip.aspectRatioFor(5), lessThan(2.39));
    expect(SystemPip.aspectRatioFor(0.1), greaterThan(1 / 2.39));
  });
}
