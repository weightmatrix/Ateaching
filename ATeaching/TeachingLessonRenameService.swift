import Foundation

// MARK: - 教案改名事务

/// 章教案和教案文件夹的名字属于H3母本身份的一部分。这里统一迁移所有可操作引用，
/// 并在任一步失败时恢复原始文件，避免只改母本名称后留下失效的SourceFile。
@MainActor
enum TeachingLessonRenameService {
    private struct PathChange {
        let oldRelativePath: String
        let newRelativePath: String
        let oldAssetPath: String
        let newAssetPath: String
        let renamedLessonFolder: (old: String, new: String)?

        func replacingSourceFile(_ value: String) -> String {
            replaceLeadingPath(value, old: oldRelativePath, new: newRelativePath)
        }

        func replacingAssetPath(_ value: String) -> String {
            let normalized = value.replacingOccurrences(of: "\\", with: "/")
            let searchable = normalized.lowercased() as NSString
            let old = oldAssetPath.lowercased()
            var searchRange = NSRange(location: 0, length: searchable.length)
            while searchRange.length > 0 {
                let match = searchable.range(of: old, options: [], range: searchRange)
                guard match.location != NSNotFound else { return value }
                let beforeIsBoundary = match.location == 0
                    || searchable.substring(with: NSRange(location: match.location - 1, length: 1)) == "/"
                let end = match.location + match.length
                let afterIsBoundary = end == searchable.length
                    || searchable.substring(with: NSRange(location: end, length: 1)) == "/"
                if beforeIsBoundary && afterIsBoundary {
                    let mutable = NSMutableString(string: normalized)
                    mutable.replaceCharacters(in: match, with: newAssetPath)
                    return mutable as String
                }
                let next = match.location + max(1, match.length)
                searchRange = NSRange(location: next, length: searchable.length - next)
            }
            return value
        }

        private func replaceLeadingPath(_ value: String, old: String, new: String) -> String {
            let normalized = value.replacingOccurrences(of: "\\", with: "/")
            if normalized.caseInsensitiveCompare(old) == .orderedSame {
                return new
            }
            let prefix = old + "/"
            guard normalized.lowercased().hasPrefix(prefix.lowercased()) else { return value }
            return new + String(normalized.dropFirst(old.count))
        }
    }

    private struct Move {
        let source: URL
        let destination: URL
    }

