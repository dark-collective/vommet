import 'package:commet/client/components/voip/voip_session.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/debug/log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebrtcAndroidScreencaptureSource implements ScreenCaptureSource {
  static Future<ScreenCaptureSource?> getCaptureSource(
      BuildContext context) async {
    if (PlatformUtils.isAndroid) {
      // Vommet: entire screen only. In Android 14's "single app" mode the
      // system switches to the chosen app right after consent, so Vommet is
      // in the background when it starts the screen-capture foreground
      // service, which Android forbids, and sharing failed (10-07).
      final permission =
          await Helper.requestCapturePermission(fullScreenOnly: true);
      if (permission == false) {
        return null;
      }

      requestBackgroundPermission([bool isRetry = false]) async {
        // Required for android screenshare.
        try {
          bool hasPermissions = await FlutterBackground.hasPermissions;

          const androidConfig = FlutterBackgroundAndroidConfig(
            notificationTitle: 'Screen Sharing',
            notificationText: 'Vommet is sharing the screen.',
            notificationImportance: AndroidNotificationImportance.normal,
            notificationIcon:
                AndroidResource(name: 'notification_icon', defType: 'mipmap'),
          );

          if (!isRetry) {
            hasPermissions = await FlutterBackground.initialize(
                androidConfig: androidConfig);
          }
          if (hasPermissions &&
              !FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        } catch (e) {
          if (!isRetry) {
            return await Future<void>.delayed(const Duration(seconds: 1),
                () => requestBackgroundPermission(true));
          }
          // Vommet: a typed error, so diagnostics show what failed without
          // the message text.
          Log.onError(AndroidScreenShareServiceError(e), StackTrace.current,
              content: "Could not start the screen-sharing service");
        }
      }

      await requestBackgroundPermission();

      return WebrtcAndroidScreencaptureSource();
    }

    return null;
  }
}

/// Vommet: the screen-sharing foreground service could not be started.
class AndroidScreenShareServiceError implements Exception {
  final Object cause;
  AndroidScreenShareServiceError(this.cause);

  @override
  String toString() => "AndroidScreenShareServiceError: $cause";
}

/// Vommet: Android screen capture failed. The subclass names the reason, so
/// diagnostics (which keep only the error's type) can tell them apart.
class AndroidScreenCaptureError implements Exception {
  final Object cause;
  AndroidScreenCaptureError(this.cause);

  /// Picks the subclass from flutter_webrtc's / Android's message.
  static AndroidScreenCaptureError from(Object e) {
    final m = e.toString().toLowerCase();
    if (m.contains("permission to capture") || m.contains("notallowed")) {
      return AndroidScreenCapturePermissionError(e);
    }
    if (m.contains("foreground service") || m.contains("foregroundservice")) {
      return AndroidScreenCaptureForegroundServiceError(e);
    }
    if (m.contains("re-use") || m.contains("reuse")) {
      return AndroidScreenCaptureConsentReusedError(e);
    }
    if (m.contains("securityexception")) {
      return AndroidScreenCaptureSecurityError(e);
    }
    return AndroidScreenCaptureError(e);
  }

  @override
  String toString() => "$runtimeType: $cause";
}

class AndroidScreenCapturePermissionError extends AndroidScreenCaptureError {
  AndroidScreenCapturePermissionError(super.cause);
}

class AndroidScreenCaptureForegroundServiceError
    extends AndroidScreenCaptureError {
  AndroidScreenCaptureForegroundServiceError(super.cause);
}

class AndroidScreenCaptureConsentReusedError extends AndroidScreenCaptureError {
  AndroidScreenCaptureConsentReusedError(super.cause);
}

class AndroidScreenCaptureSecurityError extends AndroidScreenCaptureError {
  AndroidScreenCaptureSecurityError(super.cause);
}
