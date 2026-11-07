import UIKit
import Flutter
import UserNotifications

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Vommet issue 531: lets flutter_local_notifications show notifications
    // while the app is in front.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "VommetLauncherIcon") {
      registerLauncherIcon(messenger: registrar.messenger())
    }
    if let registrar = self.registrar(forPlugin: "VommetClipboard") {
      registerClipboard(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Vommet: the home screen icon (Vommet issue 681). The V is the primary
  /// icon (AppIconV) and nil puts it back; the original is the alternate
  /// icon AppIcon.
  private func registerLauncherIcon(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "im.nether.vommet/launcher_icon", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let name: String? = (call.arguments as? String) == "original" ? "AppIcon" : nil
      let app = UIApplication.shared
      guard app.supportsAlternateIcons, app.alternateIconName != name else {
        result(nil)
        return
      }
      app.setAlternateIconName(name) { error in
        if let error = error {
          result(FlutterError(
            code: "launcher_icon", message: error.localizedDescription, details: nil))
        } else {
          result(nil)
        }
      }
    }
  }

  /// Vommet issue 1113: on iPadOS, the on-screen keyboard's paste button
  /// sends UIKit's `paste:` straight to Flutter's native text input view.
  /// When the clipboard holds an image, Flutter's default text input view
  /// ignores it because `[UIPasteboard generalPasteboard].string` is nil.
  /// We intercept `canPerformAction:withSender:` so the paste button stays
  /// enabled when an image is present, and intercept `paste:` so images are
  /// forwarded to Dart.
  private func registerClipboard(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "im.nether.vommet/clipboard", binaryMessenger: messenger)
    VommetClipboard.channel = channel
    VommetTextInputPasteHelper.swizzleIfNeeded()
  }
}

class VommetClipboard {
  static var channel: FlutterMethodChannel?
}

@objc class VommetTextInputPasteHelper: NSObject {
  private static var swizzled = false

  static func swizzleIfNeeded() {
    guard !swizzled else { return }
    swizzled = true

    guard let targetClass = NSClassFromString("FlutterTextInputView") else {
      return
    }

    swizzle(
      targetClass: targetClass,
      originalSelector: #selector(UIResponder.canPerformAction(_:withSender:)),
      swizzledClass: VommetTextInputPasteHelper.self,
      swizzledSelector: #selector(VommetTextInputPasteHelper.vommet_canPerformAction(_:withSender:))
    )

    swizzle(
      targetClass: targetClass,
      originalSelector: #selector(UIResponderStandardEditActions.paste(_:)),
      swizzledClass: VommetTextInputPasteHelper.self,
      swizzledSelector: #selector(VommetTextInputPasteHelper.vommet_paste(_:))
    )
  }

  private static func swizzle(
    targetClass: AnyClass,
    originalSelector: Selector,
    swizzledClass: AnyClass,
    swizzledSelector: Selector
  ) {
    guard let originalMethod = class_getInstanceMethod(targetClass, originalSelector),
          let swizzledMethod = class_getInstanceMethod(swizzledClass, swizzledSelector) else {
      return
    }

    let swizzledImp = method_getImplementation(swizzledMethod)
    let swizzledTypes = method_getTypeEncoding(swizzledMethod)

    let didAdd = class_addMethod(targetClass, originalSelector, swizzledImp, swizzledTypes)
    if didAdd {
      let originalImp = method_getImplementation(originalMethod)
      let originalTypes = method_getTypeEncoding(originalMethod)
      class_replaceMethod(targetClass, swizzledSelector, originalImp, originalTypes)
    } else {
      class_addMethod(targetClass, swizzledSelector, swizzledImp, swizzledTypes)
      if let newMethod = class_getInstanceMethod(targetClass, swizzledSelector) {
        method_exchangeImplementations(originalMethod, newMethod)
      }
    }
  }

  // Dynamic dispatch reaches the original selector installed on the input view.
  @objc dynamic func vommet_canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(UIResponderStandardEditActions.paste(_:)) {
      if UIPasteboard.general.hasImages && !UIPasteboard.general.hasStrings {
        return true
      }
    }
    return self.vommet_canPerformAction(action, withSender: sender)
  }

  @objc dynamic func vommet_paste(_ sender: Any?) {
    // If the pasteboard holds text, let Flutter's text input view paste the string.
    if UIPasteboard.general.hasStrings {
      self.vommet_paste(sender)
      return
    }

    // Vommet issue 1113: on iPadOS, the keyboard's paste button sends UIKit's
    // `paste:` to Flutter's text input view. If the pasteboard holds an image,
    // read it and forward the bytes to Dart so the attachment preview opens.
    if UIPasteboard.general.hasImages {
      if let image = UIPasteboard.general.image,
         let data = image.pngData() {
        VommetClipboard.channel?.invokeMethod(
          "pasteImage", FlutterStandardTypedData(bytes: data))
        return
      }
      VommetClipboard.channel?.invokeMethod("pasteImage", nil)
      return
    }

    self.vommet_paste(sender)
  }
}
