import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var systemSleepChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Vommet: docked widgets (experiment), see WidgetDock.swift.
    WidgetDock.register(
      with: flutterViewController.registrar(forPlugin: "VommetWidgetDock"),
      flutterView: flutterViewController.view)

    // Vommet issue 598: tell Dart when the Mac goes to sleep (and wakes up),
    // so it can leave any active call.
    let channel = FlutterMethodChannel(
      name: "im.nether.chat/system_sleep",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    systemSleepChannel = channel
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    workspaceCenter.addObserver(
      forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
    ) { _ in
      channel.invokeMethod("willSleep", arguments: nil)
    }
    workspaceCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { _ in
      channel.invokeMethod("didWake", arguments: nil)
    }

    super.awakeFromNib()
  }
}
