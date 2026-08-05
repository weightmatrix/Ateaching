import Foundation

// MARK: - 回收站条目模型 - v1 - 描述回收站中可恢复或清除的项目
struct RecycleBinEntry: Identifiable, Hashable {
    let storedName: String
    let originalRelativePath: String
    let deletedAt: Date
    let isDirectory: Bool

    var id: String { storedName }
    var displayName: String { URL(fileURLWithPath: originalRelativePath).lastPathComponent }
}

// MARK: - 回收站管理服务 - v1 - 负责回收站文件与CSV记录管理
enum RecycleBinManager {
    nonisolated static let recycleBinFolderName = "回收站"
    nonisolated static let csvFileName = "回收站记录.csv"

    // CSV 只记录三列：回收站内文件名、来源相对路径、删除时间。
    // 恢复和右键清除都以该记录为准，确保文件操作与记录一致。
    // MARK: - 回收记录模型 - v1 - 对应CSV中单条删除来源记录
    private struct Record: Hashable {
        let storedName: String
        let originalRelativePath: String
        let deletedAt: Date
    }

    // MARK: - 回收站上下文 - v1 - 聚合根目录回收站和CSV路径
    private struct Context {
        let rootURL: URL
        let recycleBinURL: URL
        let csvURL: URL
    }

    nonisolated private static let csvHeader = "stored_name,original_relative_path,deleted_at"

    nonisolated static func moveToRecycleBin(itemURL: URL, fileManager: FileManager = .default) throws {
        let context = try prepareContext(fileManager: fileManager)

        guard let relativePath = relativePath(of: itemURL, from: context.rootURL) else {
            throw ArchiveStorage.StorageError.invalidName
        }

        let storedName = uniqueStoredName(for: itemURL.lastPathComponent, in: context.recycleBinURL, fileManager: fileManager)
        let destinationURL = context.recycleBinURL.appendingPathComponent(storedName, isDirectory: false)

        try fileManager.moveItem(at: itemURL, to: destinationURL)

        var records = try loadRecords(from: context.csvURL)
        records.removeAll { $0.storedName == storedName }
        records.append(Record(storedName: storedName, originalRelativePath: relativePath, deletedAt: Date()))
        try saveRecords(records, to: context.csvURL)
    }

    nonisolated static func loadEntries(fileManager: FileManager = .default) throws -> [RecycleBinEntry] {
        let context = try prepareContext(fileManager: fileManager)
        var records = try loadRecords(from: context.csvURL)

        var entries: [RecycleBinEntry] = []
        var filteredRecords: [Record] = []

        for record in records {
            let fileURL = context.recycleBinURL.appendingPathComponent(record.storedName, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path) else { continue }

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            entries.append(
                RecycleBinEntry(
                    storedName: record.storedName,
                    originalRelativePath: record.originalRelativePath,
                    deletedAt: record.deletedAt,
                    isDirectory: values?.isDirectory == true
                )
            )
            filteredRecords.append(record)
        }

        if filteredRecords.count != records.count {
            try saveRecords(filteredRecords, to: context.csvURL)
            records = filteredRecords
        }

        return entries.sorted { $0.deletedAt > $1.deletedAt }
    }

    nonisolated static func restore(_ entry: RecycleBinEntry, fileManager: FileManager = .default) throws {
        let context = try prepareContext(fileManager: fileManager)
        let sourceURL = context.recycleBinURL.appendingPathComponent(entry.storedName, isDirectory: false)

        var destinationURL = context.rootURL.appendingPathComponent(entry.originalRelativePath, isDirectory: false)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        destinationURL = availableDestinationURL(preferred: destinationURL, fileManager: fileManager)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            try removeRecord(storedName: entry.storedName, csvURL: context.csvURL)
            return
        }

        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        try removeRecord(storedName: entry.storedName, csvURL: context.csvURL)
    }

    nonisolated static func permanentlyDelete(_ entry: RecycleBinEntry, fileManager: FileManager = .default) throws {
        let context = try prepareContext(fileManager: fileManager)
        let sourceURL = context.recycleBinURL.appendingPathComponent(entry.storedName, isDirectory: false)

        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.removeItem(at: sourceURL)
        }

        try removeRecord(storedName: entry.storedName, csvURL: context.csvURL)
    }

    nonisolated static func clearAll(fileManager: FileManager = .default) throws {
        let context = try prepareContext(fileManager: fileManager)
        let items = try fileManager.contentsOfDirectory(at: context.recycleBinURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        for item in items where item.lastPathComponent != csvFileName {
            try fileManager.removeItem(at: item)
        }

        try saveRecords([], to: context.csvURL)
    }

    nonisolated private static func prepareContext(fileManager: FileManager) throws -> Context {
        let rootURL = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let systemURL = rootURL.appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        let recycleBinURL = systemURL.appendingPathComponent(recycleBinFolderName, isDirectory: true)
        let csvURL = recycleBinURL.appendingPathComponent(csvFileName)

        try fileManager.createDirectory(at: recycleBinURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: csvURL.path) {
            try (csvHeader + "\n").write(to: csvURL, atomically: true, encoding: .utf8)
        }

        return Context(rootURL: rootURL, recycleBinURL: recycleBinURL, csvURL: csvURL)
    }

    nonisolated private static func relativePath(of url: URL, from rootURL: URL) -> String? {
        let rootPath = rootURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath) else { return nil }
        let value = String(targetPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return value.isEmpty ? nil : value
    }

    nonisolated private static func uniqueStoredName(for fileName: String, in recycleBinURL: URL, fileManager: FileManager) -> String {
        let base = UUID().uuidString
        let candidate = "\(base)__\(fileName)"
        let destination = recycleBinURL.appendingPathComponent(candidate, isDirectory: false)
        return fileManager.fileExists(atPath: destination.path) ? "\(UUID().uuidString)__\(fileName)" : candidate
    }

    nonisolated private static func availableDestinationURL(preferred url: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let extensionName = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent

        var index = 1
        while true {
            let suffix = "(恢复\(index))"
            let candidateName = extensionName.isEmpty ? "\(baseName)\(suffix)" : "\(baseName)\(suffix).\(extensionName)"
            let candidateURL = directory.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    nonisolated private static func removeRecord(storedName: String, csvURL: URL) throws {
        var records = try loadRecords(from: csvURL)
        records.removeAll { $0.storedName == storedName }
        try saveRecords(records, to: csvURL)
    }

    nonisolated private static func loadRecords(from csvURL: URL) throws -> [Record] {
        let formatter = ISO8601DateFormatter()
        let content = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let fields = parseCSVLine(line)
            guard fields.count == 3 else { return nil }
            guard let date = formatter.date(from: fields[2]) else { return nil }
            return Record(storedName: fields[0], originalRelativePath: fields[1], deletedAt: date)
        }
    }

    nonisolated private static func saveRecords(_ records: [Record], to csvURL: URL) throws {
        let formatter = ISO8601DateFormatter()
        var rows = [csvHeader]
        rows.append(
            contentsOf: records.map { record in
                [record.storedName, record.originalRelativePath, formatter.string(from: record.deletedAt)]
                    .map(escapeCSVField)
                    .joined(separator: ",")
            }
        )
        try rows.joined(separator: "\n").appending("\n").write(to: csvURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func escapeCSVField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    nonisolated private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        let chars = Array(line)
        var index = 0

        while index < chars.count {
            let character = chars[index]

            if character == "\"" {
                if insideQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\"")
                    index += 1
                } else {
                    insideQuotes.toggle()
                }
            } else if character == ",", !insideQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index += 1
        }

        result.append(current)
        return result
    }
}
