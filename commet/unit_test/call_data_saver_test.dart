// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:commet/config/preferences/preference.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:commet/utils/media_auto_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Vommet issue 776: "Use less data for calls".
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Preference.preferences = await SharedPreferences.getInstance();
    MediaAutoDownload.resetForTest(network: MediaNetwork.wifi);
    CallDataSaver.updateForTest();
  });

  test('which networks each choice saves data on', () {
    const wifi = MediaNetwork.wifi;
    const mobile = MediaNetwork.mobile;
    const roaming = MediaNetwork.roaming;
    expect(CallDataSaverMode.never.appliesOn(roaming), isFalse);
    expect(CallDataSaverMode.roaming.appliesOn(roaming), isTrue);
    expect(CallDataSaverMode.roaming.appliesOn(mobile), isFalse);
    expect(CallDataSaverMode.mobile.appliesOn(mobile), isTrue);
    expect(CallDataSaverMode.mobile.appliesOn(roaming), isTrue);
    expect(CallDataSaverMode.mobile.appliesOn(wifi), isFalse);
    expect(CallDataSaverMode.always.appliesOn(wifi), isTrue);
  });

  test('defaults to mobile data and roaming; unknown values too', () {
    expect(CallDataSaver.currentMode, CallDataSaverMode.mobile);
    expect(CallDataSaverMode.fromName("nope"), CallDataSaverMode.mobile);
  });

  test('follows the network and the setting', () async {
    expect(CallDataSaver.isActive, isFalse);
    MediaAutoDownload.setNetworkForTest(MediaNetwork.mobile);
    expect(CallDataSaver.isActive, isTrue);
    await CallDataSaver.mode.set(CallDataSaverMode.roaming.name);
    CallDataSaver.updateForTest();
    expect(CallDataSaver.isActive, isFalse);
    MediaAutoDownload.setNetworkForTest(MediaNetwork.roaming);
    expect(CallDataSaver.isActive, isTrue);
  });

  test('caps only while in effect', () {
    expect(CallDataSaver.cameraCaptureOptions(), isNull);
    expect(
        CallDataSaver.receiveQuality(screenShare: false), lk.VideoQuality.HIGH);
    final full = CallDataSaver.screenShare(
        width: 1920, height: 1080, framerate: 60, bitrate: 8000000);
    expect(
        full, (width: 1920, height: 1080, framerate: 60.0, bitrate: 8000000));

    MediaAutoDownload.setNetworkForTest(MediaNetwork.mobile);
    expect(CallDataSaver.voiceBitrateNow, 32000);
    final camera = CallDataSaver.cameraCaptureOptions()!;
    expect(camera.params.dimensions.height, 360);
    expect(camera.maxFrameRate, 15);
    expect(
        CallDataSaver.receiveQuality(screenShare: false), lk.VideoQuality.LOW);
    expect(CallDataSaver.receiveQuality(screenShare: true),
        lk.VideoQuality.MEDIUM);
    final saved = CallDataSaver.screenShare(
        width: 1920, height: 1080, framerate: 60, bitrate: 8000000);
    expect(
        saved, (width: 1280, height: 720, framerate: 15.0, bitrate: 1000000));
    // Settings already below the caps stay.
    final low = CallDataSaver.screenShare(
        width: 854, height: 480, framerate: 10, bitrate: 500000);
    expect(low, (width: 854, height: 480, framerate: 10.0, bitrate: 500000));
  });

  test('1:1 calls ask for a smaller camera, nothing else changes', () {
    final constraints = {
      "audio": true,
      "video": {"width": 1280, "height": 720, "facingMode": "user"},
    };
    expect(CallDataSaver.userMediaConstraints(constraints), constraints);
    MediaAutoDownload.setNetworkForTest(MediaNetwork.roaming);
    expect(CallDataSaver.userMediaConstraints(constraints), {
      "audio": true,
      "video": {
        "width": 640,
        "height": 360,
        "frameRate": 15,
        "facingMode": "user"
      },
    });
    expect(CallDataSaver.userMediaConstraints({"audio": true, "video": false}),
        {"audio": true, "video": false});
  });
}
