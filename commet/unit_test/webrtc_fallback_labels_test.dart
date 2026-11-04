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

  group('saved device', () {
    final devices = [
      device("audioinput", "USB Mic", "usb"),
      device("audioinput", "Headset", "headset"),
      device("audioinput", "Headset", "headset-2"),
    ];

    test('nothing saved picks nothing', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
              label: null, id: "usb", byId: true),
          isNull);
    });

    test('a renamed device is found again by its id', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
                  label: "Microphone 1", id: "usb", byId: true)
              ?.deviceId,
          "usb");
    });

    test('the id tells two devices with the same name apart', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
                  label: "Headset", id: "headset-2", byId: true)
              ?.deviceId,
          "headset-2");
    });

    test('a newly picked name wins over an old id', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
                  label: "Headset", id: "usb", byId: true)
              ?.deviceId,
          "headset");
    });

    test('a device that is gone falls back to the default', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
              label: "Old Mic", id: "old", byId: true),
          isNull);
    });

    test('native builds match by name only, as before', () {
      expect(
          WebrtcDefaultDevices.findSaved(devices,
              label: "Microphone 1", id: "usb", byId: false),
          isNull);
      expect(
          WebrtcDefaultDevices.findSaved(devices,
                  label: "Headset", id: "headset-2", byId: false)
              ?.deviceId,
          "headset");
    });
  });
}
