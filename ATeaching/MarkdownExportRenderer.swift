import Foundation
import SwiftUI

#if os(macOS)
import WebKit
#endif

#if os(macOS) || os(iOS)
enum MarkdownExportRenderer {
    @MainActor
    static func renderData(
        format: MarkdownExportFormat,
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        baseURL: URL?
    ) throws -> Data {
        switch format {
        case .markdown:
            return Data(source.utf8)
        case .html:
            #if os(macOS)
            return Data(try renderStaticHTML(source: source, style: style, preferredScheme: preferredScheme, baseURL: baseURL).utf8)
            #else
            return Data(renderedHTML(source: source, style: style, preferredScheme: preferredScheme).utf8)
            #endif
        case .pdf:
            #if os(macOS)
            return try renderPDFData(source: source, style: style, preferredScheme: preferredScheme, baseURL: baseURL)
            #else
            throw CocoaError(.featureUnsupported)
            #endif
        }
    }

    static func renderedHTML(
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?
    ) -> String {
        let blocks = markdownWebRenderBlocks(source: source, previousBlocks: [])
        let patchScript = markdownWebBuildPatchScript(previousBlocks: [], nextBlocks: blocks)
        let renderScript = """
        <script>
        document.addEventListener('DOMContentLoaded', function () {
            \(patchScript)
        });
        </script>
        """
        let html = injectExportStyle(into: markdownWebBootstrapHTML(style: style, preferredScheme: preferredScheme), style: style)
        if let range = html.range(of: "</body>") {
            return html.replacingCharacters(in: range, with: renderScript + "\n</body>")
        }
        return html + renderScript
    }

    private static func injectExportStyle(into html: String, style: MarkdownDocumentStyle) -> String {
        let scale = 0.6
        let css = """
        <style id="markdown-export-layout-style">
        body {
            margin: 0 !important;
            padding: 24px !important;
            box-sizing: border-box !important;
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
        }
        #md-root {
            padding: 0 !important;
            font-size: \(style.body.fontSize * scale)px !important;
            -webkit-print-color-adjust: exact !important;
            print-color-adjust: exact !important;
        }
        #md-root h1 { font-size: \(style.h1.fontSize * scale)px !important; }
        #md-root h2 { font-size: \(style.h2.fontSize * scale)px !important; }
        #md-root h3 { font-size: \(style.h3.fontSize * scale)px !important; }
        #md-root h4 { font-size: \(style.h4.fontSize * scale)px !important; }
        #md-root h5 { font-size: \(style.h5.fontSize * scale)px !important; }
        #md-root h6 { font-size: \(style.h6.fontSize * scale)px !important; }
        #md-root blockquote { font-size: \(style.comment.fontSize * scale)px !important; }
        </style>
        """
        if let range = html.range(of: "</head>") {
            return html.replacingCharacters(in: range, with: css + "\n</head>")
        }
        return css + html
    }

    #if os(macOS)
    @MainActor
    private static func renderStaticHTML(
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        baseURL: URL?
    ) throws -> String {
        let webView = try loadedWebView(source: source, style: style, preferredScheme: preferredScheme, baseURL: baseURL)
        let outerHTML = webView.markdownEvaluateJavaScriptSync(
            "document.documentElement.outerHTML;",
            timeout: 5
        ) as? String
        guard let outerHTML, !outerHTML.isEmpty else {
            throw NSError(
                domain: "MarkdownExportRenderer",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "生成Markdown HTML失败。"]
            )
        }
        return "<!doctype html>\n" + outerHTML
    }

    @MainActor
    private static func renderPDFData(
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        baseURL: URL?
    ) throws -> Data {
        let webView = try loadedWebView(source: source, style: style, preferredScheme: preferredScheme, baseURL: baseURL)
        let contentSize = webView.markdownEvaluateJavaScriptSync(
            """
            (function() {
                const root = document.getElementById('md-root') || document.body;
                return {
                    width: Math.max(document.documentElement.scrollWidth, root.scrollWidth, 960),
                    height: Math.max(document.documentElement.scrollHeight, root.scrollHeight, 1)
                };
            })();
            """,
            timeout: 5
        ) as? [String: Any]
        let width = CGFloat((contentSize?["width"] as? NSNumber)?.doubleValue ?? 960)
        let height = CGFloat((contentSize?["height"] as? NSNumber)?.doubleValue ?? 1400)
        webView.frame = CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height))
        let pdfConfiguration = WKPDFConfiguration()
        pdfConfiguration.rect = CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height))
        return try webView.markdownCreatePDFSync(configuration: pdfConfiguration, timeout: 60)
    }

    @MainActor
    private static func loadedWebView(
        source: String,
        style: MarkdownDocumentStyle,
        preferredScheme: ColorScheme?,
        baseURL: URL?
    ) throws -> WKWebView {
        let html = renderedHTML(source: source, style: style, preferredScheme: preferredScheme)
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 1400), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        let loader = MarkdownExportWebViewLoader()
        webView.navigationDelegate = loader
        webView.loadHTMLString(html, baseURL: baseURL ?? Bundle.main.resourceURL)
        try loader.waitSynchronouslyUntilFinished(timeout: 60)
        _ = webView.markdownEvaluateJavaScriptSync("document.fonts && document.fonts.ready ? document.fonts.ready : Promise.resolve();", timeout: 10)
        _ = webView.markdownEvaluateJavaScriptSync(
            """
            (function() {
                const images = Array.from(document.images || []);
                if (images.length === 0) { return Promise.resolve(true); }
                return Promise.all(images.map(function(img) {
                    if (img.complete) { return Promise.resolve(true); }
                    return new Promise(function(resolve) {
                        img.addEventListener('load', function() { resolve(true); }, { once: true });
                        img.addEventListener('error', function() { resolve(false); }, { once: true });
                    });
                }));
            })();
            """,
            timeout: 20
        )
        return webView
    }
    #endif
}

#if os(macOS)
private final class MarkdownExportWebViewLoader: NSObject, WKNavigationDelegate {
    private var settled = false
    private var finished = false
    private var capturedError: Error?

    func waitSynchronouslyUntilFinished(timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        if !finished {
            throw NSError(
                domain: "MarkdownExportRenderer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "加载Markdown导出页面超时。"]
            )
        }
        if let capturedError { throw capturedError }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !settled else { return }
        settled = true
        finished = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !settled else { return }
        settled = true
        capturedError = error
        finished = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !settled else { return }
        settled = true
        capturedError = error
        finished = true
    }
}

private extension WKWebView {
    @MainActor
    func markdownEvaluateJavaScriptSync(_ script: String, timeout: TimeInterval) -> Any {
        var resultValue: Any?
        var settled = false
        evaluateJavaScript(script) { result, _ in
            resultValue = result
            settled = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !settled && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return resultValue as Any
    }

    @MainActor
    func markdownCreatePDFSync(configuration: WKPDFConfiguration, timeout: TimeInterval) throws -> Data {
        var outputData: Data?
        var outputError: Error?
        var settled = false
        createPDF(configuration: configuration) { result in
            switch result {
            case let .success(data):
                outputData = data
            case let .failure(error):
                outputError = error
            }
            settled = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !settled && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        if !settled {
            throw NSError(
                domain: "MarkdownExportRenderer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "生成Markdown PDF超时。"]
            )
        }
        if let outputError { throw outputError }
        return outputData ?? Data()
    }
}
#endif
#endif
