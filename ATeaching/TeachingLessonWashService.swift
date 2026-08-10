import Foundation

// MARK: - 洗教案结果 - 汇总母本、随堂笔记和人工待办

struct TeachingLessonWashUnresolvedItem: Hashable {
    let category: String
    let student: String
    let file: String
    let title: String
    let uuid: String
    let sourceID: String
    let sourceFile: String
    let reason: String

    var displayLine: String {
        [category, student, title, reason].filter { !$0.isEmpty }.joined(separator: " | ")
    }
}

struct TeachingLessonWashSkippedFile: Hashable {
    let category: String
    let file: String
    let reason: String

    var displayLine: String {
        "\(category) | \(file) | \(reason)"
    }
}

struct TeachingLessonWashIdentityChange: Hashable {
    let category: String
    let student: String
    let file: String
    let row: Int
    let level: Int
    let title: String
    let oldUUID: String
    let newUUID: String
    let reason: String
}

struct TeachingLessonWashReport: Hashable {
    var lessonFileCount = 0
    var duplicateH3GroupCount = 0
    var reassignedH3Count = 0
    var reassignedOtherNodeCount = 0
    var removedImageGarbageCount = 0
    var removedFormulaLinkCount = 0
    var removedLegacyImageSizeLineCount = 0
    var notebookFileCount = 0
    var rebuiltNotebookPackageCount = 0
    var relinkedNotebookH3Count = 0
    var reassignedNotebookNewH3Count = 0
    var reassignedNotebookOtherNodeCount = 0
    var removedDuplicateNotebookPackageCount = 0
    var unresolvedItems: [TeachingLessonWashUnresolvedItem] = []
    var skippedFiles: [TeachingLessonWashSkippedFile] = []
    var identityChanges: [TeachingLessonWashIdentityChange] = []
    var mappingFileURL: URL?
    var reportFileURL: URL?
}

// MARK: - 洗教案服务 - 一次扫描形成映射，再统一修复母本和随堂笔记

enum TeachingLessonWashService {
    private static let collectorRelativePath = "上课收集/上课收集.CSV"
    private static let imagePlaceholder = "🌼{图片}🌼"

    private struct LessonState {
        let url: URL
        let relativePath: String
        var document: NodeMarkdownDocument
        let meta: NodeMarkdownFileMeta
    }

    private struct H3Occurrence {
        let fileIndex: Int
        let rowIndex: Int
        let relativePath: String
        let oldID: UUID
        let title: String
        let package: [NodeMarkdownNode]
    }

    private struct H3MappingRecord: Codable {
        let sourceFile: String
        let row: Int
        let oldUUID: String
        let title: String
        let oldSourceID: String
        let oldSourceFile: String
        let oldCache: String
        let oldPackageJSON: String
        let action: String
        let newUUID: String
    }

    private struct OccurrenceKey: Hashable {
        let fileIndex: Int
        let rowIndex: Int
    }

    private struct LinkKey: Hashable {
        let sourceFile: String
        let sourceID: String
    }

    private struct CanonicalH3 {
        let sourceFile: String
        let id: UUID
        let title: String
        let package: [NodeMarkdownNode]

        var identityKey: String {
            "\(normalizePath(sourceFile))#\(id.uuidString.lowercased())"
        }
    }

    private struct CanonicalIndex {
        var byCurrentLink: [LinkKey: [CanonicalH3]] = [:]
        var byOldLink: [LinkKey: [CanonicalH3]] = [:]
        var byCurrentID: [String: [CanonicalH3]] = [:]
        var byOldID: [String: [CanonicalH3]] = [:]
        var byTitle: [String: [CanonicalH3]] = [:]
        var byDigest: [String: [CanonicalH3]] = [:]
    }

    private struct NotebookResult {
        var document: NodeMarkdownDocument
        var rebuiltCount = 0
        var relinkedH3Count = 0
        var reassignedNewH3Count = 0
        var reassignedOtherNodeCount = 0
        var removedDuplicateCount = 0
        var unresolved: [TeachingLessonWashUnresolvedItem] = []
        var identityChanges: [TeachingLessonWashIdentityChange] = []
    }

    /// 正式母本中的UUID可以在多个学生的同一H3包中重复出现，这是引用关系；
    /// 无来源新包则尚无这种关系，它的每个Node都必须避开全部母本和其他新包。
    private struct NotebookIdentityRegistry {
        var reservedForUnlinkedPackages: Set<UUID>

        mutating func reserve(_ id: UUID) {
            reservedForUnlinkedPackages.insert(id)
        }

        mutating func freshID(alsoAvoiding localIDs: Set<UUID>) -> UUID {
            var candidate = UUID()
            while reservedForUnlinkedPackages.contains(candidate) || localIDs.contains(candidate) {
                candidate = UUID()
            }
            reservedForUnlinkedPackages.insert(candidate)
            return candidate
        }
    }

