import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - 课时统计颜色工具 - v1 - 在Color和JSON十六进制字符串之间转换

/// 将机构快照里的十六进制颜色转换成 SwiftUI Color；非法颜色统一回退为灰色。
func statisticsColor(fromHex hex: String) -> Color {
    let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
    guard value.count == 6, let number = UInt32(value, radix: 16) else {
        return .gray
    }
    let red = Double((number >> 16) & 0xFF) / 255
    let green = Double((number >> 8) & 0xFF) / 255
    let blue = Double(number & 0xFF) / 255
    return Color(red: red, green: green, blue: blue)
}

/// 将机构编辑器中选择的 SwiftUI Color 保存成 JSON 使用的 #RRGGBB 字符串。
func statisticsHex(from color: Color) -> String {
    #if os(macOS)
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .gray
    return String(
        format: "#%02X%02X%02X",
        Int(round(resolved.redComponent * 255)),
        Int(round(resolved.greenComponent * 255)),
        Int(round(resolved.blueComponent * 255))
    )
    #else
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return String(
        format: "#%02X%02X%02X",
        Int(round(red * 255)),
        Int(round(green * 255)),
        Int(round(blue * 255))
    )
    #endif
}

// MARK: - 机构辨识色规划 - v1 - 从高区分度色板中选择建议色并支持整体重排

enum TeachingInstitutionVisualPlanner {
    nonisolated static let iconNames = [
        "graduationcap.fill", "book.closed.fill", "atom", "function", "sum",
        "lightbulb.fill", "pencil.and.ruler.fill", "brain.head.profile", "globe.asia.australia.fill",
        "music.note", "paintpalette.fill", "figure.run", "star.fill", "sparkles"
    ]

    nonisolated private static let palette = [
        "#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9",
        "#F0E442", "#6F42C1", "#00A6A6", "#E83E8C", "#7A9E00", "#8B5A2B"
    ]

    nonisolated static func suggestedColorHex(existing: [String]) -> String {
        let used = existing.compactMap(rgb)
        guard !used.isEmpty else { return palette[0] }
        return palette.max { lhs, rhs in
            minimumDistance(rgb(lhs)!, from: used) < minimumDistance(rgb(rhs)!, from: used)
        } ?? palette[0]
    }

    nonisolated static func reorganizedColors(count: Int) -> [String] {
        guard count > 0 else { return [] }
        if count <= palette.count { return Array(palette.prefix(count)) }
        return (0..<count).map { index in
            let hue = (Double(index) * 0.61803398875).truncatingRemainder(dividingBy: 1)
            return hsvHex(hue: hue, saturation: 0.72, value: 0.86)
        }
    }

    nonisolated private static func minimumDistance(_ candidate: (Double, Double, Double), from used: [(Double, Double, Double)]) -> Double {
        used.map { value in
            let dr = candidate.0 - value.0
            let dg = candidate.1 - value.1
            let db = candidate.2 - value.2
            return dr * dr + dg * dg + db * db
        }.min() ?? .greatestFiniteMagnitude
    }

    nonisolated private static func rgb(_ hex: String) -> (Double, Double, Double)? {
        let value = hex.replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
        return (Double((number >> 16) & 255), Double((number >> 8) & 255), Double(number & 255))
    }

    nonisolated private static func hsvHex(hue: Double, saturation: Double, value: Double) -> String {
        let sector = hue * 6
        let index = Int(floor(sector)) % 6
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        let rgb: (Double, Double, Double)
        switch index {
        case 0: rgb = (value, t, p)
        case 1: rgb = (q, value, p)
        case 2: rgb = (p, value, t)
        case 3: rgb = (p, q, value)
        case 4: rgb = (t, p, value)
        default: rgb = (value, p, q)
        }
        return String(format: "#%02X%02X%02X", Int(rgb.0 * 255), Int(rgb.1 * 255), Int(rgb.2 * 255))
    }
}
