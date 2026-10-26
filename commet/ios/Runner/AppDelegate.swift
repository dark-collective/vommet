import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "VommetLauncherIcon") {
      registerLauncherIcon(messenger: registrar.messenger())
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
}
