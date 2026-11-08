import SwiftUI

/// 原生矢量卷草，可缩放用于墙纸、角花及分隔线，不依赖字体花符或位图。
struct VictorianFlourish: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        for mirror: CGFloat in [-1, 1] {
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { point(0.5 + mirror * x, y) }
            p.move(to: q(0, 0.92))
            p.addCurve(to: q(0.33, 0.28), control1: q(0.03, 0.50), control2: q(0.46, 0.70))
            p.addCurve(to: q(0.16, 0.39), control1: q(0.20, 0.02), control2: q(0.06, 0.24))
            p.addCurve(to: q(0.28, 0.40), control1: q(0.21, 0.54), control2: q(0.36, 0.48))
            p.move(to: q(0.08, 0.70))
            p.addCurve(to: q(0.46, 0.64), control1: q(0.27, 0.48), control2: q(0.34, 0.91))
            p.addCurve(to: q(0.34, 0.61), control1: q(0.50, 0.48), control2: q(0.31, 0.43))
            p.move(to: q(0.04, 0.54))
            p.addCurve(to: q(0.09, 0.12), control1: q(0.17, 0.37), control2: q(0.18, 0.22))
            p.addCurve(to: q(0.04, 0.54), control1: q(-0.02, 0.25), control2: q(0, 0.39))
        }
        p.move(to: point(0.5, 0.08))
        p.addQuadCurve(to: point(0.5, 0.92), control: point(0.38, 0.50))
        p.addQuadCurve(to: point(0.5, 0.08), control: point(0.62, 0.50))
        return p
    }
}

struct VictorianWallpaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 94
            let ink = Color(red: 0.55, green: 0.36, blue: 0.16)
                .opacity(colorScheme == .dark ? 0.30 : 0.19)
            for row in 0..<Int(ceil(size.height / step)) {
                for column in -1..<Int(ceil(size.width / step)) {
                    let x = CGFloat(column) * step + (row.isMultiple(of: 2) ? 0 : step / 2)
                    let rect = CGRect(x: x + 12, y: CGFloat(row) * step + 8, width: 70, height: 70)
                    context.stroke(VictorianFlourish().path(in: rect), with: .color(ink), lineWidth: 1)
                    context.stroke(VictorianFlourish().path(in: rect).applying(
                        CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
                            .concatenating(CGAffineTransform(rotationAngle: .pi))
                            .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
                    ), with: .color(ink), lineWidth: 0.7)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VictorianOrnateFrame: View {
    var compact = false
    private let gold = Color(red: 0.65, green: 0.49, blue: 0.25)

    var body: some View {
        GeometryReader { geometry in
            let ornament = min(compact ? 20.0 : 48.0, geometry.size.width / 4, geometry.size.height / 3)
            ZStack {
                RoundedRectangle(cornerRadius: 8).stroke(gold, lineWidth: 1.8)
                RoundedRectangle(cornerRadius: 5).stroke(gold.opacity(0.65), lineWidth: 0.7).padding(4)
                RoundedRectangle(cornerRadius: 3).stroke(gold.opacity(0.40), lineWidth: 0.6).padding(8)
                ForEach(0..<4) { corner in
                    VictorianFlourish()
                        .stroke(gold, style: StrokeStyle(lineWidth: compact ? 0.8 : 1.2, lineCap: .round))
                        .frame(width: ornament, height: ornament)
                        .rotationEffect(.degrees(Double(corner) * 90 - 45))
                        .position(
                            x: corner == 0 || corner == 3 ? ornament / 2 + 4 : geometry.size.width - ornament / 2 - 4,
                            y: corner < 2 ? ornament / 2 + 4 : geometry.size.height - ornament / 2 - 4
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VictorianDivider: View {
    private let gold = Color(red: 0.65, green: 0.49, blue: 0.25)

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LinearGradient(colors: [.clear, gold], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
            VictorianFlourish().stroke(gold, lineWidth: 1.1).frame(width: 90, height: 30)
            Rectangle().fill(LinearGradient(colors: [gold, .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
        }
        .frame(maxWidth: 380)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