    static func handles(itemURL: URL, fileManager: FileManager = .default) -> Bool {
        guard let root = try? lessonRoot(fileManager: fileManager) else { return false }
        let item = itemURL.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard item.path.hasPrefix(rootPath + "/") else { return false }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            return item.deletingLastPathComponent().standardizedFileURL.path == rootPath
        }
        return item.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == rootPath
    }

    static func rename(
        itemURL: URL,
        to newName: String,
        fileManager: FileManager = .default
    ) throws {
        guard TeachingClassSessionCenter.shared.session == nil else {
            throw renameError("正在上课或笔记中，不能改教案名称。请先关闭当前会话。")
        }

        let source = itemURL.standardizedFileURL
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(newName, isDirectory: false)
            .standardizedFileURL
        guard source.path != destination.path else { return }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }

        let root = try lessonRoot(fileManager: fileManager)
        let change = try makePathChange(source: source, destination: destination, lessonRoot: root, fileManager: fileManager)
        var writes: [URL: Data] = [:]
        var moves: [Move] = [Move(source: source, destination: destination)]

        for rootURL in try referenceRoots(fileManager: fileManager) {
            for fileURL in try filesRecursively(in: rootURL, fileManager: fileManager) {
                let ext = fileURL.pathExtension.lowercased()
                guard ext == "csv" || ext == "nodemarkdown" || ext == "nmd" else { continue }
                if let data = try rewrittenCSVData(fileURL: fileURL, change: change) {
                    writes[fileURL] = data
                }
            }
        }

        try collectSyncBaselineWrites(change: change, into: &writes, fileManager: fileManager)
        try collectSyncConflictWrites(change: change, into: &writes, fileManager: fileManager)
        try collectAssociatedMoves(change: change, source: source, destination: destination, into: &moves, fileManager: fileManager)
        try collectRenamedFileMetadataWrites(moves: moves, into: &writes)

        let undoFiles = try courseInsertUndoFiles(fileManager: fileManager)
        try validateMoves(moves, fileManager: fileManager)
        try executeTransaction(
            writes: writes,
            moves: moves,
            filesToRemove: undoFiles,
            fileManager: fileManager
        )
    }

    private static func makePathChange(
        source: URL,
        destination: URL,
        lessonRoot: URL,
        fileManager: FileManager
    ) throws -> PathChange {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let oldRelative = relativePath(source, under: lessonRoot)
        let newRelative = relativePath(destination, under: lessonRoot)
        if isDirectory.boolValue {
            return PathChange(
                oldRelativePath: oldRelative,
                newRelativePath: newRelative,
                oldAssetPath: oldRelative,
                newAssetPath: newRelative,
                renamedLessonFolder: (source.lastPathComponent, destination.lastPathComponent)
            )
        }
        return PathChange(
            oldRelativePath: oldRelative,
            newRelativePath: newRelative,
            oldAssetPath: (oldRelative as NSString).deletingPathExtension,
            newAssetPath: (newRelative as NSString).deletingPathExtension,
            renamedLessonFolder: nil
        )
    }

    private static func rewrittenCSVData(fileURL: URL, change: PathChange) throws -> Data? {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let rows = ArchiveStorage.parseCSVRowsForMigration(text)
        guard let header = rows.first, !header.isEmpty else { return nil }
        let sourceFileColumn = header.firstIndex { $0.caseInsensitiveCompare("SourceFile") == .orderedSame }
        let contentColumn = header.firstIndex { $0.caseInsensitiveCompare("Content") == .orderedSame }
        guard sourceFileColumn != nil || contentColumn != nil else { return nil }

        var changed = false
        var outputRows = rows
        for rowIndex in outputRows.indices where rowIndex > 0 {
            if let sourceFileColumn, outputRows[rowIndex].indices.contains(sourceFileColumn) {
                let oldValue = outputRows[rowIndex][sourceFileColumn]
                let newValue = change.replacingSourceFile(oldValue)
                if newValue != oldValue {
                    outputRows[rowIndex][sourceFileColumn] = newValue
                    changed = true
                }
            }
            if let contentColumn, outputRows[rowIndex].indices.contains(contentColumn) {
                let oldValue = outputRows[rowIndex][contentColumn]
                let newValue = rewriteImageReferences(in: oldValue, change: change)
                if newValue != oldValue {
                    outputRows[rowIndex][contentColumn] = newValue
                    changed = true
                }
            }
        }
        guard changed else { return nil }
        let output = ArchiveStorage.renderCSVRowsForMigration(outputRows)
        return Data(output.utf8)
    }

    private static func rewriteImageReferences(in text: String, change: PathChange) -> String {
        let tokens = NodeMarkdownImageResourceManager.parseImageTokens(in: text)
        guard !tokens.isEmpty else { return text }
        let mutable = NSMutableString(string: text)
        for token in tokens.sorted(by: { $0.sourceRange.location > $1.sourceRange.location }) {
            let newPath = change.replacingAssetPath(token.relativePath)
            guard newPath != token.relativePath else { continue }
            let replacement = token.sourceText.replacingOccurrences(of: token.relativePath, with: newPath)
            mutable.replaceCharacters(in: token.sourceRange, with: replacement)
        }
        return mutable as String
    }

    private static func collectSyncBaselineWrites(
        change: PathChange,
        into writes: inout [URL: Data],
        fileManager: FileManager
    ) throws {
        let folder = try systemRoot(fileManager: fileManager)
            .appendingPathComponent("course-sync-baselines", isDirectory: true)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        for url in try filesRecursively(in: folder, fileManager: fileManager) where url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            guard let oldMap = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            var newMap: [String: String] = [:]
            var changed = false
            for (key, digest) in oldMap {
                let parts = key.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else {
                    newMap[key] = digest
                    continue
                }
                let oldSource = String(parts[0])
                let newSource = change.replacingSourceFile(oldSource)
                let newKey = "\(newSource)#\(parts[1])"
                changed = changed || newKey != key
                newMap[newKey] = digest
            }
            if changed {
                writes[url] = try JSONEncoder().encode(newMap)
            }
        }
    }

    private static func collectSyncConflictWrites(
        change: PathChange,
        into writes: inout [URL: Data],
        fileManager: FileManager
    ) throws {
        let folder = try systemRoot(fileManager: fileManager)
            .appendingPathComponent("course-sync-conflicts", isDirectory: true)
        guard fileManager.fileExists(atPath: folder.path) else { return }
        for url in try filesRecursively(in: folder, fileManager: fileManager) where url.pathExtension.lowercased() == "log" {
            let text = try String(contentsOf: url, encoding: .utf8)
            var changed = false
            var output: [String] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let raw = String(line)
                guard !raw.isEmpty,
                      let data = raw.data(using: .utf8),
                      var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let oldSource = json["sourceFile"] as? String else {
                    output.append(raw)
                    continue
                }
                let newSource = change.replacingSourceFile(oldSource)
                guard newSource != oldSource else {
                    output.append(raw)
                    continue
                }
                json["sourceFile"] = newSource
                let rewritten = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                output.append(String(decoding: rewritten, as: UTF8.self))
                changed = true
            }
            if changed {
                writes[url] = Data(output.joined(separator: "\n").utf8)
            }
        }
    }

    private static func collectAssociatedMoves(
        change: PathChange,
        source: URL,
        destination: URL,
        into moves: inout [Move],
        fileManager: FileManager
    ) throws {
        if change.renamedLessonFolder == nil {
            let sourceAssets = source.deletingPathExtension()
            let destinationAssets = destination.deletingPathExtension()
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: sourceAssets.path, isDirectory: &isDirectory), isDirectory.boolValue {
                moves.append(Move(source: sourceAssets, destination: destinationAssets))
            }
            return
        }

        guard let names = change.renamedLessonFolder else { return }
        for root in try studentReferenceRoots(fileManager: fileManager) {
            for url in try filesRecursively(in: root, fileManager: fileManager) {
                let oldPrefix = "教案_\(names.old)_完成情况_"
                let oldTemplateName = "教案_\(names.old).csv"
                let lowerName = url.lastPathComponent.lowercased()
                let destinationName: String?
                if url.lastPathComponent.hasPrefix(oldPrefix) {
                    destinationName = "教案_\(names.new)_完成情况_" + String(url.lastPathComponent.dropFirst(oldPrefix.count))
                } else if lowerName == oldTemplateName.lowercased() {
                    destinationName = "教案_\(names.new)." + url.pathExtension
                } else {
                    destinationName = nil
                }
                if let destinationName {
                    moves.append(Move(source: url, destination: url.deletingLastPathComponent().appendingPathComponent(destinationName)))
                }
            }
        }

        let templateFolder = try systemRoot(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.templateFolderName, isDirectory: true)
            .appendingPathComponent("教案模板", isDirectory: true)
        if fileManager.fileExists(atPath: templateFolder.path) {
            for url in try filesRecursively(in: templateFolder, fileManager: fileManager)
            where url.lastPathComponent.caseInsensitiveCompare("教案_\(names.old).csv") == .orderedSame {
                moves.append(
                    Move(
                        source: url,
                        destination: url.deletingLastPathComponent().appendingPathComponent("教案_\(names.new).\(url.pathExtension)")
                    )
                )
            }
        }
    }

    private static func collectRenamedFileMetadataWrites(
        moves: [Move],
        into writes: inout [URL: Data]
    ) throws {
        for move in moves {
            let ext = move.source.pathExtension.lowercased()
            guard ext == "csv" || ext == "nodemarkdown" || ext == "nmd" else { continue }
            let data = try writes[move.source] ?? Data(contentsOf: move.source)
            guard let text = String(data: data, encoding: .utf8) else { continue }
            var rows = ArchiveStorage.parseCSVRowsForMigration(text)
            guard let metaIndex = rows.firstIndex(where: {
                $0.count > 1 && $0[0] == "[META_TITLE]"
            }) else { continue }
            let newTitle = move.destination.deletingPathExtension().lastPathComponent
            guard rows[metaIndex][1] != newTitle else { continue }
            rows[metaIndex][1] = newTitle
            writes[move.source] = Data(ArchiveStorage.renderCSVRowsForMigration(rows).utf8)
        }
    }

    private static func validateMoves(_ moves: [Move], fileManager: FileManager) throws {
        var destinations: Set<String> = []
        for move in moves {
            guard destinations.insert(move.destination.standardizedFileURL.path).inserted else {
                throw renameError("改名产生了重复目标：\(move.destination.path)")
            }
            if fileManager.fileExists(atPath: move.destination.path),
               move.source.standardizedFileURL.path != move.destination.standardizedFileURL.path {
                throw renameError("目标已存在：\(move.destination.path)")
            }
        }
    }

    private static func executeTransaction(
        writes: [URL: Data],
        moves: [Move],
        filesToRemove: [URL],
        fileManager: FileManager
    ) throws {
        let originalData = try Dictionary(uniqueKeysWithValues: writes.keys.map { url in
            (url, try Data(contentsOf: url))
        })
        let removedData = try Dictionary(uniqueKeysWithValues: filesToRemove.map { url in
            (url, try Data(contentsOf: url))
        })
        var completedMoves: [Move] = []

        do {
            for (url, data) in writes {
                try data.write(to: url, options: .atomic)
            }
            for url in filesToRemove {
                try fileManager.removeItem(at: url)
            }
            for move in moves {
                try fileManager.moveItem(at: move.source, to: move.destination)
                completedMoves.append(move)
            }
        } catch {
            for move in completedMoves.reversed() where fileManager.fileExists(atPath: move.destination.path) {
                try? fileManager.moveItem(at: move.destination, to: move.source)
            }
            for (url, data) in originalData {
                try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
            for (url, data) in removedData {
                try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
            throw error
        }
    }

    private static func referenceRoots(fileManager: FileManager) throws -> [URL] {
        var roots = try studentReferenceRoots(fileManager: fileManager)
        roots.append(try lessonRoot(fileManager: fileManager))
        let templateFolder = try systemRoot(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.templateFolderName, isDirectory: true)
            .appendingPathComponent("教案模板", isDirectory: true)
        if fileManager.fileExists(atPath: templateFolder.path) {
            roots.append(templateFolder)
        }
        return roots
    }

    private static func studentReferenceRoots(fileManager: FileManager) throws -> [URL] {
        let students = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)
        let backups = try systemRoot(fileManager: fileManager)
            .appendingPathComponent("学生备份", isDirectory: true)
        return [students, backups].filter { fileManager.fileExists(atPath: $0.path) }
    }

    private static func courseInsertUndoFiles(fileManager: FileManager) throws -> [URL] {
        let folder = try systemRoot(fileManager: fileManager)
            .appendingPathComponent("course-insert-undo", isDirectory: true)
        guard fileManager.fileExists(atPath: folder.path) else { return [] }
        return try filesRecursively(in: folder, fileManager: fileManager)
    }

    private static func filesRecursively(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(url)
            }
        }
        return files
    }

    private static func lessonRoot(fileManager: FileManager) throws -> URL {
        try systemRoot(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
            .standardizedFileURL
    }

    private static func systemRoot(fileManager: FileManager) throws -> URL {
        try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .standardizedFileURL
    }

    private static func relativePath(_ url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1)).replacingOccurrences(of: "\\", with: "/")
    }

    private static func renameError(_ message: String) -> NSError {
        NSError(
            domain: "TeachingLessonRenameService",
            code: 785,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
