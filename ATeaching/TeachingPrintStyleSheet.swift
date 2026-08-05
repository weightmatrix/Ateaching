// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint style sheet).
import Foundation
import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
typealias TeachingPrintColor = NSColor
typealias TeachingPrintFont = NSFont
#else
import UIKit
typealias TeachingPrintColor = UIColor
typealias TeachingPrintFont = UIFont
#endif

struct TeachingPrintPageSpec: Sendable, Hashable {
    var width: CGFloat
    var height: CGFloat
    var marginTop: CGFloat
    var marginRight: CGFloat
    var marginBottom: CGFloat
    var marginLeft: CGFloat

    static let a4 = TeachingPrintPageSpec(
        width: 595,
        height: 842,
        marginTop: 36,
        marginRight: 36,
        marginBottom: 36,
        marginLeft: 36
    )

    var contentWidth: CGFloat { max(1, width - marginLeft - marginRight) }
    var contentHeight: CGFloat { max(1, height - marginTop - marginBottom) }
}

struct TeachingPrintTypographyStyle {
    var font: TeachingPrintFont
    var textColor: TeachingPrintColor
    var isUnderline: Bool = false
    var lineSpacing: CGFloat
    var paragraphSpacingBefore: CGFloat
    var paragraphSpacingAfter: CGFloat
}

struct TeachingPrintBackgroundStripeStyle: Hashable, Sendable {
    var fillColorHexRGBA: String
    var cornerRadius: CGFloat
    var horizontalInset: CGFloat
    var verticalInset: CGFloat
}

struct TeachingPrintStyleSheet {
    var pageSpec: TeachingPrintPageSpec
    var pageBackgroundColor: TeachingPrintColor
    var body: TeachingPrintTypographyStyle
    var heading1: TeachingPrintTypographyStyle
    var heading2: TeachingPrintTypographyStyle
    var heading3: TeachingPrintTypographyStyle
    var heading4: TeachingPrintTypographyStyle
    var heading5: TeachingPrintTypographyStyle
    var heading6: TeachingPrintTypographyStyle
    var comment: TeachingPrintTypographyStyle
    var bodyStripe: TeachingPrintBackgroundStripeStyle?
    var heading3Stripe: TeachingPrintBackgroundStripeStyle?
    var heading4Stripe: TeachingPrintBackgroundStripeStyle?
    var heading5Stripe: TeachingPrintBackgroundStripeStyle?
    var pageBreakSnapTolerance: CGFloat

    static var `default`: TeachingPrintStyleSheet {
        TeachingPrintStyleSheet(
            pageSpec: .a4,
            pageBackgroundColor: .white,
            body: .init(
                font: .systemFont(ofSize: 13),
                textColor: .labelColorCompat,
                lineSpacing: 3,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 6
            ),
            heading1: .init(
                font: .boldSystemFont(ofSize: 22),
                textColor: .labelColorCompat,
                lineSpacing: 5,
                paragraphSpacingBefore: 10,
                paragraphSpacingAfter: 8
            ),
            heading2: .init(
                font: .boldSystemFont(ofSize: 18),
                textColor: .labelColorCompat,
                lineSpacing: 4,
                paragraphSpacingBefore: 8,
                paragraphSpacingAfter: 6
            ),
            heading3: .init(
                font: .boldSystemFont(ofSize: 15),
                textColor: .labelColorCompat,
                lineSpacing: 3,
                paragraphSpacingBefore: 6,
                paragraphSpacingAfter: 4
            ),
            heading4: .init(
                font: .systemFont(ofSize: 14),
                textColor: .labelColorCompat,
                lineSpacing: 3,
                paragraphSpacingBefore: 4,
                paragraphSpacingAfter: 4
            ),
            heading5: .init(
                font: .systemFont(ofSize: 13),
                textColor: .labelColorCompat,
                lineSpacing: 3,
                paragraphSpacingBefore: 3,
                paragraphSpacingAfter: 3
            ),
            heading6: .init(
                font: .systemFont(ofSize: 12),
                textColor: .labelColorCompat,
                lineSpacing: 2,
                paragraphSpacingBefore: 2,
                paragraphSpacingAfter: 2
            ),
            comment: .init(
                font: .systemFont(ofSize: 12),
                textColor: .secondaryLabelColorCompat,
                lineSpacing: 2,
                paragraphSpacingBefore: 2,
                paragraphSpacingAfter: 2
            ),
            bodyStripe: nil,
            heading3Stripe: .init(
                fillColorHexRGBA: "#F3F6FBFF",
                cornerRadius: 4,
                horizontalInset: 0,
                verticalInset: 1
            ),
            heading4Stripe: .init(
                fillColorHexRGBA: "#F3F6FBFF",
                cornerRadius: 4,
                horizontalInset: 0,
                verticalInset: 1
            ),
            heading5Stripe: .init(
                fillColorHexRGBA: "#F3F6FBFF",
                cornerRadius: 4,
                horizontalInset: 0,
                verticalInset: 1
            ),
            pageBreakSnapTolerance: 12
        )
    }
}

