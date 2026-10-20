// Does a WKWebView load an https page in an app sandboxed with Vommet's
// entitlements? Prints NETCHECK ok|fail.
import Cocoa
import WebKit

final class Nav: NSObject, WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    webView.evaluateJavaScript("document.title") { title, _ in
      print("NETCHECK ok: \(title ?? "")")
      exit(0)
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    print("NETCHECK fail: \(error)"); exit(2)
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
  ) {
    print("NETCHECK fail: \(error)"); exit(2)
  }
}

let app = NSApplication.shared
let window = NSWindow(
  contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
  backing: .buffered, defer: false)
let view = WKWebView(frame: window.contentView!.bounds)
window.contentView!.addSubview(view)
window.makeKeyAndOrderFront(nil)
let nav = Nav()
view.navigationDelegate = nav
view.load(URLRequest(url: URL(string: CommandLine.arguments[1])!))
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("NETCHECK fail: timeout"); exit(3) }
app.run()
