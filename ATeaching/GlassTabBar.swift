import SwiftUI

// MARK: - 分页类型 - v1 - 定义授课档案设置三类分页信息
enum TeachingTab: CaseIterable {
    case teaching
    case archive
    case screenCast
    case settings

    var title: String {
        switch self {
        case .teaching:
            return "授课"
        case .archive:
            return "档案"
        case .screenCast:
            return "投屏"
        case .settings:
            return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .teaching:
            return "person.2.fill"
        case .archive:
            return "tray.full.fill"
        case .screenCast:
            return "rectangle.connected.to.line.below"
        case .settings:
            return "gearshape.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .teaching:
            return .pink
        case .archive:
            return .green
        case .screenCast:
            return .blue
        case .settings:
            return .orange
        }
    }
}

// MARK: - 玻璃分页栏 - v2 - 渲染底部统一图标按钮与选中态
struct GlassTabBar: View {
    @Binding var selectedTab: TeachingTab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(TeachingTab.allCases, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func tabButton(for tab: TeachingTab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            selectedTab = tab
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 36)
        }
        .appGlassButtonStyle(.regular)
        .foregroundStyle(isSelected ? tab.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? tab.accentColor.opacity(0.18) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? tab.accentColor.opacity(0.60) : .clear, lineWidth: 1.2)
        )
        .shadow(color: isSelected ? tab.accentColor.opacity(0.45) : .clear, radius: 6, x: 0, y: 0)
        .animation(.easeOut(duration: 0.16), value: isSelected)
        .help(tab.title)
        #if os(macOS)
        .focusable(false)
        #endif
    }
}

#Preview {
    GlassTabBar(selectedTab: .constant(.teaching))
        .padding()
        .background(.background)
}
