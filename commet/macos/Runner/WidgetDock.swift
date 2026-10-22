import Cocoa
import WebKit

#if canImport(FlutterMacOS)
  import FlutterMacOS
#endif

// Vommet: docked widgets on macOS (experiment "Docked widgets", see
// lib/client/components/widgets/docked/widget_dock.dart). Each open widget
// is one WKWebView, kept here by the id the Dart side gave it. Docked, it
// fills a Flutter platform view (DockSlot) in the room; popped out, it is
// the content of its own window. Moving it between the two never reloads
// the page. Flutter draws its own UI above platform views, so unlike Linux
// no still picture is needed while a dialog covers it. Full screen (a
// video's button) is WebKit's own: the view moves into its own full screen
// window and comes back on Esc; the Dart side shows a placeholder meanwhile.

/// The web view of one widget; tells the dock when the user clicks into it.
final class DockWebView: WKWebView {
  var onFocus: (() -> Void)?

  override func becomeFirstResponder() -> Bool {
    let became = super.becomeFirstResponder()
    if became { onFocus?() }
    return became
  }
}

/// Where a docked widget shows: the platform view's own NSView.
final class DockSlot: NSView {
  let id: String
  /// Set by the dock: a slot that joins the view tree takes its widget.
  var onShow: ((DockSlot) -> Void)?

  init(id: String) {
    self.id = id
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if superview != nil { onShow?(self) }
  }
}

/// WKUserContentController keeps its handlers alive; this breaks the cycle
/// web view -> configuration -> handler -> entry -> web view.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: DockEntry?
  init(_ target: DockEntry) { self.target = target }

  func userContentController(
    _ controller: WKUserContentController, didReceive message: WKScriptMessage
  ) {
    target?.received(message)
  }
}

final class DockEntry: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
  let id: String
  let title: String
  let webView: DockWebView
  var popout: NSWindow?
  weak var dock: WidgetDockCore?
  /// The page is full screen (fullscreenEntered sent, fullscreenLeft not yet).
  private(set) var fullscreen = false
  private var fullscreenObservation: NSKeyValueObservation?
  /// Waiting for full screen to end (pop out, dock back, destroy).
  private var afterFullscreen: [() -> Void] = []

  init(id: String, url: URL, script: String, title: String, userAgent: String?, dock: WidgetDockCore) {
    self.id = id
    self.title = title
    self.dock = dock

    let config = WKWebViewConfiguration()
    // Like the widget window: nothing is kept between sessions.
    config.websiteDataStore = .nonPersistent()
    // Watch Together starts playback for everyone without a click here.
    config.mediaTypesRequiringUserActionForPlayback = []
    config.userContentController.addUserScript(
      WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    // Only where the dock can see full screen start and end.
    if #available(macOS 13.0, *) { config.preferences.isElementFullscreenEnabled = true }
    webView = DockWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 600), configuration: config)
    super.init()

    config.userContentController.add(WeakScriptHandler(self), name: "vommetIpc")
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.autoresizingMask = [.width, .height]
    if let userAgent, !userAgent.isEmpty { webView.customUserAgent = userAgent }
    webView.onFocus = { [weak self] in
      guard let self else { return }
      self.dock?.notify("focused", self)
    }
    if #available(macOS 13.0, *) {
      // Each state as it comes: a quick enter and leave still reports both.
      fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) {
        [weak self] view, _ in
        let state = view.fullscreenState
        DispatchQueue.main.async { self?.fullscreenStateChanged(state) }
      }
    }
    webView.load(URLRequest(url: url))
  }

  /// Whether WebKit has the view full screen, or is moving it in or out.
  var inFullscreenWindow: Bool {
    if #available(macOS 13.0, *) { return webView.fullscreenState != .notInFullscreen }
    return false
  }

  @available(macOS 13.0, *)
  private func fullscreenStateChanged(_ state: WKWebView.FullscreenState) {
    switch state {
    case .inFullscreen where !fullscreen:
      fullscreen = true
      dock?.notify("fullscreenEntered", self)
    case .notInFullscreen:
      if fullscreen {
        fullscreen = false
        dock?.fullscreenLeft(self)
      }
      let pending = afterFullscreen
      afterFullscreen = []
      for action in pending { action() }
    default:
      break
    }
  }

  /// Runs [action] now, or once full screen has ended (leaving it first).
  func afterLeavingFullscreen(_ action: @escaping () -> Void) {
    guard inFullscreenWindow else {
      action()
      return
    }
    afterFullscreen.append(action)
    if afterFullscreen.count > 1 { return }
    // The page's own exit covers element full screen; the other one video.
    webView.evaluateJavaScript(
      "document.fullscreenElement && document.exitFullscreen(), 0", completionHandler: nil)
    if #available(macOS 12.0, *) { webView.closeAllMediaPresentations {} }
    // Don't hang on a full screen that never ends.
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, !self.afterFullscreen.isEmpty else { return }
      NSLog("Vommet: widget %@ didn't leave full screen", self.id)
      let pending = self.afterFullscreen
      self.afterFullscreen = []
      for action in pending { action() }
    }
  }

  // Messages from the page (widgets_ipc.js sendIpc) go to Dart unchanged.
  func received(_ message: WKScriptMessage) {
    let text = message.body as? String ?? "\(message.body)"
    dock?.notify("message", self, message: text)
  }

  func move(into view: NSView) {
    if webView.superview === view { return }
    webView.removeFromSuperview()
    webView.frame = view.bounds
    view.addSubview(webView)
  }

  func close() {
    fullscreenObservation = nil
    if let window = popout {
      popout = nil
      window.delegate = nil
      window.close()
    }
    webView.stopLoading()
    webView.removeFromSuperview()
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "vommetIpc")
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
  }

  // MARK: WKUIDelegate

  // Links that open a new window go to the default browser.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
    return nil
  }

  // Microphone/camera: ask first.
  @available(macOS 12.0, *)
  func webView(
    _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    ask(
      "This widget wants to use your microphone or camera.", buttons: ["Allow", "Block"]
    ) { allowed in
      decisionHandler(allowed ? .grant : .deny)
    }
  }

  func webView(
    _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void
  ) {
    ask(message, buttons: ["OK"]) { _ in completionHandler() }
  }

  func webView(
    _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
  ) {
    ask(message, buttons: ["OK", "Cancel"]) { ok in completionHandler(ok) }
  }

  /// [first button pressed] for an alert on the window showing the widget.
  private func ask(_ text: String, buttons: [String], done: @escaping (Bool) -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    for button in buttons { alert.addButton(withTitle: button) }
    if let window = webView.window {
      alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    } else {
      done(alert.runModal() == .alertFirstButtonReturn)
    }
  }

  // MARK: WKNavigationDelegate

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    NSLog("Vommet: widget web process ended (%@)", id)
    dock?.notify("closed", self)
  }

  // MARK: NSWindowDelegate

  // Closing the popped out window docks the widget back.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    dock?.dockBack(self)
    return false
  }
}