    static func run() throws -> TeachingLessonWashReport {
        let fileManager = FileManager.default
        let workspace = try ArchiveStorage.ensureWorkspace(fileManager: fileManager)
        let lessonRoot = workspace
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
        let studentsRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
            .appendingPathComponent("学生", isDirectory: true)

        let allLessonFiles = try csvFilesRecursively(in: lessonRoot, fileManager: fileManager)
            .filter { url in isLessonDocument(url) }
        let formalLessonFiles = allLessonFiles.filter {
            normalizePath(relativePath(of: $0, under: lessonRoot)) != normalizePath(collectorRelativePath)
        }
        let notebookFiles = try listNotebookFiles(in: studentsRoot, fileManager: fileManager)

        let loadedLessonStates: [LessonState] = try formalLessonFiles.map { (fileURL: URL) -> LessonState in
            let payload = try NodeMarkdownFileManager.read(fileURL: fileURL)
            return LessonState(
                url: fileURL,
                relativePath: relativePath(of: fileURL, under: lessonRoot),
                document: payload.0,
                meta: payload.1
            )
        }
        var lessonStates: [LessonState] = loadedLessonStates.sorted { lhs, rhs in
            lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }

        let notebookPayloads = notebookFiles.reduce(into: [String: (NodeMarkdownDocument, NodeMarkdownFileMeta)]()) { result, url in
            if let payload = try? NodeMarkdownFileManager.read(fileURL: url) {
                result[url.path] = payload
            }
        }
        let referenceCounts = countNotebookReferences(notebookPayloads)
        let occurrences = collectH3Occurrences(from: lessonStates)
        let identityPlan = makeH3IdentityPlan(
            occurrences: occurrences,
            referenceCounts: referenceCounts,
            allExistingIDs: Set(lessonStates.flatMap { state in state.document.nodes.map { node in node.id } })
        )

        var report = TeachingLessonWashReport()
        report.lessonFileCount = lessonStates.count
        report.duplicateH3GroupCount = identityPlan.duplicateGroupCount
        report.reassignedH3Count = identityPlan.reassignedCount

        applyH3IdentityPlan(identityPlan.targets, to: &lessonStates)
        report.reassignedOtherNodeCount = makeOtherLessonNodeIDsUnique(in: &lessonStates)

        for index in lessonStates.indices {
            let cleaned = cleanLessonDocument(lessonStates[index].document, fileURL: lessonStates[index].url)
            lessonStates[index].document = cleaned.document
            report.removedImageGarbageCount += cleaned.imageCount
            report.removedFormulaLinkCount += cleaned.formulaLinkCount
            report.removedLegacyImageSizeLineCount += cleaned.imageSizeLineCount
            normalizeFormalLessonSourceFields(in: &lessonStates[index].document)
        }

        let canonicalIndex = buildCanonicalIndex(
            lessonStates: lessonStates,
            occurrences: occurrences,
            identityTargets: identityPlan.targets
        )
        var notebookIdentityRegistry = NotebookIdentityRegistry(
            reservedForUnlinkedPackages: Set(
                lessonStates.flatMap { state in state.document.nodes.map(\.id) }
            )
        )

        var notebookWrites: [(url: URL, document: NodeMarkdownDocument, meta: NodeMarkdownFileMeta)] = []
        for notebookURL in notebookFiles {
            guard let payload = notebookPayloads[notebookURL.path] else {
                report.skippedFiles.append(
                    TeachingLessonWashSkippedFile(
                        category: "随堂笔记",
                        file: notebookURL.path,
                        reason: "文件无法读取"
                    )
                )
                continue
            }
            let studentName = notebookURL.deletingLastPathComponent().lastPathComponent
            var candidateIdentityRegistry = notebookIdentityRegistry
            let result = rebuildNotebook(
                payload.0,
                studentName: studentName,
                notebookFile: notebookURL.path,
                canonicalIndex: canonicalIndex,
                identityRegistry: &candidateIdentityRegistry
            )
            do {
                try NodeMarkdownIdentityPolicy.validateForPersistence(result.document)
                notebookIdentityRegistry = candidateIdentityRegistry
                notebookWrites.append((notebookURL, result.document, payload.1))
                report.notebookFileCount += 1
                report.rebuiltNotebookPackageCount += result.rebuiltCount
                report.relinkedNotebookH3Count += result.relinkedH3Count
                report.reassignedNotebookNewH3Count += result.reassignedNewH3Count
                report.reassignedNotebookOtherNodeCount += result.reassignedOtherNodeCount
                report.removedDuplicateNotebookPackageCount += result.removedDuplicateCount
                report.unresolvedItems.append(contentsOf: result.unresolved)
                report.identityChanges.append(contentsOf: result.identityChanges)
            } catch {
                report.skippedFiles.append(
                    TeachingLessonWashSkippedFile(
                        category: "随堂笔记",
                        file: notebookURL.path,
                        reason: error.localizedDescription
                    )
                )
                report.unresolvedItems.append(contentsOf: result.unresolved)
            }
        }

        try validateFormalLessons(lessonStates)
        for state in lessonStates {
            try NodeMarkdownFileManager.write(document: state.document, meta: state.meta, to: state.url)
        }
        for write in notebookWrites {
            try NodeMarkdownFileManager.write(document: write.document, meta: write.meta, to: write.url)
        }
        let reportURLs = try writeReports(
            report: report,
            mappings: identityPlan.mappingRecords,
            workspace: workspace,
            fileManager: fileManager
        )
        report.mappingFileURL = reportURLs.mapping
        report.reportFileURL = reportURLs.report
        return report
    }

