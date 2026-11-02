import SwiftUI

enum FrequentDocumentUsage {
    static let prefix = "frequent-document."
    static func record(_ url: URL) {
        guard let root = try? ArchiveStorage.ensureWorkspace(),
              url.path.hasPrefix(root.path + "/") else { return }
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
}

struct FrequentDocumentsView: View {
    @AppStorage("frequentItemCount") private var limit = 20
    @State private var revision = 0
    var body: some View {
        List {
            if let root = try? ArchiveStorage.ensureWorkspace() {
                let items = FrequentDocumentUsage.ranked().filter {
                    FileManager.default.fileExists(atPath: root.appendingPathComponent($0.path).path)
                }.prefix(limit)
                if items.isEmpty { Text("打开文档后，将自动统计常用文档").foregroundStyle(.secondary) }
                ForEach(Array(items), id: \.path) { item in
                    let url = root.appendingPathComponent(item.path)
                    NavigationLink {
                        FrequentDocumentDestination(url: url)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.deletingPathExtension().lastPathComponent)
                            Text("\(item.path) · 使用 \(item.count) 次").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .id(revision)
        .onAppear { NSUbiquitousKeyValueStore.default.synchronize(); revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in revision += 1 }
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
        List { NavigationLink("常用栏") { FrequentTabSettingsView() } }
            .navigationTitle("项目设置")
    }
}

private struct FrequentTabSettingsView: View {
    @AppStorage("frequentTabEnabled") private var enabled = true
    @AppStorage("frequentItemCount") private var limit = 20
    var body: some View {
        Form {
            Toggle("显示常用栏", isOn: $enabled)
            Picker("常用项目个数", selection: $limit) {
                ForEach(10...50, id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.menu)
        }.navigationTitle("常用栏")
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
