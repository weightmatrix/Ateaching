import SwiftUI

// MARK: - 主内容页 - v1 - 承载顶部导航与底部分页栏
struct ContentView: View {
    @State private var selectedTab: TeachingTab = .teaching

    private var displayTitle: String {
        AppDisplayTitle.mainWindowTitle(forPage: selectedTab.title)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                currentPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                GlassTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .ignoresSafeArea(.keyboard)
            .background(AppBackgroundVisualStyle.pageBackground)
            .navigationTitle(displayTitle)
            .buttonStyle(AppGlassButtonStyle(tier: .regular))
            #if os(macOS)
            .background(MacMainWindowAccessor(title: displayTitle))
            #endif
        }
    }

    @ViewBuilder
    private var currentPage: some View {
        switch selectedTab {
        case .teaching:
            TeachingHomeView()
        case .archive:
            ArchiveView()
        case .screenCast:
            ScreenCastView()
        case .settings:
            AppSettingsView()
        }
    }
}

// MARK: - 空状态页 - v1 - 显示功能待上线占位内容
private struct EmptyStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text("内容即将上线")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