    // MARK: H3身份计划

    private static func collectH3Occurrences(from states: [LessonState]) -> [H3Occurrence] {
        var result: [H3Occurrence] = []
        for fileIndex in states.indices {
            let state = states[fileIndex]
            for range in TeachingCoursePackageContentSignature.packageRanges(in: state.document.nodes) {
                let root = state.document.nodes[range.start]
                result.append(
                    H3Occurrence(
                        fileIndex: fileIndex,
                        rowIndex: range.start,
                        relativePath: state.relativePath,
                        oldID: root.id,
                        title: root.text,
                        package: Array(state.document.nodes[range.start..<range.end])
                    )
                )
            }
        }
        return result
    }

    private static func makeH3IdentityPlan(
        occurrences: [H3Occurrence],
        referenceCounts: [LinkKey: Int],
        allExistingIDs: Set<UUID>
    ) -> (
        targets: [OccurrenceKey: UUID],
        mappingRecords: [H3MappingRecord],
        duplicateGroupCount: Int,
        reassignedCount: Int
    ) {
        let groups = Dictionary(grouping: occurrences, by: \.oldID)
        var usedIDs = allExistingIDs
        var targets: [OccurrenceKey: UUID] = [:]
        var records: [H3MappingRecord] = []
        var duplicateGroupCount = 0
        var reassignedCount = 0
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        for oldID in groups.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let group = groups[oldID] else { continue }
            let ordered = group.sorted { lhs, rhs in
                let lhsCount = referenceCounts[linkKey(sourceFile: lhs.relativePath, sourceID: lhs.oldID.uuidString)] ?? 0
                let rhsCount = referenceCounts[linkKey(sourceFile: rhs.relativePath, sourceID: rhs.oldID.uuidString)] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                if lhs.relativePath != rhs.relativePath {
                    return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
                }
                return lhs.rowIndex < rhs.rowIndex
            }
            if ordered.count > 1 { duplicateGroupCount += 1 }

            for (position, occurrence) in ordered.enumerated() {
                let targetID: UUID
                if position == 0 {
                    targetID = oldID
                } else {
                    targetID = freshUUID(avoiding: &usedIDs)
                    reassignedCount += 1
                }
                targets[OccurrenceKey(fileIndex: occurrence.fileIndex, rowIndex: occurrence.rowIndex)] = targetID

                guard ordered.count > 1, let root = occurrence.package.first else { continue }
                let packageJSON = (try? encoder.encode(occurrence.package)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                records.append(
                    H3MappingRecord(
                        sourceFile: occurrence.relativePath,
                        row: occurrence.rowIndex + 1,
                        oldUUID: oldID.uuidString,
                        title: occurrence.title,
                        oldSourceID: root.sourceID,
                        oldSourceFile: root.sourceFile,
                        oldCache: root.cache,
                        oldPackageJSON: packageJSON,
                        action: position == 0 ? "保留" : "更换",
                        newUUID: targetID.uuidString
                    )
                )
            }
        }
        return (targets, records, duplicateGroupCount, reassignedCount)
    }

    private static func applyH3IdentityPlan(
        _ targets: [OccurrenceKey: UUID],
        to states: inout [LessonState]
    ) {
        for (key, targetID) in targets {
            guard states.indices.contains(key.fileIndex),
                  states[key.fileIndex].document.nodes.indices.contains(key.rowIndex) else { continue }
            states[key.fileIndex].document.nodes[key.rowIndex].id = targetID
        }
    }

    private static func makeOtherLessonNodeIDsUnique(in states: inout [LessonState]) -> Int {
        let h3IDs = Set(states.flatMap { state in
            state.document.nodes.filter { $0.level == 3 }.map(\.id)
        })
        var used = h3IDs
        var changed = 0
        for fileIndex in states.indices {
            for nodeIndex in states[fileIndex].document.nodes.indices where states[fileIndex].document.nodes[nodeIndex].level != 3 {
                let oldID = states[fileIndex].document.nodes[nodeIndex].id
                if used.contains(oldID) {
                    states[fileIndex].document.nodes[nodeIndex].id = freshUUID(avoiding: &used)
                    changed += 1
                } else {
                    used.insert(oldID)
                }
            }
        }
        return changed
    }

