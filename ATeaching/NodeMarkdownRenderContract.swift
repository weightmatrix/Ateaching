import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - NodeMarkdown渲染契约 - v1 - 统一编辑器与导出使用的行级视觉参数
struct NodeMarkdownRenderContract: Hashable {
    /// 背景条在编辑器、HTML 和 PDF 中共用的唯一饱和度规则。
    /// 这里表示在层级文字颜色上增加 10%，导出器不得再二次增强。
    static let backgroundSaturationMultiplier: CGFloat = 1.1

    struct Layout: Hashable {
        var leadingPadding: CGFloat = 16
        var levelIndentStep: CGFloat = 18
        var markerWidth: CGFloat = 16
        var markerGap: CGFloat = 6
        var backgroundCornerRadius: CGFloat = 8
        var backgroundHorizontalPadding: CGFloat = 4
        var backgroundVerticalPadding: CGFloat = 2

        func contentX(for level: Int, roleStyle: NodeMarkdownRoleStyle) -> CGFloat {
            let reservedMarkerAdvance = max(
                markerWidth + markerGap,
                CGFloat(roleStyle.fontSize)
            )
            return markerX(for: level) + reservedMarkerAdvance
        }

        func markerX(for level: Int) -> CGFloat {
            leadingPadding
                + CGFloat(max(0, min(12, level) - 1)) * levelIndentStep
        }

        func lockedPrefixBoundaryX() -> CGFloat {
            leadingPadding + markerWidth + markerGap
        }
    }

    struct BackgroundBar: Hashable {
        var startAlpha: Double = 0.28
        var endAlpha: Double = 0.14
        var printStartAlpha: Double = 0.28
        var printEndAlpha: Double = 0.14
        var minimumHeight: CGFloat = 12
    }

    struct LineStyle: Hashable {
        var level: Int
        var prefix: String
        var iconSymbol: String
        var iconGlyph: String
        var roleStyle: NodeMarkdownRoleStyle
        var contentX: CGFloat
        var markerX: CGFloat
        var markerWidth: CGFloat
        var markerGap: CGFloat
        var hasBackgroundBar: Bool
        var backgroundBar: BackgroundBar
    }

    var layout = Layout()
    var backgroundBar = BackgroundBar()

    static let `default` = NodeMarkdownRenderContract()

    struct InlineVerticalMetrics: Hashable {
        let textHeight: CGFloat
        let lineHeight: CGFloat
        let textBaselineOffset: CGFloat
    }

    /// 公式行只使用真实字体度量和SwiftMath实际图像高度决定行框。
    /// TextKit在扩大的行框中会把普通文字留在基线一侧，因此正文需要抬升
    /// “额外高度的一半”，才能与公式、编号共用同一条视觉中轴。
    static func inlineVerticalMetrics(
        fontAscender: CGFloat,
        fontDescender: CGFloat,
        fontLeading: CGFloat,
        existingMinimumLineHeight: CGFloat,
        renderedContentHeight: CGFloat
    ) -> InlineVerticalMetrics {
        let textHeight = ceil(
            max(1, fontAscender - fontDescender + max(0, fontLeading))
        )
        let naturalLineHeight = max(textHeight, existingMinimumLineHeight)
        let lineHeight = ceil(max(naturalLineHeight, renderedContentHeight))
        return InlineVerticalMetrics(
            textHeight: textHeight,
            lineHeight: lineHeight,
            textBaselineOffset: max(0, (lineHeight - naturalLineHeight) * 0.5)
        )
    }

    /// 背景条使用椭圆圆角：横向半轴固定为当前行一个字宽，纵向半轴始终为条高的一半。
    /// 因而单行两端接近半圆，多行背景只向纵向自然增长，不再由同一个常数限制两轴。
    static func backgroundBarCornerRadii(fontSize: CGFloat, barHeight: CGFloat) -> CGSize {
        CGSize(width: max(1, fontSize), height: max(1, barHeight * 0.5))
    }

    func lineStyle(level rawLevel: Int, prefix: String, documentStyle: NodeMarkdownDocumentStyle) -> LineStyle {
        let level = max(1, min(12, rawLevel))
        let roleStyle = documentStyle.style(forLevel: level)
        let iconSymbol = documentStyle.iconConfig.symbol(for: level)
        return LineStyle(
            level: level,
            prefix: prefix,
            iconSymbol: iconSymbol,
            iconGlyph: Self.markerDisplayText(from: iconSymbol),
            roleStyle: roleStyle,
            contentX: layout.contentX(for: level, roleStyle: roleStyle),
            markerX: layout.markerX(for: level),
            markerWidth: layout.markerWidth,
            markerGap: layout.markerGap,
            hasBackgroundBar: roleStyle.hasBackgroundBar,
            backgroundBar: backgroundBar
        )
    }

