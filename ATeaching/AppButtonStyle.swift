import SwiftUI

// MARK: - 统一高亮色 - v1 - 使用原生淡蓝色作为全局亮灯色
let appHighlightBlue = Color(red: 0.45, green: 0.78, blue: 1.0)

// MARK: - 应用按钮等级 - v1 - 统一主次危险三类按钮视觉语义
enum AppButtonTier {
    case regular
    case prominent
    case danger
}

// MARK: - 应用玻璃按钮样式 - v1 - 统一原生玻璃圆角极速按钮风格
struct AppGlassButtonStyle: ButtonStyle {
    let tier: AppButtonTier

    private var designStyle: AppBackgroundSettings.DesignStyle {
        AppBackgroundSettingsStore.load().designStyle
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: designStyle.cornerRadius, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: designStyle == .minimal ? .medium : .semibold))
            .fontDesign(designStyle == .victorian ? .serif : .default)
            .padding(.horizontal, designStyle == .victorian ? 24 : (designStyle == .minimal ? 10 : 12))
            .padding(.vertical, designStyle == .minimal ? 7 : 8)
            .frame(minHeight: 36)
            .foregroundStyle(foregroundColor)
            .background(buttonBackground(isPressed: configuration.isPressed))
            .overlay {
                if designStyle == .victorian {
                    VictorianOrnateFrame(compact: true)
                }
            }
            .clipShape(shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tier {
        case .regular:
            return .primary
        case .prominent:
            return .primary
        case .danger:
            return .red
        }
    }

    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        let cornerRadius = designStyle.cornerRadius
        if designStyle != .apple {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(designStyle.accent.opacity(isPressed ? 0.25 : (tier == .prominent ? 0.20 : 0.09)))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(designStyle.border, lineWidth: designStyle == .victorian ? 1.5 : 1)
                }
        } else if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.clear)
                .glassEffect(glassVariant(isPressed: isPressed), in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundColor.opacity(isPressed ? 0.72 : 0.9))
        }
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
    private func glassVariant(isPressed: Bool) -> Glass {
        let base: Glass
        switch tier {
        case .regular:
            base = .regular
        case .prominent:
            base = .regular.tint(appHighlightBlue)
        case .danger:
            base = .regular
        }
        return base.interactive(true)
    }

    private var backgroundColor: Color {
        switch tier {
        case .regular:
            return Color.secondary.opacity(0.20)
        case .prominent:
            return (designStyle == .vibrant ? Color.purple : appHighlightBlue).opacity(0.86)
        case .danger:
            return Color.secondary.opacity(0.20)
        }
    }
}

// MARK: - 按钮样式快捷扩展 - v1 - 统一调用入口减少重复样式代码
extension View {
    func appGlassButtonStyle(_ tier: AppButtonTier = .regular) -> some View {
        buttonStyle(AppGlassButtonStyle(tier: tier))
    }

    @ViewBuilder
    func appGlassControlChrome(_ tier: AppButtonTier = .regular) -> some View {
        let cornerRadius = 12.0
        let tint: Color = {
            switch tier {
            case .regular: return .secondary.opacity(0.20)
            case .prominent: return appHighlightBlue.opacity(0.86)
            case .danger: return .secondary.opacity(0.20)
            }
        }()

        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            self
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .glassEffect(.regular.interactive(true), in: .rect(cornerRadius: cornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint)
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
