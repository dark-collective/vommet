import 'package:commet/client/components/voip/webrtc_default_devices.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

webrtc.MediaDeviceInfo device(String kind, String label, String id) =>
    webrtc.MediaDeviceInfo(kind: kind, label: label, deviceId: id);

void main() {
  test('unnamed devices are numbered per kind', () {
    final labelled = WebrtcDefaultDevices.withFallbackLabels([
      device("audioinput", "", "a"),
      device("audiooutput", "", "b"),
      device("audioinput", "", "c"),
      device("videoinput", "", "d"),
    ]);

    expect(labelled.map((d) => d.label),
        ["Microphone 1", "Speaker 1", "Microphone 2", "Camera 1"]);
    expect(labelled.map((d) => d.deviceId), ["a", "b", "c", "d"]);
    expect(labelled.map((d) => d.kind),
        ["audioinput", "audiooutput", "audioinput", "videoinput"]);
  });

  test('named devices keep their names', () {
    final labelled = WebrtcDefaultDevices.withFallbackLabels([
      device("audioinput", "USB Mic", "a"),
      device("audioinput", "", "b"),
    ]);

    expect(labelled.map((d) => d.label), ["USB Mic", "Microphone 1"]);
  });
}
