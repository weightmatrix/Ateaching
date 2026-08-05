import Foundation

struct TeachingNotebookSSCMigrationReport: Hashable {
    var lessonPlanFileCount: Int = 0
    var notebookFileCount: Int = 0
    var clearedNonH3FieldCount: Int = 0
    var repairedH3LinkCount: Int = 0
    var unresolvedH3LinkCount: Int = 0
    var removedCollectorPackageCount: Int = 0
    var repairedSamples: [String] = []
    var issueMessages: [String] = []
}

enum TeachingNotebookSSCMigrationService {
    static func run() throws -> TeachingNotebookSSCMigrationReport {
        let fileManager = FileManager.default
        let workspace = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let archiveRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
        let lessonRoot = workspace
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)

        let lessonFiles = try listCSVFilesRecursively(in: lessonRoot, fileManager: fileManager)
            .filter { isLessonMetaType($0) }
        let lessonIndex = try buildLessonIndex(lessonFiles: lessonFiles)

        let studentsRoot = archiveRoot.appendingPathComponent("学生", isDirectory: true)
        let notebookFiles = try listNotebookFiles(in: studentsRoot, fileManager: fileManager)

        var report = TeachingNotebookSSCMigrationReport()

        for lessonFile in lessonFiles {
            do {
                report.clearedNonH3FieldCount += try migrateLessonPlan(fileURL: lessonFile)
                report.lessonPlanFileCount += 1
            } catch {
                report.issueMessages.append("教案迁移失败：\(lessonFile.lastPathComponent) - \(error.localizedDescription)")
            }
        }

        for notebookFile in notebookFiles {
            do {
                let result = try migrateNotebook(fileURL: notebookFile, lessonIndex: lessonIndex)
                report.clearedNonH3FieldCount += result.clearedCount
                report.repairedH3LinkCount += result.repairedCount
                report.unresolvedH3LinkCount += result.unresolvedCount
                report.removedCollectorPackageCount += result.removedCollectorPackageCount
                if report.repairedSamples.count < 20 {
                    let remain = 20 - report.repairedSamples.count
                    report.repairedSamples.append(contentsOf: result.repairedSamples.prefix(remain))
                }
                report.issueMessages.append(contentsOf: result.issues)
                report.notebookFileCount += 1
            } catch {
                report.issueMessages.append("随堂迁移失败：\(notebookFile.lastPathComponent) - \(error.localizedDescription)")
            }
        }

