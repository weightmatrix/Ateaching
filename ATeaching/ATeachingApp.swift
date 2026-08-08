import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - 应用入口 - v4 - 启动主窗口并在退出前统一关闭子窗口
@main
struct ATeachingApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ATeachingMacApplicationDelegate.self) private var macApplicationDelegate
    #endif

    var body: some Scene {
        WindowGroup(AppDisplayTitle.defaultMainWindowTitle, id: ATeachingWindowID.main) {
            ATeachingRootWindowView()
                .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                .monospaced()
                .task {
                    await ATeachingLaunchBootstrapper.bootstrapIfNeeded()
                }
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    closeChildWindowsBeforeTerminate()
                }
                #endif
        }
        #if os(macOS)
        .defaultLaunchBehavior(.suppressed)
        #endif

        #if os(macOS)
        WindowGroup(id: ATeachingExternalMarkdownWindowID.markdownEditor, for: String.self) { $filePath in
            if let filePath {
                MarkdownEditorView(fileURL: URL(fileURLWithPath: filePath))
                    .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                    .monospaced()
            } else {
                Text("未选择Markdown文件")
            }
        }
        .defaultSize(width: 1080, height: 760)
        .restorationBehavior(.disabled)

        WindowGroup(id: "nodemarkdown-editor", for: String.self) { $filePath in
            if let filePath {
                NodeMarkdownEditorView(fileURL: URL(fileURLWithPath: filePath))
                    .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                    .monospaced()
            } else {
                Text("未选择NodeMarkdown文件")
            }
        }
        .defaultSize(width: 1080, height: 760)
        .restorationBehavior(.disabled)

        WindowGroup(id: "teaching-course-page", for: String.self) { $studentID in
            if let studentID {
                TeachingCoursePageWindowHostView(studentID: studentID)
                    .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                    .monospaced()
            } else {
                Text("未选择学生")
            }
        }
        .defaultSize(width: 980, height: 720)
        .restorationBehavior(.disabled)
        #endif
    }

    #if os(macOS)
    private func closeChildWindowsBeforeTerminate() {
        for window in NSApplication.shared.windows {
            if window.title.hasPrefix("Markdown-") {
                window.close()
            }
        }
    }
    #endif
}

private enum ATeachingWindowID {
    static let main = "main-window"
}

enum ATeachingExternalMarkdownWindowID {
    static let markdownEditor = "markdown-editor"
}

private struct ATeachingRootWindowView: View {
    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            ContentView()
                .focusEffectDisabled()
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

}

@MainActor
private enum ATeachingLaunchBootstrapper {
    private static var didBootstrap = false

    static func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        Task(priority: .utility) {
            _ = try? ArchiveStorage.ensureArchiveRoot()
        }
        MarkdownFontCatalog.shared.prewarmIfNeeded()
        TeachingBackupScheduler.shared.bootstrapIfNeeded()
        TeachingCourseConsistencyScheduler.shared.bootstrapIfNeeded()
    }
}

#if os(macOS)
@MainActor
private enum ATeachingExternalMarkdownOpenRouter {
    static let didReceiveMarkdownFilesNotification = Notification.Name("ATeachingExternalMarkdownOpenRouter.didReceiveMarkdownFiles")
    private(set) static var hasReceivedExternalMarkdownOpen = false

    static func enqueue(_ urls: [URL]) {
        let filePaths = urls
            .filter(isMarkdownFile(_:))
            .map(\.path)
        guard !filePaths.isEmpty else { return }
        hasReceivedExternalMarkdownOpen = true
        ATeachingMacLaunchMainWindowGate.suppressForExternalMarkdownOpen()
        ExternalMarkdownWindowPresenter.openInTabs(filePaths: filePaths)
        NotificationCenter.default.post(name: didReceiveMarkdownFilesNotification, object: nil)
    }

    static func isMarkdownFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

@MainActor
private final class ATeachingMacApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await ATeachingLaunchBootstrapper.bootstrapIfNeeded() }
        ATeachingMacLaunchMainWindowGate.scheduleAutomaticOpenIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        ATeachingExternalMarkdownOpenRouter.enqueue(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        guard ATeachingExternalMarkdownOpenRouter.isMarkdownFile(url) else { return false }
        ATeachingExternalMarkdownOpenRouter.enqueue([url])
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        ATeachingMacMainWindowPresenter.ensureMainWindowVisible()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "主窗口",
            action: #selector(showMainWindowFromDockMenu(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func showMainWindowFromDockMenu(_ sender: Any?) {
        ATeachingMacMainWindowPresenter.ensureMainWindowVisible()
    }
}

