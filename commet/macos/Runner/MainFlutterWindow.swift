import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
