// Vommet issue 868: on Linux and Windows, libwebrtc's automatic gain control
// is AGC1 in analog mode, which never gets a microphone volume to steer there
// and made voices quieter and muffled. The voice filter runs AGC2 instead, so
// the microphone must be opened with libwebrtc's AGC off while the setting is
// on. The unit gate runs on Linux.
import 'package:commet/client/components/voip/voice_filter.dart';
import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final desktop = PlatformUtils.isLinux || PlatformUtils.isWindows;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await preferences.init();
  });

  test("with the setting on, the microphone opens with libwebrtc's AGC off",
      () async {
    await preferences.experimentAutoGainControl.set(true);
    expect(VoiceFilter.ownsAutoGainControl, isTrue);
    expect(WebrtcDefaultDevices.useAutoGainControl, isFalse);
    expect(WebrtcDefaultDevices.microphoneConstraints()['autoGainControl'],
        isFalse);
  }, skip: desktop ? false : "Linux and Windows only");

  test("with the setting off, libwebrtc's AGC stays off too", () async {
    await preferences.experimentAutoGainControl.set(false);
    expect(WebrtcDefaultDevices.microphoneConstraints()['autoGainControl'],
        isFalse);
  });

  test("automatic gain control alone puts the voice filter in the pipeline",
      () {
    expect(VoiceFilter.processorNeeded(0, 1.0, true), isTrue);
    expect(VoiceFilter.processorNeeded(0, 1.0, false), isFalse);
    expect(VoiceFilter.processorNeeded(1, 1.0, false), isTrue);
    expect(VoiceFilter.processorNeeded(0, 1.5, false), isTrue);
  });
}
