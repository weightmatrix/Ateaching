// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint decorations).
import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum TeachingPrintDecorationTheme: String, Sendable {
    case plain
    case nodeMarkdown
}

enum TeachingPrintDecorationRenderer {
    static func drawStripe(
        in context: CGContext,
        rect: CGRect,
        style: TeachingPrintBackgroundStripeStyle,
        theme: TeachingPrintDecorationTheme = .nodeMarkdown
    ) {
        switch theme {
        case .plain:
            guard let color = colorFromHexRGBA(style.fillColorHexRGBA) else { return }
            context.saveGState()
            context.setFillColor(color.cgColor)
            let path = CGPath(
                roundedRect: rect,
                cornerWidth: style.cornerRadius,
                cornerHeight: style.cornerRadius,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        case .nodeMarkdown:
            drawGradientStripe(in: context, rect: rect, style: style)
        }
    }

    private static func drawGradientStripe(
        in context: CGContext,
        rect: CGRect,
        style: TeachingPrintBackgroundStripeStyle
    ) {
        guard let base = colorFromHexRGBA(style.fillColorHexRGBA) else { return }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        let start = base.withAlphaComponent(0.10).cgColor
        let end = base.withAlphaComponent(0.02).cgColor
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: [start, end] as CFArray, locations: [0, 1]) else { return }

        context.saveGState()
        let clipPath = CGPath(
            roundedRect: rect,
            cornerWidth: style.cornerRadius,
            cornerHeight: style.cornerRadius,
            transform: nil
        )
        context.addPath(clipPath)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
    }

    private static func colorFromHexRGBA(_ hex: String) -> TeachingPrintColor? {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 8, let raw = UInt32(value, radix: 16) else { return nil }
        let red = CGFloat((raw & 0xFF00_0000) >> 24) / 255
        let green = CGFloat((raw & 0x00FF_0000) >> 16) / 255
        let blue = CGFloat((raw & 0x0000_FF00) >> 8) / 255
        let alpha = CGFloat(raw & 0x0000_00FF) / 255
        #if os(macOS)
        return TeachingPrintColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
        #else
        return TeachingPrintColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}
