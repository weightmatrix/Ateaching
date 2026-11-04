import SwiftUI

// MARK: - 主内容页 - v1 - 承载顶部导航与底部分页栏
struct ContentView: View {
    @AppStorage("frequentTabEnabled") private var frequentTabEnabled = true
    @State private var selectedTab: TeachingTab = .teaching
    @StateObject private var screenCastService = ScreenCastService()
    @State private var appearanceRevision = 0

    private var displayTitle: String {
        AppDisplayTitle.mainWindowTitle(forPage: selectedTab.title)
    }

    var body: some View {
        Group {
            if screenCastService.isReceiving && screenCastService.isConnected {
                NavigationStack {
                    ScreenCastReceiverView(service: screenCastService)
                }
            } else {
                mainNavigation
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: appWillTerminate)) { _ in
            screenCastService.stopAll(reason: "应用将终止")
            TeachingDebugLogStore.append("normal termination", category: "App.Session")
            TeachingDebugLogStore.flushPending()
        }
        .onAppear { TeachingDebugLogStore.beginSession() }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            TeachingDebugLogStore.flushPending()
        }
        #endif
        .onChange(of: frequentTabEnabled) { _, enabled in
            if !enabled && selectedTab == .frequent { selectedTab = .teaching }
        }
        .onChange(of: screenCastService.isConnected) { _, connected in
            if connected && screenCastService.isReceiving {
                ScreenCastReceiverWindowCoordinator.enterExclusiveReceiving()
            } else {
                ScreenCastReceiverWindowCoordinator.leaveExclusiveReceiving()
            }
        }
    }

    private var mainNavigation: some View {
        #if os(macOS)
        macMainNavigation
        #else
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
            .id(appearanceRevision)
            .navigationTitle(displayTitle)
            .navigationBarTitleDisplayMode(.inline)
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
        .onReceive(NotificationCenter.default.publisher(for: .appAppearanceDidChange)) { _ in
            appearanceRevision += 1
        }
        #endif
    }

    #if os(macOS)
    private var macMainNavigation: some View {
        NavigationStack {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("李知本")
                                .font(.system(size: 15, weight: .semibold))
                            Text("授课系统")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)

                    ForEach(TeachingTab.allCases.filter { frequentTabEnabled || $0 != .frequent }, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(width: 22)
                                Text(tab.title)
                                    .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                                Spacer()
                            }
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.14) : .clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: 205)
                .background(.ultraThinMaterial)
                .overlay(alignment: .trailing) { Divider() }

                currentPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppBackgroundVisualStyle.pageBackground)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .id(appearanceRevision)
            .navigationTitle(displayTitle)
            .toolbar {
                if screenCastService.isCasting || screenCastService.isReceiving {
                    ToolbarItem(placement: .automatic) {
                        Label(
                            screenCastService.isCasting ? "投屏中" : "接收中",
                            systemImage: screenCastService.isCasting ? "arrow.up.forward" : "arrow.down.forward"
                        )
                        .foregroundStyle(.blue)
                    }
                }
            }
            .background(MacMainWindowAccessor(title: displayTitle))
        }
        .onReceive(NotificationCenter.default.publisher(for: .appAppearanceDidChange)) { _ in
            appearanceRevision += 1
        }
    }
    #endif

    #if os(macOS)
    private var appWillTerminate: Notification.Name { NSApplication.willTerminateNotification }
    #else
    private var appWillTerminate: Notification.Name { UIApplication.willTerminateNotification }
    #endif

    @ViewBuilder
    private var currentPage: some View {
        switch selectedTab {
        case .frequent:
            FrequentDocumentsView()
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