@MainActor
private enum ATeachingMacLaunchMainWindowGate {
    private static var pendingAutomaticOpen: DispatchWorkItem?
    private static var didSuppressForExternalMarkdownOpen = false
    private static var launchDate = Date()

    static func scheduleAutomaticOpenIfNeeded() {
        launchDate = Date()
        pendingAutomaticOpen?.cancel()
        let workItem = DispatchWorkItem {
            guard !didSuppressForExternalMarkdownOpen,
                  !ATeachingExternalMarkdownOpenRouter.hasReceivedExternalMarkdownOpen else {
                return
            }
            ATeachingMacMainWindowPresenter.ensureMainWindowVisible(markAsAutomaticLaunch: true)
        }
        pendingAutomaticOpen = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    static func suppressForExternalMarkdownOpen() {
        didSuppressForExternalMarkdownOpen = true
        pendingAutomaticOpen?.cancel()
        pendingAutomaticOpen = nil
        if Date().timeIntervalSince(launchDate) < 6 {
            ATeachingMacMainWindowPresenter.closeMainWindowsOpenedForExternalMarkdown()
        }
    }
}

@MainActor
private enum ATeachingMacMainWindowPresenter {
    private static var fallbackWindow: NSWindow?
    private static var automaticLaunchWindow: NSWindow?
    private static var automaticLaunchWindowOpenedAt: Date?

    static func ensureMainWindowVisible(markAsAutomaticLaunch: Bool = false) {
        if focusMainWindow() {
            return
        }
        presentFallbackMainWindow(markAsAutomaticLaunch: markAsAutomaticLaunch)
    }

    @discardableResult
    static func focusMainWindow() -> Bool {
        guard let window = NSApplication.shared.windows.first(where: { window in
            window.identifier?.rawValue == ATeachingWindowID.main ||
            window.title == AppDisplayTitle.defaultMainWindowTitle ||
            window.title.contains(AppDisplayTitle.mainWindowBaseTitle)
        }) else {
            return false
        }

        show(window)
        return true
    }

    private static func presentFallbackMainWindow(markAsAutomaticLaunch: Bool) {
        if let fallbackWindow {
            show(fallbackWindow)
            if markAsAutomaticLaunch {
                automaticLaunchWindow = fallbackWindow
                automaticLaunchWindowOpenedAt = Date()
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(ATeachingWindowID.main)
        window.title = AppDisplayTitle.defaultMainWindowTitle
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: MacFallbackMainWindowRoot())
        fallbackWindow = window
        if markAsAutomaticLaunch {
            automaticLaunchWindow = window
            automaticLaunchWindowOpenedAt = Date()
        }
        show(window)
    }

    static func closeMainWindowsOpenedForExternalMarkdown() {
        closeAutomaticLaunchWindowIfFresh()
        for window in NSApplication.shared.windows {
            guard isMainWindow(window) else { continue }
            window.close()
            if fallbackWindow === window {
                fallbackWindow = nil
            }
        }
    }

    private static func closeAutomaticLaunchWindowIfFresh() {
        if let window = automaticLaunchWindow,
           let openedAt = automaticLaunchWindowOpenedAt,
           Date().timeIntervalSince(openedAt) < 4 {
            window.close()
            if fallbackWindow === window {
                fallbackWindow = nil
            }
        }
        automaticLaunchWindow = nil
        automaticLaunchWindowOpenedAt = nil
    }

    private static func show(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == ATeachingWindowID.main ||
        window.title == AppDisplayTitle.defaultMainWindowTitle ||
        window.title.contains(AppDisplayTitle.mainWindowBaseTitle)
    }
}

private struct MacFallbackMainWindowRoot: View {
    var body: some View {
        ATeachingRootWindowView()
            .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
            .monospaced()
            .task {
                await ATeachingLaunchBootstrapper.bootstrapIfNeeded()
            }
    }
}

struct MacMainWindowAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        let minimumContentSize = NSSize(width: 720, height: 520)
        window.identifier = NSUserInterfaceItemIdentifier(ATeachingWindowID.main)
        window.title = title
        window.contentMinSize = minimumContentSize
        window.minSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size

        let currentContentSize = window.contentLayoutRect.size
        guard currentContentSize.width < minimumContentSize.width
                || currentContentSize.height < minimumContentSize.height else { return }
        window.setContentSize(
            NSSize(
                width: max(currentContentSize.width, minimumContentSize.width),
                height: max(currentContentSize.height, minimumContentSize.height)
            )
        )
    }
}
#endif
