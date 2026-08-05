// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint layout engine).
import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct TeachingPrintLayoutParagraph {
    enum Kind: Sendable, Hashable {
        case body
        case heading1
        case heading2
        case heading3
        case heading4
        case heading5
        case heading6
        case comment
    }

    var text: String
    var kind: Kind
    var stripeEnabled: Bool
}

struct TeachingPrintLayoutLine: Sendable, Hashable {
    var paragraphIndex: Int
    var textRange: NSRange
    var text: String
    var frame: CGRect
    var baselineY: CGFloat
    var stripeRect: CGRect?
    var stripeStyle: TeachingPrintBackgroundStripeStyle?
}

struct TeachingPrintLayoutPage: Sendable, Hashable {
    var index: Int
    var contentRect: CGRect
    var lines: [TeachingPrintLayoutLine]
}

struct TeachingPrintLayoutResult: Sendable, Hashable {
    var pageSpec: TeachingPrintPageSpec
    var pages: [TeachingPrintLayoutPage]
}

enum TeachingPrintLayoutEngine {
    static func layout(
        paragraphs: [TeachingPrintLayoutParagraph],
        styleSheet: TeachingPrintStyleSheet = .default
    ) -> TeachingPrintLayoutResult {
        let contentRect = CGRect(
            x: styleSheet.pageSpec.marginLeft,
            y: styleSheet.pageSpec.marginTop,
            width: styleSheet.pageSpec.contentWidth,
            height: styleSheet.pageSpec.contentHeight
        )
        var pages: [TeachingPrintLayoutPage] = []
        var currentLines: [TeachingPrintLayoutLine] = []
        var pageIndex = 0
        var cursorY = contentRect.minY

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let typography = typographyStyle(for: paragraph.kind, from: styleSheet)
            let stripeStyle = stripeStyle(for: paragraph.kind, from: styleSheet, enabled: paragraph.stripeEnabled)
            cursorY += typography.paragraphSpacingBefore

            let attributed = attributedString(for: paragraph.text, style: typography)
            let ctText = attributed as CFAttributedString
            let typesetter = CTTypesetterCreateWithAttributedString(ctText)
            let fullNSString = paragraph.text as NSString

            var location = 0
            let paragraphLength = fullNSString.length
            while location < paragraphLength {
                let count = CTTypesetterSuggestLineBreak(typesetter, location, Double(contentRect.width))
                let safeCount = max(1, count)
                let range = CFRange(location: location, length: safeCount)
                let line = CTTypesetterCreateLine(typesetter, range)

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
                let lineHeight = max(typography.font.pointSize, ceil(ascent + descent + leading)) + typography.lineSpacing

                let requiredHeight = lineHeight + styleSheet.pageBreakSnapTolerance
                if cursorY + requiredHeight > contentRect.maxY, !currentLines.isEmpty {
                    pages.append(
                        TeachingPrintLayoutPage(
                            index: pageIndex,
                            contentRect: contentRect,
                            lines: currentLines
                        )
                    )
                    pageIndex += 1
                    currentLines.removeAll(keepingCapacity: true)
                    cursorY = contentRect.minY
                }

                let frame = CGRect(
                    x: contentRect.minX,
                    y: cursorY,
                    width: contentRect.width,
                    height: lineHeight
                )
                let baselineY = frame.minY + ascent
                let slice = fullNSString.substring(with: NSRange(location: location, length: safeCount))
                let stripeRect: CGRect? = {
                    guard paragraph.stripeEnabled, let stripeStyle else { return nil }
                    let contentRightPadding: CGFloat = 28
                    let leadingTrimCount = slice.prefix { $0 == " " || $0 == "\t" }.count
                    let leadingOffset = leadingTrimCount > 0
                        ? CGFloat(CTLineGetOffsetForStringIndex(line, leadingTrimCount, nil))
                        : 0
                    let textStartX = frame.minX + max(0, leadingOffset) - 4
                    let textBodyWidth = max(1, ceil(lineWidth - max(0, leadingOffset)))
                    let requestedWidth = textBodyWidth + 22
                    let maxWidth = max(24, contentRect.maxX - textStartX - contentRightPadding)
                    let stripeWidth = min(maxWidth, requestedWidth)
                    let stripeHeight = max(1, lineHeight - stripeStyle.verticalInset * 2)
                    return CGRect(
                        x: textStartX,
                        y: frame.minY + stripeStyle.verticalInset,
                        width: stripeWidth,
                        height: stripeHeight
                    )
                }()
                currentLines.append(
                    TeachingPrintLayoutLine(
                        paragraphIndex: paragraphIndex,
                        textRange: NSRange(location: location, length: safeCount),
                        text: slice,
                        frame: frame,
                        baselineY: baselineY,
                        stripeRect: stripeRect,
                        stripeStyle: stripeStyle
                    )
                )

                cursorY += lineHeight
                location += safeCount
            }

            cursorY += typography.paragraphSpacingAfter
        }

        if !currentLines.isEmpty || pages.isEmpty {
            pages.append(
                TeachingPrintLayoutPage(
                    index: pageIndex,
                    contentRect: contentRect,
                    lines: currentLines
                )
            )
        }
        return TeachingPrintLayoutResult(pageSpec: styleSheet.pageSpec, pages: pages)
    }

    private static func typographyStyle(
        for kind: TeachingPrintLayoutParagraph.Kind,
        from sheet: TeachingPrintStyleSheet
    ) -> TeachingPrintTypographyStyle {
        switch kind {
        case .body:
            return sheet.body
        case .heading1:
            return sheet.heading1
        case .heading2:
            return sheet.heading2
        case .heading3:
            return sheet.heading3
        case .heading4:
            return sheet.heading4
        case .heading5:
            return sheet.heading5
        case .heading6:
            return sheet.heading6
        case .comment:
            return sheet.comment
        }
    }

    private static func stripeStyle(
        for kind: TeachingPrintLayoutParagraph.Kind,
        from sheet: TeachingPrintStyleSheet,
        enabled: Bool
    ) -> TeachingPrintBackgroundStripeStyle? {
        guard enabled else { return nil }
        switch kind {
        case .heading3:
            return sheet.heading3Stripe
        case .heading4:
            return sheet.heading4Stripe
        case .heading5:
            return sheet.heading5Stripe
        case .body:
            return sheet.bodyStripe
        case .heading1, .heading2, .heading6, .comment:
            return nil
        }
    }

    private static func attributedString(
        for text: String,
        style: TeachingPrintTypographyStyle
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = style.lineSpacing
        paragraph.paragraphSpacing = style.paragraphSpacingAfter
        paragraph.paragraphSpacingBefore = style.paragraphSpacingBefore
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.textColor,
            .paragraphStyle: paragraph
        ]
        if style.isUnderline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: text, attributes: attrs)
    }
}
