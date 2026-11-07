import 'package:commet/config/platform_utils.dart';
import 'package:commet/config/preferences/string_preference.dart';
import 'package:commet/utils/call_data_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Vommet issue 1075: the front or back camera in calls on Android and iOS.
/// The last choice is kept, and every camera start in a call uses it.
class CallCameraPosition {
  static final StringPreference saved = StringPreference(
      "vommet_call_camera_position",
      defaultValue: lk.CameraPosition.front.name);

  @visibleForTesting
  static bool? supportedForTest;

  /// Phones and tablets have a front and a back camera to switch between.
  static bool get supported =>
      supportedForTest ?? (PlatformUtils.isAndroid || PlatformUtils.isIOS);

  /// The camera to start with; always the front one where switching isn't
  /// offered.
  static lk.CameraPosition get current =>
      supported && saved.value == lk.CameraPosition.back.name
          ? lk.CameraPosition.back
          : lk.CameraPosition.front;

  static Future<void> set(lk.CameraPosition position) =>
      saved.set(position.name);

  /// LiveKit calls: the camera's capture options, "Use less data for
  /// calls" or else the room's [defaults], with the saved camera.
  static lk.CameraCaptureOptions captureOptions(
          lk.CameraCaptureOptions defaults) =>
      (CallDataSaver.cameraCaptureOptions() ?? defaults)
          .copyWith(cameraPosition: current);

  /// Classic 1:1 calls: asks getUserMedia for the saved camera.
  static Map<String, dynamic> userMediaConstraints(
      Map<String, dynamic> constraints) {
    final video = constraints["video"];
    if (!supported || video is! Map || video["deviceId"] != null) {
      return constraints;
    }
    return {
      ...constraints,
      "video": {
        ...video,
        "facingMode":
            current == lk.CameraPosition.back ? "environment" : "user",
      },
    };
  }
}
