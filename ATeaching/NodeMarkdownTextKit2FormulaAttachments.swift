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
struct NodeMarkdownTextKit2FormulaMetrics {
    let baselineAscent: CGFloat
    let baselineDescent: CGFloat
    let width: CGFloat
    let imageOriginY: CGFloat
}

extension NodeMarkdownTextKit2TextView {
    /// 不能使用systemFont(ofSize: 0)：AppKit会把0解释成默认13pt，
    /// 导致透明公式源码继续占据完整宽度。0.001pt可保留1:1字符位置，
    /// 同时把残余宽度压到亚像素级，实际行宽只由公式附件决定。
    private static let collapsedFormulaSourceFontSize: CGFloat = 0.001

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
                guard let (image, metrics) = renderedFormula(
                    latex: latex,
                    mode: mode,
                    textColor: textColor,
                    fontSize: fontSize,
                    baseFont: baseFont
                ) else {
                    applyDelimiterFade(to: storage, fullRange: fullRange, innerRange: innerRange, textColor: textColor)
                    return
                }

                let attachment = NodeMarkdownTextKit2FormulaAttachment(
                    image: image,
                    width: metrics.width,
                    imageHeight: image.size.height / max(1, formulaRenderScale),
                    baselineOriginY: metrics.imageOriginY,
                    formulaAscent: metrics.baselineAscent,
                    formulaDescent: metrics.baselineDescent
                )
                prepareFormulaTokenForAttachment(
                    in: storage,
                    range: fullRange,
                    baseFont: baseFont,
                    sourceToken: sourceToken
                )
                storage.addAttributes(
                    [.attachment: attachment, .baselineOffset: 0],
                    range: NSRange(location: fullRange.location, length: 1)
                )
                NodeMarkdownTextKit2Diagnostics.log("公式附件安装：源码UTF16长度=\(fullRange.length)，渲染宽度=\(String(format: "%.2f", metrics.width))，图片高度=\(String(format: "%.2f", image.size.height / max(1, formulaRenderScale)))，透明源码字号=\(collapsedFormulaSourceFontSize)。")
                protectedRanges.append(fullRange)
            }
        }

        let formulaFontSize = baseFont.pointSize
        let displayFormulaSize = baseFont.pointSize * 1.2
        applyFormulaPattern(#"\$\$([^$\n]+)\$\$"#, mode: .display, fontSize: displayFormulaSize)
        applyFormulaPattern(#"(?<!\$)\$([^$\n]+)\$(?!\$)"#, mode: .text, fontSize: formulaFontSize)
        applyFormulaPattern(#"\\\(([^)\n]+)\\\)"#, mode: .text, fontSize: formulaFontSize)
        applyFormulaPattern(#"\\\[([^\]\n]+)\\\]"#, mode: .display, fontSize: displayFormulaSize)

        return protectedRanges
    }

    #if canImport(SwiftMath)
    private static func renderedFormula(
        latex: String,
        mode: NodeMarkdownTextKit2FormulaRenderMode,
        textColor: NSColor,
        fontSize: CGFloat,
        baseFont: NSFont
    ) -> (NSImage, NodeMarkdownTextKit2FormulaMetrics)? {
        let normalizedLatex = normalizedFormulaLatex(latex)
        let normalizedColor = formulaRenderColor(from: textColor)
        let scale = max(1, formulaRenderScale)
        let scaledSize = fontSize * scale

        let cacheKey = NodeMarkdownTextKit2FormulaAttachmentCacheKey(
            latex: normalizedLatex,
            mode: mode == .display ? 1 : 0,
            fontSize: Int(scaledSize.rounded()),
            red: Int((normalizedColor.redComponent * 255).rounded()),
            green: Int((normalizedColor.greenComponent * 255).rounded()),
            blue: Int((normalizedColor.blueComponent * 255).rounded()),
            alpha: Int((normalizedColor.alphaComponent * 255).rounded())
        )
        if let cached = cachedFormulaResult[cacheKey] {
            return cached
        }

        let imageBuilder = MTMathImage(
            latex: normalizedLatex,
            fontSize: scaledSize,
            textColor: normalizedColor,
            labelMode: mode == .display ? .display : .text,
            textAlignment: .left
        )
        imageBuilder.font?.fallbackFont = regularFormulaFallbackFont(size: scaledSize)
        let result = imageBuilder.asImage()
        guard result.0 == nil, let image = result.1 else { return nil }

        let rawAscent = imageBuilder.mathAscent
        let rawDescent = imageBuilder.mathDescent
        let rawWidth = image.size.width
        let axisHeight: CGFloat
        if mode == .text {
            axisHeight = baseFont.xHeight * 0.5 * scale
        } else {
            axisHeight = (baseFont.ascender + baseFont.descender) * 0.5 * scale
        }

        // Math axis position from image bottom (MTMathImage centers vertically)
        let sumHeight = rawAscent + rawDescent
        let axisFromBottom: CGFloat
        if sumHeight >= scaledSize * 0.5 {
            axisFromBottom = rawDescent
        } else {
            axisFromBottom = (sumHeight - scaledSize * 0.5) * 0.5 + rawDescent
        }

        let originY = axisHeight - axisFromBottom
        let metrics = NodeMarkdownTextKit2FormulaMetrics(
            baselineAscent: (axisHeight + rawAscent) / scale,
            baselineDescent: max(0, (rawDescent - axisHeight)) / scale,
            width: rawWidth / scale,
            imageOriginY: originY / scale
        )

        guard metrics.width > 0, (metrics.baselineAscent + metrics.baselineDescent) > 0 else { return nil }

        let output = (image, metrics)
        cachedFormulaResult[cacheKey] = output
        return output
    }

    private static var cachedFormulaResult: [NodeMarkdownTextKit2FormulaAttachmentCacheKey: (NSImage, NodeMarkdownTextKit2FormulaMetrics)] = [:]


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
        if CTFontGetGlyphCount(preferred) > 0 { return preferred }
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
        let anchorRange = NSRange(location: range.location, length: 1)
        let currentAnchor = (storage.string as NSString).substring(with: anchorRange)
        if currentAnchor != "\u{FFFC}" {
            storage.replaceCharacters(in: anchorRange, with: "\u{FFFC}")
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
            let collapsedFont = NSFont.monospacedSystemFont(
                ofSize: collapsedFormulaSourceFontSize,
                weight: .regular
            )
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: collapsedFont,
                    .kern: 0,
                    .ligature: 0,
                    .expansion: 0
                ],
                range: NSRange(location: range.location + 1, length: range.length - 1)
            )
        }
    }
}
#endif
