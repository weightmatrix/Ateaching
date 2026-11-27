import SwiftUI
import WebKit

struct TeachingScheduleWebView: View {
    @State private var reloadID = UUID()
    @State private var failure: String?

    var body: some View {
        ScheduleWebSurface { failure = $0 }
            .id(reloadID)
            .overlay {
                if let failure {
                    VStack(spacing: 12) {
                        Text("排课网加载失败").font(.headline)
                        Text(failure).foregroundStyle(.secondary)
                        Button("重新加载") {
                            self.failure = nil
                            reloadID = UUID()
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
    }
}

private struct ScheduleWebSurface {
    let onFailure: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }

    func makeWebView(coordinator: Coordinator) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        view.load(URLRequest(url: URL(string: "https://zhibenwang.com/app/")!))
        return view
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onFailure: (String?) -> Void

        init(onFailure: @escaping (String?) -> Void) {
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFailure(nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onFailure("网页进程已结束。")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(isScheduleURL(action.request.url) ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for action: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if action.targetFrame == nil, isScheduleURL(action.request.url) {
                webView.load(action.request)
            }
            return nil
        }

        private func report(_ error: Error) {
            let error = error as NSError
            guard error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled else { return }
            onFailure(error.localizedDescription)
        }

        private func isScheduleURL(_ url: URL?) -> Bool {
            url?.scheme == "https" && url?.host == "zhibenwang.com" &&
                (url?.port == nil || url?.port == 443)
        }
    }
}

#if os(macOS)
extension ScheduleWebSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
extension ScheduleWebSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
