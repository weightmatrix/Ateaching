import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - 全局背景视觉样式 - v1 - 主界面、清单、单列表格和导出图共用背景板

enum AppBackgroundVisualStyle {
    static var pageBackground: some View {
        AppBackgroundView(style: AppBackgroundSettingsStore.load().backgroundStyle)
            .ignoresSafeArea()
    }

    static var roundedPageBackground: some View {
        AppBackgroundView(style: AppBackgroundSettingsStore.load().backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    static func pageBackground(for style: AppBackgroundSettings.BackgroundStyle) -> some View {
        AppBackgroundView(style: style, followsDesign: false)
    }
}

enum SingleListVisualStyle {
    static var pageBackground: some View {
        AppBackgroundVisualStyle.pageBackground
    }

    static var roundedPageBackground: some View {
        AppBackgroundVisualStyle.roundedPageBackground
    }

    static var rowBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.58))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    static var editorBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.36))
    }
}

private struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: AppBackgroundSettings.BackgroundStyle
    var followsDesign = true

    var body: some View {
        let design: AppBackgroundSettings.DesignStyle = followsDesign ? AppBackgroundSettingsStore.load().designStyle : .apple
        if design == .victorian {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.18, green: 0.12, blue: 0.10), Color(red: 0.10, green: 0.15, blue: 0.13)]
                    : [Color(red: 0.96, green: 0.91, blue: 0.79), Color(red: 0.86, green: 0.77, blue: 0.59)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay { VictorianWallpaper() }
        } else if design == .minimal {
            plainBackground
        } else if design == .vibrant {
            LinearGradient(colors: [Color.purple.opacity(colorScheme == .dark ? 0.32 : 0.18), Color.pink.opacity(0.16), Color.blue.opacity(0.20)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .background(plainBackground)
        } else if style == .plain {
            plainBackground
        } else {
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 0.86 : 0.62)
        }
    }

    private var colors: [Color] {
        switch colorScheme {
        case .dark:
            return [
                Color(red: 0.02, green: 0.20, blue: 0.14),
                Color(red: 0.00, green: 0.19, blue: 0.33)
            ]
        default:
            return [
                Color(red: 0.66, green: 0.88, blue: 0.55),
                Color(red: 0.99, green: 0.86, blue: 0.46)
            ]
        }
    }

    private var plainBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #elseif os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(.background)
        #endif
    }
}
