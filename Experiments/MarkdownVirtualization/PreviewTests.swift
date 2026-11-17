import AppKit
import WebKit

@MainActor final class Runner: NSObject, WKNavigationDelegate {
    var web: WKWebView!
    var window: NSWindow!
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:750),styleMask:[.titled,.resizable],backing:.buffered,defer:false)
        web=WKWebView(frame:window.contentView!.bounds,configuration:config)
        web.navigationDelegate=self;window.contentView=web;window.orderFrontRegardless()
        web.loadFileURL(root.appendingPathComponent("test.html"),allowingReadAccessTo:root)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            do {
                let script = try String(contentsOf:root.appendingPathComponent("test.js"),encoding:.utf8)
                let result: Any = try await withCheckedThrowingContinuation { continuation in
                    web.callAsyncJavaScript(script,arguments:[:],in:nil,in:.page) { continuation.resume(with:$0) }
                }
                let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
                try data.write(to:root.appendingPathComponent("results.json"));print(String(decoding:data,as:UTF8.self))
                NSApplication.shared.terminate(nil)
            } catch { print("FAIL",error);exit(1) }
        }
    }
}
@main struct Main {
 @MainActor static func main() {
  let app=NSApplication.shared;let runner=Runner();runner.start();app.run();withExtendedLifetime(runner) {}
 }
}
