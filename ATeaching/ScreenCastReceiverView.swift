import SwiftUI

#if os(macOS)
import AppKit
import WebKit
#else
import UIKit
import WebKit
#endif

struct ScreenCastReceiverView: View {
    let document: NodeMarkdownDocument
    @ObservedObject var service: ScreenCastService
    @State private var isAnnotationActive = false
    @StateObject private var annotationController = TeachingAnnotationController()

    private var studentName: String { service.receivedStudentName ?? "学生" }
    private var annotationColor: Color { service.annotationColor(for: service.receivedStudentName) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("接收自: \(studentName)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isAnnotationActive.toggle()
                    if isAnnotationActive {
                        annotationController.isActive = true
                        annotationController.tool = .pen
                    } else {
                        annotationController.clearAll()
                    }
                } label: {
                    Label("批注", systemImage: "pencil.tip")
                }
                .buttonStyle(.bordered)
                .tint(isAnnotationActive ? annotationColor : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ZStack {
                ScreenCastDocumentView(html: rowsHTML)

                if isAnnotationActive {
                    TeachingAnnotationCanvasHost(controller: annotationController)
                        .allowsHitTesting(true)
                }
            }
        }
    }

    private var rowsHTML: String {
        let displayDoc = document.nodes.isEmpty
            ? NodeMarkdownDocument(nodes: [NodeMarkdownNode(level: 1, text: "等待投屏内容...")])
            : document
        return NodeMarkdownHTMLBuilder.buildRows(
            document: displayDoc,
            style: NodeMarkdownDocumentStyle()
        )
    }
}

#if os(macOS)
private struct ScreenCastDocumentView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let webView = WKWebView()
        scrollView.documentView = webView
        webView.loadHTMLString(NodeMarkdownHTMLBuilder.documentHTML(initialRowsHTML: html), baseURL: nil)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
#else
private struct ScreenCastDocumentView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.loadHTMLString(NodeMarkdownHTMLBuilder.documentHTML(initialRowsHTML: html), baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
