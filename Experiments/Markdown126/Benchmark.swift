import AppKit
import WebKit

@MainActor final class Runner: NSObject, WKNavigationDelegate {
    var web: WKWebView!
    var window: NSWindow!
    var rows: [[String: Any]] = []
    let base = URL(fileURLWithPath: CommandLine.arguments[1])
    func start() {
        NSApplication.shared.setActivationPolicy(.accessory)
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1080,height: 800),styleMask:[.titled],backing:.buffered,defer:false)
        web = WKWebView(frame: window.contentView!.bounds)
        web.navigationDelegate = self
        window.contentView = web
        window.orderFrontRegardless()
        web.loadFileURL(base.appendingPathComponent("index.html"),allowingReadAccessTo:base)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await run(); NSApplication.shared.terminate(nil) }
    }
    func now() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
    func native(_ text: String, tk2: Bool) -> [String:Any] {
        let scroll = NSScrollView(frame: NSRect(x:0,y:0,width:1080,height:650))
        let view: NSTextView
        if tk2 {
            let content = NSTextContentStorage(), layout = NSTextLayoutManager()
            let container = NSTextContainer(size:NSSize(width:1060,height:CGFloat.greatestFiniteMagnitude))
            content.addTextLayoutManager(layout); layout.textContainer = container
            view = NSTextView(frame:scroll.bounds,textContainer:container)
        } else {
            let storage = NSTextStorage(), layout = NSLayoutManager()
            let container = NSTextContainer(size:NSSize(width:1060,height:CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout); layout.addTextContainer(container)
            view = NSTextView(frame:scroll.bounds,textContainer:container)
        }
        view.isVerticallyResizable = true; view.font = .monospacedSystemFont(ofSize:15,weight:.regular)
        scroll.documentView = view; window.contentView = scroll
        let start = now(); view.string = text
        view.displayIfNeeded(); let open = now()-start
        var edits:[Double]=[]
        for _ in 0..<40 {
            let start = now(), point = view.textStorage!.length/2
            view.textStorage!.replaceCharacters(in:NSRange(location:point,length:0),with:"测")
            view.setSelectedRange(NSRange(location:point+1,length:0));view.scrollRangeToVisible(view.selectedRange());view.displayIfNeeded()
            edits.append(now()-start)
        }
        edits.sort()
        let result:[String:Any] = ["engine":tk2 ? "Native TK2 plain" : "Native TK1 plain","utf8Bytes":text.utf8.count,"utf16":(text as NSString).length,"openMs":open,"editP50SyncMs":edits[20],"editP95SyncMs":edits[38],"textKit2":view.textLayoutManager != nil]
        window.contentView = web
        return result
    }
    func run() async {
        do {
            var inputs:[String] = []
            if CommandLine.arguments.count > 2 { inputs.append(try String(contentsOfFile:CommandLine.arguments[2],encoding:.utf8)) }
            let unit = "# 标题\n\n普通文字，含 **粗体** 和 `code`。\n\n- 列表内容\n\n"
            for size in [400_000,2_000_000,10_000_000] { inputs.append(String(repeating:unit,count:size/unit.utf8.count+1)) }
            for text in inputs {
                rows.append(native(text,tk2:false));rows.append(native(text,tk2:true))
                let value: Any = try await withCheckedThrowingContinuation { continuation in
                    web.callAsyncJavaScript("return await window.benchmark(text)", arguments:["text":text], in:nil, in:.page) { result in
                        continuation.resume(with: result)
                    }
                }
                var row = value as! [String:Any];row["utf8Bytes"]=text.utf8.count;row["engine"]="CodeMirror 6 / WKWebView";rows.append(row)
            }
            let data = try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys])
            try data.write(to:base.appendingPathComponent("results.json"))
            print(String(decoding:data,as:UTF8.self))
        } catch { print("ERROR",error); exit(1) }
    }
}
@main struct Main {
 @MainActor static func main() {
  let app = NSApplication.shared
  let runner = Runner(); runner.start(); app.run()
  withExtendedLifetime(runner) {}
 }
}
