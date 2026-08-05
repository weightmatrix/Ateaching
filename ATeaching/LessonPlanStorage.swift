import Foundation

// MARK: - 教案存储服务 - v1 - 管理系统教案目录与章教案文件创建
enum LessonPlanStorage {
    enum LessonPlanError: LocalizedError {
        case invalidName
        case invalidDirectoryLevel
        case unsupportedOperation

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "名称无效。"
            case .invalidDirectoryLevel:
                return "仅支持一级教案目录。"
            case .unsupportedOperation:
                return "当前目录不支持此操作。"
            }
        }
    }

    static func lessonPlanRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let url = root
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadRootEntries(fileManager: FileManager = .default) throws -> (URL, [ArchiveEntry]) {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        return (root, try loadEntries(in: root, fileManager: fileManager))
    }

    static func loadEntries(in directoryURL: URL, fileManager: FileManager = .default) throws -> [ArchiveEntry] {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        guard isAllowedDirectory(directoryURL, root: root) else {
            throw LessonPlanError.invalidDirectoryLevel
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let entries = urls.compactMap { url -> ArchiveEntry? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values?.isDirectory == true
            if isDirectory, directoryURL.standardizedFileURL.path != root.standardizedFileURL.path {
                return nil
            }
            let metaType: String?
            if isDirectory || url.pathExtension.lowercased() != "csv" {
                metaType = nil
            } else {
                metaType = ArchiveStorage.readMetaType(fileURL: url)
            }
            return ArchiveEntry(url: url, isDirectory: isDirectory, metaType: metaType)
        }

        return entries.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory && !$1.isDirectory
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func createLessonFolder(named name: String, in rootURL: URL, fileManager: FileManager = .default) throws {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        guard rootURL.standardizedFileURL.path == root.standardizedFileURL.path else {
            throw LessonPlanError.unsupportedOperation
        }
        let validated = try validateName(name)
        let folderURL = rootURL.appendingPathComponent(validated, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
    }

    static func createChapterFile(named name: String, in lessonFolderURL: URL, fileManager: FileManager = .default) throws -> URL {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        guard directoryDepth(of: lessonFolderURL, root: root) == 1 else {
            throw LessonPlanError.unsupportedOperation
        }
        let validated = try validateName(name)
        let finalName = validated.lowercased().hasSuffix(".csv") ? validated : "\(validated).csv"
        let fileURL = lessonFolderURL.appendingPathComponent(finalName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileWriteFileExists)
        }

        let now = Date()
        let document = NodeMarkdownDocument(nodes: [
            NodeMarkdownNode(
                level: 1,
                text: "",
                sourceID: "",
                sourceFile: "",
                cache: NodeMarkdownCacheCodec.encode(mtime: now),
                mtimeCache: now
            )
        ])
        let meta = NodeMarkdownFileMeta(
            id: UUID().uuidString,
            title: (finalName as NSString).deletingPathExtension,
            template: "nil",
            createdAt: ISO8601DateFormatter().string(from: now),
            type: "lessonplan"
        )
        try NodeMarkdownFileManager.write(document: document, meta: meta, to: fileURL)
        return fileURL
    }

    @MainActor
    static func renameItem(at itemURL: URL, to newName: String, fileManager: FileManager = .default) throws {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        let depth = directoryDepth(of: itemURL, root: root)
        guard depth == 1 || depth == 2 else {
            throw LessonPlanError.unsupportedOperation
        }
        let validated = try validateName(newName)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let finalName: String
        if isDirectory.boolValue {
            finalName = validated
        } else {
            finalName = validated.lowercased().hasSuffix(".csv") ? validated : "\(validated).csv"
        }
        try TeachingLessonRenameService.rename(itemURL: itemURL, to: finalName, fileManager: fileManager)
    }

    static func deleteItem(at itemURL: URL, fileManager: FileManager = .default) throws {
        let root = try lessonPlanRootURL(fileManager: fileManager)
        let depth = directoryDepth(of: itemURL, root: root)
        guard depth == 1 || depth == 2 else {
            throw LessonPlanError.unsupportedOperation
        }
        try RecycleBinManager.moveToRecycleBin(itemURL: itemURL, fileManager: fileManager)
    }

    static func isAtRoot(_ directoryURL: URL, fileManager: FileManager = .default) -> Bool {
        guard let root = try? lessonPlanRootURL(fileManager: fileManager) else { return false }
        return directoryURL.standardizedFileURL.path == root.standardizedFileURL.path
    }

    static func directoryDepth(of directoryURL: URL, fileManager: FileManager = .default) -> Int {
        guard let root = try? lessonPlanRootURL(fileManager: fileManager) else { return 0 }
        return directoryDepth(of: directoryURL, root: root)
    }

    private static func isAllowedDirectory(_ directoryURL: URL, root: URL) -> Bool {
        let depth = directoryDepth(of: directoryURL, root: root)
        return depth == 0 || depth == 1
    }

    private static func directoryDepth(of directoryURL: URL, root: URL) -> Int {
        let rootPath = root.standardizedFileURL.path
        let currentPath = directoryURL.standardizedFileURL.path
        guard currentPath.hasPrefix(rootPath) else { return Int.max }
        let suffix = String(currentPath.dropFirst(rootPath.count))
        return suffix.split(separator: "/").count
    }

    private static func validateName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw LessonPlanError.invalidName
        }
        guard !name.contains("/") && !name.contains(":") else {
            throw LessonPlanError.invalidName
        }
        return name
    }
}
