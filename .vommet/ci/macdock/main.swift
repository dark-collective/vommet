// Vommet CI smoke for macos/Runner/WidgetDock.swift without Flutter: a widget
// page docked in a slot, popped out, docked back by closing its window, moved
// to a new slot (room switch), docked back with no slot, then destroyed. The
// page must never reload (same loadId, ticks keep counting) and answer every
// ping through the widgets_ipc.js bridge with e.source == window.parent.
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

  core.destroy(entry)
  if !core.entries.isEmpty || entry.webView.superview != nil { fail("destroy") }

  print("SMOKE PASS: same page load \(loadId) through dock -> pop out -> close window -> slot changes, \(pingCount) IPC acks")
  exit(0)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 120) { fail("overall timeout") }
app.run()
