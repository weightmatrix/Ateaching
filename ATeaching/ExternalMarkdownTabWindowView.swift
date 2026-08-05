import SwiftUI
import Combine

#if os(macOS)
import AppKit
// MARK: - 外部Markdown标签页窗口 - v1 - Finder打开的MD文件集中进入同一标签页窗口

/// 外部 Markdown 文件的轻量标签模型。使用标准化文件路径做稳定 ID，避免同一文件重复开多个标签。
struct ExternalMarkdownTabItem: Identifiable, Hashable {
    let id: String
    let fileURL: URL

    var displayName: String {
        fileURL.lastPathComponent.isEmpty ? "未命名.md" : fileURL.lastPathComponent
    }

    init(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        self.fileURL = standardizedURL
        self.id = standardizedURL.path
    }
}

/// 外部 Markdown 标签页状态中心。只负责标签页选择与增删；文件读写仍交给现有 MarkdownEditorView。
@MainActor
final class ExternalMarkdownTabStore: ObservableObject {
    static let shared = ExternalMarkdownTabStore()

    @Published private(set) var tabs: [ExternalMarkdownTabItem] = []
    @Published var selectedID: ExternalMarkdownTabItem.ID?

    private init() {}

    func open(fileURLs: [URL]) {
        for fileURL in fileURLs {
            open(fileURL: fileURL)
        }
    }

    func open(filePaths: [String]) {
        open(fileURLs: filePaths.map { URL(fileURLWithPath: $0) })
    }

    func close(_ tab: ExternalMarkdownTabItem) {
        guard let index = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: index)
        guard selectedID == tab.id else { return }
        if tabs.indices.contains(index) {
            selectedID = tabs[index].id
        } else {
            selectedID = tabs.last?.id
        }
    }

    var selectedTab: ExternalMarkdownTabItem? {
        guard let selectedID else { return tabs.first }
        return tabs.first { $0.id == selectedID } ?? tabs.first
    }

    private func open(fileURL: URL) {
        let item = ExternalMarkdownTabItem(fileURL: fileURL)
        if tabs.contains(item) {
            selectedID = item.id
            return
        }
        tabs.append(item)
        selectedID = item.id
    }
}

/// 外部 Markdown 专用单窗口多标签页外壳；内部编辑能力复用普通 MarkdownEditorView。
struct ExternalMarkdownTabWindowView: View {
    @StateObject private var store = ExternalMarkdownTabStore.shared
    @State private var draggingTabID: ExternalMarkdownTabItem.ID?
    @State private var dragTranslations: [ExternalMarkdownTabItem.ID: CGSize] = [:]

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider()
            editorArea
        }
        .navigationTitle(windowTitle)
        .background(ExternalMarkdownWindowTitleAccessor(title: windowTitle))
        .frame(minWidth: 760, minHeight: 520)
    }

    private var windowTitle: String {
        if let selectedTab = store.selectedTab {
            return "Markdown-\(selectedTab.displayName)"
        }
        return "Markdown"
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.tabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.primary.opacity(0.05))
    }

    @ViewBuilder
    private var editorArea: some View {
        if let tab = store.selectedTab {
            MarkdownEditorView(fileURL: tab.fileURL)
                .id(tab.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("没有打开的 Markdown 文件")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tabButton(_ tab: ExternalMarkdownTabItem) -> some View {
        let isSelected = tab.id == store.selectedTab?.id
        let dragTranslation = dragTranslations[tab.id] ?? .zero
        let isDragging = draggingTabID == tab.id
        return HStack(spacing: 6) {
            Button {
                store.selectedID = tab.id
            } label: {
                Text(tab.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180)
            }
            .buttonStyle(.plain)

            Button {
                store.close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.42) : Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .offset(dragTranslation)
        .scaleEffect(isDragging ? 1.04 : 1)
        .shadow(color: isDragging ? Color.black.opacity(0.22) : Color.clear, radius: 10, x: 0, y: 5)
        .zIndex(isDragging ? 5 : 0)
        .gesture(tabDetachDragGesture(for: tab))
        .contextMenu {
            Button("在新窗口打开") {
                openTabInSeparateWindow(tab)
            }
            Button("关闭") {
                store.close(tab)
            }
        }
        .onTapGesture(count: 2) {
            openTabInSeparateWindow(tab)
        }
    }

    private func tabDetachDragGesture(for tab: ExternalMarkdownTabItem) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                draggingTabID = tab.id
                dragTranslations[tab.id] = value.translation
            }
            .onEnded { value in
                dragTranslations[tab.id] = nil
                draggingTabID = nil
                let distance = hypot(value.translation.width, value.translation.height)
                if distance >= 90 {
                    openTabInSeparateWindow(tab)
                }
            }
    }

    private func openTabInSeparateWindow(_ tab: ExternalMarkdownTabItem) {
        ExternalMarkdownWindowPresenter.presentSingleMarkdownWindow(fileURL: tab.fileURL)
        store.close(tab)
    }
}

/// SwiftUI 的 WindowGroup 标题是静态的，这里把当前选中的 Markdown 文件名同步到真实 NSWindow 标题。
private struct ExternalMarkdownWindowTitleAccessor: NSViewRepresentable {
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
        window.title = title
    }
}

/// 外部 Markdown 使用手动 NSWindow 承载，保证 Finder 连续打开多个 MD 时始终复用同一个标签页窗口。
@MainActor
enum ExternalMarkdownWindowPresenter {
    private static var tabWindow: NSWindow?
    private static var singleWindows: [String: NSWindow] = [:]

    static func openInTabs(fileURLs: [URL]) {
        ExternalMarkdownTabStore.shared.open(fileURLs: fileURLs)
        showTabWindow()
    }

    static func openInTabs(filePaths: [String]) {
        openInTabs(fileURLs: filePaths.map { URL(fileURLWithPath: $0) })
    }

    static func presentSingleMarkdownWindow(fileURL: URL) {
        let standardizedURL = fileURL.standardizedFileURL
        let key = standardizedURL.path
        if let window = singleWindows[key] {
            show(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown-\(standardizedURL.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: MarkdownEditorView(fileURL: standardizedURL)
                .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                .monospaced()
        )
        singleWindows[key] = window
        show(window)
    }

    private static func showTabWindow() {
        if let tabWindow {
            show(tabWindow)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Markdown"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: ExternalMarkdownTabWindowView()
                .environment(\.font, .system(size: 14, weight: .regular, design: .monospaced))
                .monospaced()
        )
        tabWindow = window
        show(window)
    }

    private static func show(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
