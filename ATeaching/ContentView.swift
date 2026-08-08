import SwiftUI

// MARK: - 主内容页 - v1 - 承载顶部导航与底部分页栏
struct ContentView: View {
    @State private var selectedTab: TeachingTab = .teaching
    @StateObject private var screenCastService = ScreenCastService()

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
            .toolbar {
                if screenCastService.isCasting || screenCastService.isReceiving {
                    ToolbarItem(placement: .automatic) {
                        HStack(spacing: 4) {
                            Image(systemName: screenCastService.isCasting
                                   ? "arrow.up.forward" : "arrow.down.forward")
                                .font(.caption)
                            Text(screenCastService.isCasting ? "投屏中" : "接收中")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                }
            }
            #if os(macOS)
            .background(MacMainWindowAccessor(title: displayTitle))
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: appWillTerminate)) { _ in
            screenCastService.stopAll()
        }
    }

    #if os(macOS)
    private var appWillTerminate: Notification.Name { NSApplication.willTerminateNotification }
    #else
    private var appWillTerminate: Notification.Name { UIApplication.willTerminateNotification }
    #endif

    @ViewBuilder
    private var currentPage: some View {
        switch selectedTab {
        case .teaching:
            TeachingHomeView()
        case .archive:
            ArchiveView()
        case .screenCast:
            ScreenCastView(service: screenCastService)
        case .settings:
            AppSettingsView()
        }
    }
}
