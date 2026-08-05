// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint render engine).
import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum TeachingPrintRenderEngine {
    static func renderPDFData(
        paragraphs: [TeachingPrintLayoutParagraph],
        layout: TeachingPrintLayoutResult,
        styleSheet: TeachingPrintStyleSheet
    ) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw NSError(
                domain: "TeachingPrintRenderEngine",
                code: 5001,
                userInfo: [NSLocalizedDescriptionKey: "无法创建PDF数据输出。"]
            )
        }
        var mediaBox = CGRect(x: 0, y: 0, width: layout.pageSpec.width, height: layout.pageSpec.height)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(
                domain: "TeachingPrintRenderEngine",
                code: 5002,
                userInfo: [NSLocalizedDescriptionKey: "无法创建PDF绘制上下文。"]
            )
        }

        for page in layout.pages {
            context.beginPDFPage(nil)
            context.setFillColor(styleSheet.pageBackgroundColor.cgColor)
            context.fill(mediaBox)
            draw(page: page, in: context, pageHeight: layout.pageSpec.height, paragraphs: paragraphs, styleSheet: styleSheet)
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    private static func draw(
        page: TeachingPrintLayoutPage,
        in context: CGContext,
        pageHeight: CGFloat,
        paragraphs: [TeachingPrintLayoutParagraph],
        styleSheet: TeachingPrintStyleSheet
    ) {
        for line in page.lines {
            guard paragraphs.indices.contains(line.paragraphIndex) else { continue }
            let paragraph = paragraphs[line.paragraphIndex]
            let typography = typographyStyle(for: paragraph.kind, from: styleSheet)

            if let stripe = line.stripeRect, paragraph.stripeEnabled, let stripeStyle = line.stripeStyle {
                let drawStripe = CGRect(
                    x: stripe.minX,
                    y: pageHeight - stripe.maxY,
                    width: stripe.width,
                    height: stripe.height
                )
                TeachingPrintDecorationRenderer.drawStripe(
                    in: context,
                    rect: drawStripe,
                    style: stripeStyle,
                    theme: .nodeMarkdown
                )
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .font: typography.font,
                .foregroundColor: typography.textColor
            ]
            if typography.isUnderline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            let attributed = NSAttributedString(string: line.text, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attributed as CFAttributedString)
            let baselineY = pageHeight - line.baselineY
            context.textPosition = CGPoint(x: line.frame.minX, y: baselineY)
            CTLineDraw(ctLine, context)
        }
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
}
