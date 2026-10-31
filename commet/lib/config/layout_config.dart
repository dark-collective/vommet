import 'package:commet/config/layout_size_rule.dart';
import 'package:commet/config/platform_utils.dart';
import 'package:commet/main.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Layout {
  static WebBrowserInfo? browserInfo;
  static bool? _isWebDesktopCache;

  /// Vommet issue 991: phones and tablets type on an on-screen keyboard that
  /// any text field taking the focus brings up. An iPad gets the desktop
  /// layout, so [LayoutQueryData.desktop] can't tell it from a computer.
  static bool get onScreenKeyboard =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static bool _isWebDesktop() {
    if (_isWebDesktopCache != null) {
      return _isWebDesktopCache!;
    }

    if (browserInfo == null) {
      return true;
    }

    var userAgent = browserInfo!.userAgent ?? "";
    userAgent = userAgent.toLowerCase();

    if (userAgent.contains("android")) {
      return false;
    }

    if (userAgent.contains("iphone")) {
      return false;
    }

    if (userAgent.contains("mobile")) {
      return false;
    }

    if (userAgent.contains("macintosh")) {
      return true;
    }

    if (userAgent.contains("windows")) {
      return true;
    }

    if (userAgent.contains("linux")) {
      return true;
    }

    // assume desktop otherwise
    return true;
  }
}

enum LayoutType {
  mobile,
  desktop;
}

extension LayoutQueryData on MediaQueryData {
  LayoutType get layout {
    if (preferences.layoutOverride.value == "mobile") {
      return LayoutType.mobile;
    }

    if (preferences.layoutOverride.value == "desktop") {
      return LayoutType.desktop;
    }

    if (PlatformUtils.isWeb && Layout._isWebDesktop()) {
      return LayoutType.desktop;
    }

    if (PlatformUtils.isAndroid || PlatformUtils.isIOS || PlatformUtils.isWeb) {
      // Vommet: width AND shorter side, so a phone in landscape stays mobile.
      final bool useMobileLayout = useMobileLayoutForSize(
          size.width, size.height, preferences.appScale.value);
      if (useMobileLayout) {
        return LayoutType.mobile;
      }
    }

    return LayoutType.desktop;
  }

  bool get mobile {
    return layout == LayoutType.mobile;
  }

  bool get desktop {
    return layout == LayoutType.desktop;
  }

  /// Whether a picker's search field takes the focus when it opens. Not with
  /// an on-screen keyboard, which has to stay as it was (Vommet issue 991).
  bool get focusPickerSearch => desktop && !Layout.onScreenKeyboard;
}
