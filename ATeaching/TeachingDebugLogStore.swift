import Foundation

nonisolated enum TeachingDebugLogStore {
    static let didAppendNotification = Notification.Name("TeachingDebugLogStore.didAppend")
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
    private static let settingsLock = NSRecursiveLock()
    private static let writer = BufferedWriter()

    private final class BufferedWriter: @unchecked Sendable {
        let queue = DispatchQueue(label: "ATeaching.debug-log", qos: .utility)
        let lock = NSLock()
        var pending: [(Date, String, String)] = []
        var scheduled = false
        var dropped = 0
        let formatter = ISO8601DateFormatter()
        let session = UUID().uuidString.prefix(8)
        var heartbeatStarted = false

        func startHeartbeat() {
            lock.lock()
            let shouldStart = !heartbeatStarted
            heartbeatStarted = true
            lock.unlock()
            guard shouldStart else { return }
            scheduleHeartbeat()
        }

        private func scheduleHeartbeat() {
            queue.asyncAfter(deadline: .now() + 2) {
                let sent = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async {
                    let delay = ProcessInfo.processInfo.systemUptime - sent
                    if delay >= 0.5 {
                        TeachingDebugLogStore.append("mainQueueDelayMs=\(Int(delay * 1000))", category: "App.MainThreadDelay")
                    }
                    self.scheduleHeartbeat()
                }
            }
        }

        func enqueue(_ message: String, category: String) {
            lock.lock()
            if pending.count < 256 {
                pending.append((Date(), String(category.prefix(80)), String(message.prefix(4096))))
            } else {
                dropped += 1
            }
            let needsSchedule = !scheduled
            scheduled = true
            lock.unlock()
            if needsSchedule {
                queue.asyncAfter(deadline: .now() + 1) { self.flush() }
            }
        }

        func flush() {
            lock.lock()
            let entries = pending
            let lost = dropped
            pending.removeAll(keepingCapacity: true)
            dropped = 0
            scheduled = false
            lock.unlock()
            guard !entries.isEmpty else { return }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            var text = entries.map {
                "[\(formatter.string(from: $0.0))][\($0.1)] [session=\(session) version=\(version) pid=\(ProcessInfo.processInfo.processIdentifier)] \($0.2)\n"
            }.joined()
            if lost > 0 { text += "[Log.Throttle] discarded=\(lost)\n" }
            do {
                let url = try logFileURL(fileManager: .default)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size >= 4 * 1024 * 1024 {
                    let previous = url.deletingLastPathComponent().appendingPathComponent("调试日志.previous.log")
                    if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                    try FileManager.default.moveItem(at: url, to: previous)
                }
                if !FileManager.default.fileExists(atPath: url.path) {
                    try Data().write(to: url, options: .atomic)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(text.utf8))
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: didAppendNotification, object: nil)
                }
            } catch {
                NSLog("ATeaching log write failed: %@", error.localizedDescription)
            }
        }
    }

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
        settingsLock.lock()
        defer { settingsLock.unlock() }
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
        settingsLock.lock()
        defer { settingsLock.unlock() }
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
        settingsLock.lock()
        defer { settingsLock.unlock() }
        if let cachedSettings { return cachedSettings.layoutJitterLogsEnabled }
        return UserDefaults.standard.bool(forKey: layoutJitterLogEnabledDefaultsKey)
    }

    static func nodeMarkdownEditorPipeline() -> NodeMarkdownEditorPipeline {
        return loadSettings().nodeMarkdownEditorPipeline
    }

    static func isTextKit2FocusLocationOverlayEnabled() -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        if let cachedSettings {
            return cachedSettings.textKit2FocusLocationOverlayEnabled
        }
        return UserDefaults.standard.bool(forKey: textKit2FocusLocationOverlayDefaultsKey)
    }

    static func isLessonStatisticsEnabled() -> Bool {
        settingsLock.lock()
        defer { settingsLock.unlock() }
        if let cachedSettings {
            return cachedSettings.lessonStatisticsEnabled
        }
        return UserDefaults.standard.bool(forKey: lessonStatisticsEnabledDefaultsKey)
    }

    private static func nodeMarkdownEditorPipelineFromDefaults() -> NodeMarkdownEditorPipeline {
        let rawValue = UserDefaults.standard.string(forKey: nodeMarkdownEditorPipelineDefaultsKey) ?? NodeMarkdownEditorPipeline.textKit2.rawValue
        return NodeMarkdownEditorPipeline(rawValue: rawValue) ?? .textKit2
    }

    static func append(
        _ message: String,
        category: String = "General",
        force: Bool = false,
        fileManager: FileManager = .default
    ) {
        let settings = loadSettings(fileManager: fileManager)
        guard force || settings.persistLogsEnabled else { return }
        writer.enqueue(message, category: category)
    }

    static func readLog(fileManager: FileManager = .default) -> String {
        writer.queue.sync { writer.flush() }
        guard let url = try? logFileURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return content
    }

    static func clearLog(fileManager: FileManager = .default) throws {
        try writer.queue.sync {
            writer.lock.lock()
            writer.pending.removeAll()
            writer.dropped = 0
            writer.lock.unlock()
            let url = try logFileURL(fileManager: fileManager)
            try Data().write(to: url, options: .atomic)
        }
    }

    static func flushPending() { writer.queue.sync { writer.flush() } }

    static func beginSession() {
        guard loadSettings().persistLogsEnabled else { return }
        append("start pipeline=\(nodeMarkdownEditorPipeline().rawValue) jitter=\(isLayoutJitterLogsEnabled()) os=\(ProcessInfo.processInfo.operatingSystemVersionString)", category: "App.Session")
        writer.startHeartbeat()
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
