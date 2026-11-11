import SwiftUI
import UniformTypeIdentifiers

fileprivate struct FrequentDocumentSnapshotItem: Codable, Hashable, Identifiable {
    let relativePath: String
    let absolutePath: String
    let metaType: String?

    var id: String { relativePath }
    var url: URL { URL(fileURLWithPath: absolutePath) }
}

enum FrequentDocumentUsage {
    static let prefix = "frequent-document."
    private static let pinnedKey = "frequent-document.pinned-paths"
    private static let snapshotKey = "frequent-document.snapshot"

    static func record(_ url: URL) {
        guard let root = try? ArchiveStorage.ensureWorkspace(),
              isEligible(url, workspaceRoot: root) else { return }
        let relative = String(url.path.dropFirst(root.path.count + 1))
        let defaults = UserDefaults.standard
        let device = defaults.string(forKey: "frequentDeviceID") ?? UUID().uuidString
        defaults.set(device, forKey: "frequentDeviceID")
        let key = prefix + device
        let cloud = NSUbiquitousKeyValueStore.default
        var counts = cloud.dictionary(forKey: key) ?? [:]
        for (path, value) in defaults.dictionary(forKey: key) ?? [:] {
            counts[path] = max((counts[path] as? NSNumber)?.intValue ?? 0, (value as? NSNumber)?.intValue ?? 0)
        }
        counts[relative] = ((counts[relative] as? NSNumber)?.intValue ?? 0) + 1
        defaults.set(counts, forKey: key)
        cloud.set(counts, forKey: key)
        cloud.synchronize()
        persistSnapshot(workspaceRoot: root)
    }

    static func ranked() -> [(path: String, count: Int)] {
        var totals: [String: Int] = [:]
        var records = NSUbiquitousKeyValueStore.default.dictionaryRepresentation
        if let device = UserDefaults.standard.string(forKey: "frequentDeviceID") {
            let key = prefix + device
            var counts = records[key] as? [String: Any] ?? [:]
            for (path, value) in UserDefaults.standard.dictionary(forKey: key) ?? [:] {
                counts[path] = max((counts[path] as? NSNumber)?.intValue ?? 0, (value as? NSNumber)?.intValue ?? 0)
            }
            records[key] = counts
        }
        for (key, value) in records where key.hasPrefix(prefix) {
            guard let counts = value as? [String: Any] else { continue }
            for (path, count) in counts {
                totals[path, default: 0] += (count as? NSNumber)?.intValue ?? 0
            }
        }
        return totals.map { (path: $0.key, count: $0.value) }.sorted {
            $0.count == $1.count ? $0.path < $1.path : $0.count > $1.count
        }
    }

    static func pinnedPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
    }

    static func setPinnedPaths(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: pinnedKey)
    }

    fileprivate static func loadSnapshot() -> [FrequentDocumentSnapshotItem] {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return [] }
        return (try? JSONDecoder().decode([FrequentDocumentSnapshotItem].self, from: data)) ?? []
    }

    private static func persistSnapshot(workspaceRoot: URL) {
        let items = ranked().compactMap { rankedItem -> FrequentDocumentSnapshotItem? in
            let url = workspaceRoot.appendingPathComponent(rankedItem.path)
            guard isEligible(url, workspaceRoot: workspaceRoot) else { return nil }
            return FrequentDocumentSnapshotItem(
                relativePath: rankedItem.path,
                absolutePath: url.path,
                metaType: ArchiveStorage.readMetaType(fileURL: url)
            )
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: snapshotKey)
    }

    static func isEligible(_ url: URL, workspaceRoot: URL) -> Bool {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return false }

        let relative = String(path.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        guard components.first == ArchiveStorage.archiveFolderName,
              components.count >= 2,
              FileManager.default.fileExists(atPath: path) else { return false }

        let studentNames = Set(((try? TeachingStudentSettingsStore.loadStudents()) ?? []).map(\.name))
        if components.count >= 3, studentNames.contains(components[1]) { return false }

        let name = url.lastPathComponent
        let excludedPrefixes = ["随堂笔记_", "学生信息_", "上课信息_"]
        guard !excludedPrefixes.contains(where: name.hasPrefix),
              !(name.hasPrefix("教案_") && name.contains("_完成情况_")) else { return false }

        let ext = url.pathExtension.lowercased()
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        return ext == "md"
            || ext == "nodemarkdown"
            || ext == "nmd"
            || (ext == "csv" && ["singlelist", "autosinglelist", "checklist", "nodemarkdown", "nodesmarkdown", "lessonplan"].contains(type))
    }
}

