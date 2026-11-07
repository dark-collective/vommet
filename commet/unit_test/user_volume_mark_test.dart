// Vommet issue 1078: which mark a saved call volume gets.
import 'package:commet/ui/atoms/user_volume_mark.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('100% shows nothing', () {
    expect(UserVolumeMark.stateFor(1.0), VolumeMarkState.none);
    expect(UserVolumeMark.stateFor(1.004), VolumeMarkState.none);
    expect(UserVolumeMark.stateFor(0.996), VolumeMarkState.none);
    // The icon follows the shown percentage.
    expect(UserVolumeMark.stateFor(0.9951), VolumeMarkState.none);
  });

  test('louder, quieter and muted', () {
    expect(UserVolumeMark.stateFor(1.5), VolumeMarkState.louder);
    expect(UserVolumeMark.stateFor(0.4), VolumeMarkState.quieter);
    expect(UserVolumeMark.stateFor(0.0), VolumeMarkState.muted);
    expect(UserVolumeMark.stateFor(0.004), VolumeMarkState.muted);
  });

  test('percent text and display setting', () {
    expect(UserVolumeMark.percentOf(1.5), 150);
    expect(UserVolumeMark.percentOf(0.404), 40);
    expect(VolumeMarkStyle.parse("both"), VolumeMarkStyle.both);
    expect(VolumeMarkStyle.parse("bogus"), VolumeMarkStyle.icon);
  });
}