    private static func freshUUID(avoiding used: inout Set<UUID>) -> UUID {
        var candidate = UUID()
        while used.contains(candidate) {
            candidate = UUID()
        }
        used.insert(candidate)
        return candidate
    }

    // MARK: 母本正文清洗

    private static func cleanLessonDocument(
        _ document: NodeMarkdownDocument,
        fileURL: URL
    ) -> (document: NodeMarkdownDocument, imageCount: Int, formulaLinkCount: Int, imageSizeLineCount: Int) {
        var nodes = document.nodes
        var imageCount = 0
        var formulaLinkCount = 0
        var imageSizeLineCount = 0
        var imageSizeOnlyNodeIndices: [Int] = []

        for index in nodes.indices {
            let sizeLineResult = removeLegacyImageSizeLines(from: nodes[index].text)
            nodes[index].text = sizeLineResult.text
            imageSizeLineCount += sizeLineResult.count
            if sizeLineResult.count > 0, sizeLineResult.text.isEmpty {
                imageSizeOnlyNodeIndices.append(index)
            }

            let formulaResult = removeLegacyFormulaLinks(from: nodes[index].text)
            nodes[index].text = formulaResult.text
            formulaLinkCount += formulaResult.count

            let imageResult = replaceMissingCompleteImages(in: nodes[index].text, fileURL: fileURL)
            nodes[index].text = imageResult.text
            imageCount += imageResult.count
        }

        for index in imageSizeOnlyNodeIndices.reversed() {
            nodes.remove(at: index)
        }

        var index = 0
        while index < nodes.count {
            guard isMalformedImageStart(nodes[index].text) else {
                index += 1
                continue
            }
            nodes[index].text = imagePlaceholder
            imageCount += 1
            var end = index + 1
            var consumed = 0
            while end < nodes.count, consumed < 2, nodes[end].level > 3, isMalformedImageContinuation(nodes[end].text) {
                end += 1
                consumed += 1
            }
            if end > index + 1 {
                nodes.removeSubrange((index + 1)..<end)
            }
            index += 1
        }
        return (NodeMarkdownDocument(nodes: nodes), imageCount, formulaLinkCount, imageSizeLineCount)
    }

    private static func removeLegacyImageSizeLines(from text: String) -> (text: String, count: Int) {
        let lines = text.components(separatedBy: "\n")
        let retained = lines.filter { !isLegacyImageSizeLine($0) }
        return (retained.joined(separator: "\n"), lines.count - retained.count)
    }