/// Everything except the Flutter glue, so the dock can be tested without
/// Flutter (the CI smoke builds this file on its own).
class WidgetDockCore: NSObject {
  private(set) var entries: [String: DockEntry] = [:]
  private var slots: [String: WeakSlot] = [:]
  /// Called with (method, id, message) for the Dart side.
  var send: ((String, String, String?) -> Void)?

  private struct WeakSlot { weak var slot: DockSlot? }

  func notify(_ method: String, _ entry: DockEntry, message: String? = nil) {
    send?(method, entry.id, message)
  }

  func create(id: String, url: URL, script: String, title: String, userAgent: String?) -> Bool {
    if entries[id] != nil { return false }
    let entry = DockEntry(
      id: id, url: url, script: script, title: title, userAgent: userAgent, dock: self)
    entries[id] = entry
    if let slot = slots[id]?.slot { entry.move(into: slot) }
    return true
  }

  /// A platform view for [id] was made: the docked widget moves into it.
  /// A rebuilt room makes a new one before the old one goes; the newest wins.
  func attach(_ slot: DockSlot) {
    slots = slots.filter { $0.value.slot != nil }
    slots[slot.id] = WeakSlot(slot: slot)
    slot.onShow = { [weak self] in self?.attach($0) }
    // Full screen, WebKit holds the view; it moves in once that ends.
    if let entry = entries[slot.id], entry.popout == nil, !entry.inFullscreenWindow {
      entry.move(into: slot)
    }
  }

  /// WebKit put the view back where it was; that slot may be gone by now.
  func fullscreenLeft(_ entry: DockEntry) {
    if let content = entry.popout?.contentView {
      entry.move(into: content)
    } else if let slot = slots[entry.id]?.slot, slot.superview != nil {
      entry.move(into: slot)
    }
    notify("fullscreenLeft", entry)
  }

