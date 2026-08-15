// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif
#if canImport(SwiftMath)
import SwiftMath
#endif

#if os(macOS)
extension NodeMarkdownTextKit2TextView {
    func applyNodeMarkdownStyle(
        to styled: NSMutableAttributedString,
        source nsText: NSString,
        layout: NodeMarkdownTextKit2RowLayout,
        documentStyle: NodeMarkdownDocumentStyle,
        baseDirectoryURL: URL?,
        searchQuery: String,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?,
        editingRowIndex: Int?,
        textLength: Int
    ) {
        guard let rowRange = layout.range.exact(toLength: textLength),
              rowRange.length > 0 else { return }

        let roleStyle = layout.lineStyle.roleStyle
        let font = Self.resolvedFont(for: roleStyle)
        let textColor = NSColor(roleStyle.renderedColor)

        applyBaseRowStyle(
            to: styled,
            layout: layout,
            rowRange: rowRange,
            font: font,
            textColor: textColor
        )

        guard let contentRange = layout.contentRange.exact(toLength: textLength),
              contentRange.length > 0 else {
            applySearchHighlightIfNeeded(
                to: styled,
                source: nsText,
                layout: layout,
                textLength: textLength,
                searchQuery: searchQuery,
                activeRowIndex: activeRowIndex,
                activeMatchLocationInRow: activeMatchLocationInRow
            )
            return
        }

        if layout.rowIndex == editingRowIndex {
            applySourceEditingStyle(
                to: styled,
                source: nsText,
                contentRange: contentRange,
                font: font,
                textColor: textColor
            )
        } else {
            applyRenderedStyle(
                to: styled,
                source: nsText,
                contentRange: contentRange,
                layout: layout,
                baseDirectoryURL: baseDirectoryURL,
                font: font,
                textColor: textColor
            )
        }

        applySearchHighlightIfNeeded(
            to: styled,
            source: nsText,
            layout: layout,
            textLength: textLength,
            searchQuery: searchQuery,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow
        )
    }

    private func applyBaseRowStyle(
        to styled: NSMutableAttributedString,
        layout: NodeMarkdownTextKit2RowLayout,
        rowRange: NSRange,
        font: NSFont,
        textColor: NSColor
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: Self.paragraphStyle(for: layout, font: font),
            .baselineOffset: 0
        ]
        if layout.lineStyle.roleStyle.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = NSColor.systemBlue
        }
        styled.addAttributes(
            attributes,
            range: rowRange
        )
        hideSourcePrefix(in: styled, layout: layout, rowRange: rowRange)
    }

    static func applyTextAttributesOfFollowingRowToPrecedingSeparator(
        in styled: NSMutableAttributedString,
        followingLayout: NodeMarkdownTextKit2RowLayout
    ) {
        let separatorLocation = followingLayout.range.location - 1
        guard separatorLocation >= 0,
              separatorLocation < styled.length,
              (styled.string as NSString).character(at: separatorLocation) == 10 else { return }

        let roleStyle = followingLayout.lineStyle.roleStyle
        var attributes: [NSAttributedString.Key: Any] = [
            .font: Self.resolvedFont(for: roleStyle),
            .foregroundColor: NSColor(roleStyle.renderedColor)
        ]
        if roleStyle.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = NSColor.systemBlue
        } else {
            attributes[.underlineStyle] = 0
            attributes[.underlineColor] = NSColor.clear
        }
        styled.addAttributes(
            attributes,
            range: NSRange(location: separatorLocation, length: 1)
        )
    }

    private func hideSourcePrefix(
        in styled: NSMutableAttributedString,
        layout: NodeMarkdownTextKit2RowLayout,
        rowRange: NSRange
    ) {
        let prefixLength = min(
            (layout.prefix as NSString).length,
            max(0, layout.contentRange.location - rowRange.location)
        )
        guard prefixLength > 0 else { return }
        styled.addAttribute(
            .foregroundColor,
            value: NSColor.clear,
            range: NSRange(location: rowRange.location, length: prefixLength)
        )
    }

    private func applySourceEditingStyle(
        to styled: NSMutableAttributedString,
        source nsText: NSString,
        contentRange: NSRange,
        font: NSFont,
        textColor: NSColor
    ) {
        styled.addAttributes(
            [
                .font: font,
                .foregroundColor: textColor
            ],
            range: contentRange
        )
        Self.applyInlineMarkdownStyles(
            to: styled,
            source: nsText,
            contentRange: contentRange,
            baseFont: font,
            textColor: textColor,
            protectedRanges: [],
            hideHTMLDelimiters: false
        )
    }

    private func applyRenderedStyle(
        to styled: NSMutableAttributedString,
        source nsText: NSString,
        contentRange: NSRange,
        layout: NodeMarkdownTextKit2RowLayout,
        baseDirectoryURL: URL?,
        font: NSFont,
        textColor: NSColor
    ) {
        let formulaRanges = Self.applyFormulaAttachments(
            to: styled,
            source: nsText,
            contentRange: contentRange,
            baseFont: font,
            textColor: textColor,
            usesScreenMinimumFontSize: usesScreenMinimumFormulaFontSize
        )
        let imageRanges = Self.applyImageAttachments(
            to: styled,
            source: nsText,
            contentRange: contentRange,
            baseDirectoryURL: baseDirectoryURL,
            baseFont: font,
            maxWidth: maxImageWidth(for: layout)
        )
        Self.applyInlineMarkdownStyles(
            to: styled,
            source: nsText,
            contentRange: contentRange,
            baseFont: font,
            textColor: textColor,
            protectedRanges: formulaRanges + imageRanges,
            hideHTMLDelimiters: true
        )
    }

    private func applySearchHighlightIfNeeded(
        to styled: NSMutableAttributedString,
        source nsText: NSString,
        layout: NodeMarkdownTextKit2RowLayout,
        textLength: Int,
        searchQuery: String,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?
    ) {
        Self.applySearchHighlights(
            to: styled,
            source: nsText,
            layout: layout,
            textLength: textLength,
            searchQuery: searchQuery,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow
        )
    }
}
#endif
