import Foundation

enum TeachingDebugLogStore {
    private static let debugFolderName = "Debug"
    private static let logFileName = "调试日志.log"
    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        return value
    }()
    private static let decoder = JSONDecoder()
    private static let layoutJitterLogEnabledDefaultsKey = "TeachingDebugLogStore.layoutJitterLogsEnabled"
    private static let nodeMarkdownEditorPipelineDefaultsKey = "TeachingDebugLogStore.nodeMarkdownEditorPipeline"
    private static let textKit2FocusLocationOverlayDefaultsKey = "TeachingDebugLogStore.textKit2FocusLocationOverlayEnabled"
    private static let lessonStatisticsEnabledDefaultsKey = "TeachingDebugLogStore.lessonStatisticsEnabled"
    private static var cachedSettings: DebugSettings?

    struct DebugSettings: Codable, Equatable {
        var persistLogsEnabled: Bool = false
        var layoutJitterLogsEnabled: Bool = false
        var nodeMarkdownEditorPipeline: NodeMarkdownEditorPipeline = .textKit2
        var textKit2FocusLocationOverlayEnabled: Bool = false
        var lessonStatisticsEnabled: Bool = false

        private enum CodingKeys: String, CodingKey {
            case persistLogsEnabled
            case layoutJitterLogsEnabled
            case nodeMarkdownEditorPipeline
            case textKit2FocusLocationOverlayEnabled
            case lessonStatisticsEnabled
        }

        init(
            persistLogsEnabled: Bool = false,
            layoutJitterLogsEnabled: Bool = false,
            nodeMarkdownEditorPipeline: NodeMarkdownEditorPipeline = .textKit2,
            textKit2FocusLocationOverlayEnabled: Bool = false,
            lessonStatisticsEnabled: Bool = false
        ) {
            self.persistLogsEnabled = persistLogsEnabled
            self.layoutJitterLogsEnabled = layoutJitterLogsEnabled
            self.nodeMarkdownEditorPipeline = nodeMarkdownEditorPipeline
            self.textKit2FocusLocationOverlayEnabled = textKit2FocusLocationOverlayEnabled
            self.lessonStatisticsEnabled = lessonStatisticsEnabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            persistLogsEnabled = try container.decodeIfPresent(Bool.self, forKey: .persistLogsEnabled) ?? false
            layoutJitterLogsEnabled = try container.decodeIfPresent(Bool.self, forKey: .layoutJitterLogsEnabled) ?? false
            let pipelineRawValue = try container.decodeIfPresent(String.self, forKey: .nodeMarkdownEditorPipeline) ?? NodeMarkdownEditorPipeline.textKit2.rawValue
            nodeMarkdownEditorPipeline = NodeMarkdownEditorPipeline(rawValue: pipelineRawValue) ?? .textKit2
            textKit2FocusLocationOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .textKit2FocusLocationOverlayEnabled) ?? false
            lessonStatisticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lessonStatisticsEnabled) ?? false
        }
    }

    static func loadSettings(fileManager: FileManager = .default) -> DebugSettings {
        if let cachedSettings {
            return cachedSettings
        }
        guard let url = try? settingsFileURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(DebugSettings.self, from: data) else {
            let fallback = DebugSettings(
                persistLogsEnabled: false,
                layoutJitterLogsEnabled: UserDefaults.standard.bool(forKey: layoutJitterLogEnabledDefaultsKey),
                nodeMarkdownEditorPipeline: nodeMarkdownEditorPipelineFromDefaults(),
                textKit2FocusLocationOverlayEnabled: UserDefaults.standard.bool(forKey: textKit2FocusLocationOverlayDefaultsKey),
                lessonStatisticsEnabled: UserDefaults.standard.bool(forKey: lessonStatisticsEnabledDefaultsKey)
            )
            cachedSettings = fallback
            return fallback
        }
        cachedSettings = settings
        UserDefaults.standard.set(settings.layoutJitterLogsEnabled, forKey: layoutJitterLogEnabledDefaultsKey)
        UserDefaults.standard.set(settings.nodeMarkdownEditorPipeline.rawValue, forKey: nodeMarkdownEditorPipelineDefaultsKey)
        UserDefaults.standard.set(settings.textKit2FocusLocationOverlayEnabled, forKey: textKit2FocusLocationOverlayDefaultsKey)
        UserDefaults.standard.set(settings.lessonStatisticsEnabled, forKey: lessonStatisticsEnabledDefaultsKey)
        return settings
    }

    static func saveSettings(_ settings: DebugSettings, fileManager: FileManager = .default) throws {
        let url = try settingsFileURL(fileManager: fileManager)
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
        cachedSettings = settings
        UserDefaults.standard.set(settings.layoutJitterLogsEnabled, forKey: layoutJitterLogEnabledDefaultsKey)
        UserDefaults.standard.set(settings.nodeMarkdownEditorPipeline.rawValue, forKey: nodeMarkdownEditorPipelineDefaultsKey)
        UserDefaults.standard.set(settings.textKit2FocusLocationOverlayEnabled, forKey: textKit2FocusLocationOverlayDefaultsKey)
        UserDefaults.standard.set(settings.lessonStatisticsEnabled, forKey: lessonStatisticsEnabledDefaultsKey)
    }

    static func isLayoutJitterLogsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: layoutJitterLogEnabledDefaultsKey)
    }

    static func nodeMarkdownEditorPipeline() -> NodeMarkdownEditorPipeline {
        if let cachedSettings {
            return cachedSettings.nodeMarkdownEditorPipeline
        }
        return loadSettings().nodeMarkdownEditorPipeline
    }

    static func isTextKit2FocusLocationOverlayEnabled() -> Bool {
        if let cachedSettings {
            return cachedSettings.textKit2FocusLocationOverlayEnabled
        }
        return UserDefaults.standard.bool(forKey: textKit2FocusLocationOverlayDefaultsKey)
    }

    static func isLessonStatisticsEnabled() -> Bool {
        if let cachedSettings {
            return cachedSettings.lessonStatisticsEnabled
        }
        return UserDefaults.standard.bool(forKey: lessonStatisticsEnabledDefaultsKey)
    }

    private static func nodeMarkdownEditorPipelineFromDefaults() -> NodeMarkdownEditorPipeline {
        let rawValue = UserDefaults.standard.string(forKey: nodeMarkdownEditorPipelineDefaultsKey) ?? NodeMarkdownEditorPipeline.textKit2.rawValue
        return NodeMarkdownEditorPipeline(rawValue: rawValue) ?? .textKit2
    }

    static func append(_ message: String, category: String = "General", fileManager: FileManager = .default) {
        let settings = loadSettings(fileManager: fileManager)
        guard settings.persistLogsEnabled else { return }
        guard let url = try? logFileURL(fileManager: fileManager) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)][\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            if !fileManager.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    static func readLog(fileManager: FileManager = .default) -> String {
        guard let url = try? logFileURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }

    static func clearLog(fileManager: FileManager = .default) throws {
        let url = try logFileURL(fileManager: fileManager)
        try Data().write(to: url, options: .atomic)
    }

    private static func settingsFileURL(fileManager: FileManager) throws -> URL {
        let settingsRoot = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: settingsRoot, withIntermediateDirectories: true)
        return settingsRoot.appendingPathComponent("setting-debug", isDirectory: false)
    }

    private static func logFileURL(fileManager: FileManager) throws -> URL {
        let debugFolder = try debugFolderURL(fileManager: fileManager)
        return debugFolder.appendingPathComponent(logFileName, isDirectory: false)
    }

    private static func debugFolderURL(fileManager: FileManager) throws -> URL {
        let root = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(debugFolderName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