    static func interRowSpacing(
        previousLevel: Int?,
        previousRoleStyle: NodeMarkdownRoleStyle?,
        currentLevel: Int,
        currentRoleStyle: NodeMarkdownRoleStyle,
        scale: CGFloat = 1
    ) -> CGFloat {
        guard let previousLevel, let previousRoleStyle else { return 0 }
        if previousLevel == currentLevel {
            return max(0, CGFloat(currentRoleStyle.peerLineSpacing) * scale)
        }
        let previousAfter = max(0, CGFloat(previousRoleStyle.paragraphSpacingAfter) * scale)
        let currentBefore = max(0, CGFloat(currentRoleStyle.paragraphSpacingBefore) * scale)
        return max(previousAfter, currentBefore)
    }

    static func markerDisplayText(from raw: String) -> String {
        switch raw {
        case "circle.fill": return "●"
        case "diamond.fill": return "◆"
        case "triangle.fill": return "▲"
        case "seal.fill": return "✦"
        case "hexagon.fill": return "⬢"
        case "capsule.fill": return "◉"
        case "star.fill": return "★"
        case "bookmark.fill": return "❖"
        case "flag.fill": return "⚑"
        case "pin.fill": return "📍"
        case "bolt.fill": return "⚡︎"
        case "moon.fill": return "☾"
        default:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "•" : trimmed
        }
    }

    static func webRGBA(fromHex hex: String, alpha: Double) -> String {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let raw = Int(value, radix: 16) else {
            return "rgba(120,120,120,\(alpha))"
        }
        let red = (raw >> 16) & 0xFF
        let green = (raw >> 8) & 0xFF
        let blue = raw & 0xFF
        return "rgba(\(red),\(green),\(blue),\(alpha))"
    }

    static func backgroundWebHex(fromHex hex: String) -> String {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let raw = Int(value, radix: 16) else { return hex }
        let red = CGFloat((raw >> 16) & 0xFF) / 255
        let green = CGFloat((raw >> 8) & 0xFF) / 255
        let blue = CGFloat(raw & 0xFF) / 255
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard maximum > 0, delta > 0 else { return String(format: "#%06X", raw) }

        var hue: CGFloat
        if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        let saturation = min(1, (delta / maximum) * backgroundSaturationMultiplier)
        let sector = hue * 6
        let chroma = maximum * saturation
        let intermediate = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let offset = maximum - chroma
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch sector {
        case 0..<1: rgb = (chroma, intermediate, 0)
        case 1..<2: rgb = (intermediate, chroma, 0)
        case 2..<3: rgb = (0, chroma, intermediate)
        case 3..<4: rgb = (0, intermediate, chroma)
        case 4..<5: rgb = (intermediate, 0, chroma)
        default: rgb = (chroma, 0, intermediate)
        }
        let result = (
            Int(((rgb.0 + offset) * 255).rounded()),
            Int(((rgb.1 + offset) * 255).rounded()),
            Int(((rgb.2 + offset) * 255).rounded())
        )
        return String(format: "#%02X%02X%02X", result.0, result.1, result.2)
    }

    #if os(macOS)
    static func backgroundColor(from sourceColor: NSColor) -> NSColor {
        let source = sourceColor.usingColorSpace(.deviceRGB) ?? sourceColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            calibratedHue: hue,
            saturation: min(1, saturation * backgroundSaturationMultiplier),
            brightness: brightness,
            alpha: alpha
        ).usingColorSpace(.deviceRGB) ?? source
    }
    #endif

    func webBackgroundCSS(colorHex: String, enabled: Bool) -> String {
        guard enabled else { return "" }
        let start = Self.webRGBA(fromHex: colorHex, alpha: backgroundBar.startAlpha)
        let end = Self.webRGBA(fromHex: colorHex, alpha: backgroundBar.endAlpha)
        return "background:linear-gradient(90deg,\(start) 0%,\(end) 100%);border-radius:1em / 50%;padding-top:1px;padding-bottom:1px;"
    }

    func imageTokens(in text: String) -> [NodeMarkdownImageToken] {
        NodeMarkdownImageResourceManager.parseImageTokens(in: text)
    }

    func resolvedImageURL(relativePath: String, baseDirectoryURL: URL?) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if NSString(string: trimmed).isAbsolutePath {
            return URL(fileURLWithPath: trimmed)
        }
        return baseDirectoryURL?.appendingPathComponent(trimmed).standardizedFileURL
    }
}