        return report
    }

    private static func migrateLessonPlan(fileURL: URL) throws -> Int {
        var payload = try NodeMarkdownFileManager.read(fileURL: fileURL)
        let fixedTime = noon(of: Date())
        var cleared = 0

        for index in payload.0.nodes.indices {
            if payload.0.nodes[index].level == 3 {
                let expected = NodeMarkdownCacheCodec.encode(mtime: fixedTime)
                if payload.0.nodes[index].cache != expected {
                    payload.0.nodes[index].cache = expected
                    payload.0.nodes[index].mtimeCache = fixedTime
                }
                if !payload.0.nodes[index].sourceID.isEmpty {
                    payload.0.nodes[index].sourceID = ""
                    cleared += 1
                }
                if !payload.0.nodes[index].sourceFile.isEmpty {
                    payload.0.nodes[index].sourceFile = ""
                    cleared += 1
                }
            } else {
                if !payload.0.nodes[index].sourceID.isEmpty {
                    payload.0.nodes[index].sourceID = ""
                    cleared += 1
                }
                if !payload.0.nodes[index].sourceFile.isEmpty {
                    payload.0.nodes[index].sourceFile = ""
                    cleared += 1
                }
                if !payload.0.nodes[index].cache.isEmpty {
                    payload.0.nodes[index].cache = ""
                    cleared += 1
                }
            }
        }

        try NodeMarkdownFileManager.write(document: payload.0, meta: payload.1, to: fileURL)
        return cleared
    }

    private static func migrateNotebook(
        fileURL: URL,
        lessonIndex: LessonIndex
    ) throws -> (
        clearedCount: Int,
        repairedCount: Int,
        unresolvedCount: Int,
        removedCollectorPackageCount: Int,
        repairedSamples: [String],
        issues: [String]
    ) {
        var payload = try NodeMarkdownFileManager.read(fileURL: fileURL)
        let h3Time = noon(of: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        var cleared = 0
        var repaired = 0
        var unresolved = 0
        var removedCollectorPackageCount = 0
        var repairedSamples: [String] = []
        var issues: [String] = []

        payload.1.createdAt = isoString(noon(of: Date()))

        let h3Ranges = h3PackageRanges(in: payload.0.nodes)
        for range in h3Ranges.reversed() {
            guard payload.0.nodes.indices.contains(range.start) else { continue }
            guard payload.0.nodes[range.start].level == 3 else { continue }
            let sourceFile = payload.0.nodes[range.start].sourceFile
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceFile.contains("上课收集") {
                payload.0.nodes.removeSubrange(range.start..<range.end)
                removedCollectorPackageCount += 1
            }
        }

        for index in payload.0.nodes.indices {
            if payload.0.nodes[index].level != 3 {
                if !payload.0.nodes[index].sourceID.isEmpty {
                    payload.0.nodes[index].sourceID = ""
                    cleared += 1
                }
                if !payload.0.nodes[index].sourceFile.isEmpty {
                    payload.0.nodes[index].sourceFile = ""
                    cleared += 1
                }
                if !payload.0.nodes[index].cache.isEmpty {
                    payload.0.nodes[index].cache = ""
                    cleared += 1
                }
                continue
            }

            let oldSourceFile = payload.0.nodes[index].sourceFile
            let oldSourceID = payload.0.nodes[index].sourceID
            let rootText = payload.0.nodes[index].text

            if let resolved = resolveH3Link(sourceFile: oldSourceFile, sourceID: oldSourceID, h3Text: rootText, lessonIndex: lessonIndex) {
                let oldFile = oldSourceFile
                let oldID = oldSourceID
                if payload.0.nodes[index].sourceFile != resolved.sourceFile {
                    payload.0.nodes[index].sourceFile = resolved.sourceFile
                    repaired += 1
                }
                if payload.0.nodes[index].sourceID.caseInsensitiveCompare(resolved.sourceID) != .orderedSame {
                    payload.0.nodes[index].sourceID = resolved.sourceID
                    repaired += 1
                }
                if repairedSamples.count < 20, (oldFile != resolved.sourceFile || oldID.caseInsensitiveCompare(resolved.sourceID) != .orderedSame) {
                    repairedSamples.append("\(fileURL.lastPathComponent) | \(rootText) | \(oldFile)#\(oldID) -> \(resolved.sourceFile)#\(resolved.sourceID)")
                }
            } else {
                unresolved += 1
                issues.append("未修复H3链接：\(fileURL.lastPathComponent) / \(rootText)")
            }

            let expected = NodeMarkdownCacheCodec.encode(mtime: h3Time)
            if payload.0.nodes[index].cache != expected {
                payload.0.nodes[index].cache = expected
                payload.0.nodes[index].mtimeCache = h3Time
            }
        }

        try NodeMarkdownFileManager.write(document: payload.0, meta: payload.1, to: fileURL)
        return (cleared, repaired, unresolved, removedCollectorPackageCount, repairedSamples, issues)
    }

    private static func h3PackageRanges(in nodes: [NodeMarkdownNode]) -> [(start: Int, end: Int)] {
        var ranges: [(start: Int, end: Int)] = []
        var index = 0
        while index < nodes.count {
            if nodes[index].level == 3 {
                var end = index + 1
                while end < nodes.count {
                    let level = nodes[end].level
                    if level == 1 || level == 2 || level == 3 {
                        break
                    }
                    end += 1
                }
                ranges.append((start: index, end: end))
                index = end
            } else {
                index += 1
            }
        }
        return ranges
    }

    private struct LessonIndex {
        var byPathKey: [String: LessonChapter] = [:]
        var byFilenameKey: [String: [LessonChapter]] = [:]
        var byLessonNameKey: [String: [LessonChapter]] = [:]
        var byChapterNameKey: [String: [LessonChapter]] = [:]
    }

    private struct LessonChapter {
        var sourceFile: String
        var h3ByIDKey: [String: NodeMarkdownNode]
        var h3ByTextKey: [String: [NodeMarkdownNode]]
    }

    private static func buildLessonIndex(lessonFiles: [URL]) throws -> LessonIndex {
        var index = LessonIndex()
        let lessonRoot = try lessonPlanRoot()

        for file in lessonFiles {
            let relative = makeRelativePath(file, base: lessonRoot)
            guard !relative.isEmpty else { continue }
            let payload = try NodeMarkdownFileManager.read(fileURL: file)
            let h3Nodes = payload.0.nodes.filter { $0.level == 3 }
            var byID: [String: NodeMarkdownNode] = [:]
            var byText: [String: [NodeMarkdownNode]] = [:]

            for node in h3Nodes {
                byID[normalizeKey(node.id.uuidString)] = node
                byText[normalizeKey(node.text), default: []].append(node)
            }

            let chapter = LessonChapter(sourceFile: relative, h3ByIDKey: byID, h3ByTextKey: byText)
            index.byPathKey[normalizePathKey(relative)] = chapter
            index.byPathKey[normalizePathKey("教案/\(relative)")] = chapter
            let fileNameKey = normalizeKey(file.lastPathComponent)
            index.byFilenameKey[fileNameKey, default: []].append(chapter)
            let pathParts = relative.split(separator: "/").map(String.init)
            if let lessonName = pathParts.first {
                let lessonKey = chineseKey(lessonName)
                if !lessonKey.isEmpty {
                    index.byLessonNameKey[lessonKey, default: []].append(chapter)
                }
            }
            let chapterName = (file.lastPathComponent as NSString).deletingPathExtension
            let chapterKey = chineseKey(chapterName)
            if !chapterKey.isEmpty {
                index.byChapterNameKey[chapterKey, default: []].append(chapter)
            }
        }
        return index
    }

    private static func resolveH3Link(
        sourceFile: String,
        sourceID: String,
        h3Text: String,
        lessonIndex: LessonIndex
    ) -> (sourceFile: String, sourceID: String)? {
        let normalizedPath = normalizePathKey(sourceFile)
        let normalizedID = normalizeKey(sourceID)
        let normalizedText = normalizeKey(h3Text)
        let fileName = normalizeKey((sourceFile as NSString).lastPathComponent)
        let sourceIDSuffix6 = normalizedIDSuffix6(normalizedID)

        let chapterCandidates: [LessonChapter] = {
            if let direct = lessonIndex.byPathKey[normalizedPath] {
                return [direct]
            }
            if let byName = lessonIndex.byFilenameKey[fileName], !byName.isEmpty {
                return byName
            }
            let parsed = parseLegacySourceFile(sourceFile)
            if !parsed.lessonKey.isEmpty || !parsed.chapterKey.isEmpty {
                var candidates: [LessonChapter] = []
                if !parsed.lessonKey.isEmpty {
                    candidates.append(contentsOf: lessonIndex.byLessonNameKey[parsed.lessonKey] ?? [])
                }
                if !parsed.chapterKey.isEmpty {
                    candidates.append(contentsOf: lessonIndex.byChapterNameKey[parsed.chapterKey] ?? [])
                }
                if !candidates.isEmpty {
                    return deduplicatedChapters(candidates)
                }
            }
            return []
        }()

        for chapter in chapterCandidates {
            if let node = chapter.h3ByIDKey[normalizedID] {
                return (chapter.sourceFile, node.id.uuidString)
            }
            if !sourceIDSuffix6.isEmpty,
               let matched = chapter.h3ByIDKey.values.first(where: {
                   normalizedIDSuffix6(normalizeKey($0.id.uuidString)) == sourceIDSuffix6
               }) {
                return (chapter.sourceFile, matched.id.uuidString)
            }
        }

        for chapter in chapterCandidates {
            if let matches = chapter.h3ByTextKey[normalizedText], matches.count == 1, let node = matches.first {
                return (chapter.sourceFile, node.id.uuidString)
            }
        }

        return nil
    }

    private static func listNotebookFiles(in studentsRoot: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: studentsRoot.path) else { return [] }
        let studentFolders = try fileManager.contentsOfDirectory(
            at: studentsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        var files: [URL] = []
        for folder in studentFolders {
            let entries = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            files.append(contentsOf: entries.filter {
                $0.pathExtension.lowercased() == "csv"
                && $0.lastPathComponent.hasPrefix("随堂笔记_")
            })
        }
        return files
    }

    private static func listCSVFilesRecursively(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var files: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            guard item.pathExtension.lowercased() == "csv" else { continue }
            files.append(item)
        }
        return files
    }

    private static func isLessonMetaType(_ url: URL) -> Bool {
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        return type == "lessonplan" || type == "nodemarkdown" || type == "nodesmarkdown"
    }

    private static func lessonPlanRoot() throws -> URL {
        try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
    }

    private static func makeRelativePath(_ url: URL, base: URL) -> String {
        let full = url.standardizedFileURL.path
        let prefix = base.standardizedFileURL.path + "/"
        guard full.hasPrefix(prefix) else { return "" }
        return String(full.dropFirst(prefix.count))
            .replacingOccurrences(of: "\\", with: "/")
    }

    private static func normalizePathKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "//", with: "/")
            .lowercased()
    }

    private static func normalizeKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .lowercased()
    }

    private static func chineseKey(_ value: String) -> String {
        let base = (value as NSString).deletingPathExtension
        return base.unicodeScalars
            .filter { scalar in
                (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF)
                    || (scalar.value >= 0x3400 && scalar.value <= 0x4DBF)
            }
            .map(String.init)
            .joined()
    }

    private static func parseLegacySourceFile(_ sourceFile: String) -> (lessonKey: String, chapterKey: String) {
        let normalized = sourceFile.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return ("", "") }
        let lessonPart = parts.first ?? ""
        let chapterPart = parts.count > 1 ? parts[1] : (parts.first ?? "")
        return (chineseKey(lessonPart), chineseKey(chapterPart))
    }

    private static func deduplicatedChapters(_ chapters: [LessonChapter]) -> [LessonChapter] {
        var seen: Set<String> = []
        var result: [LessonChapter] = []
        for chapter in chapters {
            if seen.contains(chapter.sourceFile) { continue }
            seen.insert(chapter.sourceFile)
            result.append(chapter)
        }
        return result
    }

    private static func normalizedIDSuffix6(_ value: String) -> String {
        let token = value.replacingOccurrences(of: "-", with: "")
        guard token.count >= 6 else { return token }
        return String(token.suffix(6))
    }

    private static func noon(of date: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12, minute: 0, second: 0)) ?? date
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
