// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    static func baseAttributes(for documentStyle: NodeMarkdownDocumentStyle) -> [NSAttributedString.Key: Any] {
        let baseStyle = documentStyle.style(forLevel: 7)
        let font = resolvedFont(for: baseStyle)
        return [
            .font: font,
            .foregroundColor: NSColor(baseStyle.renderedColor)
        ]
    }

    static func resolvedFont(for style: NodeMarkdownRoleStyle) -> NSFont {
        var font = NSFont(name: style.fontName, size: style.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .regular)
        if style.isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        return font
    }

    static func markerFont(for roleStyle: NodeMarkdownRoleStyle) -> NSFont {
        resolvedFont(for: roleStyle)
    }

    static func markerDisplayWidth(for layout: NodeMarkdownTextKit2RowLayout) -> CGFloat {
        let marker = layout.lineStyle.iconGlyph
        guard !marker.isEmpty else { return layout.lineStyle.markerWidth }
        let markerFont = markerFont(for: layout.lineStyle.roleStyle)
        let markerWidth = (marker as NSString).size(withAttributes: [.font: markerFont]).width
        return max(1, markerWidth)
    }

    static func renderedContentX(for layout: NodeMarkdownTextKit2RowLayout) -> CGFloat {
        layout.lineStyle.contentX
    }

    static func paragraphStyle(for layout: NodeMarkdownTextKit2RowLayout, font: NSFont) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let contentX = renderedContentX(for: layout)
        let prefixWidth = (layout.prefix as NSString).size(withAttributes: [.font: font]).width
        paragraph.firstLineHeadIndent = max(0, contentX - prefixWidth)
        paragraph.headIndent = contentX
        paragraph.paragraphSpacingBefore = layout.spacingBefore
        paragraph.paragraphSpacing = 0
        paragraph.lineSpacing = max(0, CGFloat(layout.lineStyle.roleStyle.peerLineSpacing))
        paragraph.minimumLineHeight = max(0, font.ascender - font.descender + 4)
        return paragraph
    }

    static func defaultParagraphStyle(documentStyle: NodeMarkdownDocumentStyle) -> NSParagraphStyle {
        let baseStyle = documentStyle.style(forLevel: 7)
        let lineStyle = NodeMarkdownRenderContract.default.lineStyle(level: 7, prefix: "", documentStyle: documentStyle)
        let font = resolvedFont(for: baseStyle)
        let layout = NodeMarkdownTextKit2RowLayout(
            rowIndex: 0,
            range: NSRange(location: 0, length: 0),
            contentRange: NSRange(location: 0, length: 0),
            prefix: "",
            level: 7,
            lineStyle: lineStyle,
            spacingBefore: 0,
            isProtectedH3: false
        )
        return paragraphStyle(for: layout, font: font)
    }
}
#endif
