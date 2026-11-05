// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/utils/call_camera_position.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Vommet issue 1075: the front or back camera, remembered between calls.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    MediaAutoDownload.resetForTest(network: MediaNetwork.wifi);
    await CallDataSaver.mode.set(CallDataSaverMode.never.name);
    CallDataSaver.updateForTest();
    CallCameraPosition.supportedForTest = true;
  });

  tearDown(() => CallCameraPosition.supportedForTest = null);

  test('starts with the front camera and remembers the back one', () async {
    expect(CallCameraPosition.current, lk.CameraPosition.front);
    await CallCameraPosition.set(lk.CameraPosition.back);
    expect(CallCameraPosition.current, lk.CameraPosition.back);
    expect(Preference.preferences!.getString("vommet_call_camera_position"),
        "back");
  });

  test('always the front camera where switching is not offered', () async {
    await CallCameraPosition.set(lk.CameraPosition.back);
    CallCameraPosition.supportedForTest = false;
    expect(CallCameraPosition.current, lk.CameraPosition.front);
  });

  test('capture options keep the room defaults and add the camera', () async {
    await CallCameraPosition.set(lk.CameraPosition.back);
    final options = CallCameraPosition.captureOptions(
        const lk.CameraCaptureOptions(maxFrameRate: 24));
    expect(options.cameraPosition, lk.CameraPosition.back);
    expect(options.maxFrameRate, 24);
  });

  test('capture options use less data while that is on', () async {
    await CallDataSaver.mode.set(CallDataSaverMode.always.name);
    CallDataSaver.updateForTest();
    await CallCameraPosition.set(lk.CameraPosition.back);
    final options = CallCameraPosition.captureOptions(
        const lk.CameraCaptureOptions(maxFrameRate: 24));
    expect(options.cameraPosition, lk.CameraPosition.back);
    expect(options.maxFrameRate, CallDataSaver.cameraFramerate);
  });

  test('1:1 calls ask getUserMedia for the saved camera', () async {
    final constraints = {
      "audio": true,
      "video": {"facingMode": "user", "optional": []},
    };
    expect(
        (CallCameraPosition.userMediaConstraints(constraints)["video"]
            as Map)["facingMode"],
        "user");
    await CallCameraPosition.set(lk.CameraPosition.back);
    final back = CallCameraPosition.userMediaConstraints(constraints);
    expect((back["video"] as Map)["facingMode"], "environment");
    expect((back["video"] as Map)["optional"], isEmpty);
    expect(back["audio"], isTrue);
    expect(CallCameraPosition.userMediaConstraints({"audio": true}),
        {"audio": true});
  });
}
