import Foundation

enum TeachingPDFSettingsStore {
    private static let fileName = "Setting-PDFout"
    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        return value
    }()
    private static let decoder = JSONDecoder()

    static func load(fileManager: FileManager = .default) -> TeachingPDFExportSettings {
        guard let url = try? fileURL(fileManager: fileManager),
              fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let settings = try? decoder.decode(TeachingPDFExportSettings.self, from: data) else {
            return TeachingPDFExportSettings()
        }
        return settings.normalized()
    }

    static func save(_ settings: TeachingPDFExportSettings, fileManager: FileManager = .default) throws {
        let url = try fileURL(fileManager: fileManager)
        let data = try encoder.encode(settings.normalized())
        try data.write(to: url, options: .atomic)
    }

    private static func fileURL(fileManager: FileManager) throws -> URL {
        let root = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.settingsFolderName, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(fileName, isDirectory: false)
    }
}