struct FrequentDocumentsView: View {
    @AppStorage("frequentItemCount") private var limit = 20
    @State private var snapshot: [FrequentDocumentSnapshotItem] = []
    @State private var pinnedPaths: [String] = []
    @State private var draggedPinnedPath: String?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        List {
            let itemsByPath = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.relativePath, $0) })
            let existingPinned = pinnedPaths.filter { itemsByPath[$0] != nil }
            let regularItems = snapshot.filter { !existingPinned.contains($0.relativePath) }
            let visibleRegularItems = Array(regularItems.prefix(max(0, limit - existingPinned.count)))

            if existingPinned.isEmpty, visibleRegularItems.isEmpty {
                ContentUnavailableView("暂无常用文件", systemImage: "star", description: Text("从档案打开文件后会显示在这里"))
            }

            if !existingPinned.isEmpty {
                Section("置顶") {
                    ForEach(existingPinned, id: \.self) { path in
                        if let item = itemsByPath[path] {
                            documentRow(item: item, isPinned: true)
                                .onDrag {
                                    draggedPinnedPath = path
                                    return NSItemProvider(object: path as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: FrequentPinnedDropDelegate(
                                        targetPath: path,
                                        pinnedPaths: $pinnedPaths,
                                        draggedPath: $draggedPinnedPath,
                                        onDropCompleted: savePins
                                    )
                                )
                        }
                    }
                }
            }

            if !visibleRegularItems.isEmpty {
                Section(existingPinned.isEmpty ? "文件" : "常用") {
                    ForEach(visibleRegularItems) { item in
                        documentRow(item: item, isPinned: false)
                    }
                }
            }
        }
        .listStyle(.plain)
        .onAppear {
            snapshot = FrequentDocumentUsage.loadSnapshot()
            pinnedPaths = FrequentDocumentUsage.pinnedPaths()
        }
    }

    @ViewBuilder
    private func documentRow(item: FrequentDocumentSnapshotItem, isPinned: Bool) -> some View {
        let url = item.url
        let entry = ArchiveEntry(url: url, isDirectory: false, metaType: item.metaType)

        Group {
            #if os(macOS)
            if opensInSeparateWindow(url) {
                Button { open(url) } label: { archiveStyleLabel(entry) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink { FrequentDocumentDestination(url: url) } label: { archiveStyleLabel(entry) }
            }
            #else
            NavigationLink { FrequentDocumentDestination(url: url) } label: { archiveStyleLabel(entry) }
            #endif
        }
        .contextMenu {
            if isPinned {
                Button("取消置顶", systemImage: "pin.slash") { unpin(item.relativePath) }
            } else {
                Button("置顶", systemImage: "pin") { pin(item.relativePath) }
            }
        }
    }

    private func archiveStyleLabel(_ entry: ArchiveEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.iconName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(entry.iconColor)
                .frame(width: 36, height: 36)
            Text(entry.name)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func pin(_ path: String) {
        guard !pinnedPaths.contains(path) else { return }
        pinnedPaths.append(path)
        savePins()
    }

    private func unpin(_ path: String) {
        pinnedPaths.removeAll { $0 == path }
        savePins()
    }

    private func savePins() {
        FrequentDocumentUsage.setPinnedPaths(pinnedPaths)
    }

    #if os(macOS)
    private func opensInSeparateWindow(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        return ext == "md" || ext == "nodemarkdown" || ext == "nmd"
            || type == "nodemarkdown" || type == "nodesmarkdown" || type == "lessonplan"
    }

    private func open(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        if ext == "md" {
            openWindow(id: "markdown-editor", value: url.path)
        } else if ext == "nodemarkdown" || ext == "nmd" || type == "nodemarkdown" || type == "nodesmarkdown" || type == "lessonplan" {
            openWindow(id: "nodemarkdown-editor", value: url.path)
        }
    }
    #endif
}

private struct FrequentPinnedDropDelegate: DropDelegate {
    let targetPath: String
    @Binding var pinnedPaths: [String]
    @Binding var draggedPath: String?
    let onDropCompleted: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedPath,
              draggedPath != targetPath,
              let sourceIndex = pinnedPaths.firstIndex(of: draggedPath),
              let targetIndex = pinnedPaths.firstIndex(of: targetPath) else { return }
        withAnimation {
            pinnedPaths.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedPath = nil
        onDropCompleted()
        return true
    }
}

private struct FrequentDocumentDestination: View {
    let url: URL
    @ViewBuilder var body: some View {
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        if url.pathExtension.lowercased() == "md" {
            MarkdownEditorView(fileURL: url)
        } else if type == "singlelist" {
            SingleListDocumentEditorView(fileURL: url)
        } else if type == "autosinglelist" {
            AutoFillDocumentEditorView(fileURL: url)
        } else if type == "checklist" {
            ChecklistDocumentEditorView(fileURL: url)
        } else {
            NodeMarkdownEditorView(fileURL: url)
        }
    }
}

struct ProjectUsageSettingsView: View {
    var body: some View {
        AppSettingsPage(title: "项目设置", subtitle: "管理主界面项目的显示与使用方式") {
            AppSettingsCard(title: "导航栏", systemImage: "square.grid.2x2") {
                AppSettingsNavigationRow(
                    title: "常用栏",
                    subtitle: "设置常用入口的显示和文档数量",
                    systemImage: "star.fill"
                ) {
                    FrequentTabSettingsView()
                }
            }
        }
    }
}

private struct FrequentTabSettingsView: View {
    @AppStorage("frequentTabEnabled") private var enabled = true
    @AppStorage("frequentItemCount") private var limit = 20
    var body: some View {
        AppSettingsPage(title: "常用栏", subtitle: "自动汇总常用文档，方便快速打开") {
            AppSettingsCard(title: "显示设置", systemImage: "star.fill") {
                Toggle(isOn: $enabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示常用栏").font(.headline)
                        Text("在主导航中显示常用入口")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .padding(.vertical, 8)
                Divider()
                Picker(selection: $limit) {
                    ForEach(10...50, id: \.self) { Text("\($0) 个").tag($0) }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("常用项目个数").font(.headline)
                        Text("选择常用列表最多显示的文档数量")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .pickerStyle(.menu)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - 分页类型 - v1 - 定义授课档案设置三类分页信息
enum TeachingTab: CaseIterable, Hashable {
    case teaching
    case frequent
    case archive
    case screenCast
    case settings

    var title: String {
        switch self {
        case .teaching:
            return "教学"
        case .frequent:
            return "常用"
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
        case .frequent: return "star.fill"
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
        if AppBackgroundSettingsStore.load().designStyle == .apple {
            return .accentColor
        }
        if AppBackgroundSettingsStore.load().designStyle == .minimal {
            return .primary
        }
        if AppBackgroundSettingsStore.load().designStyle.isOrnamental {
            return AppBackgroundSettingsStore.load().designStyle.accent
        }
        switch self {
        case .frequent: return .yellow
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
    @AppStorage("frequentTabEnabled") private var frequentTabEnabled = true
    @Binding var selectedTab: TeachingTab

    var body: some View {
        let style = AppBackgroundSettingsStore.load().designStyle
        HStack(spacing: 12) {
            ForEach(TeachingTab.allCases.filter { frequentTabEnabled || $0 != .frequent }, id: \.self) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, style == .minimal ? 6 : 10)
        .padding(.vertical, style == .minimal ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: style == .minimal ? 9 : 18, style: .continuous)
                .fill(style == .apple ? Color.primary.opacity(0.055) : Color.secondary.opacity(style == .vibrant ? 0.13 : 0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: style == .minimal ? 9 : 18, style: .continuous)
                .stroke(Color.primary.opacity(style == .apple ? 0.10 : 0.06), lineWidth: 1)
        }
        .shadow(color: style == .apple ? Color.black.opacity(0.10) : .clear, radius: 18, y: 8)
    }

    @ViewBuilder
    private func tabButton(for tab: TeachingTab) -> some View {
        let isSelected = selectedTab == tab
        let style = AppBackgroundSettingsStore.load().designStyle

        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                Text(tab.title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .appGlassButtonStyle(.regular)
        .foregroundStyle(isSelected ? tab.accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: style == .minimal ? 7 : 12, style: .continuous)
                .fill(isSelected ? tab.accentColor.opacity(style == .vibrant ? 0.22 : 0.13) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected && style != .apple ? tab.accentColor.opacity(0.45) : .clear, lineWidth: 1)
        )
        .shadow(color: isSelected && style == .vibrant ? tab.accentColor.opacity(0.40) : .clear, radius: 7)
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
