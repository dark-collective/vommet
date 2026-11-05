import Flutter
import UIKit

/// Reports the hinge of a foldable iPhone (iOS 27.1+, UIHingeInteraction) to
/// Dart as `{"status": String, "angle": Double}` events, angle in degrees.
///
/// iOS sends the same state about every 30 ms even while the hinge is still,
/// so only changes are forwarded: any status change, or the angle moving by at
/// least one degree.
public class VommetHingePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private weak var registrar: FlutterPluginRegistrar?
  private var sink: FlutterEventSink?
  private var interaction: UIInteraction?
  private var lastStatus: String?
  private var lastAngle: Double?
  private var sceneObserver: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = VommetHingePlugin()
    instance.registrar = registrar
    let channel = FlutterEventChannel(
      name: "im.nether.vommet/hinge", binaryMessenger: registrar.messenger())
    channel.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    if !install() {
      // With scenes, the view controller may not exist yet: try again when a
      // scene becomes active.
      sceneObserver = NotificationCenter.default.addObserver(
        forName: UIScene.didActivateNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self, self.install(), let observer = self.sceneObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        self.sceneObserver = nil
      }
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = sceneObserver {
      NotificationCenter.default.removeObserver(observer)
      sceneObserver = nil
    }
    if let interaction, let view = interaction.view {
      view.removeInteraction(interaction)
    }
    interaction = nil
    sink = nil
    lastStatus = nil
    lastAngle = nil
    return nil
  }

  /// Adds the hinge interaction to the Flutter view. Returns false while there
  /// is no view yet; true once installed, or when this iOS has no hinge API.
  private func install() -> Bool {
    if interaction != nil { return true }
    guard #available(iOS 27.1, *) else { return true }
    guard let view = registrar?.viewController?.view else { return false }

    let hingeInteraction = UIHingeInteraction { [weak self] _, update in
      self?.report(update.hinge)
    }
    view.addInteraction(hingeInteraction)
    interaction = hingeInteraction
    return true
  }

  @available(iOS 27.1, *)
  private func report(_ hinge: UIHinge?) {
    guard let sink else { return }
    guard let hinge else {
      // The view left a hierarchy that provides hinge updates.
      if lastStatus != nil {
        lastStatus = nil
        lastAngle = nil
        sink(nil)
      }
      return
    }

    let status: String
    switch hinge.status {
    case .closed: status = "closed"
    case .partiallyOpen: status = "partiallyOpen"
    case .fullyOpen: status = "fullyOpen"
    default: status = "unknown"
    }
    let angle = Double(hinge.angle) * 180 / .pi

    if status == lastStatus, let lastAngle, abs(angle - lastAngle) < 1 { return }
    lastStatus = status
    lastAngle = angle
    sink(["status": status, "angle": angle])
  }
}