    private static func isLegacyImageSizeLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("height") && trimmed.hasSuffix("}")
    }

    private static func removeLegacyFormulaLinks(from text: String) -> (text: String, count: Int) {
        let pattern = #"<!--\s*LP_SOURCEFILE:[\s\S]*?-->"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (text, 0)
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return (text, 0) }
        return (regex.stringByReplacingMatches(in: text, range: range, withTemplate: ""), matches.count)
    }

    private static func replaceMissingCompleteImages(
        in text: String,
        fileURL: URL
    ) -> (text: String, count: Int) {
        let patterns = [
            #"!\[[^\]\n]*\]\(([^)\n]*)\)(?:\{[^}\n]*(?:\}|$))?"#,
            #"<img\s+[^>\n]*?src\s*=\s*[\"']([^\"']*)[\"'][^>\n]*>"#
        ]
        var output = text
        var replacedCount = 0
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsText = output as NSString
            let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() where match.numberOfRanges > 1 {
                let path = nsText.substring(with: match.range(at: 1))
                guard !imageReferenceExists(path, relativeTo: fileURL) else { continue }
                output = (output as NSString).replacingCharacters(in: match.range, with: imagePlaceholder)
                replacedCount += 1
            }
        }
        return (output, replacedCount)
    }

    private static func imageReferenceExists(_ rawPath: String, relativeTo fileURL: URL) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        if lower.hasPrefix("asset:") { return false }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let url: URL
        if decoded.hasPrefix("/") {
            url = URL(fileURLWithPath: decoded)
        } else {
            url = fileURL.deletingLastPathComponent().appendingPathComponent(decoded)
        }
        return FileManager.default.fileExists(atPath: url.standardizedFileURL.path)
    }

    private static func isMalformedImageStart(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("![") else { return false }
        if trimmed.contains("](") { return false }
        return trimmed.contains("AI") || trimmed.contains("图片") || trimmed.contains("图示")
            || trimmed.contains("图形") || trimmed.contains("形状") || trimmed.contains("箭头")
    }

    private static func isMalformedImageContinuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("生成的内容可能不正确")
            || trimmed.hasPrefix("height=")
            || trimmed.hasPrefix("width=")
    }

    private static func normalizeFormalLessonSourceFields(in document: inout NodeMarkdownDocument) {
        for index in document.nodes.indices {
            document.nodes[index].sourceID = ""
            document.nodes[index].sourceFile = ""
        }
    }

    // MARK: 随堂笔记解析与覆盖

    private static func buildCanonicalIndex(
        lessonStates: [LessonState],
        occurrences: [H3Occurrence],
        identityTargets: [OccurrenceKey: UUID]
    ) -> CanonicalIndex {
        var index = CanonicalIndex()
        var canonicalByIdentity: [String: CanonicalH3] = [:]

        for state in lessonStates {
            for range in TeachingCoursePackageContentSignature.packageRanges(in: state.document.nodes) {
                let root = state.document.nodes[range.start]
                let canonical = CanonicalH3(
                    sourceFile: state.relativePath,
                    id: root.id,
                    title: root.text,
                    package: Array(state.document.nodes[range.start..<range.end])
                )
                canonicalByIdentity[canonical.identityKey] = canonical
                index.byCurrentLink[linkKey(sourceFile: canonical.sourceFile, sourceID: canonical.id.uuidString), default: []].append(canonical)
                index.byCurrentID[canonical.id.uuidString.lowercased(), default: []].append(canonical)
                index.byTitle[normalizeTitle(canonical.title), default: []].append(canonical)
                index.byDigest[TeachingCoursePackageContentSignature.digest(canonical.package), default: []].append(canonical)
            }
        }

        for occurrence in occurrences {
            guard let targetID = identityTargets[OccurrenceKey(fileIndex: occurrence.fileIndex, rowIndex: occurrence.rowIndex)] else { continue }
            let identity = "\(normalizePath(occurrence.relativePath))#\(targetID.uuidString.lowercased())"
            guard let canonical = canonicalByIdentity[identity] else { continue }
            index.byOldLink[linkKey(sourceFile: occurrence.relativePath, sourceID: occurrence.oldID.uuidString), default: []].append(canonical)
            index.byOldID[occurrence.oldID.uuidString.lowercased(), default: []].append(canonical)
        }
        return index
    }

    private static func rebuildNotebook(
        _ document: NodeMarkdownDocument,
        studentName: String,
        notebookFile: String,
        canonicalIndex: CanonicalIndex,
        identityRegistry: inout NotebookIdentityRegistry
    ) -> NotebookResult {
        var result = NotebookResult(document: document)
        let ranges = TeachingCoursePackageContentSignature.packageRanges(in: result.document.nodes)
        for range in ranges.reversed() {
            guard result.document.nodes.indices.contains(range.start) else { continue }
            let package = Array(result.document.nodes[range.start..<range.end])
            guard let root = package.first else { continue }
            let sourceID = root.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = root.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)

            // 两项来源都为空就是尚未入库的新包。即使标题或UUID碰巧和母本相同，
            // 也不能把它猜成母本包；身份碰撞会在后面的新包清洗中换新UUID。
            if sourceID.isEmpty && sourceFile.isEmpty {
                continue
            }
            guard let canonical = resolveCanonicalH3(root: root, package: package, index: canonicalIndex) else {
                if !sourceFile.isEmpty {
                    let reason: String
                    if normalizePath(sourceFile).contains("上课收集") {
                        reason = "仍指向上课收集，无法唯一确认正式母本"
                    } else if !root.sourceID.isEmpty,
                              root.sourceID.caseInsensitiveCompare(root.id.uuidString) != .orderedSame {
                        reason = "H3 UUID与SourceID不一致，无法唯一确认正式母本"
                    } else {
                        reason = "现有来源无法唯一确认正式母本"
                    }
                    result.unresolved.append(
                        TeachingLessonWashUnresolvedItem(
                            category: "随堂H3",
                            student: studentName,
                            file: notebookFile,
                            title: root.text,
                            uuid: root.id.uuidString,
                            sourceID: root.sourceID,
                            sourceFile: root.sourceFile,
                            reason: reason
                        )
                    )
                }
                continue
            }
            var replacement = canonical.package
            guard !replacement.isEmpty else { continue }
            if root.id != canonical.id
                || sourceID.caseInsensitiveCompare(canonical.id.uuidString) != .orderedSame
                || normalizePath(sourceFile) != normalizePath(canonical.sourceFile) {
                result.relinkedH3Count += 1
                result.identityChanges.append(
                    TeachingLessonWashIdentityChange(
                        category: "随堂H3重连",
                        student: studentName,
                        file: notebookFile,
                        row: range.start + 1,
                        level: 3,
                        title: root.text,
                        oldUUID: root.id.uuidString,
                        newUUID: canonical.id.uuidString,
                        reason: "母本H3身份更新，随堂UUID与SourceID同步改为母本UUID"
                    )
                )
            }
            replacement[0].id = canonical.id
            replacement[0].sourceID = canonical.id.uuidString
            replacement[0].sourceFile = canonical.sourceFile
            for index in replacement.indices where index > 0 {
                replacement[index].sourceID = ""
                replacement[index].sourceFile = ""
            }
            result.document.nodes.replaceSubrange(range.start..<range.end, with: replacement)
            result.rebuiltCount += 1
        }

        let refreshedRanges = TeachingCoursePackageContentSignature.packageRanges(in: result.document.nodes)
        var seenH3: Set<UUID> = []
        var duplicateRanges: [Range<Int>] = []
        for range in refreshedRanges {
            let root = result.document.nodes[range.start]
            guard !root.sourceID.isEmpty, !root.sourceFile.isEmpty else { continue }
            let canonicalCandidates = canonicalIndex.byCurrentLink[
                linkKey(sourceFile: root.sourceFile, sourceID: root.sourceID)
            ] ?? []
            guard canonicalCandidates.contains(where: { $0.id == root.id }) else { continue }
            if !seenH3.insert(root.id).inserted {
                duplicateRanges.append(range.start..<range.end)
            }
        }
        for range in duplicateRanges.reversed() {
            result.document.nodes.removeSubrange(range)
            result.removedDuplicateCount += 1
        }
        repairNotebookIdentityConflicts(
            result: &result,
            studentName: studentName,
            notebookFile: notebookFile,
            identityRegistry: &identityRegistry
        )
        _ = result.document.ensureTrailingBlankLine(defaultLevel: 1)
        return result
    }

    private static func resolveCanonicalH3(
        root: NodeMarkdownNode,
        package: [NodeMarkdownNode],
        index: CanonicalIndex
    ) -> CanonicalH3? {
        let titleKey = normalizeTitle(root.text)
        let sourceID = root.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceFile = root.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)

        if !sourceFile.isEmpty, !sourceID.isEmpty {
            if let exact = uniqueCandidate(index.byCurrentLink[linkKey(sourceFile: sourceFile, sourceID: sourceID)] ?? [], titleKey: titleKey) {
                return exact
            }
            if let migrated = uniqueCandidate(index.byOldLink[linkKey(sourceFile: sourceFile, sourceID: sourceID)] ?? [], titleKey: titleKey) {
                return migrated
            }
        }
        if let byNodeID = uniqueCandidate(index.byCurrentID[root.id.uuidString.lowercased()] ?? [], titleKey: titleKey) {
            return byNodeID
        }
        if let byOldNodeID = uniqueCandidate(index.byOldID[root.id.uuidString.lowercased()] ?? [], titleKey: titleKey) {
            return byOldNodeID
        }
        if !sourceID.isEmpty,
           let byOldSourceID = uniqueCandidate(index.byOldID[sourceID.lowercased()] ?? [], titleKey: titleKey) {
            return byOldSourceID
        }
        if let byTitle = uniqueCandidate(index.byTitle[titleKey] ?? [], titleKey: titleKey) {
            return byTitle
        }
        let digest = TeachingCoursePackageContentSignature.digest(package)
        return uniqueCandidate(index.byDigest[digest] ?? [], titleKey: titleKey)
    }

    private static func uniqueCandidate(_ candidates: [CanonicalH3], titleKey: String) -> CanonicalH3? {
        let unique = deduplicatedCanonical(candidates)
        if unique.count == 1 { return unique[0] }
        let titleMatches = unique.filter { normalizeTitle($0.title) == titleKey }
        return titleMatches.count == 1 ? titleMatches[0] : nil
    }

    private static func deduplicatedCanonical(_ values: [CanonicalH3]) -> [CanonicalH3] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0.identityKey).inserted }
    }

    private static func repairNotebookIdentityConflicts(
        result: inout NotebookResult,
        studentName: String,
        notebookFile: String,
        identityRegistry: inout NotebookIdentityRegistry
    ) {
        let ranges = TeachingCoursePackageContentSignature.packageRanges(in: result.document.nodes)
        var unlinkedNodeIndexes: Set<Int> = []
        var unlinkedRootIndexes: Set<Int> = []
        for range in ranges {
            let root = result.document.nodes[range.start]
            let sourceID = root.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = root.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sourceID.isEmpty && sourceFile.isEmpty else { continue }
            unlinkedRootIndexes.insert(range.start)
            unlinkedNodeIndexes.formUnion(range.start..<range.end)
        }

        // 先固定所有既有结构和已连接母本包。这样新包与任何既有Node撞车时，
        // 永远只更换新包一侧，不会破坏已经建立的母本引用。
        var localUsed: Set<UUID> = []
        for index in result.document.nodes.indices where !unlinkedNodeIndexes.contains(index) {
            if result.document.nodes[index].level != 3 {
                result.document.nodes[index].sourceID = ""
                result.document.nodes[index].sourceFile = ""
            }
            let oldID = result.document.nodes[index].id
            guard localUsed.contains(oldID) else {
                localUsed.insert(oldID)
                continue
            }
            guard result.document.nodes[index].level != 3 else { continue }
            let newID = identityRegistry.freshID(alsoAvoiding: localUsed)
            result.document.nodes[index].id = newID
            localUsed.insert(newID)
            result.reassignedOtherNodeCount += 1
            result.identityChanges.append(
                identityChange(
                    category: "随堂普通Node换UUID",
                    studentName: studentName,
                    notebookFile: notebookFile,
                    rowIndex: index,
                    node: result.document.nodes[index],
                    oldID: oldID,
                    newID: newID,
                    reason: "随堂笔记内非H3节点UUID重复"
                )
            )
        }

        for index in result.document.nodes.indices where unlinkedNodeIndexes.contains(index) {
            result.document.nodes[index].sourceID = ""
            result.document.nodes[index].sourceFile = ""
            let oldID = result.document.nodes[index].id
            let conflicts = localUsed.contains(oldID)
                || identityRegistry.reservedForUnlinkedPackages.contains(oldID)
            if conflicts {
                let newID = identityRegistry.freshID(alsoAvoiding: localUsed)
                result.document.nodes[index].id = newID
                localUsed.insert(newID)
                let isRoot = unlinkedRootIndexes.contains(index)
                if isRoot {
                    result.reassignedNewH3Count += 1
                } else {
                    result.reassignedOtherNodeCount += 1
                }
                result.identityChanges.append(
                    identityChange(
                        category: isRoot ? "随堂新包换UUID" : "随堂新包子Node换UUID",
                        studentName: studentName,
                        notebookFile: notebookFile,
                        rowIndex: index,
                        node: result.document.nodes[index],
                        oldID: oldID,
                        newID: newID,
                        reason: "未入库新包与母本、其他新包或本随堂笔记发生UUID冲突"
                    )
                )
            } else {
                localUsed.insert(oldID)
                identityRegistry.reserve(oldID)
            }
        }
    }

    private static func identityChange(
        category: String,
        studentName: String,
        notebookFile: String,
        rowIndex: Int,
        node: NodeMarkdownNode,
        oldID: UUID,
        newID: UUID,
        reason: String
    ) -> TeachingLessonWashIdentityChange {
        TeachingLessonWashIdentityChange(
            category: category,
            student: studentName,
            file: notebookFile,
            row: rowIndex + 1,
            level: node.level,
            title: node.text,
            oldUUID: oldID.uuidString,
            newUUID: newID.uuidString,
            reason: reason
        )
    }

    // MARK: 验证、报告和文件枚举

    private static func validateFormalLessons(_ states: [LessonState]) throws {
        var used: Set<UUID> = []
        for state in states {
            try NodeMarkdownIdentityPolicy.validateForPersistence(state.document)
            for node in state.document.nodes {
                guard used.insert(node.id).inserted else {
                    throw NSError(
                        domain: "TeachingLessonWashService",
                        code: 7841,
                        userInfo: [NSLocalizedDescriptionKey: "正式教案仍存在全局重复UUID：\(node.id.uuidString)"]
                    )
                }
            }
        }
    }

    private static func writeReports(
        report: TeachingLessonWashReport,
        mappings: [H3MappingRecord],
        workspace: URL,
        fileManager: FileManager
    ) throws -> (mapping: URL, report: URL) {
        let folder = workspace
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("暂存", isDirectory: true)
            .appendingPathComponent("洗教案", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = compactTimestamp()
        let mappingURL = folder.appendingPathComponent("洗教案-H3-UUID暂存表-\(stamp).csv")
        let reportURL = folder.appendingPathComponent("洗教案报告-\(stamp).md")

        let header = ["SourceFile", "Row", "OldUUID", "Title", "OldSourceID", "OldSourceFile", "OldCache", "OldPackageJSON", "Action", "NewUUID"]
        var mappingLines = [header.map { csvEscape($0) }.joined(separator: ",")]
        mappingLines.append(contentsOf: mappings.map { record in
            [
                record.sourceFile, String(record.row), record.oldUUID, record.title,
                record.oldSourceID, record.oldSourceFile, record.oldCache,
                record.oldPackageJSON, record.action, record.newUUID
            ].map { csvEscape($0) }.joined(separator: ",")
        })
        try mappingLines.joined(separator: "\n").write(to: mappingURL, atomically: true, encoding: .utf8)

        var lines = [
            "# 洗教案报告 \(stamp)",
            "",
            "- 正式教案：\(report.lessonFileCount)",
            "- 重复H3组：\(report.duplicateH3GroupCount)",
            "- 更换H3 UUID：\(report.reassignedH3Count)",
            "- 更换其他Node UUID：\(report.reassignedOtherNodeCount)",
            "- 清理图片残留：\(report.removedImageGarbageCount)",
            "- 清理图片height残留行：\(report.removedLegacyImageSizeLineCount)",
            "- 清理公式旧链接：\(report.removedFormulaLinkCount)",
            "- 写入随堂笔记：\(report.notebookFileCount)",
            "- 重建随堂H3包：\(report.rebuiltNotebookPackageCount)",
            "- 随母本重连随堂H3：\(report.relinkedNotebookH3Count)",
            "- 更换随堂新包H3 UUID：\(report.reassignedNotebookNewH3Count)",
            "- 更换随堂其他Node UUID：\(report.reassignedNotebookOtherNodeCount)",
            "- 删除随堂重复H3包：\(report.removedDuplicateNotebookPackageCount)",
            "",
            "## 待人工处理",
            ""
        ]
        if report.unresolvedItems.isEmpty {
            lines.append("无")
        } else {
            lines.append("| 类型 | 学生 | 文件 | H3标题 | 当前UUID | SourceID | SourceFile | 未处理原因 |")
            lines.append("|---|---|---|---|---|---|---|---|")
            lines.append(contentsOf: report.unresolvedItems.map { item in
                markdownTableRow([
                    item.category, item.student, item.file, item.title,
                    item.uuid, item.sourceID, item.sourceFile, item.reason
                ])
            })
        }
        lines.append(contentsOf: ["", "## 随堂笔记身份改动", ""])
        if report.identityChanges.isEmpty {
            lines.append("无")
        } else {
            lines.append("| 类型 | 学生 | 文件 | 行 | 层级 | 内容 | 旧UUID | 新UUID | 原因 |")
            lines.append("|---|---|---|---:|---:|---|---|---|---|")
            lines.append(contentsOf: report.identityChanges.map { change in
                markdownTableRow([
                    change.category,
                    change.student,
                    change.file,
                    String(change.row),
                    String(change.level),
                    change.title,
                    change.oldUUID,
                    change.newUUID,
                    change.reason
                ])
            })
        }
        lines.append(contentsOf: ["", "## 保持原样的文件", ""])
        if report.skippedFiles.isEmpty {
            lines.append("无")
        } else {
            lines.append("| 类型 | 文件 | 保持原样原因 |")
            lines.append("|---|---|---|")
            lines.append(contentsOf: report.skippedFiles.map { item in
                markdownTableRow([item.category, item.file, item.reason])
            })
        }
        try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        return (mappingURL, reportURL)
    }

    private static func markdownTableRow(_ columns: [String]) -> String {
        "| " + columns.map { value in
            value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\n", with: "<br>")
        }.joined(separator: " | ") + " |"
    }

    private static func countNotebookReferences(
        _ payloads: [String: (NodeMarkdownDocument, NodeMarkdownFileMeta)]
    ) -> [LinkKey: Int] {
        var counts: [LinkKey: Int] = [:]
        for payload in payloads.values {
            for range in TeachingCoursePackageContentSignature.packageRanges(in: payload.0.nodes) {
                let root = payload.0.nodes[range.start]
                let sourceFile = root.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
                let sourceID = root.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sourceFile.isEmpty, !sourceID.isEmpty else { continue }
                counts[linkKey(sourceFile: sourceFile, sourceID: sourceID), default: 0] += 1
            }
        }
        return counts
    }

    private static func csvFilesRecursively(in root: URL, fileManager: FileManager) throws -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension.lowercased() == "csv" {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func listNotebookFiles(in studentsRoot: URL, fileManager: FileManager) throws -> [URL] {
        try csvFilesRecursively(in: studentsRoot, fileManager: fileManager).filter {
            $0.lastPathComponent.hasPrefix("随堂笔记_")
        }
    }

    private static func isLessonDocument(_ url: URL) -> Bool {
        let type = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
        return type == "lessonplan" || type == "nodemarkdown" || type == "nodesmarkdown"
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path
        let prefix = root.standardizedFileURL.path + "/"
        guard full.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(full.dropFirst(prefix.count)).replacingOccurrences(of: "\\", with: "/")
    }

    private static func normalizePath(_ value: String) -> String {
        var result = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        while result.contains("//") { result = result.replacingOccurrences(of: "//", with: "/") }
        if result.hasPrefix("教案/") { result.removeFirst("教案/".count) }
        if result.hasPrefix("系统/教案/") { result.removeFirst("系统/教案/".count) }
        return result
    }

    private static func normalizeTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func linkKey(sourceFile: String, sourceID: String) -> LinkKey {
        LinkKey(sourceFile: normalizePath(sourceFile), sourceID: sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func compactTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
