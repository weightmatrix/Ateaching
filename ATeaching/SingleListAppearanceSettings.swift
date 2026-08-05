import Foundation
import SwiftUI

// MARK: - 全局背景设置 - v1 - 管理主界面、清单、单列表格和导出图共用背景

struct AppBackgroundSettings: Codable, Equatable {
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

struct AppBackgroundSettingsView: View {
    @State private var settings = AppBackgroundSettingsStore.load()
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("背景管理") {
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

            TeachingStatusMessageSection(message: statusMessage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("背景设置")
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