extension TeachingPrintStyleSheet {
    static func make(
        documentStyle: NodeMarkdownDocumentStyle,
        pdfSettings: TeachingPDFExportSettings
    ) -> TeachingPrintStyleSheet {
        let normalized = pdfSettings.normalized()
        let pageSpec: TeachingPrintPageSpec = {
            let base: (CGFloat, CGFloat)
            switch normalized.paperPreset {
            case .a4:
                base = (595, 842)
            case .letter:
                base = (612, 792)
            case .custom:
                base = (CGFloat(normalized.customWidth), CGFloat(normalized.customHeight))
            }
            let size: (CGFloat, CGFloat) = {
                switch normalized.orientation {
                case .portrait:
                    return base
                case .landscape:
                    return (base.1, base.0)
                }
            }()
            return TeachingPrintPageSpec(
                width: size.0,
                height: size.1,
                marginTop: CGFloat(normalized.marginTop),
                marginRight: CGFloat(normalized.marginRight),
                marginBottom: CGFloat(normalized.marginBottom),
                marginLeft: CGFloat(normalized.marginLeft)
            )
        }()
        let scale = CGFloat(max(0.1, min(1.0, normalized.nodeMarkdownScalePercent / 100)))
        let exportScheme = documentStyle.preferredScheme.resolvedExportScheme
        let h1 = typography(from: documentStyle.h1, scale: scale, exportScheme: exportScheme)
        let h2 = typography(from: documentStyle.h2, scale: scale, exportScheme: exportScheme)
        let h3 = typography(from: documentStyle.h3, scale: scale, exportScheme: exportScheme)
        let h4 = typography(from: documentStyle.h4, scale: scale, exportScheme: exportScheme)
        let h5 = typography(from: documentStyle.h5, scale: scale, exportScheme: exportScheme)
        let h6 = typography(from: documentStyle.h6, scale: scale, exportScheme: exportScheme)
        let body = typography(from: documentStyle.body1, scale: scale, exportScheme: exportScheme)
        let comment = typography(from: documentStyle.comment, scale: scale, exportScheme: exportScheme)
        let stripeScale = scale
        let makeStripe: (Bool) -> TeachingPrintBackgroundStripeStyle? = { enabled in
            guard enabled else { return nil }
            return TeachingPrintBackgroundStripeStyle(
                fillColorHexRGBA: "#F3F6FBFF",
                cornerRadius: max(1, 4 * stripeScale),
                horizontalInset: 0,
                verticalInset: max(0, 1 * stripeScale)
            )
        }
        return TeachingPrintStyleSheet(
            pageSpec: pageSpec,
            pageBackgroundColor: documentStyle.useSystemBackground
                ? (exportScheme == .dark ? .black : .white)
                : platformColor(from: documentStyle.editorBackgroundColor, exportScheme: exportScheme),
            body: body,
            heading1: h1,
            heading2: h2,
            heading3: h3,
            heading4: h4,
            heading5: h5,
            heading6: h6,
            comment: comment,
            bodyStripe: nil,
            heading3Stripe: makeStripe(documentStyle.h3.hasBackgroundBar),
            heading4Stripe: makeStripe(documentStyle.h4.hasBackgroundBar),
            heading5Stripe: makeStripe(documentStyle.h5.hasBackgroundBar),
            pageBreakSnapTolerance: max(8, 12 * scale)
        )
    }

    private static func typography(
        from roleStyle: NodeMarkdownRoleStyle,
        scale: CGFloat,
        exportScheme: NodeMarkdownPreferredScheme
    ) -> TeachingPrintTypographyStyle {
        let size = CGFloat(max(8, roleStyle.fontSize)) * scale
        let font = buildFont(name: roleStyle.fontName, size: size, bold: roleStyle.isBold)
        let color = platformColor(from: roleStyle.renderedColor, exportScheme: exportScheme)
        return TeachingPrintTypographyStyle(
            font: font,
            textColor: color,
            isUnderline: roleStyle.isUnderline,
            lineSpacing: CGFloat(roleStyle.peerLineSpacing) * scale,
            paragraphSpacingBefore: CGFloat(roleStyle.paragraphSpacingBefore) * scale,
            paragraphSpacingAfter: CGFloat(roleStyle.paragraphSpacingAfter) * scale
        )
    }

    private static func buildFont(name: String, size: CGFloat, bold: Bool) -> TeachingPrintFont {
        #if os(macOS)
        let base = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        if bold {
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        }
        return base
        #else
        if let custom = UIFont(name: name, size: size) {
            if bold, let desc = custom.fontDescriptor.withSymbolicTraits(.traitBold) {
                return UIFont(descriptor: desc, size: size)
            }
            return custom
        }
        return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        #endif
    }

    private static func platformColor(
        from color: Color,
        exportScheme: NodeMarkdownPreferredScheme
    ) -> TeachingPrintColor {
        #if os(macOS)
        let appearance = NSAppearance(named: exportScheme == .dark ? .darkAqua : .aqua)
        var resolved: NSColor?
        appearance?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return resolved ?? NSColor(color)
        #else
        let traits = UITraitCollection(userInterfaceStyle: exportScheme == .dark ? .dark : .light)
        return UIColor(color).resolvedColor(with: traits)
        #endif
    }
}

private extension TeachingPrintColor {
    static var labelColorCompat: TeachingPrintColor {
        #if os(macOS)
        return .labelColor
        #else
        return .label
        #endif
    }

    static var secondaryLabelColorCompat: TeachingPrintColor {
        #if os(macOS)
        return .secondaryLabelColor
        #else
        return .secondaryLabel
        #endif
    }
}
