// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Representable {
    func makeConfiguredTextView(context: Context) -> NodeMarkdownTextKit2TextView {
        let textView = NodeMarkdownTextKit2TextView()
        textView.delegate = context.coordinator
        // 正文安装前不预设任何Node层级样式。载入后只由逐Node真实level设置。
        textView.insertionPointColor = .controlAccentColor
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]
        textView.postsFrameChangedNotifications = true
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "视图属性配置完成，尚未安装正文",
            textView: textView,
            bindingText: text,
            metadataCount: rowMetadata.count
        )
        return textView
    }

    func makeConfiguredScrollView(textView: NodeMarkdownTextKit2TextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.installNodeMarkdownDiagnostics19(in: scrollView)
        // NSViewRepresentable刚创建时尚未获得SwiftUI分配的尺寸，contentSize此时可能接近0。
        // 不得用这个临时值覆盖TextView的有效初始frame，否则整篇正文会被排进1pt容器而不可见。
        textView.minSize = .zero
        NodeMarkdownTextKit2Diagnostics.report(stage: "ScrollView连接完成", textView: textView)
        return scrollView
    }
}
#endif
