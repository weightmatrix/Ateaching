// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
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

    static func blockVerticalInset(for layout: NodeMarkdownTextKit2RowLayout) -> CGFloat {
        layout.lineStyle.hasBackgroundBar
            ? NodeMarkdownRenderContract.default.layout.backgroundVerticalPadding
            : 0
    }

    static func emptyParagraphRect(
        for layout: NodeMarkdownTextKit2RowLayout,
        textContainerOrigin: NSPoint
    ) -> NSRect {
        let font = resolvedFont(for: layout.lineStyle.roleStyle)
        let paragraph = paragraphStyle(for: layout, font: font)
        let naturalHeight = ceil(max(1, font.ascender - font.descender + max(0, font.leading)))
        let lineHeight = max(naturalHeight, paragraph.minimumLineHeight)
        return NSRect(
            x: textContainerOrigin.x + renderedContentX(for: layout),
            y: textContainerOrigin.y + layout.spacingBefore,
            width: 0,
            height: lineHeight
        )
    }

}
#endif
