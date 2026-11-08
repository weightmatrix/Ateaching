import Foundation
import SwiftUI

// MARK: - 全局背景设置 - v1 - 管理主界面、清单、单列表格和导出图共用背景

struct AppBackgroundSettings: Codable, Equatable {
    enum DesignStyle: String, Codable, CaseIterable, Identifiable {
        case apple
        case minimal
        case vibrant
        case victorian

        var id: String { rawValue }

        var title: String {
            switch self {
            case .apple: return "Apple"
            case .minimal: return "极简"
            case .vibrant: return "活力"
            case .victorian: return "维多利亚"
            }
        }

        var accent: Color {
            switch self {
            case .apple: return .blue
            case .minimal: return .primary
            case .vibrant: return .purple
            case .victorian: return Color(red: 0.65, green: 0.32, blue: 0.30)
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .apple: return 18
            case .minimal: return 4
            case .vibrant: return 26
            case .victorian: return 8
            }
        }

        var border: Color {
            self == .victorian ? Color(red: 0.65, green: 0.49, blue: 0.25) : accent.opacity(0.25)
        }

        var subtitle: String {
            switch self {
            case .apple: return "系统蓝、通透材质与柔和圆角"
            case .minimal: return "灰阶、细边框与紧凑布局"
            case .vibrant: return "紫色渐层、大圆角与彩色卡片"
            case .victorian: return "卷草墙纸、繁复角花与古典雕花边框"
            }
        }
    }

    enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
        case plain
        case verdantGold

        var id: String { rawValue }

        var title: String {
            switch self {
            case .plain: return "纯色"
            case .verdantGold: return "青金渐层"
            }
        }
    }

    var backgroundStyle: BackgroundStyle = .verdantGold
    var designStyle: DesignStyle = .apple

    private enum CodingKeys: String, CodingKey {
        case backgroundStyle
        case designStyle
    }

    init(
        backgroundStyle: BackgroundStyle = .verdantGold,
        designStyle: DesignStyle = .apple
    ) {
        self.backgroundStyle = backgroundStyle
        self.designStyle = designStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backgroundStyle = try container.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .verdantGold
        designStyle = try container.decodeIfPresent(DesignStyle.self, forKey: .designStyle) ?? .apple
    }
}

enum AppBackgroundSettingsStore {
    private static let fileName = "setting-背景.json"
    private static let legacyFileName = "setting-单列表格外观.json"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private static let decoder = JSONDecoder()

    static func load(fileManager: FileManager = .default) -> AppBackgroundSettings {
        guard let url = try? fileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: existingURL(preferredURL: url, fileManager: fileManager)),
              let settings = try? decoder.decode(AppBackgroundSettings.self, from: data) else {
            return AppBackgroundSettings()
        }
        return settings
    }

    static func save(_ settings: AppBackgroundSettings, fileManager: FileManager = .default) throws {
        let url = try fileURL(fileManager: fileManager)
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .appAppearanceDidChange, object: nil)
    }

    private static func fileURL(fileManager: FileManager) throws -> URL {
        let root = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let folder = root.appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName, isDirectory: false)
    }

    private static func existingURL(preferredURL: URL, fileManager: FileManager) -> URL {
        if fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }
        let legacyURL = preferredURL.deletingLastPathComponent().appendingPathComponent(legacyFileName, isDirectory: false)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : preferredURL
    }
}

extension Notification.Name {
    static let appAppearanceDidChange = Notification.Name("appAppearanceDidChange")
}

struct AppDisplaySettingsView: View {
    @State private var settings = AppBackgroundSettingsStore.load()
    @State private var statusMessage = ""

    var body: some View {
        AppSettingsPage(title: "显示设置", subtitle: "调整界面风格与全局背景") {
            AppSettingsCard(title: "设计风格", systemImage: "circle.lefthalf.filled") {
                VStack(spacing: 10) {
                    ForEach(AppBackgroundSettings.DesignStyle.allCases) { style in
                        Button {
                            settings.designStyle = style
                        } label: {
                            HStack(spacing: 14) {
                                DesignStylePreview(style: style)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(style.title).font(.headline)
                                    Text(style.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: settings.designStyle == style ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.designStyle == style ? Color.accentColor : .secondary)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(settings.designStyle == style ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AppSettingsCard(title: "背景", systemImage: "paintpalette") {
                AppSettingsNavigationRow(
                    title: "背景设置",
                    subtitle: "管理主界面、清单和表格共用的背景",
                    systemImage: "photo.on.rectangle.angled"
                ) {
                    AppBackgroundSettingsView()
                }
            }
            AppSettingsStatusMessage(message: statusMessage)
        }
        .onChange(of: settings) { _, _ in save() }
    }

    private func save() {
        do {
            try AppBackgroundSettingsStore.save(settings)
            statusMessage = "已应用"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct DesignStylePreview: View {
    let style: AppBackgroundSettings.DesignStyle

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .fill(fill)
            if style == .victorian {
                VictorianFlourish()
                    .stroke(style.border, lineWidth: 1)
                    .padding(7)
            } else {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 0 ? accent : Color.primary.opacity(0.13))
                            .frame(width: index == 0 ? 13 : 7, height: 7)
                    }
                }
            }
        }
        .frame(width: 56, height: 42)
        .overlay(
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .stroke(style.border, lineWidth: style == .victorian ? 2 : 1)
        )
    }

    private var fill: Color {
        switch style {
        case .apple: return Color.blue.opacity(0.13)
        case .minimal: return Color.secondary.opacity(0.08)
        case .vibrant: return Color.purple.opacity(0.30)
        case .victorian: return Color(red: 0.91, green: 0.83, blue: 0.66)
        }
    }

    private var accent: Color { style.accent }
}

struct AppBackgroundSettingsView: View {
    @State private var settings = AppBackgroundSettingsStore.load()
    @State private var statusMessage = ""

    var body: some View {
        AppSettingsPage(
            title: "背景设置",
            subtitle: "选择主界面、清单和表格共用的背景"
        ) {
            AppSettingsCard(title: "背景管理", systemImage: "paintpalette") {
                Picker("背景", selection: $settings.backgroundStyle) {
                    ForEach(AppBackgroundSettings.BackgroundStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                AppBackgroundPreview(style: settings.backgroundStyle)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            AppSettingsStatusMessage(message: statusMessage)
        }
        .onChange(of: settings) { _, _ in
            save()
        }
    }

    private func save() {
        do {
            try AppBackgroundSettingsStore.save(settings)
            statusMessage = "已保存"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct AppBackgroundPreview: View {
    let style: AppBackgroundSettings.BackgroundStyle

    var body: some View {
        ZStack {
            AppBackgroundVisualStyle.pageBackground(for: style)
            VStack(alignment: .leading, spacing: 8) {
                Text(style.title)
                    .font(.headline)
                Text(style == .plain ? "主界面保持系统纯色背景" : "浅色：草绿到淡金；深色：墨绿到普鲁士蓝")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
