// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    func defaultTypingAttributes(documentStyle: NodeMarkdownDocumentStyle) -> [NSAttributedString.Key: Any] {
        Self.baseAttributes(for: documentStyle).merging(
            [.paragraphStyle: Self.defaultParagraphStyle(documentStyle: documentStyle)],
            uniquingKeysWith: { _, new in new }
        )
    }

    func typingAttributes(
        for layout: NodeMarkdownTextKit2RowLayout,
        documentStyle: NodeMarkdownDocumentStyle
    ) -> [NSAttributedString.Key: Any] {
        let roleStyle = layout.lineStyle.roleStyle
        let font = Self.resolvedFont(for: roleStyle)
        return [
            .font: font,
            .foregroundColor: NSColor(roleStyle.renderedColor),
            .paragraphStyle: Self.paragraphStyle(for: layout, font: font)
        ]
    }
}
#endif
