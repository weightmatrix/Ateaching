// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// 首帧只请求TextKit2当前视口，不执行全文ensureLayout。
    func prepareViewport(
        in textView: NodeMarkdownTextKit2TextView,
        scrollView: NSScrollView
    ) {
        NodeMarkdownTextKit2Diagnostics.report(stage: "视口同步准备前", textView: textView)
        configureViewportGeometry(in: textView, scrollView: scrollView)
        textView.nodeTextLayoutManager.textViewportLayoutController.layoutViewport()
        textView.invalidateNodeMarkdownDecorationsAfterViewportLayout()
        NodeMarkdownTextKit2Diagnostics.report(stage: "视口同步准备后", textView: textView)

        DispatchQueue.main.async { [weak textView, weak scrollView] in
            guard let textView, let scrollView else { return }
            // 到下一轮主线程时SwiftUI已经给NSScrollView真实尺寸。这里再次配置，
            // 首帧因此既不会使用0宽度，也无需对整篇文档执行布局。
            self.configureViewportGeometry(in: textView, scrollView: scrollView)
            let viewportController = textView.nodeTextLayoutManager.textViewportLayoutController
            viewportController.layoutViewport()
            textView.invalidateNodeMarkdownDecorationsAfterViewportLayout()
            NodeMarkdownTextKit2Diagnostics.report(stage: "视口异步真实尺寸准备后", textView: textView)
            #if DEBUG
            if !textView.documentString().isEmpty {
                assert(
                    viewportController.viewportRange != nil || !scrollView.contentView.bounds.isEmpty,
                    "TextKit2 failed to establish its first viewport"
                )
            }
            #endif
        }
    }

    private func configureViewportGeometry(
        in textView: NodeMarkdownTextKit2TextView,
        scrollView: NSScrollView
    ) {
        let measuredWidth = scrollView.contentView.bounds.width
        let viewportWidth: CGFloat
        if measuredWidth > 1 {
            viewportWidth = measuredWidth
        } else if textView.frame.width > 1 {
            viewportWidth = textView.frame.width
        } else {
            viewportWidth = 720
        }

        if abs(textView.frame.width - viewportWidth) > 0.5 {
            textView.setFrameSize(
                NSSize(
                    width: viewportWidth,
                    height: max(1, textView.frame.height)
                )
            )
        }
        textView.nodeTextContainer.size = NSSize(
            width: max(1, viewportWidth - textView.textContainerInset.width * 2),
            height: CGFloat.greatestFiniteMagnitude
        )
    }
}
#endif
