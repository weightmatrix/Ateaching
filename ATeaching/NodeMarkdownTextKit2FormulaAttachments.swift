// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif
#if canImport(SwiftMath)
import SwiftMath
import CoreText
#endif

#if os(macOS)
extension NodeMarkdownTextKit2TextView {
    static func applyFormulaAttachments(
        to storage: NSMutableAttributedString,
        source: NSString,
        contentRange: NSRange,
        baseFont: NSFont,
        textColor: NSColor,
        usesScreenMinimumFontSize: Bool = true
    ) -> [NSRange] {
        var protectedRanges: [NSRange] = []

        func applyFormulaPattern(
            _ pattern: String,
            mode: NodeMarkdownTextKit2FormulaRenderMode,
            fontSize: CGFloat
        ) {
            applyInlinePattern(pattern, source: source, contentRange: contentRange) { fullRange, innerRange in
                guard !overlapsAny(fullRange, protectedRanges) else { return }
                let latex = source.substring(with: innerRange)
                let sourceToken = source.substring(with: fullRange)
                guard let attachment = formulaAttachment(
                    latex: latex,
                    mode: mode,
                    textColor: textColor,
                    fontSize: fontSize,
                    baseFont: baseFont
                ) else {
                    applyDelimiterFade(to: storage, fullRange: fullRange, innerRange: innerRange, textColor: textColor)
                    return
                }

                prepareFormulaTokenForAttachment(
                    in: storage,
                    range: fullRange,
                    baseFont: baseFont,
                    sourceToken: sourceToken
                )
                storage.addAttributes(
                    [
                        .attachment: attachment,
                        .baselineOffset: 0
                    ],
                    range: NSRange(location: fullRange.location, length: 1)
                )
                protectedRanges.append(fullRange)
            }
        }

        let textFormulaSize = usesScreenMinimumFontSize ? max(baseFont.pointSize, 14) : max(1, baseFont.pointSize)
        let displayFormulaSize = usesScreenMinimumFontSize ? max(baseFont.pointSize * 1.2, 18) : max(1, baseFont.pointSize * 1.2)
        applyFormulaPattern(#"\$\$([^$\n]+)\$\$"#, mode: .display, fontSize: displayFormulaSize)
        applyFormulaPattern(#"(?<!\$)\$([^$\n]+)\$(?!\$)"#, mode: .text, fontSize: textFormulaSize)
        applyFormulaPattern(#"\\\(([^)\n]+)\\\)"#, mode: .text, fontSize: textFormulaSize)
        applyFormulaPattern(#"\\\[([^\]\n]+)\\\]"#, mode: .display, fontSize: displayFormulaSize)

        return protectedRanges
    }

    private static func formulaAttachment(
        latex: String,
        mode: NodeMarkdownTextKit2FormulaRenderMode,
        textColor: NSColor,
        fontSize: CGFloat,
        baseFont: NSFont
    ) -> NSTextAttachment? {
        #if canImport(SwiftMath)
        guard let image = formulaAttachmentImage(
            latex: latex,
            mode: mode,
            textColor: textColor,
            fontSize: fontSize
        ) else {
            return nil
        }
        let renderScale = max(1, formulaRenderScale)
        let width = image.size.width / renderScale
        let height = image.size.height / renderScale
        guard width > 0, height > 0 else { return nil }
        return NodeMarkdownTextKit2FormulaAttachment(
            image: image,
            width: width,
            height: height,
            baselineOriginY: formulaBaselineOriginY(height: height, baseFont: baseFont)
        )
        #else
        return nil
        #endif
    }

    private static func formulaBaselineOriginY(height: CGFloat, baseFont: NSFont) -> CGFloat {
        let textCenterY = (baseFont.ascender + baseFont.descender) * 0.5
        return textCenterY - height * 0.5
    }

    #if canImport(SwiftMath)
    private static func formulaAttachmentImage(
        latex: String,
        mode: NodeMarkdownTextKit2FormulaRenderMode,
        textColor: NSColor,
        fontSize: CGFloat
    ) -> NSImage? {
        let normalizedLatex = normalizedFormulaLatex(latex)
        let normalizedColor = formulaRenderColor(from: textColor)
        let cacheKey = NodeMarkdownTextKit2FormulaAttachmentCacheKey(
            latex: normalizedLatex,
            mode: mode == .display ? 1 : 0,
            fontSize: Int((fontSize * formulaRenderScale).rounded()),
            red: Int((normalizedColor.redComponent * 255).rounded()),
            green: Int((normalizedColor.greenComponent * 255).rounded()),
            blue: Int((normalizedColor.blueComponent * 255).rounded()),
            alpha: Int((normalizedColor.alphaComponent * 255).rounded())
        )
        if let cached = formulaAttachmentImageCache[cacheKey] {
            return cached
        }
        let imageBuilder = MTMathImage(
            latex: normalizedLatex,
            fontSize: fontSize * formulaRenderScale,
            textColor: normalizedColor,
            labelMode: mode == .display ? .display : .text,
            textAlignment: .left
        )
        imageBuilder.font?.fallbackFont = regularFormulaFallbackFont(size: fontSize * formulaRenderScale)
        let result = imageBuilder.asImage()
        guard result.0 == nil, let image = result.1 else { return nil }
        formulaAttachmentImageCache[cacheKey] = image
        return image
    }

    private static func formulaRenderColor(from textColor: NSColor) -> NSColor {
        let appearance = NSAppearance(named: .aqua)
        var resolved: NSColor?
        appearance?.performAsCurrentDrawingAppearance {
            resolved = textColor.usingColorSpace(.deviceRGB)
        }
        if resolved == nil {
            resolved = textColor.usingColorSpace(.deviceRGB)
        }
        return resolved ?? textColor
    }

    private static func normalizedFormulaLatex(_ latex: String) -> String {
        NodeMarkdownFormulaLatexNormalizer.normalize(latex)
    }

    private static func regularFormulaFallbackFont(size: CGFloat) -> CTFont {
        let preferred = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
        if CTFontGetGlyphCount(preferred) > 0 {
            return preferred
        }
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }
    #endif

    private static func prepareFormulaTokenForAttachment(
        in storage: NSMutableAttributedString,
        range: NSRange,
        baseFont: NSFont,
        sourceToken: String
    ) {
        guard range.length > 0 else { return }
        let attachmentAnchorRange = NSRange(location: range.location, length: 1)
        let currentAnchor = (storage.string as NSString).substring(with: attachmentAnchorRange)
        if currentAnchor != "\u{FFFC}" {
            storage.replaceCharacters(in: attachmentAnchorRange, with: "\u{FFFC}")
        }
        storage.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.clear,
                .kern: 0,
                .ligature: 0,
                .expansion: 0,
                nodeMarkdownTextKit2AttachmentSourceTokenKey: sourceToken
            ],
            range: range
        )
        if range.length > 1 {
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                    .kern: -2.0,
                    .ligature: 0
                ],
                range: NSRange(location: range.location + 1, length: range.length - 1)
            )
        }
    }
}
#endif