  func popOut(_ entry: DockEntry) {
    if entry.inFullscreenWindow {
      entry.afterLeavingFullscreen { [weak self] in self?.popOut(entry) }
      return
    }
    if let window = entry.popout {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let size = NSSize(
      width: max(entry.webView.bounds.width, 960), height: max(entry.webView.bounds.height, 600))
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered,
      defer: false)
    window.isReleasedWhenClosed = false
    window.title = "Vommet | \(entry.title)"
    window.delegate = entry
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    window.contentView = content
    entry.move(into: content)
    entry.popout = window
    window.center()
    window.makeKeyAndOrderFront(nil)
    notify("poppedOut", entry)
  }

  func dockBack(_ entry: DockEntry) {
    if entry.inFullscreenWindow {
      entry.afterLeavingFullscreen { [weak self] in self?.dockBack(entry) }
      return
    }
    guard let window = entry.popout else { return }
    entry.popout = nil
    if let slot = slots[entry.id]?.slot, slot.superview != nil {
      entry.move(into: slot)
    } else {
      // The room isn't showing; the next platform view for it picks it up.
      entry.webView.removeFromSuperview()
    }
    window.delegate = nil
    window.close()
    notify("docked", entry)
  }

  func destroy(_ entry: DockEntry) {
    entries.removeValue(forKey: entry.id)
    entry.afterLeavingFullscreen { entry.close() }
  }

  /// Whether the mouse is over a docked or popped out widget right now.
  func mouseIsOverWidget() -> Bool {
    let point = NSEvent.mouseLocation
    return entries.values.contains { entry in
      guard let window = entry.webView.window else { return false }
      let frame = window.convertToScreen(
        entry.webView.convert(entry.webView.bounds, to: nil))
      return frame.contains(point)
    }
  }
}

#if canImport(FlutterMacOS)

  /// The `vommet/widget_dock` channel (same calls as linux/widget_dock.cc) and
  /// the `vommet/widget_dock_view` platform view.
  final class WidgetDock: WidgetDockCore, FlutterPlatformViewFactory {
    private var channel: FlutterMethodChannel?
    private weak var flutterView: NSView?

    static func register(with registrar: FlutterPluginRegistrar, flutterView: NSView) {
      let dock = WidgetDock()
      dock.flutterView = flutterView
      let channel = FlutterMethodChannel(
        name: "vommet/widget_dock", binaryMessenger: registrar.messenger)
      dock.channel = channel
      dock.send = { [weak dock] method, id, message in
        var args: [String: Any] = ["id": id]
        if let message { args["message"] = message }
        dock?.channel?.invokeMethod(method, arguments: args)
      }
      channel.setMethodCallHandler { call, result in dock.handle(call, result) }
      registrar.register(dock, withId: "vommet/widget_dock_view")
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
      let id = (args as? [String: Any])?["id"] as? String ?? ""
      let slot = DockSlot(id: id)
      attach(slot)
      return slot
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
      FlutterStandardMessageCodec.sharedInstance()
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
      if call.method == "isAvailable" {
        result(true)
        return
      }
      if call.method == "focusFlutter" {
        // A click into the widget can reach Flutter too; don't take the
        // keyboard back from the widget for that one.
        if let view = flutterView, !mouseIsOverWidget() {
          view.window?.makeFirstResponder(view)
        }
        result(nil)
        return
      }
      guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else {
        result(FlutterError(code: "bad_args", message: "missing id", details: nil))
        return
      }
      if call.method == "create" {
        guard let urlText = args["url"] as? String, let url = URL(string: urlText),
          let script = args["script"] as? String,
          create(
            id: id, url: url, script: script, title: args["title"] as? String ?? "Widget",
            userAgent: args["userAgent"] as? String)
        else {
          result(FlutterError(code: "bad_args", message: "bad create", details: nil))
          return
        }
        result(nil)
        return
      }
      guard let entry = entries[id] else {
        result(FlutterError(code: "unknown_id", message: id, details: nil))
        return
      }
      switch call.method {
      case "setRect", "setVisible":
        // The platform view places and shows it.
        break
      case "evaluate":
        if let script = args["script"] as? String {
          entry.webView.evaluateJavaScript(script, completionHandler: nil)
        }
      case "popOut":
        popOut(entry)
      case "dockBack":
        dockBack(entry)
      case "snapshot":
        // The app doesn't need it (Flutter draws over platform views);
        // the integration test checks with it that the view shows.
        entry.webView.takeSnapshot(with: nil) { image, _ in
          guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
          else {
            result(nil)
            return
          }
          result(FlutterStandardTypedData(bytes: png))
        }
        return
      case "destroy":
        destroy(entry)
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
  }

#endif
