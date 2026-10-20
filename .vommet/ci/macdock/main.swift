// Vommet CI smoke for macos/Runner/WidgetDock.swift without Flutter: a widget
// page docked in a slot, popped out, docked back by closing its window, moved
// to a new slot (room switch), docked back with no slot, then destroyed. The
// page must never reload (same loadId, ticks keep counting) and answer every
// ping through the widgets_ipc.js bridge with e.source == window.parent.
// Then full screen: docked, popped out, and pop out/dock back/destroy while
// full screen (macOS 13+).
import Cocoa
import WebKit

let args = CommandLine.arguments
let pageURL = URL(string: args[1])!
let script = try! String(contentsOfFile: args[2], encoding: .utf8)
let outDir = args[3]

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let core = WidgetDockCore()
var events: [(String, String?)] = []
core.send = { method, id, message in
  print("event \(method) \(id) \(message ?? "")")
  events.append((method, message))
}

func fail(_ text: String) -> Never {
  print("SMOKE FAIL: \(text)")
  exit(1)
}

let mainWindow = NSWindow(
  contentRect: NSRect(x: 80, y: 80, width: 1000, height: 700),
  styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
mainWindow.title = "smoke main"
mainWindow.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

func newSlot() -> DockSlot {
  let slot = DockSlot(id: "w1")
  slot.frame = mainWindow.contentView!.bounds.insetBy(dx: 40, dy: 40)
  mainWindow.contentView!.addSubview(slot)
  core.attach(slot)
  return slot
}

@MainActor
func waitFor(_ what: String, timeout: Double = 20, _ cond: () -> Bool) async {
  let end = Date().addingTimeInterval(timeout)
  while !cond() {
    if Date() > end { fail("timed out waiting for \(what)") }
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
}

func json(_ text: String?) -> [String: Any] {
  guard let data = text?.data(using: .utf8),
    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else { return [:] }
  return obj
}

var pingCount = 0

@MainActor
func pingAck(_ entry: DockEntry, expect loadId: String, _ label: String) async {
  pingCount += 1
  let n = pingCount
  let payload = "{\"action\":\"ping\",\"n\":\(n)}"
  let quoted = String(
    data: try! JSONSerialization.data(withJSONObject: [payload], options: []), encoding: .utf8)!
  // ["..."] -> "..."
  let arg = String(quoted.dropFirst().dropLast())
  entry.webView.evaluateJavaScript("window.onMessagePolyfill(\(arg))", completionHandler: nil)
  await waitFor("ack \(n) (\(label))") {
    events.contains { $0.0 == "message" && (json($0.1)["n"] as? Int) == n }
  }
  let ack = events.last { $0.0 == "message" && (json($0.1)["n"] as? Int) == n }!
  if (json(ack.1)["loadId"] as? String) != loadId { fail("ack \(n) from another page load") }
  if events.contains(where: { json($0.1)["action"] as? String == "bad-source" }) {
    fail("page saw a message without source == window.parent")
  }
  print("ok: ping/ack \(n) (\(label))")
}

@MainActor
func pageState(_ entry: DockEntry) async -> (String, Int) {
  let id = try? await entry.webView.evaluateJavaScript("window.loadId") as? String
  let ticks = try? await entry.webView.evaluateJavaScript("window.ticks") as? Int
  return (id ?? "", ticks ?? -1)
}

@MainActor
func shot(_ entry: DockEntry, _ name: String) async {
  let image = try? await entry.webView.takeSnapshot(configuration: nil)
  guard let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
  else {
    print("note: no snapshot for \(name)")
    return
  }
  try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

Task { @MainActor in
  var slot: DockSlot? = newSlot()
  guard core.create(id: "w1", url: pageURL, script: script, title: "Smoke", userAgent: nil) else {
    fail("create")
  }
  let entry = core.entries["w1"]!
  var fsObservation: NSKeyValueObservation?
  if #available(macOS 13.0, *) {
    fsObservation = entry.webView.observe(\.fullscreenState, options: [.new]) { view, _ in
      print("kvo fullscreenState \(view.fullscreenState.rawValue) in \(view.window?.title ?? "no window")")
    }
  }
  _ = fsObservation
  await waitFor("hello") { events.contains { json($0.1)["action"] as? String == "hello" } }
  let loadId = json(events.first { json($0.1)["action"] as? String == "hello" }!.1)["loadId"]
    as! String
  print("ok: page loaded, loadId \(loadId)")
  if entry.webView.superview !== slot { fail("not docked in the slot after create") }
  await pingAck(entry, expect: loadId, "docked")
  await shot(entry, "1-docked")

  // Pop out.
  core.popOut(entry)
  guard let popout = entry.popout else { fail("no popout window") }
  if popout.title != "Vommet | Smoke" { fail("popout title \(popout.title)") }
  if entry.webView.window !== popout { fail("web view not in the popout window") }
  var (id, ticks1) = await pageState(entry)
  if id != loadId { fail("reloaded on pop out") }
  await pingAck(entry, expect: loadId, "popped out")
  await shot(entry, "2-popped")

  // Closing the window docks it back.
  popout.performClose(nil)
  if entry.popout != nil || popout.isVisible { fail("window close didn't dock back") }
  if entry.webView.superview !== slot { fail("not back in the slot") }
  if !events.contains(where: { $0.0 == "docked" }) { fail("no docked event") }
  try? await Task.sleep(nanoseconds: 500_000_000)
  var ticks2: Int
  (id, ticks2) = await pageState(entry)
  if id != loadId { fail("reloaded on dock back") }
  if ticks2 <= ticks1 { fail("timers stopped (\(ticks1) -> \(ticks2))") }
  await pingAck(entry, expect: loadId, "docked back")

  // Room switch: the old slot goes, a new one takes the view.
  slot?.removeFromSuperview()
  slot = nil
  let slot2 = newSlot()
  if entry.webView.superview !== slot2 { fail("new slot didn't take the view") }
  (id, _) = await pageState(entry)
  if id != loadId { fail("reloaded on slot change") }

  // Dock back while the room isn't showing, then show it.
  core.popOut(entry)
  slot2.removeFromSuperview()
  core.dockBack(entry)
  if entry.webView.superview != nil { fail("docked into a gone slot") }
  let slot3 = newSlot()
  if entry.webView.superview !== slot3 { fail("slot after hidden dock back") }
  (id, _) = await pageState(entry)
  if id != loadId { fail("reloaded after hidden dock back") }
  await pingAck(entry, expect: loadId, "after room switch")
  await shot(entry, "3-redocked")

  // Full screen (macOS 13+): docked, WebKit takes the view into its own
  // window; the Dart side drops the platform view meanwhile (placeholder)
  // and makes a new one after fullscreenLeft.
  @MainActor func count(_ method: String) -> Int { events.filter { $0.0 == method }.count }
  /// nil once full screen, else what the page and WebKit said.
  @MainActor func tryFullscreen(_ label: String) async -> String? {
    let before = count("fullscreenEntered")
    _ = try? await entry.webView.evaluateJavaScript("window.fsResult = '', 0")
    // A click in the page (a user gesture) asks for it, as a video's button.
    guard let window = entry.webView.window else { return "no window" }
    let point = entry.webView.convert(
      NSPoint(x: entry.webView.bounds.midX, y: entry.webView.bounds.midY), to: nil)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      if let event = NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
      {
        window.sendEvent(event)
      }
    }
    let end = Date().addingTimeInterval(20)
    while count("fullscreenEntered") <= before {
      if Date() > end {
        let enabled = try? await entry.webView.evaluateJavaScript(
          "String(document.fullscreenEnabled)")
        let result = try? await entry.webView.evaluateJavaScript("window.fsResult")
        var state = -1
        if #available(macOS 13.0, *) { state = entry.webView.fullscreenState.rawValue }
        return "fullscreenEnabled \(enabled ?? "?"), request: \(result ?? "?"), state \(state), "
          + "window key \(window.isKeyWindow) visible \(window.isVisible) app active \(app.isActive)"
      }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return nil
  }
  @MainActor func enterFullscreen(_ label: String) async {
    // AppKit refuses a new full screen while the last one's Space animation
    // still runs (windowDidFailToEnterFullScreen); a person is never that quick.
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    if let problem = await tryFullscreen(label) {
      print("no full screen (\(label)): \(problem)")
      fflush(stdout)
      if label == "docked" {
        // Diagnostic: does it work from a plain top-level window?
        core.popOut(entry)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let popped = await tryFullscreen("popped out (diagnostic)")
        print("popped out diagnostic: \(popped ?? "FULL SCREEN OK")")
      }
      fail("no fullscreenEntered (\(label))")
    }
    if entry.webView.window === mainWindow || entry.webView.window == nil {
      fail("full screen view still in the main window (\(label))")
    }
    print("ok: full screen (\(label))")
  }
  // Environment check: can any window go full screen on this machine?
  let probe = NSWindow(
    contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
    styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
  probe.isReleasedWhenClosed = false
  probe.collectionBehavior.insert(.fullScreenPrimary)
  probe.makeKeyAndOrderFront(nil)
  probe.toggleFullScreen(nil)
  try? await Task.sleep(nanoseconds: 4_000_000_000)
  let probeFull = probe.styleMask.contains(.fullScreen)
  print("probe: a plain NSWindow \(probeFull ? "CAN" : "CANNOT") go full screen here")
  if probeFull {
    probe.toggleFullScreen(nil)
    try? await Task.sleep(nanoseconds: 3_000_000_000)
  }
  probe.orderOut(nil)
  mainWindow.makeKeyAndOrderFront(nil)
  fflush(stdout)
  if #available(macOS 13.0, *) {
    await enterFullscreen("docked")
    await pingAck(entry, expect: loadId, "full screen")
    await shot(entry, "4-fullscreen")
    slot3.removeFromSuperview()
    // A platform view made while full screen must not take the view.
    let early = newSlot()
    if entry.webView.superview === early { fail("slot took the view during full screen") }
    early.removeFromSuperview()
    entry.webView.evaluateJavaScript("document.exitFullscreen(), 0", completionHandler: nil)
    await waitFor("fullscreenLeft (Esc)") { count("fullscreenLeft") == 1 }
    let slot4 = newSlot()
    if entry.webView.superview !== slot4 { fail("slot after full screen") }
    await pingAck(entry, expect: loadId, "after full screen")

    // Pop out while full screen: leaves full screen first.
    await enterFullscreen("before pop out")
    core.popOut(entry)
    await waitFor("popped out after full screen") { entry.popout != nil }
    if count("fullscreenLeft") != 2 { fail("no fullscreenLeft before pop out") }
    if entry.webView.window !== entry.popout { fail("not in the popout after full screen") }
    await pingAck(entry, expect: loadId, "popped out after full screen")

    // Popped out full screen, then dock back.
    await enterFullscreen("popped out")
    core.dockBack(entry)
    await waitFor("docked after full screen") { entry.popout == nil }
    if count("fullscreenLeft") != 3 { fail("no fullscreenLeft before dock back") }
    if entry.webView.superview !== slot4 { fail("not back in the slot after full screen") }

    // Destroy while full screen.
    await enterFullscreen("before destroy")
    core.destroy(entry)
    await waitFor("closed after full screen") { entry.webView.superview == nil }
    if count("fullscreenLeft") != 4 { fail("no fullscreenLeft before destroy") }
    if !core.entries.isEmpty { fail("destroy") }
    print("ok: full screen enter/leave, pop out, dock back, destroy")
  } else {
    print("note: macOS < 13, no full screen check")
    core.destroy(entry)
    if !core.entries.isEmpty || entry.webView.superview != nil { fail("destroy") }
  }

  print("SMOKE PASS: same page load \(loadId) through dock -> pop out -> close window -> slot changes, \(pingCount) IPC acks")
  exit(0)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 240) { fail("overall timeout") }
app.run()
