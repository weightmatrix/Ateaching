// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Representable {
    func makeConfiguredTextView(context: Context) -> NodeMarkdownTextKit2TextView {
        let textView = NodeMarkdownTextKit2TextView()
        textView.delegate = context.coordinator
        textView.replaceDocumentText(text, documentStyle: documentStyle)
        let baseStyle = documentStyle.style(forLevel: 7)
        textView.font = NSFont(name: baseStyle.fontName, size: baseStyle.fontSize) ?? NSFont.monospacedSystemFont(ofSize: baseStyle.fontSize, weight: .regular)
        textView.textColor = NSColor(baseStyle.renderedColor)
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
        return scrollView
    }
}
#endif
