import Foundation

struct TeachingCoursePreparationSummary: Hashable {
    var lessonPlanCount: Int
    var templateFileCount: Int
    var completionFileCount: Int
    var refreshedPackageCount: Int
    var detachedPackageCount: Int
    var completedTaskCount: Int
    var classInfoCreated: Bool
}

struct TeachingCourseSyncSummary: Hashable {
    var updatedSourcePackageCount: Int
    var collectedNewPackageCount: Int
    var conflictPackageCount: Int = 0
    var packageResults: [TeachingCourseSyncPackageResult] = []
}

struct TeachingCourseSyncPackageResult: Hashable, Identifiable {
    var packageTitle: String
    var sourceFile: String
    var sourceID: String
    var isNewPackage: Bool
    var success: Bool
    var reason: String

    var id: String {
        "\(sourceFile)#\(sourceID)#\(packageTitle)"
    }
}

struct TeachingCourseInsertSummary: Hashable {
    var insertedPackageCount: Int
    var skippedPackageCount: Int
    var firstInsertedRowIndex: Int?
    var canUndo: Bool
    var insertedH3Titles: [String] = []
}

enum TeachingCourseConflictResolutionAction: String, Hashable, CaseIterable {
    case acceptSource
    case acceptNotebook
    case clearMarker

    var displayName: String {
        switch self {
        case .acceptSource:
            return "采用母本"
        case .acceptNotebook:
            return "采用笔记"
        case .clearMarker:
            return "仅清标记"
        }
    }
}

struct TeachingCourseSyncConflictItem: Hashable, Identifiable {
    var timestamp: String
    var sourceFile: String
    var sourceID: String
    var note: String

    var id: String {
        "\(timestamp)|\(sourceFile)|\(sourceID)"
    }

    var displayText: String {
        "\(timestamp) | \(sourceFile)#\(sourceID) | \(note)"
    }
}

struct TeachingCourseAuditLogItem: Hashable, Identifiable {
    enum Source: String, Hashable {
        case transaction
        case conflict
        case exportSignature
    }

    var id: String
    var source: Source
    var timestamp: String
    var summary: String
    var rawLine: String
}

struct TeachingCourseConsistencyIssue: Hashable, Identifiable {
    enum Code: String, Hashable {
        case missingStudentFolder
        case missingNotebook
        case corruptedNotebook
        case missingStudentInfo
        case corruptedStudentInfo
        case missingLessonFolder
        case missingSyncBasePath
        case missingSyncPDFFolder
        case notebookFileNameMismatch
        case notebookMetaTypeMismatch
        case notebookDuplicateSourceID
        case notebookBrokenSourceFile
        case notebookBrokenSourceID
    }

    var code: Code
    var message: String
    var context: String?
    var fixable: Bool

    var id: String {
        if let context, !context.isEmpty {
            return "\(code.rawValue)-\(context)"
        }
        return code.rawValue
    }
}

struct TeachingCourseConsistencySummary: Hashable {
    var checkedItemCount: Int
    var issueItems: [TeachingCourseConsistencyIssue]

    var isHealthy: Bool {
        issueItems.isEmpty
    }

    var issues: [String] {
        issueItems.map(\.message)
    }
}

struct TeachingCourseConsistencyFixSummary: Hashable, Codable {
    var requestedIssueCount: Int
    var fixedIssueCount: Int
    var skippedIssueCount: Int
    var repairBatchID: String? = nil
    var rolledBackStudentCount: Int = 0
}

enum TeachingCourseRepairStrategy: String, Hashable, CaseIterable {
    case conservative
    case standard
    case aggressive

    var displayName: String {
        switch self {
        case .conservative:
            return "保守"
        case .standard:
            return "标准"
        case .aggressive:
            return "激进"
        }
    }
}

struct TeachingCourseConsistencyBulkFixResult: Hashable {
    var summary: TeachingCourseConsistencyFixSummary
    var reportsByStudent: [String: TeachingCourseConsistencySummary]
}

struct TeachingCourseUpdatePreview: Hashable {
    var dirtyPackageCount: Int
    var newPackageCount: Int
    var sourceUpdatePackageCount: Int = 0
    var conflictPackageCount: Int = 0
    var chapterTargets: [TeachingCourseUpdateChapterTarget]

    var totalPendingCount: Int {
        dirtyPackageCount + newPackageCount + sourceUpdatePackageCount + conflictPackageCount
    }
}

struct TeachingCourseUpdateChapterTarget: Hashable, Identifiable {
    var relativePath: String
    var displayName: String
    var anchors: [TeachingCourseUpdateAnchorTarget]

    var id: String { relativePath }
}

struct TeachingCourseUpdateAnchorTarget: Hashable, Identifiable {
    var sourceID: String
    var displayName: String

    var id: String { sourceID }
}

struct TeachingCourseUpdatePlacementTarget: Hashable {
    var sourceFile: String
    var anchorSourceID: String?
}

struct TeachingCourseFinishSummary: Hashable {
    var removedEmptyNodeCount: Int
    var syncSummary: TeachingCourseSyncSummary
    var exportedPDFPath: String?
}

private struct TeachingNotebookSplitPDF: Sendable {
    let fileName: String
    let data: Data
}

private struct TeachingNotebookExportPayload: Sendable {
    let pdf: Data
    let h1PDF: Data
    let splitPDFs: [TeachingNotebookSplitPDF]
    let html: Data
}

private struct TeachingCourseFinishClassService {
    struct CleanupResult {
        var removedNodeCount: Int
        var dirtyH3NodeIDs: [String]
    }

    static func runCleanup(document: inout NodeMarkdownDocument, syncTime: Date) -> CleanupResult {
        let originalNodes = document.nodes
        var dirtyH3IDs = Set<UUID>()

        for index in originalNodes.indices {
            let node = originalNodes[index]
            guard node.level != 3 else { continue }
            guard node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let ownerIndex = document.owningH3Index(for: index),
               document.nodes.indices.contains(ownerIndex) {
                dirtyH3IDs.insert(document.nodes[ownerIndex].id)
            }
        }

        let filteredNodes = originalNodes.filter { node in
            if node.level == 3 { return true }
            return !node.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let removedNodeCount = max(0, originalNodes.count - filteredNodes.count)
        document.nodes = filteredNodes

        if document.nodes.isEmpty {
            let now = Date()
            document.nodes = [
                NodeMarkdownNode(
                    level: 1,
                    text: "",
                    sourceID: "",
                    sourceFile: "",
                    cache: NodeMarkdownCacheCodec.encode(mtime: now),
                    mtimeCache: now
                )
            ]
        }

        for index in document.nodes.indices where document.nodes[index].level == 3 {
            if dirtyH3IDs.contains(document.nodes[index].id) {
                document.nodes[index].mtimeCache = syncTime
                document.nodes[index].cache = NodeMarkdownCacheCodec.encode(mtime: syncTime)
            }
        }

        _ = document.ensureTrailingBlankLine(defaultLevel: min(12, max(1, document.nodes.last?.level ?? 1)))
        let dirtyIDs = document.nodes
            .filter { $0.level == 3 && dirtyH3IDs.contains($0.id) }
            .map { $0.id.uuidString }
        return CleanupResult(
            removedNodeCount: removedNodeCount,
            dirtyH3NodeIDs: dirtyIDs
        )
    }
}

actor TeachingCourseEditingAnchorStore {
    static let shared = TeachingCourseEditingAnchorStore()

    private var activeRowByFilePath: [String: Int] = [:]

    func setActiveRow(filePath: String, rowIndex: Int?) {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let rowIndex {
            activeRowByFilePath[trimmed] = rowIndex
        } else {
            activeRowByFilePath.removeValue(forKey: trimmed)
        }
    }

    func activeRow(filePath: String) -> Int? {
        let trimmed = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return activeRowByFilePath[trimmed]
    }
}

/// 随堂插包只接受稳定Node身份或明确文末，禁止把编辑器里的瞬时行号带入磁盘事务。
enum TeachingCourseInsertAnchor: Sendable, Equatable {
    case documentEnd
    case node(UUID)

    /// 活动行本身不能证明编辑器仍有焦点。只有有效输入会话中的Node身份
    /// 才能成为锚点；ESC、弹窗或窗口失焦后统一回到文末。
    static func resolve(isEditing: Bool, activeNodeID: UUID?) -> TeachingCourseInsertAnchor {
        guard isEditing, let activeNodeID else { return .documentEnd }
        return .node(activeNodeID)
    }
}

private struct TeachingCourseTransactionLogEntry: Codable {
    var timestamp: String
    var transactionID: String
    var operation: String
    var studentID: String
    var studentName: String
    var phase: String
    var detail: String
}

private struct TeachingCourseFolderSnapshot: Codable {
    var folderExisted: Bool
    var fileDataByRelativePath: [String: Data]
    var directoryRelativePaths: [String]
}

private struct TeachingCourseSyncConflictRecord: Codable {
    var timestamp: String
    var studentID: String
    var studentName: String
    var sourceFile: String
    var sourceID: String
    var baselineDigest: String?
    var notebookDigest: String
    var sourceDigest: String
    var note: String
}

enum TeachingCourseWorkflowService {
    static func prepareForTeaching(student: TeachingStudentItem) async throws -> TeachingCoursePreparationSummary {
        try await runStudentFolderTransaction(student: student, operation: "prepareForTeaching") {
            try await prepareForSession(student: student, createClassInfo: true)
        }
    }

    static func prepareForNotes(student: TeachingStudentItem) async throws -> TeachingCoursePreparationSummary {
        try await runStudentFolderTransaction(student: student, operation: "prepareForNotes") {
            try await prepareForSession(student: student, createClassInfo: false)
        }
    }

    static func syncNotebookDirtyPackages(
        student: TeachingStudentItem,
        placementTarget: TeachingCourseUpdatePlacementTarget? = nil,
        allowedNewPackageIDs: Set<String>? = nil
    ) async throws -> TeachingCourseSyncSummary {
        try await runStudentFolderTransaction(student: student, operation: "syncNotebookDirtyPackages") {
            try await performNotebookSync(
                student: student,
                placementTarget: placementTarget,
                allowedNewPackageIDs: allowedNewPackageIDs
            )
        }
    }

    static func previewNotebookUpdate(student: TeachingStudentItem) async throws -> TeachingCourseUpdatePreview {
        let notebookURL = try notebookURL(for: student)
        let notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookURL)
        let chapterTargets = try buildUpdateChapterTargets(student: student)
        let summary = try TeachingCoursePackageStateEngine.summarizePreviewState(
            notebookDocument: notebookPayload.0,
            resolveSourceURL: { sourceFile in
                try sourceURLFromRelative(sourceFile)
            },
            loadSourceDocument: { sourceURL in
                try NodeMarkdownFileManager.read(fileURL: sourceURL).0
            }
        )
        return TeachingCourseUpdatePreview(
            dirtyPackageCount: summary.dirtyPackageCount,
            newPackageCount: summary.newPackageCount,
            sourceUpdatePackageCount: summary.sourceUpdatePackageCount,
            conflictPackageCount: summary.conflictPackageCount,
            chapterTargets: chapterTargets
        )
    }

    static func insertLessonPackagesIntoNotebook(
        student: TeachingStudentItem,
        pickedRows: [ChecklistTemplateRow],
        completionChecklistFileURL: URL? = nil,
        insertionAnchorOverride: TeachingCourseInsertAnchor? = nil,
        usesStoredActiveRow: Bool = true
    ) async throws -> TeachingCourseInsertSummary {
        try await runStudentFolderTransaction(student: student, operation: "insertLessonPackagesIntoNotebook") {
            let notebookURL = try notebookURL(for: student)
            try persistInsertUndoSnapshot(student: student, notebookURL: notebookURL)
            var notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookURL)
            let storedActiveRowIndex = usesStoredActiveRow
                ? await TeachingCourseEditingAnchorStore.shared.activeRow(filePath: notebookURL.path)
                : nil
            let activeRowIndex: Int? = {
                switch insertionAnchorOverride {
                case .documentEnd:
                    return nil
                case let .node(nodeID):
                    return notebookPayload.0.nodes.firstIndex { $0.id == nodeID }
                case nil:
                    return storedActiveRowIndex
                }
            }()
            let candidateRows = pickedRows.filter { row in
                row.level == 3
                    && row.status == 0
                    && !row.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !row.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let orderedRows = candidateRows
            guard !orderedRows.isEmpty else {
                return TeachingCourseInsertSummary(
                    insertedPackageCount: 0,
                    skippedPackageCount: pickedRows.count,
                    firstInsertedRowIndex: nil,
                    canUndo: false,
                    insertedH3Titles: []
                )
            }

            var sourceCache: [String: NodeMarkdownDocument] = [:]
            var packagesToInsert: [[NodeMarkdownNode]] = []
            var insertedH3Titles: [String] = []
            var skippedCount = max(0, pickedRows.count - orderedRows.count)
            var handledRows: [ChecklistTemplateRow] = []
            var existingPackageKeys = completedLessonPackageKeys(in: notebookPayload.0)
            var existingPackageIDs = completedLessonPackageIDs(in: notebookPayload.0)

            for row in orderedRows {
                if let sourceUUID = UUID(uuidString: row.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)),
                   existingPackageIDs.contains(sourceUUID) {
                    skippedCount += 1
                    handledRows.append(row)
                    continue
                }
                if let packageKey = lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID),
                   existingPackageKeys.contains(packageKey) {
                    skippedCount += 1
                    handledRows.append(row)
                    continue
                }
                guard let sourceURL = try sourceURLFromRelative(row.sourceFile) else {
                    skippedCount += 1
                    continue
                }
                let sourceDocument: NodeMarkdownDocument
                if let cached = sourceCache[sourceURL.path] {
                    sourceDocument = cached
                } else {
                    let payload = try NodeMarkdownFileManager.read(fileURL: sourceURL)
                    sourceCache[sourceURL.path] = payload.0
                    sourceDocument = payload.0
                }
                guard let sourceRange = h3PackageRange(in: sourceDocument.nodes, sourceID: row.sourceID) else {
                    skippedCount += 1
                    continue
                }
                var package = Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
                if package.isEmpty {
                    skippedCount += 1
                    continue
                }
                package[0].sourceID = row.sourceID
                package[0].sourceFile = row.sourceFile
                packagesToInsert.append(package)
                insertedH3Titles.append(package[0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.task : package[0].text)
                handledRows.append(row)
                if let packageKey = lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID) {
                    existingPackageKeys.insert(packageKey)
                }
                existingPackageIDs.insert(package[0].id)
            }

            if packagesToInsert.isEmpty {
                if let completionChecklistFileURL, !handledRows.isEmpty {
                    try markCompletionChecklistRowsDone(
                        checklistURL: completionChecklistFileURL,
                        pickedRows: handledRows
                    )
                }
                return TeachingCourseInsertSummary(
                    insertedPackageCount: 0,
                    skippedPackageCount: skippedCount,
                    firstInsertedRowIndex: nil,
                    canUndo: false,
                    insertedH3Titles: []
                )
            }

            removeTrailingBlankNodesBeforeCourseInsert(from: &notebookPayload.0)
            var insertIndex = insertionIndexForCourseInsert(
                document: notebookPayload.0,
                activeRowIndex: activeRowIndex
            )
            let firstInsertedRowIndex = insertIndex
            for package in packagesToInsert {
                notebookPayload.0.nodes.insert(contentsOf: package, at: insertIndex)
                insertIndex += package.count
            }
            _ = notebookPayload.0.ensureTrailingBlankLine(defaultLevel: 1)
            try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookURL)
            try appendInsertedH3TitlesToTodayClassInfoIfExists(student: student, titles: insertedH3Titles)
            NotificationCenter.default.post(
                name: .teachingNotebookDidPersistChange,
                object: nil,
                userInfo: ["filePath": notebookURL.path, "reason": "courseInsert"]
            )

            if let completionChecklistFileURL {
                try markCompletionChecklistRowsDone(
                    checklistURL: completionChecklistFileURL,
                    pickedRows: handledRows
                )
            }

            return TeachingCourseInsertSummary(
                insertedPackageCount: packagesToInsert.count,
                skippedPackageCount: skippedCount,
                firstInsertedRowIndex: firstInsertedRowIndex,
                canUndo: true,
                insertedH3Titles: insertedH3Titles
            )
        }
    }

    private static func markCompletionChecklistRowsDone(
        checklistURL: URL,
        pickedRows: [ChecklistTemplateRow]
    ) throws {
        guard !pickedRows.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: checklistURL.path) else { return }
        var payload = try ArchiveStorage.readChecklistDocument(fileURL: checklistURL)
        let pickedIDs = Set(pickedRows.map(\.id))
        let pickedPackageKeys = Set(pickedRows.compactMap { row in
            lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID)
        })
        guard !pickedIDs.isEmpty || !pickedPackageKeys.isEmpty else { return }
        var touched = false
        for index in payload.0.indices {
            guard payload.0[index].level == 3 else { continue }
            let rowPackageKey = lessonPackageKey(
                sourceFile: payload.0[index].sourceFile,
                sourceID: payload.0[index].sourceID
            )
            let shouldMarkDone = pickedIDs.contains(payload.0[index].id)
                || rowPackageKey.map { pickedPackageKeys.contains($0) } == true
            if shouldMarkDone, payload.0[index].status != 1 {
                payload.0[index].status = 1
                touched = true
            }
        }
        guard touched else { return }
        try ArchiveStorage.writeChecklistDocument(
            fileURL: checklistURL,
            rows: payload.0,
            meta: payload.1
        )
    }

    private static func latestUnfinishedPickedRows(
        _ pickedRows: [ChecklistTemplateRow],
        completionChecklistFileURL: URL?
    ) throws -> [ChecklistTemplateRow] {
        guard !pickedRows.isEmpty else { return [] }
        guard let completionChecklistFileURL,
              FileManager.default.fileExists(atPath: completionChecklistFileURL.path) else {
            return pickedRows.filter { $0.status == 0 }
        }

        let payload = try ArchiveStorage.readChecklistDocument(fileURL: completionChecklistFileURL)
        let unfinishedIDs = Set(
            payload.0
                .filter { $0.level == 3 && $0.status == 0 }
                .map(\.id)
        )
        let unfinishedPackageKeys = Set(
            payload.0.compactMap { row -> String? in
                guard row.level == 3, row.status == 0 else { return nil }
                return lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID)
            }
        )

        return pickedRows.filter { row in
            if unfinishedIDs.contains(row.id) {
                return true
            }
            guard let key = lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID) else {
                return false
            }
            return unfinishedPackageKeys.contains(key)
        }
    }

    private static func completedLessonPackageKeys(in document: NodeMarkdownDocument) -> Set<String> {
        Set(document.nodes.compactMap { node in
            guard node.level == 3 else { return nil }
            return lessonPackageKey(sourceFile: node.sourceFile, sourceID: node.sourceID)
        })
    }

    /// UUID是H3包跨改名、跨文件移动后仍不变化的身份。插入前先按UUID拦截，
    /// 不能只依赖SourceFile，否则母本改名后同一个包仍可能被再次选中插入。
    private static func completedLessonPackageIDs(in document: NodeMarkdownDocument) -> Set<UUID> {
        Set(document.nodes.compactMap { node in
            guard node.level == 3 else { return nil }
            if let linkedID = UUID(uuidString: node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return linkedID
            }
            return node.id
        })
    }

    private static func lessonPackageKey(sourceFile: String, sourceID: String) -> String? {
        let file = sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !file.isEmpty, !id.isEmpty else { return nil }
        return "\(file.lowercased())#\(id.lowercased())"
    }

    static func undoLastLessonPackageInsert(student: TeachingStudentItem) async throws -> Bool {
        try await runStudentFolderTransaction(student: student, operation: "undoLastLessonPackageInsert") {
            let snapshotURL = try insertUndoSnapshotURL(for: student)
            guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
                return false
            }
            let data = try Data(contentsOf: snapshotURL)
            var stack = try JSONDecoder().decode(TeachingCourseInsertUndoStack.self, from: data)
            guard let snapshot = stack.snapshots.popLast() else {
                try? FileManager.default.removeItem(at: snapshotURL)
                return false
            }
            let notebookURL = try notebookURL(for: student)
            let parent = notebookURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            guard let snapshotText = String(data: snapshot.notebookData, encoding: .utf8) else {
                throw NSError(
                    domain: "TeachingCourseWorkflowService",
                    code: 7836,
                    userInfo: [NSLocalizedDescriptionKey: "撤销快照不是有效的UTF-8 NodeMarkdown文件。"]
                )
            }
            let snapshotPayload = NodeMarkdownFileManager.read(
                rawText: snapshotText,
                fileTitleFallback: notebookURL.deletingPathExtension().lastPathComponent
            )
            try NodeMarkdownFileManager.write(
                document: snapshotPayload.0,
                meta: snapshotPayload.1,
                to: notebookURL
            )
            if stack.snapshots.isEmpty {
                try FileManager.default.removeItem(at: snapshotURL)
            } else {
                let stackData = try JSONEncoder().encode(stack)
                try stackData.write(to: snapshotURL, options: .atomic)
            }
            return true
        }
    }

    static func checkStudentConsistency(student: TeachingStudentItem) throws -> TeachingCourseConsistencySummary {
        var checked = 0
        var issues: [TeachingCourseConsistencyIssue] = []
        let fileManager = FileManager.default

        let studentFolder = try studentFolderURL(for: student)
        checked += 1
        if !fileManager.fileExists(atPath: studentFolder.path) {
            issues.append(
                TeachingCourseConsistencyIssue(
                    code: .missingStudentFolder,
                    message: "学生目录缺失",
                    context: nil,
                    fixable: true
                )
            )
            return TeachingCourseConsistencySummary(checkedItemCount: checked, issueItems: issues)
        }

        let notebookFile = try notebookURL(for: student)
        checked += 1
        if !fileManager.fileExists(atPath: notebookFile.path) {
            issues.append(
                TeachingCourseConsistencyIssue(
                    code: .missingNotebook,
                    message: "随堂笔记缺失",
                    context: nil,
                    fixable: true
                )
            )
        } else {
            let expectedNotebookName = "随堂笔记_\(student.name).CSV"
            if notebookFile.lastPathComponent != expectedNotebookName {
                issues.append(
                    TeachingCourseConsistencyIssue(
                        code: .notebookFileNameMismatch,
                        message: "随堂笔记文件名不规范：\(notebookFile.lastPathComponent)",
                        context: expectedNotebookName,
                        fixable: false
                    )
                )
            }
            if let notebookPayload = try? NodeMarkdownFileManager.read(fileURL: notebookFile) {
                let metaType = notebookPayload.1.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let allowedTypes: Set<String> = ["nodemarkdown", "nodesmarkdown", "lessonplan"]
                if !allowedTypes.contains(metaType) {
                    issues.append(
                        TeachingCourseConsistencyIssue(
                            code: .notebookMetaTypeMismatch,
                            message: "随堂笔记META类型异常：\(notebookPayload.1.type)",
                            context: notebookPayload.1.type,
                            fixable: true
                        )
                    )
                }

                let packageRanges = h3PackageRanges(in: notebookPayload.0.nodes)
                var sourceIDSet: Set<String> = []
                for packageRange in packageRanges {
                    guard notebookPayload.0.nodes.indices.contains(packageRange.start) else { continue }
                    let rootNode = notebookPayload.0.nodes[packageRange.start]
                    let sourceID = rootNode.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
                    let sourceFile = rootNode.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !sourceID.isEmpty, !sourceFile.isEmpty else { continue }

                    if sourceIDSet.contains(sourceID) {
                        issues.append(
                            TeachingCourseConsistencyIssue(
                                code: .notebookDuplicateSourceID,
                                message: "随堂笔记存在重复SourceID：\(sourceID)",
                                context: sourceID,
                                fixable: false
                            )
                        )
                    } else {
                        sourceIDSet.insert(sourceID)
                    }

                    guard let sourceURL = try sourceURLFromRelative(sourceFile),
                          fileManager.fileExists(atPath: sourceURL.path) else {
                        issues.append(
                            TeachingCourseConsistencyIssue(
                                code: .notebookBrokenSourceFile,
                                message: "SourceFile失效：\(sourceFile)",
                                context: sourceFile,
                                fixable: false
                            )
                        )
                        continue
                    }
                    if let sourcePayload = try? NodeMarkdownFileManager.read(fileURL: sourceURL),
                       h3PackageRange(in: sourcePayload.0.nodes, sourceID: sourceID) == nil {
                        issues.append(
                            TeachingCourseConsistencyIssue(
                                code: .notebookBrokenSourceID,
                                message: "SourceID断链：\(sourceID)",
                                context: sourceID,
                                fixable: false
                            )
                        )
                    }
                }
            } else {
                issues.append(
                    TeachingCourseConsistencyIssue(
                        code: .corruptedNotebook,
                        message: "随堂笔记损坏",
                        context: nil,
                        fixable: true
                    )
                )
            }
        }

        let studentInfoFile = try studentInfoFileURL(student: student)
        checked += 1
        if !fileManager.fileExists(atPath: studentInfoFile.path) {
            issues.append(
                TeachingCourseConsistencyIssue(
                    code: .missingStudentInfo,
                    message: "学生信息文件缺失",
                    context: nil,
                    fixable: true
                )
            )
        } else if (try? ArchiveStorage.readSingleListDocument(fileURL: studentInfoFile)) == nil {
            issues.append(
                TeachingCourseConsistencyIssue(
                    code: .corruptedStudentInfo,
                    message: "学生信息文件损坏",
                    context: nil,
                    fixable: true
                )
            )
        }

        let effective = try resolveEffectiveSettings(student: student)
        let lessonPlanFolderIDs = try selectedLessonPlanFolders(effectiveSettings: effective)
        for folderID in lessonPlanFolderIDs {
            checked += 1
            let folderURL = try lessonFolderURL(for: folderID)
            if !fileManager.fileExists(atPath: folderURL.path) {
                issues.append(
                    TeachingCourseConsistencyIssue(
                        code: .missingLessonFolder,
                        message: "教案目录缺失：\(folderID)",
                        context: folderID,
                        fixable: true
                    )
                )
            }
        }

        checked += 1
        if let syncBasePath = effective.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines), !syncBasePath.isEmpty {
            let syncBaseURL = URL(fileURLWithPath: syncBasePath, isDirectory: true)
            let pdfFolderURL: URL = {
                if syncBaseURL.lastPathComponent == "1-教案PDF" {
                    return syncBaseURL
                }
                return syncBaseURL.appendingPathComponent("1-教案PDF", isDirectory: true)
            }()
            if !fileManager.fileExists(atPath: pdfFolderURL.path) {
                issues.append(
                    TeachingCourseConsistencyIssue(
                        code: .missingSyncPDFFolder,
                        message: "同步PDF目录缺失",
                        context: pdfFolderURL.path,
                        fixable: true
                    )
                )
            }
        } else {
            issues.append(
                TeachingCourseConsistencyIssue(
                    code: .missingSyncBasePath,
                    message: "未配置同步基础目录",
                    context: nil,
                    fixable: false
                )
            )
        }

        return TeachingCourseConsistencySummary(checkedItemCount: checked, issueItems: issues)
    }

    static func fixStudentConsistency(
        student: TeachingStudentItem,
        strategy: TeachingCourseRepairStrategy = .standard
    ) throws -> TeachingCourseConsistencyFixSummary {
        let result = try fixConsistencyForStudents(
            students: [student],
            reportsByStudent: nil,
            strategy: strategy
        )
        return result.summary
    }

    static func fixStudentConsistencyIssues(
        student: TeachingStudentItem,
        issues: [TeachingCourseConsistencyIssue],
        strategy: TeachingCourseRepairStrategy = .standard
    ) throws -> TeachingCourseConsistencyFixSummary {
        let reports = [
            student.name: TeachingCourseConsistencySummary(
                checkedItemCount: issues.count,
                issueItems: issues
            )
        ]
        let result = try fixConsistencyForStudents(
            students: [student],
            reportsByStudent: reports,
            strategy: strategy
        )
        return result.summary
    }

    static func fixConsistencyForStudents(
        students: [TeachingStudentItem],
        reportsByStudent: [String: TeachingCourseConsistencySummary]?,
        strategy: TeachingCourseRepairStrategy
    ) throws -> TeachingCourseConsistencyBulkFixResult {
        guard !students.isEmpty else {
            return TeachingCourseConsistencyBulkFixResult(
                summary: TeachingCourseConsistencyFixSummary(
                    requestedIssueCount: 0,
                    fixedIssueCount: 0,
                    skippedIssueCount: 0
                ),
                reportsByStudent: [:]
            )
        }

        let issueMapByStudentID = try buildIssueMap(
            students: students,
            reportsByStudent: reportsByStudent
        )
        let requestedIssueCount = issueMapByStudentID.values.reduce(0) { $0 + $1.count }
        guard requestedIssueCount > 0 else {
            let refreshed = try buildConsistencyReports(students: students)
            return TeachingCourseConsistencyBulkFixResult(
                summary: TeachingCourseConsistencyFixSummary(
                    requestedIssueCount: 0,
                    fixedIssueCount: 0,
                    skippedIssueCount: 0
                ),
                reportsByStudent: refreshed
            )
        }

        let batchID = UUID().uuidString
        let studentByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        var studentSnapshots: [String: TeachingCourseFolderSnapshot] = [:]
        for student in students {
            let folderURL = try studentFolderURL(for: student)
            studentSnapshots[student.id.uuidString] = try captureStudentFolderSnapshot(studentFolderURL: folderURL)
        }

        let externalPaths = try collectExternalRepairPaths(
            studentByID: studentByID,
            issueMapByStudentID: issueMapByStudentID
        )
        var externalSnapshots: [String: TeachingCourseFolderSnapshot] = [:]
        for path in externalPaths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            externalSnapshots[path] = try captureStudentFolderSnapshot(studentFolderURL: url)
        }

        var fixedIssueCount = 0
        var skippedIssueCount = 0
        do {
            for student in students {
                let issues = issueMapByStudentID[student.id] ?? []
                let result = try applyConsistencyFixes(
                    student: student,
                    issues: issues,
                    strategy: strategy
                )
                fixedIssueCount += result.fixed
                skippedIssueCount += result.skipped
            }
            let refreshedReports = try buildConsistencyReports(students: students)
            let summary = TeachingCourseConsistencyFixSummary(
                requestedIssueCount: requestedIssueCount,
                fixedIssueCount: fixedIssueCount,
                skippedIssueCount: skippedIssueCount,
                repairBatchID: batchID
            )
            try appendRepairAuditBatch(
                batchID: batchID,
                strategy: strategy,
                studentByID: studentByID,
                studentIssueMapByID: issueMapByStudentID,
                studentSnapshots: studentSnapshots,
                externalSnapshots: externalSnapshots,
                summary: summary
            )
            return TeachingCourseConsistencyBulkFixResult(
                summary: summary,
                reportsByStudent: refreshedReports
            )
        } catch {
            for student in students {
                let folderURL = try studentFolderURL(for: student)
                if let snapshot = studentSnapshots[student.id.uuidString] {
                    try? restoreStudentFolderSnapshot(snapshot, studentFolderURL: folderURL)
                }
            }
            for (path, snapshot) in externalSnapshots {
                try? restoreStudentFolderSnapshot(snapshot, studentFolderURL: URL(fileURLWithPath: path, isDirectory: true))
            }
            throw error
        }
    }

    static func rollbackLatestConsistencyRepairBatch() throws -> TeachingCourseConsistencyFixSummary {
        let latestURL = try latestRepairAuditPointerURL()
        guard FileManager.default.fileExists(atPath: latestURL.path) else {
            return TeachingCourseConsistencyFixSummary(
                requestedIssueCount: 0,
                fixedIssueCount: 0,
                skippedIssueCount: 0,
                repairBatchID: nil,
                rolledBackStudentCount: 0
            )
        }
        let latestData = try Data(contentsOf: latestURL)
        let pointer = try JSONDecoder().decode(TeachingCourseRepairAuditPointer.self, from: latestData)
        let batchURL = try repairAuditBatchURL(batchID: pointer.latestBatchID)
        guard FileManager.default.fileExists(atPath: batchURL.path) else {
            return TeachingCourseConsistencyFixSummary(
                requestedIssueCount: 0,
                fixedIssueCount: 0,
                skippedIssueCount: 0,
                repairBatchID: nil,
                rolledBackStudentCount: 0
            )
        }
        let batchData = try Data(contentsOf: batchURL)
        let batch = try JSONDecoder().decode(TeachingCourseRepairAuditBatch.self, from: batchData)

        var restoredStudents = 0
        for (studentID, snapshot) in batch.studentSnapshotsByID {
            guard let studentName = batch.studentNameByID[studentID] else { continue }
            let student = TeachingStudentItem(id: UUID(uuidString: studentID) ?? UUID(), name: studentName)
            let folderURL = try studentFolderURL(for: student)
            try restoreStudentFolderSnapshot(snapshot, studentFolderURL: folderURL)
            restoredStudents += 1
        }
        for (path, snapshot) in batch.externalSnapshotsByPath {
            try restoreStudentFolderSnapshot(snapshot, studentFolderURL: URL(fileURLWithPath: path, isDirectory: true))
        }

        try FileManager.default.removeItem(at: batchURL)
        let remaining = try listRepairAuditBatchIDsSortedDescending()
        if let next = remaining.first {
            let newPointer = TeachingCourseRepairAuditPointer(latestBatchID: next)
            let pointerData = try JSONEncoder().encode(newPointer)
            try pointerData.write(to: latestURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: latestURL)
        }

        return TeachingCourseConsistencyFixSummary(
            requestedIssueCount: batch.summary.requestedIssueCount,
            fixedIssueCount: 0,
            skippedIssueCount: 0,
            repairBatchID: batch.batchID,
            rolledBackStudentCount: restoredStudents
        )
    }

    static func loadRecentSyncConflicts(student: TeachingStudentItem, limit: Int = 50) throws -> [String] {
        try loadRecentSyncConflictItems(student: student, limit: limit).map(\.displayText)
    }

    static func loadRecentSyncConflictItems(
        student: TeachingStudentItem,
        limit: Int = 50
    ) throws -> [TeachingCourseSyncConflictItem] {
        let logURL = try syncConflictLogURL(student: student)
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let lines = text.split(separator: "\n").suffix(max(1, limit))
        return lines.compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let record = try? JSONDecoder().decode(TeachingCourseSyncConflictRecord.self, from: data) else {
                return nil
            }
            return TeachingCourseSyncConflictItem(
                timestamp: record.timestamp,
                sourceFile: record.sourceFile,
                sourceID: record.sourceID,
                note: record.note
            )
        }
    }

    static func clearSyncConflicts(student: TeachingStudentItem) throws {
        let logURL = try syncConflictLogURL(student: student)
        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.removeItem(at: logURL)
        }
    }

    static func resolveSyncConflict(
        student: TeachingStudentItem,
        item: TeachingCourseSyncConflictItem,
        action: TeachingCourseConflictResolutionAction
    ) async throws -> String {
        try await runStudentFolderTransaction(student: student, operation: "resolveSyncConflict") {
            let notebookFileURL = try notebookURL(for: student)
            var notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookFileURL)
            guard let notebookRange = h3PackageRange(in: notebookPayload.0.nodes, sourceID: item.sourceID) else {
                throw NSError(
                    domain: "TeachingCourseWorkflowService",
                    code: 4101,
                    userInfo: [NSLocalizedDescriptionKey: "笔记中未找到冲突包：\(item.sourceID)"]
                )
            }

            var notebookPackage = Array(notebookPayload.0.nodes[notebookRange.start..<notebookRange.end])
            notebookPackage = clearConflictMarkers(in: notebookPackage)

            switch action {
            case .acceptSource:
                guard let sourceURL = try sourceURLFromRelative(item.sourceFile) else {
                    throw NSError(
                        domain: "TeachingCourseWorkflowService",
                        code: 4102,
                        userInfo: [NSLocalizedDescriptionKey: "母本路径不存在：\(item.sourceFile)"]
                    )
                }
                let sourcePayload = try NodeMarkdownFileManager.read(fileURL: sourceURL)
                guard let sourceRange = h3PackageRange(in: sourcePayload.0.nodes, sourceID: item.sourceID) else {
                    throw NSError(
                        domain: "TeachingCourseWorkflowService",
                        code: 4103,
                        userInfo: [NSLocalizedDescriptionKey: "母本中未找到冲突包：\(item.sourceID)"]
                    )
                }
                var sourcePackage = Array(sourcePayload.0.nodes[sourceRange.start..<sourceRange.end])
                sourcePackage = clearConflictMarkers(in: sourcePackage)
                notebookPayload.0.nodes.replaceSubrange(notebookRange.start..<notebookRange.end, with: sourcePackage)
                try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookFileURL)

            case .acceptNotebook:
                guard let sourceURL = try sourceURLFromRelative(item.sourceFile) else {
                    throw NSError(
                        domain: "TeachingCourseWorkflowService",
                        code: 4104,
                        userInfo: [NSLocalizedDescriptionKey: "母本路径不存在：\(item.sourceFile)"]
                    )
                }
                var sourcePayload = try NodeMarkdownFileManager.read(fileURL: sourceURL)
                guard let sourceRange = h3PackageRange(in: sourcePayload.0.nodes, sourceID: item.sourceID) else {
                    throw NSError(
                        domain: "TeachingCourseWorkflowService",
                        code: 4105,
                        userInfo: [NSLocalizedDescriptionKey: "母本中未找到冲突包：\(item.sourceID)"]
                    )
                }
                sourcePayload.0.nodes.replaceSubrange(sourceRange.start..<sourceRange.end, with: notebookPackage)
                try NodeMarkdownFileManager.write(document: sourcePayload.0, meta: sourcePayload.1, to: sourceURL)
                notebookPayload.0.nodes.replaceSubrange(notebookRange.start..<notebookRange.end, with: notebookPackage)
                try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookFileURL)

            case .clearMarker:
                notebookPayload.0.nodes.replaceSubrange(notebookRange.start..<notebookRange.end, with: notebookPackage)
                try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookFileURL)
            }

            var baselineMap = (try? loadSyncBaselineMap(student: student)) ?? [:]
            let baselineKey = syncBaselineKey(sourceFile: item.sourceFile, sourceID: item.sourceID)
            baselineMap[baselineKey] = packageDigest(notebookPackage)
            try saveSyncBaselineMap(baselineMap, student: student)

            try removeSyncConflictRecords(student: student, sourceFile: item.sourceFile, sourceID: item.sourceID)

            return "\(action.displayName)完成：\(item.sourceFile)#\(item.sourceID)"
        }
    }

    static func searchAuditLogs(
        keyword: String,
        limit: Int = 200
    ) throws -> [TeachingCourseAuditLogItem] {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let loweredKeyword = trimmedKeyword.lowercased()
        let systemFolder = try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        let fileManager = FileManager.default
        var results: [TeachingCourseAuditLogItem] = []

        let transactionLog = systemFolder.appendingPathComponent("course-transactions.log", isDirectory: false)
        if fileManager.fileExists(atPath: transactionLog.path) {
            let text = (try? String(contentsOf: transactionLog, encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n").suffix(max(1, limit)) {
                let rawLine = String(line)
                if !loweredKeyword.isEmpty && !rawLine.lowercased().contains(loweredKeyword) {
                    continue
                }
                let json = (try? JSONSerialization.jsonObject(with: Data(rawLine.utf8))) as? [String: Any]
                let timestamp = (json?["timestamp"] as? String) ?? ""
                let operation = (json?["operation"] as? String) ?? ""
                let studentName = (json?["studentName"] as? String) ?? ""
                let phase = (json?["phase"] as? String) ?? ""
                let summary = [operation, studentName, phase]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                results.append(
                    TeachingCourseAuditLogItem(
                        id: "txn-\(timestamp)-\(results.count)",
                        source: .transaction,
                        timestamp: timestamp,
                        summary: summary.isEmpty ? rawLine : summary,
                        rawLine: rawLine
                    )
                )
            }
        }

        let conflictFolder = systemFolder.appendingPathComponent("course-sync-conflicts", isDirectory: true)
        if fileManager.fileExists(atPath: conflictFolder.path) {
            let urls = (try? fileManager.contentsOfDirectory(
                at: conflictFolder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension.lowercased() == "log" {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                for line in text.split(separator: "\n").suffix(80) {
                    let rawLine = String(line)
                    if !loweredKeyword.isEmpty && !rawLine.lowercased().contains(loweredKeyword) {
                        continue
                    }
                    let json = (try? JSONSerialization.jsonObject(with: Data(rawLine.utf8))) as? [String: Any]
                    let timestamp = (json?["timestamp"] as? String) ?? ""
                    let sourceFile = (json?["sourceFile"] as? String) ?? ""
                    let sourceID = (json?["sourceID"] as? String) ?? ""
                    let summary = "\(url.deletingPathExtension().lastPathComponent) · \(sourceFile)#\(sourceID)"
                    results.append(
                        TeachingCourseAuditLogItem(
                            id: "conf-\(timestamp)-\(results.count)",
                            source: .conflict,
                            timestamp: timestamp,
                            summary: summary,
                            rawLine: rawLine
                        )
                    )
                }
            }
        }

        let signatureLog = systemFolder.appendingPathComponent("course-export-signatures.log", isDirectory: false)
        if fileManager.fileExists(atPath: signatureLog.path) {
            let text = (try? String(contentsOf: signatureLog, encoding: .utf8)) ?? ""
            for line in text.split(separator: "\n").suffix(max(1, limit)) {
                let rawLine = String(line)
                if !loweredKeyword.isEmpty && !rawLine.lowercased().contains(loweredKeyword) {
                    continue
                }
                let json = (try? JSONSerialization.jsonObject(with: Data(rawLine.utf8))) as? [String: Any]
                let timestamp = (json?["timestamp"] as? String) ?? ""
                let destinationPath = (json?["destinationPath"] as? String) ?? ""
                results.append(
                    TeachingCourseAuditLogItem(
                        id: "sig-\(timestamp)-\(results.count)",
                        source: .exportSignature,
                        timestamp: timestamp,
                        summary: destinationPath.isEmpty ? "导出签名" : destinationPath,
                        rawLine: rawLine
                    )
                )
            }
        }

        return results
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(max(1, limit))
            .map { $0 }
    }

    static func finishClass(student: TeachingStudentItem) async throws -> TeachingCourseFinishSummary {
        try await runStudentFolderTransaction(student: student, operation: "finishClass") {
            let notebookURL = try notebookURL(for: student)
            var notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookURL)
            let syncTime = Date()
            let cleanupResult = TeachingCourseFinishClassService.runCleanup(
                document: &notebookPayload.0,
                syncTime: syncTime
            )
            let dirtyH3Summary: String = {
                if cleanupResult.dirtyH3NodeIDs.isEmpty { return "none" }
                return cleanupResult.dirtyH3NodeIDs.joined(separator: "|")
            }()
            try appendTransactionLog(
                transactionID: UUID().uuidString,
                operation: "finishClassCleanup",
                student: student,
                phase: "cleanup",
                detail: "removedEmptyNonH3=\(cleanupResult.removedNodeCount), dirtyH3=\(cleanupResult.dirtyH3NodeIDs.count), dirtyH3IDs=\(dirtyH3Summary)"
            )
            try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookURL)
            let syncSummary = try await performNotebookSync(student: student, placementTarget: nil)
            let exportedPDFPath = try await exportNotebookExportsIfPossible(
                student: student,
                notebookURL: notebookURL,
                document: notebookPayload.0
            )
            return TeachingCourseFinishSummary(
                removedEmptyNodeCount: cleanupResult.removedNodeCount,
                syncSummary: syncSummary,
                exportedPDFPath: exportedPDFPath
            )
        }
    }

    /// 同步页与下课共用同一套导出实现，始终重建普通PDF、分H1 PDF、分文件PDF和HTML。
    static func regenerateNotebookExports(student: TeachingStudentItem) async throws -> String? {
        try await runStudentFolderTransaction(student: student, operation: "regenerateNotebookExports") {
            let notebookURL = try notebookURL(for: student)
            let document = try NodeMarkdownFileManager.read(fileURL: notebookURL).0
            return try await exportNotebookExportsIfPossible(
                student: student,
                notebookURL: notebookURL,
                document: document
            )
        }
    }

    static func latestClassInfoFileURL(student: TeachingStudentItem) throws -> URL? {
        try classInfoFileURLs(student: student).first
    }

    /// 首页“上课记录”入口：当天排课存在时先补齐当天课反，再打开日期最晚的一份。
    /// 课反仍只由明确的排课或开课动作建立；仅浏览学生不会凭空产生文件。
    static func latestClassInfoFileURLPreparingScheduledToday(
        student: TeachingStudentItem,
        now: Date = Date()
    ) throws -> URL? {
        let calendar = Calendar.current
        let hasScheduledLessonToday = try TeachingLessonPlanningStore.load(.planning).contains { record in
            guard record.studentID == student.id,
                  let start = TeachingLessonStatisticsStore.date(from: record.startAt) else {
                return false
            }
            return calendar.isDate(start, inSameDayAs: now)
        }
        if hasScheduledLessonToday {
            _ = try classInfoFileURL(student: student, on: now)
        }
        return try latestClassInfoFileURL(student: student)
    }

    static func classInfoFileURLs(student: TeachingStudentItem) throws -> [URL] {
        let folderURL = try studentFolderURL(for: student)
        let prefix = "上课信息_\(student.name)_"
        let urls = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { url in
                guard url.pathExtension.lowercased() == "csv" else { return false }
                let fileName = url.deletingPathExtension().lastPathComponent
                guard fileName.hasPrefix(prefix) else { return false }
                let dateToken = fileName.dropFirst(prefix.count)
                return dateToken.count == 6 && dateToken.allSatisfy(\.isNumber)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
    }

    static func studentInfoFileURL(student: TeachingStudentItem) throws -> URL {
        try studentFolderURL(for: student).appendingPathComponent("学生信息_\(student.name).CSV", isDirectory: false)
    }

    /// 排课页按课程日期打开课反。文件不存在时复用学生统一模板建立对应日期的上课信息表。
    static func classInfoFileURL(student: TeachingStudentItem, on date: Date) throws -> URL {
        let studentFolder = try studentFolderURL(for: student)
        let effectiveSettings = try resolveEffectiveSettings(student: student)
        let dateToken = classInfoDateToken(for: date)
        _ = try createClassInfoIfNeeded(
            student: student,
            studentFolder: studentFolder,
            effectiveSettings: effectiveSettings,
            date: dateToken
        )
        return studentFolder.appendingPathComponent("上课信息_\(student.name)_\(dateToken).CSV", isDirectory: false)
    }

    static func lessonCompletionChecklistFiles(student: TeachingStudentItem) throws -> [URL] {
        let effective = try resolveEffectiveSettings(student: student)
        let lessonFolderIDs = try selectedLessonPlanFolders(effectiveSettings: effective)
        let studentFolder = try studentFolderURL(for: student)
        let files = lessonFolderIDs.map { folderID in
            studentFolder.appendingPathComponent("教案_\(folderID)_完成情况_\(student.name).CSV", isDirectory: false)
        }
        return files.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func prepareForSession(
        student: TeachingStudentItem,
        createClassInfo: Bool
    ) async throws -> TeachingCoursePreparationSummary {
        try ensureInitializationReadyForTeaching(student: student)
        let effective = try resolveEffectiveSettings(student: student)
        let lessonFolderIDs = try selectedLessonPlanFolders(effectiveSettings: effective)
        let studentFolder = try studentFolderURL(for: student)
        let lessonTemplateFolder = try lessonPlanTemplateRootURL()
        let notebookURL = try notebookURL(for: student)

        var lessonTemplateMap: [String: [ChecklistTemplateRow]] = [:]
        var templateFileCount = 0
        var completionFileCount = 0
        var completedTaskCount = 0

        for folderID in lessonFolderIDs {
            let templateRows = try buildTemplateRows(lessonFolderID: folderID)
            lessonTemplateMap[folderID] = templateRows
            templateFileCount += 1

            let templateMeta = ChecklistDocumentMeta(
                id: UUID().uuidString,
                title: "教案_\(folderID)",
                templateID: "",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                type: "workbook"
            )
            let templateURL = lessonTemplateFolder.appendingPathComponent("教案_\(folderID).CSV", isDirectory: false)
            try writeChecklistRows(templateRows, meta: templateMeta, to: templateURL, metaType: "workbook")
            let legacyTemplateURL = studentFolder.appendingPathComponent("教案_\(folderID).CSV", isDirectory: false)
            if FileManager.default.fileExists(atPath: legacyTemplateURL.path) {
                try? FileManager.default.removeItem(at: legacyTemplateURL)
            }
        }

        var notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookURL)
        let notebookBeforePreparation = notebookPayload.0
        let studentWriteKey = notebookURL.deletingLastPathComponent().standardizedFileURL.path
        let sourceKeys = try sourceWriteKeys(document: notebookPayload.0, placementTarget: nil)
            .filter { $0 != studentWriteKey }
        await acquireWriteKeys(sourceKeys)
        let refreshResult: (replacedCount: Int, detachedCount: Int)
        do {
            refreshResult = try refreshNotebookBySources(document: &notebookPayload.0)
            if notebookPayload.0 != notebookBeforePreparation {
                try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookURL)
            }
            await releaseWriteKeys(sourceKeys)
        } catch {
            await releaseWriteKeys(sourceKeys)
            throw error
        }

        let completedPackageKeys = completedLessonPackageKeys(in: notebookPayload.0)

        for folderID in lessonFolderIDs {
            let templateRows = lessonTemplateMap[folderID] ?? []
            let completionRows = templateRows.map { row in
                var next = row
                if let packageKey = lessonPackageKey(sourceFile: row.sourceFile, sourceID: row.sourceID) {
                    next.status = completedPackageKeys.contains(packageKey) ? 1 : 0
                } else {
                    next.status = 0
                }
                return next
            }
            completedTaskCount += completionRows.filter { $0.status == 1 && $0.level == 3 }.count
            completionFileCount += 1
            let completionMeta = ChecklistDocumentMeta(
                id: UUID().uuidString,
                title: "教案_\(folderID)_完成情况_\(student.name)",
                templateID: "",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                type: "tablelist"
            )
            let completionURL = studentFolder.appendingPathComponent("教案_\(folderID)_完成情况_\(student.name).CSV", isDirectory: false)
            try writeChecklistRows(completionRows, meta: completionMeta, to: completionURL, metaType: "tablelist")
        }

        var classInfoCreated = false
        if createClassInfo {
            classInfoCreated = try createClassInfoForTodayIfNeeded(
                student: student,
                studentFolder: studentFolder,
                effectiveSettings: effective
            )
            let focusRowIndex = appendTeachingSessionHeader(to: &notebookPayload.0, at: Date())
            try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookURL)
            await TeachingCourseEditingAnchorStore.shared.setActiveRow(
                filePath: notebookURL.standardizedFileURL.path,
                rowIndex: focusRowIndex
            )
        }

        return TeachingCoursePreparationSummary(
            lessonPlanCount: lessonFolderIDs.count,
            templateFileCount: templateFileCount,
            completionFileCount: completionFileCount,
            refreshedPackageCount: refreshResult.replacedCount,
            detachedPackageCount: refreshResult.detachedCount,
            completedTaskCount: completedTaskCount,
            classInfoCreated: classInfoCreated
        )
    }

    /// 开课区块固定为“日期H1 + 空H2”。当天日期H1在整篇随堂笔记中唯一：
    /// 已存在时直接复用其后的H2，不因日期节点位于文中而重复追加。仅在首次追加时
    /// 清理文件末尾普通空节点，绝不删除带来源信息的受保护H3。
    private static func appendTeachingSessionHeader(
        to document: inout NodeMarkdownDocument,
        at date: Date
    ) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyMMdd"
        let dateText = formatter.string(from: date)

        if let dateRowIndex = document.nodes.lastIndex(where: {
            $0.level == 1 && $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == dateText
        }) {
            let followingRowIndex = dateRowIndex + 1
            if document.nodes.indices.contains(followingRowIndex),
               document.nodes[followingRowIndex].level == 2 {
                return followingRowIndex
            }
            document.nodes.insert(
                NodeMarkdownNode(level: 2, text: "", mtimeCache: Date()),
                at: followingRowIndex
            )
            return followingRowIndex
        }

        while let last = document.nodes.last,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(last.level == 3 && (!last.sourceID.isEmpty || !last.sourceFile.isEmpty)) {
            document.nodes.removeLast()
        }
        let now = Date()
        document.nodes.append(
            NodeMarkdownNode(level: 1, text: dateText, mtimeCache: now)
        )
        document.nodes.append(
            NodeMarkdownNode(level: 2, text: "", mtimeCache: now)
        )
        return document.nodes.count - 1
    }

    private static func ensureInitializationReadyForTeaching(student: TeachingStudentItem) throws {
        let profile = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
        let syncPath = profile?.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !syncPath.isEmpty else {
            throw NSError(
                domain: "TeachingCourseWorkflowService",
                code: 4601,
                userInfo: [NSLocalizedDescriptionKey: "未完成初始化：请先在“初始”页选择同步文件夹后再开始上课。"]
            )
        }
    }

    private static func performNotebookSync(
        student: TeachingStudentItem,
        placementTarget: TeachingCourseUpdatePlacementTarget?,
        allowedNewPackageIDs: Set<String>? = nil
    ) async throws -> TeachingCourseSyncSummary {
        let initialNotebookURL = try notebookURL(for: student)
        let initialNotebook = try NodeMarkdownFileManager.read(fileURL: initialNotebookURL).0
        let studentWriteKey = initialNotebookURL.deletingLastPathComponent().standardizedFileURL.path
        let sourceKeys = try sourceWriteKeys(
            document: initialNotebook,
            placementTarget: placementTarget
        ).filter { $0 != studentWriteKey }
        await acquireWriteKeys(sourceKeys)
        do {
            let result = try await performNotebookSyncWithSourcesLocked(
                student: student,
                placementTarget: placementTarget,
                allowedNewPackageIDs: allowedNewPackageIDs
            )
            await releaseWriteKeys(sourceKeys)
            return result
        } catch {
            await releaseWriteKeys(sourceKeys)
            throw error
        }
    }

    private static func performNotebookSyncWithSourcesLocked(
        student: TeachingStudentItem,
        placementTarget: TeachingCourseUpdatePlacementTarget?,
        allowedNewPackageIDs: Set<String>?
    ) async throws -> TeachingCourseSyncSummary {
        let notebookURL = try notebookURL(for: student)
        var notebookPayload = try NodeMarkdownFileManager.read(fileURL: notebookURL)
        let baselineMap = (try? loadSyncBaselineMap(student: student)) ?? [:]
        let originalNotebookDocument = notebookPayload.0
        var execution = try TeachingCoursePackageSyncEngine.execute(
            student: student,
            notebookDocument: notebookPayload.0,
            placementTarget: placementTarget,
            allowedNewPackageIDs: allowedNewPackageIDs,
            baselineMap: baselineMap,
            resolveSourceURL: { sourceFile in
                try sourceURLFromRelative(sourceFile)
            },
            loadSourcePayload: { sourceURL in
                try NodeMarkdownFileManager.read(fileURL: sourceURL)
            },
            appendPackageToTargetOrCollector: { packageNodes, placementTarget in
                try appendPackageToTargetOrCollector(
                    packageNodes: packageNodes,
                    placementTarget: placementTarget
                )
            }
        )

        // 新包入口会先把完整H3包写入用户选中的章教案。若同一章在本轮还有脏包，
        // 同步引擎手里可能已经有一份较早的章教案缓存；必须先把脏包改动合并到
        // 刚写入新包的磁盘版本，后面才能以一份最终文档统一迁图、落盘和复核。
        try reconcileSourceCacheWithPersistedNewPackages(execution: &execution)
        try migrateCollectedPackageImages(
            previousNotebookDocument: originalNotebookDocument,
            execution: &execution,
            notebookURL: notebookURL
        )
        notebookPayload.0 = execution.notebookDocument

        for (path, payload) in execution.sourceDocumentCache {
            try NodeMarkdownFileManager.write(document: payload.0, meta: payload.1, to: URL(fileURLWithPath: path))
        }
        if notebookPayload.0 != originalNotebookDocument {
            try NodeMarkdownFileManager.write(document: notebookPayload.0, meta: notebookPayload.1, to: notebookURL)
            NodeMarkdownImageResourceManager.restoreReferencedStashedImages(
                currentDocument: notebookPayload.0,
                notebookFileURL: notebookURL
            )
        }
        try verifyCollectedNewPackagesAfterPersistence(
            execution: &execution,
            notebookURL: notebookURL,
            requireAllNewPackagesResolved: allowedNewPackageIDs == nil
        )
        try saveSyncBaselineMap(execution.baselineMap, student: student)
        let workflowConflictRecords = execution.conflictRecords.map {
            TeachingCourseSyncConflictRecord(
                timestamp: $0.timestamp,
                studentID: $0.studentID,
                studentName: $0.studentName,
                sourceFile: $0.sourceFile,
                sourceID: $0.sourceID,
                baselineDigest: $0.baselineDigest,
                notebookDigest: $0.notebookDigest,
                sourceDigest: $0.sourceDigest,
                note: $0.note
            )
        }
        try appendSyncConflictRecords(workflowConflictRecords, student: student)

        return TeachingCourseSyncSummary(
            updatedSourcePackageCount: execution.updatedSourcePackageCount,
            collectedNewPackageCount: execution.collectedNewPackageCount,
            conflictPackageCount: execution.conflictPackageCount,
            packageResults: execution.packageResults
        )
    }

    private static func reconcileSourceCacheWithPersistedNewPackages(
        execution: inout TeachingCoursePackageSyncExecutionResult
    ) throws {
        let newPackageSourcePaths = Set(
            try execution.packageResults.compactMap { result -> String? in
                guard result.isNewPackage,
                      result.success,
                      result.reason != "new package skipped by selection",
                      let sourceURL = try sourceURLFromRelative(result.sourceFile) else {
                    return nil
                }
                return sourceURL.standardizedFileURL.path
            }
        )
        guard !newPackageSourcePaths.isEmpty else { return }

        let dirtyResults = execution.packageResults.filter {
            !$0.isNewPackage
                && $0.success
                && $0.reason == "notebook H3 modification time won"
        }

        for cachePath in Array(execution.sourceDocumentCache.keys) {
            let standardizedPath = URL(fileURLWithPath: cachePath).standardizedFileURL.path
            guard newPackageSourcePaths.contains(standardizedPath),
                  let cachedPayload = execution.sourceDocumentCache[cachePath] else {
                continue
            }

            let diskPayload = try NodeMarkdownFileManager.read(
                fileURL: URL(fileURLWithPath: standardizedPath)
            )
            var finalDocument = diskPayload.0

            for result in dirtyResults {
                guard let resultURL = try sourceURLFromRelative(result.sourceFile),
                      resultURL.standardizedFileURL.path == standardizedPath,
                      let cachedRange = TeachingCoursePackageContentSignature.packageRange(
                          in: cachedPayload.0.nodes,
                          sourceID: result.sourceID
                      ),
                      let finalRange = TeachingCoursePackageContentSignature.packageRange(
                          in: finalDocument.nodes,
                          sourceID: result.sourceID
                      ) else {
                    continue
                }
                let replacement = cachedPayload.0.nodes[cachedRange.start..<cachedRange.end]
                finalDocument.nodes.replaceSubrange(
                    finalRange.start..<finalRange.end,
                    with: replacement
                )
            }

            execution.sourceDocumentCache[cachePath] = (finalDocument, diskPayload.1)
        }
    }

    // 入库成功以磁盘事实为准：随堂H3、SourceID和母本H3必须是同一个出生UUID。
    private static func verifyCollectedNewPackagesAfterPersistence(
        execution: inout TeachingCoursePackageSyncExecutionResult,
        notebookURL: URL,
        requireAllNewPackagesResolved: Bool
    ) throws {
        let notebook = try NodeMarkdownFileManager.read(fileURL: notebookURL).0
        var verifiedCount = 0

        for index in execution.packageResults.indices {
            let result = execution.packageResults[index]
            guard result.isNewPackage,
                  result.success,
                  result.reason != "new package skipped by selection" else {
                continue
            }

            let sourceID = result.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = result.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let packageUUID = UUID(uuidString: sourceID),
                  !sourceFile.isEmpty,
                  let notebookRoot = notebook.nodes.first(where: {
                      $0.level == 3 && $0.id == packageUUID
                  }),
                  notebookRoot.sourceID.caseInsensitiveCompare(sourceID) == .orderedSame,
                  notebookRoot.sourceFile == sourceFile else {
                execution.packageResults[index].success = false
                execution.packageResults[index].reason = "new package persistence verification failed in notebook"
                continue
            }

            guard let notebookRange = TeachingCoursePackageContentSignature.packageRange(
                      in: notebook.nodes,
                      rootID: packageUUID
                  ),
                  let sourceURL = try sourceURLFromRelative(sourceFile),
                  FileManager.default.fileExists(atPath: sourceURL.path),
                  let sourceDocument = try? NodeMarkdownFileManager.read(fileURL: sourceURL).0,
                  let sourceRange = TeachingCoursePackageContentSignature.packageRange(
                      in: sourceDocument.nodes,
                      rootID: packageUUID
                  ) else {
                execution.packageResults[index].success = false
                execution.packageResults[index].reason = "new package persistence verification failed in source"
                continue
            }
            let notebookPackage = Array(notebook.nodes[notebookRange.start..<notebookRange.end])
            let sourcePackage = Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
            guard TeachingCoursePackageContentSignature.persistenceDigest(
                notebookPackage,
                documentFileURL: notebookURL
            ) == TeachingCoursePackageContentSignature.persistenceDigest(
                sourcePackage,
                documentFileURL: sourceURL
            ) else {
                execution.packageResults[index].success = false
                execution.packageResults[index].reason = "new package content verification failed in source"
                continue
            }
            verifiedCount += 1
        }
        execution.collectedNewPackageCount = verifiedCount

        // 关闭和下课不相信界面名单，重新扫描磁盘；名单残影不会进入这里。
        guard requireAllNewPackagesResolved else { return }
        for root in notebook.nodes where root.level == 3 {
            guard TeachingCoursePackageContentSignature.isCollectableNewPackageRoot(root) else { continue }
            execution.packageResults.append(
                TeachingCourseSyncPackageResult(
                    packageTitle: root.text,
                    sourceFile: "",
                    sourceID: root.id.uuidString,
                    isNewPackage: true,
                    success: false,
                    reason: "final disk scan found an uncollected new package"
                )
            )
        }
    }

    private static func migrateCollectedPackageImages(
        previousNotebookDocument: NodeMarkdownDocument,
        execution: inout TeachingCoursePackageSyncExecutionResult,
        notebookURL: URL
    ) throws {
        let notebookBaseDirectoryURL = notebookURL.deletingLastPathComponent()
        var previousH3ByID: [UUID: NodeMarkdownNode] = [:]
        for node in previousNotebookDocument.nodes where node.level == 3 {
            if let existing = previousH3ByID[node.id] {
                previousH3ByID[node.id] = preferredPreviousH3ForImageMigration(existing, node)
            } else {
                previousH3ByID[node.id] = node
            }
        }

        for range in h3PackageRanges(in: execution.notebookDocument.nodes).reversed() {
            guard execution.notebookDocument.nodes.indices.contains(range.start) else { continue }
            let currentRoot = execution.notebookDocument.nodes[range.start]
            let currentSourceFile = currentRoot.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentSourceID = currentRoot.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !currentSourceFile.isEmpty, !currentSourceID.isEmpty else { continue }

            guard let previousRoot = previousH3ByID[currentRoot.id] else { continue }
            let previousSourceFile = previousRoot.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            let previousSourceID = previousRoot.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard previousSourceFile.isEmpty || previousSourceID.isEmpty else { continue }
            guard let sourceURL = try sourceURLFromRelative(currentSourceFile) else { continue }

            let temporaryPackageID = previousSourceID.isEmpty ? previousRoot.id.uuidString : previousSourceID
            let notebookPackage = Array(execution.notebookDocument.nodes[range.start..<range.end])
            let migratedNotebookPackage = try NodeMarkdownImageResourceManager.migrateTemporaryImageTokens(
                in: notebookPackage,
                temporaryPackageID: temporaryPackageID,
                formalSourceFileURL: sourceURL,
                sourceTokenBaseDirectoryURL: notebookBaseDirectoryURL,
                outputTokenBaseDirectoryURL: notebookBaseDirectoryURL,
                notebookFileURL: notebookURL
            )
            guard migratedNotebookPackage.migratedCount > 0 else { continue }

            execution.notebookDocument.nodes.replaceSubrange(range.start..<range.end, with: migratedNotebookPackage.nodes)
            try migrateCollectedPackageImagesInSource(
                sourceURL: sourceURL,
                sourceFile: currentSourceFile,
                sourceID: currentSourceID,
                temporaryPackageID: temporaryPackageID,
                notebookBaseDirectoryURL: notebookBaseDirectoryURL,
                notebookURL: notebookURL,
                execution: &execution
            )

            let baselineKey = syncBaselineKey(sourceFile: currentSourceFile, sourceID: currentSourceID)
            execution.baselineMap[baselineKey] = packageDigest(migratedNotebookPackage.nodes)
        }
    }

    private static func preferredPreviousH3ForImageMigration(
        _ lhs: NodeMarkdownNode,
        _ rhs: NodeMarkdownNode
    ) -> NodeMarkdownNode {
        let lhsNeedsMigration = lhs.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || lhs.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rhsNeedsMigration = rhs.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || rhs.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if lhsNeedsMigration != rhsNeedsMigration {
            return lhsNeedsMigration ? lhs : rhs
        }
        return lhs
    }

    private static func migrateCollectedPackageImagesInSource(
        sourceURL: URL,
        sourceFile: String,
        sourceID: String,
        temporaryPackageID: String,
        notebookBaseDirectoryURL: URL,
        notebookURL: URL,
        execution: inout TeachingCoursePackageSyncExecutionResult
    ) throws {
        let cacheKey = sourceURL.path
        let payload: (NodeMarkdownDocument, NodeMarkdownFileMeta)
        if let cached = execution.sourceDocumentCache[cacheKey] {
            payload = cached
        } else {
            payload = try NodeMarkdownFileManager.read(fileURL: sourceURL)
        }

        var sourceDocument = payload.0
        guard let sourceRange = h3PackageRange(in: sourceDocument.nodes, sourceID: sourceID) else { return }
        let sourcePackage = Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
        let migratedSourcePackage = try NodeMarkdownImageResourceManager.migrateTemporaryImageTokens(
            in: sourcePackage,
            temporaryPackageID: temporaryPackageID,
            formalSourceFileURL: sourceURL,
            sourceTokenBaseDirectoryURL: notebookBaseDirectoryURL,
            outputTokenBaseDirectoryURL: sourceURL.deletingLastPathComponent(),
            notebookFileURL: notebookURL
        )
        guard migratedSourcePackage.migratedCount > 0 else { return }

        sourceDocument.nodes.replaceSubrange(sourceRange.start..<sourceRange.end, with: migratedSourcePackage.nodes)
        execution.sourceDocumentCache[cacheKey] = (sourceDocument, payload.1)
    }

    private static func packageDigest(_ packageNodes: [NodeMarkdownNode]) -> String {
        TeachingCoursePackageContentSignature.digest(packageNodes)
    }

    private static func syncBaselineKey(sourceFile: String, sourceID: String) -> String {
        "\(sourceFile)#\(sourceID)"
    }

    private static func loadSyncBaselineMap(student: TeachingStudentItem) throws -> [String: String] {
        let url = try syncBaselineFileURL(student: student)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveSyncBaselineMap(_ baselineMap: [String: String], student: TeachingStudentItem) throws {
        let url = try syncBaselineFileURL(student: student)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(baselineMap)
        try data.write(to: url, options: .atomic)
    }

    private static func syncBaselineFileURL(student: TeachingStudentItem) throws -> URL {
        try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("course-sync-baselines", isDirectory: true)
            .appendingPathComponent("\(student.id.uuidString).json", isDirectory: false)
    }

    private static func appendSyncConflictRecords(
        _ records: [TeachingCourseSyncConflictRecord],
        student: TeachingStudentItem
    ) throws {
        guard !records.isEmpty else { return }
        let logURL = try syncConflictLogURL(student: student)
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            for record in records {
                let data = try encoder.encode(record)
                if let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) {
                    try handle.write(contentsOf: line)
                }
            }
        } else {
            var text = ""
            for record in records {
                let data = try encoder.encode(record)
                if let line = String(data: data, encoding: .utf8) {
                    text.append(line)
                    text.append("\n")
                }
            }
            try text.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private static func syncConflictLogURL(student: TeachingStudentItem) throws -> URL {
        try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("course-sync-conflicts", isDirectory: true)
            .appendingPathComponent("\(student.id.uuidString).log", isDirectory: false)
    }

    private static func removeSyncConflictRecords(
        student: TeachingStudentItem,
        sourceFile: String,
        sourceID: String
    ) throws {
        let logURL = try syncConflictLogURL(student: student)
        guard FileManager.default.fileExists(atPath: logURL.path) else { return }
        let text = try String(contentsOf: logURL, encoding: .utf8)
        let remains = text.split(separator: "\n").filter { line in
            guard let data = String(line).data(using: .utf8),
                  let record = try? JSONDecoder().decode(TeachingCourseSyncConflictRecord.self, from: data) else {
                return false
            }
            return !(record.sourceFile == sourceFile && record.sourceID == sourceID)
        }
        let output = remains.map(String.init).joined(separator: "\n")
        let finalText = output.isEmpty ? "" : output + "\n"
        try finalText.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func markPackageConflictIfNeeded(_ packageNodes: [NodeMarkdownNode]) -> [NodeMarkdownNode] {
        guard !packageNodes.isEmpty else { return packageNodes }
        let markerPrefix = "⚠️冲突待确认"
        if packageNodes.contains(where: { $0.text.hasPrefix(markerPrefix) }) {
            return packageNodes
        }
        var result = packageNodes
        let marker = NodeMarkdownNode(
            level: min(12, max(7, result[0].level + 4)),
            text: "\(markerPrefix)：母本与随堂笔记均有更新，请人工确认后再同步",
            sourceID: "",
            sourceFile: "",
            cache: NodeMarkdownCacheCodec.encode(mtime: Date()),
            mtimeCache: Date()
        )
        result.insert(marker, at: 1)
        return result
    }

    private static func clearConflictMarkers(in packageNodes: [NodeMarkdownNode]) -> [NodeMarkdownNode] {
        let markerPrefix = "⚠️冲突待确认"
        return packageNodes.filter { !$0.text.hasPrefix(markerPrefix) }
    }

    private static func buildTemplateRows(lessonFolderID: String) throws -> [ChecklistTemplateRow] {
        let lessonFolderURL = try lessonFolderURL(for: lessonFolderID)
        let chapterURLs = try FileManager.default.contentsOfDirectory(
            at: lessonFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            guard url.pathExtension.lowercased() == "csv" else { return false }
            let metaType = (ArchiveStorage.readMetaType(fileURL: url) ?? "").lowercased()
            return metaType == "lessonplan" || metaType == "nodemarkdown" || metaType == "nodesmarkdown"
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var rows: [ChecklistTemplateRow] = []
        for chapterURL in chapterURLs {
            let payload = try NodeMarkdownFileManager.read(fileURL: chapterURL)
            for node in payload.0.nodes where (1...3).contains(node.level) {
                let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let level = node.level
                let sourceFile = level == 3 ? "\(lessonFolderID)/\(chapterURL.lastPathComponent)" : ""
                let sourceID = level == 3 ? node.id.uuidString : ""
                rows.append(
                    ChecklistTemplateRow(
                        id: node.id.uuidString,
                        task: trimmed,
                        level: level,
                        status: 0,
                        sourceFile: sourceFile,
                        sourceID: sourceID
                    )
                )
            }
        }
        return rows
    }

    private static func refreshNotebookBySources(
        document: inout NodeMarkdownDocument
    ) throws -> (replacedCount: Int, detachedCount: Int) {
        var replaced = 0
        var detached = 0
        var sourceCache: [String: (NodeMarkdownDocument, NodeMarkdownFileMeta)] = [:]
        var dirtySourcePaths: Set<String> = []
        let ranges = h3PackageRanges(in: document.nodes)

        for range in ranges.reversed() {
            guard document.nodes.indices.contains(range.start) else { continue }
            let rootNode = document.nodes[range.start]
            let sourceID = rootNode.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = rootNode.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceID.isEmpty, !sourceFile.isEmpty else { continue }
            guard let sourceURL = try sourceURLFromRelative(sourceFile),
                  FileManager.default.fileExists(atPath: sourceURL.path) else {
                document.nodes[range.start].sourceID = ""
                document.nodes[range.start].sourceFile = ""
                detached += 1
                continue
            }

            var sourceDocument: NodeMarkdownDocument
            let sourceMeta: NodeMarkdownFileMeta
            if let cached = sourceCache[sourceURL.path] {
                sourceDocument = cached.0
                sourceMeta = cached.1
            } else {
                let loaded = try NodeMarkdownFileManager.read(fileURL: sourceURL)
                sourceCache[sourceURL.path] = loaded
                sourceDocument = loaded.0
                sourceMeta = loaded.1
            }

            guard let sourceRange = h3PackageRange(in: sourceDocument.nodes, sourceID: sourceID) else {
                document.nodes[range.start].sourceID = ""
                document.nodes[range.start].sourceFile = ""
                detached += 1
                continue
            }

            var sourcePackage = Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
            guard let sourceRoot = sourcePackage.first else { continue }
            let notebookPackage = Array(document.nodes[range.start..<range.end])
            let notebookDigest = TeachingCoursePackageContentSignature.digest(notebookPackage)
            let sourceDigest = TeachingCoursePackageContentSignature.digest(sourcePackage)
            if notebookDigest == sourceDigest {
                continue
            }
            if sourceRoot.mtimeCache >= rootNode.mtimeCache {
                sourcePackage[0].sourceID = sourceID
                sourcePackage[0].sourceFile = sourceFile
                document.nodes.replaceSubrange(range.start..<range.end, with: sourcePackage)
                replaced += 1
            } else {
                var sourceReplacement = NodeMarkdownPackageCleaner.cleanPackage(notebookPackage)
                sourceReplacement[0].id = sourceRoot.id
                sourceReplacement[0].sourceID = sourceRoot.sourceID
                sourceReplacement[0].sourceFile = sourceRoot.sourceFile
                sourceDocument.nodes.replaceSubrange(sourceRange.start..<sourceRange.end, with: sourceReplacement)
                sourceCache[sourceURL.path] = (sourceDocument, sourceMeta)
                dirtySourcePaths.insert(sourceURL.path)
            }
        }

        for path in dirtySourcePaths {
            guard let payload = sourceCache[path] else { continue }
            try NodeMarkdownFileManager.write(
                document: payload.0,
                meta: payload.1,
                to: URL(fileURLWithPath: path)
            )
        }

        _ = document.ensureTrailingBlankLine(defaultLevel: 1)
        return (replaced, detached)
    }

    private static func createClassInfoForTodayIfNeeded(
        student: TeachingStudentItem,
        studentFolder: URL,
        effectiveSettings: TeachingStudentProfileSettings
    ) throws -> Bool {
        try createClassInfoIfNeeded(
            student: student,
            studentFolder: studentFolder,
            effectiveSettings: effectiveSettings,
            date: compactDate()
        )
    }

    private static func createClassInfoIfNeeded(
        student: TeachingStudentItem,
        studentFolder: URL,
        effectiveSettings: TeachingStudentProfileSettings,
        date: String
    ) throws -> Bool {
        let fileURL = studentFolder.appendingPathComponent("上课信息_\(student.name)_\(date).CSV", isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return false
        }

        var rows: [SingleListDocumentRow] = []
        var templateID = ""
        if let classTemplateID = effectiveSettings.classInfoTemplateID,
           let templateURL = try resolveSingleListTemplateURL(by: classTemplateID) {
            let templatePayload = try ArchiveStorage.readSingleListTemplate(fileURL: templateURL)
            rows = templatePayload.0.map { row in
                SingleListDocumentRow(id: row.id, keyName: row.keyName, content: row.content)
            }
            templateID = classTemplateID
        } else {
            rows = [
                SingleListDocumentRow(id: UUID().uuidString, keyName: "姓名", content: ""),
                SingleListDocumentRow(id: UUID().uuidString, keyName: "内容", content: ""),
                SingleListDocumentRow(id: UUID().uuidString, keyName: "时间", content: "")
            ]
        }

        for index in rows.indices {
            if let key = effectiveSettings.classInfoNameKeyID, rows[index].id == key {
                rows[index].content = student.name
            }
            if let key = effectiveSettings.classInfoTimeKeyID, rows[index].id == key {
                rows[index].content = date
            }
            if let key = effectiveSettings.classInfoContentKeyID,
               rows[index].id == key,
               rows[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows[index].content = "上课"
            }
        }

        let meta = SingleListDocumentMeta(
            id: UUID().uuidString,
            title: "上课信息_\(student.name)_\(date)",
            templateID: templateID,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            type: "singlelist"
        )
        try ArchiveStorage.writeSingleListDocument(fileURL: fileURL, rows: rows, meta: meta)
        return true
    }

    private static func appendInsertedH3TitlesToTodayClassInfoIfExists(
        student: TeachingStudentItem,
        titles rawTitles: [String]
    ) throws {
        let titles = rawTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !titles.isEmpty else { return }

        let studentFolder = try studentFolderURL(for: student)
        let date = compactDate()
        let fileURL = studentFolder.appendingPathComponent("上课信息_\(student.name)_\(date).CSV", isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let effectiveSettings = try resolveEffectiveSettings(student: student)
        var payload = try ArchiveStorage.readSingleListDocument(fileURL: fileURL)
        guard let contentIndex = classInfoContentRowIndex(in: payload.0, effectiveSettings: effectiveSettings) else {
            return
        }

        payload.0[contentIndex].content = appendedClassInfoContent(
            existing: payload.0[contentIndex].content,
            titles: titles
        )
        try ArchiveStorage.writeSingleListDocument(fileURL: fileURL, rows: payload.0, meta: payload.1)
    }

    private static func classInfoContentRowIndex(
        in rows: [SingleListDocumentRow],
        effectiveSettings: TeachingStudentProfileSettings
    ) -> Int? {
        if let contentKeyID = effectiveSettings.classInfoContentKeyID,
           let index = rows.firstIndex(where: { $0.id == contentKeyID }) {
            return index
        }

        if let exactIndex = rows.firstIndex(where: {
            let keyName = $0.keyName.trimmingCharacters(in: .whitespacesAndNewlines)
            return keyName == "上课内容" || keyName == "内容" || keyName.caseInsensitiveCompare("content") == .orderedSame
        }) {
            return exactIndex
        }

        return rows.firstIndex {
            $0.keyName.localizedStandardContains("内容")
        }
    }

    private static func appendedClassInfoContent(existing: String, titles: [String]) -> String {
        let heading = "详细内容："
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: String
        if trimmed.isEmpty || trimmed == "上课" {
            base = heading
        } else if existing.contains(heading) {
            base = existing.trimmingCharacters(in: .newlines)
        } else {
            base = existing.trimmingCharacters(in: .newlines) + "\n" + heading
        }

        let nextNumber = nextClassInfoDetailNumber(in: base)
        let additions = titles.enumerated().map { offset, title in
            "\(nextNumber + offset).\(title) ；"
        }.joined(separator: " ")
        if nextNumber == 1 {
            return base + "\n" + additions + "\n"
        }
        return appendClassInfoDetailsToExistingLine(base: base, additions: additions)
    }

    private static func appendClassInfoDetailsToExistingLine(base: String, additions: String) -> String {
        var lines = base.components(separatedBy: "\n")
        let detailLineIndex = lines.indices.reversed().first { index in
            nextClassInfoDetailNumber(in: lines[index]) > 1
        }
        guard let detailLineIndex else {
            return base + "\n" + additions
        }

        let currentLine = lines[detailLineIndex].trimmingCharacters(in: .whitespaces)
        let separator = currentLine.isEmpty ? "" : " "
        lines[detailLineIndex] = currentLine + separator + additions
        return lines.joined(separator: "\n") + "\n"
    }

    private static func nextClassInfoDetailNumber(in content: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)(\d+)\."#) else { return 1 }
        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        let maxNumber = matches.compactMap { match -> Int? in
            guard match.numberOfRanges > 1 else { return nil }
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            return Int(nsContent.substring(with: range))
        }.max() ?? 0
        return maxNumber + 1
    }

    private static func resolveEffectiveSettings(student: TeachingStudentItem) throws -> TeachingStudentProfileSettings {
        let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
        let override = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
        return TeachingStudentProfileSettings(
            studentInfoTemplateID: override?.studentInfoTemplateID ?? defaults.studentInfoTemplateID,
            studentNameKeyID: override?.studentNameKeyID ?? defaults.studentNameKeyID,
            classInfoTemplateID: override?.classInfoTemplateID ?? defaults.classInfoTemplateID,
            classInfoNameKeyID: override?.classInfoNameKeyID ?? defaults.classInfoNameKeyID,
            classInfoContentKeyID: override?.classInfoContentKeyID ?? defaults.classInfoContentKeyID,
            classInfoTimeKeyID: override?.classInfoTimeKeyID ?? defaults.classInfoTimeKeyID,
            lessonPlanFolderIDs: override?.lessonPlanFolderIDs.isEmpty == false ? (override?.lessonPlanFolderIDs ?? []) : defaults.lessonPlanFolderIDs,
            workbookFileID: override?.workbookFileID ?? defaults.workbookFileID,
            syncBaseFolderPath: override?.syncBaseFolderPath ?? defaults.syncBaseFolderPath
        )
    }

    private static func selectedLessonPlanFolders(effectiveSettings: TeachingStudentProfileSettings) throws -> [String] {
        if !effectiveSettings.lessonPlanFolderIDs.isEmpty {
            return effectiveSettings.lessonPlanFolderIDs
        }
        let rootPayload = try LessonPlanStorage.loadRootEntries()
        return rootPayload.1.filter(\.isDirectory).map(\.name)
    }

    private static func writeChecklistRows(
        _ rows: [ChecklistTemplateRow],
        meta: ChecklistDocumentMeta,
        to fileURL: URL,
        metaType: String
    ) throws {
        func encodeCSV(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return value
        }
        let header = ["UUID", "Task", "Level", "Status", "SourceFile", "SourceID"]
        let records = rows.map { row in
            [row.id, row.task, String(row.level), row.status == 0 ? "0" : "1", row.sourceFile, row.sourceID]
        }
        var lines: [String] = [header.joined(separator: ",")]
        lines.append(contentsOf: records.map { $0.map(encodeCSV).joined(separator: ",") })
        lines.append("")
        lines.append("[META_ID],\(encodeCSV(meta.id))")
        lines.append("[META_TITLE],\(encodeCSV(meta.title))")
        lines.append("[META_TEMPLATE],\(encodeCSV(meta.templateID))")
        lines.append("[META_CREATED],\(encodeCSV(meta.createdAt))")
        lines.append("[META_TYPE],\(encodeCSV(metaType))")
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func lessonPlanRootURL() throws -> URL {
        try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.teachingPlanFolderName, isDirectory: true)
    }

    private static func lessonPlanTemplateRootURL() throws -> URL {
        let folder = try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent(ArchiveStorage.templateFolderName, isDirectory: true)
            .appendingPathComponent("教案模板", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func lessonFolderURL(for folderID: String) throws -> URL {
        try lessonPlanRootURL().appendingPathComponent(folderID, isDirectory: true)
    }

    private static func studentFolderURL(for student: TeachingStudentItem) throws -> URL {
        try ArchiveStorage.ensureArchiveRoot()
            .appendingPathComponent("学生", isDirectory: true)
            .appendingPathComponent(student.name, isDirectory: true)
    }

    private static func notebookURL(for student: TeachingStudentItem) throws -> URL {
        try studentFolderURL(for: student).appendingPathComponent("随堂笔记_\(student.name).CSV", isDirectory: false)
    }

    private static func sourceURLFromRelative(_ relative: String) throws -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("档案/") {
            let suffix = String(trimmed.dropFirst("档案/".count))
            guard !suffix.isEmpty else { return nil }
            return try ArchiveStorage.ensureArchiveRoot().appendingPathComponent(suffix, isDirectory: false)
        }
        return try lessonPlanRootURL().appendingPathComponent(trimmed, isDirectory: false)
    }

    private static func resolveSingleListTemplateURL(by templateID: String) throws -> URL? {
        let entries = try ArchiveStorage.loadTemplateEntries(category: .singleList)
        for entry in entries {
            let payload = try ArchiveStorage.readSingleListTemplate(fileURL: entry.url)
            if payload.1.id == templateID {
                return entry.url
            }
        }
        return nil
    }

    private static func compactDate() -> String {
        classInfoDateToken(for: Date())
    }

    /// 上课、首页与排课必须用同一套课反文件名：两位年份 + 月 + 日。
    private static func classInfoDateToken(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
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

    private static func h3PackageRange(in nodes: [NodeMarkdownNode], sourceID: String) -> (start: Int, end: Int)? {
        guard !sourceID.isEmpty else { return nil }
        guard let startIndex = nodes.firstIndex(where: {
            $0.level == 3 && $0.id.uuidString.caseInsensitiveCompare(sourceID) == .orderedSame
        }) else {
            return nil
        }
        var end = startIndex + 1
        while end < nodes.count {
            let level = nodes[end].level
            if level == 1 || level == 2 || level == 3 {
                break
            }
            end += 1
        }
        return (start: startIndex, end: end)
    }

    private static func insertionIndexForCourseInsert(
        document: NodeMarkdownDocument,
        activeRowIndex: Int?
    ) -> Int {
        guard let activeRowIndex, document.nodes.indices.contains(activeRowIndex) else {
            return document.nodes.count
        }

        if let ownerH3Index = document.owningH3Index(for: activeRowIndex) {
            let end = nodePackageEndIndex(in: document.nodes, startIndex: ownerH3Index)
            return max(0, min(end, document.nodes.count))
        }

        let activeLevel = document.nodes[activeRowIndex].level
        if activeLevel == 1 || activeLevel == 2 {
            return min(activeRowIndex + 1, document.nodes.count)
        }

        // 合法随堂结构中的H4及以下必然属于H3包。若旧数据结构残缺，
        // 仍然紧跟焦点Node，不能悄悄退回章末或文末。
        return min(activeRowIndex + 1, document.nodes.count)
    }

    /// 无焦点时，插包必须落在最后一个有效Node之后。尾部普通空行全部清掉，
    /// 但H3本身即使标题为空也可能是受保护包或尚未命名的新包，不能在这里删除。
    private static func removeTrailingBlankNodesBeforeCourseInsert(
        from document: inout NodeMarkdownDocument
    ) {
        while let last = document.nodes.last,
              last.level != 3,
              last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.nodes.removeLast()
        }
    }

    private static func nodePackageEndIndex(in nodes: [NodeMarkdownNode], startIndex: Int) -> Int {
        guard nodes.indices.contains(startIndex) else { return nodes.count }
        let rootLevel = max(1, min(12, nodes[startIndex].level))
        var end = startIndex + 1
        while end < nodes.count {
            let level = nodes[end].level
            if level > 0 && level <= rootLevel {
                break
            }
            end += 1
        }
        return end
    }

    private static func appendToCollector(packageNodes: [NodeMarkdownNode]) throws -> (sourceFile: String, sourceID: String) {
        let collectorFolder = try lessonPlanRootURL().appendingPathComponent("上课收集", isDirectory: true)
        try FileManager.default.createDirectory(at: collectorFolder, withIntermediateDirectories: true)
        let collectorURL = collectorFolder.appendingPathComponent("上课收集.CSV", isDirectory: false)
        let payload: (NodeMarkdownDocument, NodeMarkdownFileMeta)
        if FileManager.default.fileExists(atPath: collectorURL.path) {
            payload = try NodeMarkdownFileManager.read(fileURL: collectorURL)
        } else {
            let now = Date()
            payload = (
                NodeMarkdownDocument(nodes: [
                    NodeMarkdownNode(level: 1, text: "", cache: NodeMarkdownCacheCodec.encode(mtime: now), mtimeCache: now)
                ]),
                NodeMarkdownFileMeta(
                    id: UUID().uuidString,
                    title: "上课收集",
                    template: "nil",
                    createdAt: ISO8601DateFormatter().string(from: now),
                    type: "lessonplan"
                )
            )
        }

        var document = payload.0
        let package = normalizedNewPackageForInsertion(packageNodes)
        let sourceID = package[0].id.uuidString

        if let existingRange = TeachingCoursePackageContentSignature.packageRange(
            in: document.nodes,
            rootID: package[0].id
        ) {
            document.nodes.replaceSubrange(existingRange.start..<existingRange.end, with: package)
        } else {
            let insertIndex: Int
            if let last = document.nodes.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                insertIndex = max(0, document.nodes.count - 1)
            } else {
                insertIndex = document.nodes.count
            }
            document.nodes.insert(contentsOf: package, at: insertIndex)
        }
        _ = document.ensureTrailingBlankLine(defaultLevel: 1)
        if document != payload.0 {
            try NodeMarkdownFileManager.write(document: document, meta: payload.1, to: collectorURL)
        }
        return ("上课收集/上课收集.CSV", sourceID)
    }

    private static func appendPackageToTargetOrCollector(
        packageNodes: [NodeMarkdownNode],
        placementTarget: TeachingCourseUpdatePlacementTarget?
    ) throws -> (sourceFile: String, sourceID: String) {
        let package = normalizedNewPackageForInsertion(packageNodes)
        if let existingSourceFile = try existingSourceFile(
            containingPackageID: package[0].id
        ) {
            return try appendToLessonFile(
                packageNodes: package,
                sourceFile: existingSourceFile,
                anchorSourceID: nil
            )
        }
        guard let placementTarget else {
            return try appendToCollector(packageNodes: package)
        }
        do {
            return try appendToLessonFile(
                packageNodes: package,
                sourceFile: placementTarget.sourceFile,
                anchorSourceID: placementTarget.anchorSourceID
            )
        } catch {
            return try appendToCollector(packageNodes: package)
        }
    }

    // 上次若只写成了母本而未能回写随堂，重试先凭出生UUID找回原入库位置。
    private static func existingSourceFile(containingPackageID packageID: UUID) throws -> String? {
        let rootURL = try lessonPlanRootURL().standardizedFileURL
        let csvFiles = try collectRegularFilesRecursively(root: rootURL)
            .filter { $0.pathExtension.caseInsensitiveCompare("csv") == .orderedSame }
            .sorted { $0.path < $1.path }
        var matches: [String] = []

        for fileURL in csvFiles {
            guard let document = try? NodeMarkdownFileManager.read(fileURL: fileURL).0,
                  TeachingCoursePackageContentSignature.packageRange(
                      in: document.nodes,
                      rootID: packageID
                  ) != nil else {
                continue
            }
            let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            guard fileURL.standardizedFileURL.path.hasPrefix(prefix) else { continue }
            matches.append(String(fileURL.standardizedFileURL.path.dropFirst(prefix.count)))
        }
        guard matches.count <= 1 else {
            throw NSError(
                domain: "TeachingCourseWorkflowService",
                code: 7802,
                userInfo: [NSLocalizedDescriptionKey: "中心教案中发现多个相同UUID的新包，已停止自动入库：\(packageID.uuidString)"]
            )
        }
        return matches.first
    }

    private static func appendToLessonFile(
        packageNodes: [NodeMarkdownNode],
        sourceFile: String,
        anchorSourceID: String?
    ) throws -> (sourceFile: String, sourceID: String) {
        guard let chapterURL = try sourceURLFromRelative(sourceFile) else {
            return try appendToCollector(packageNodes: packageNodes)
        }
        let payload = try NodeMarkdownFileManager.read(fileURL: chapterURL)
        var document = payload.0
        let package = normalizedNewPackageForInsertion(packageNodes)
        let sourceID = package[0].id.uuidString

        if let existingRange = TeachingCoursePackageContentSignature.packageRange(
            in: document.nodes,
            rootID: package[0].id
        ) {
            document.nodes.replaceSubrange(existingRange.start..<existingRange.end, with: package)
            _ = document.ensureTrailingBlankLine(defaultLevel: 1)
            if document != payload.0 {
                try NodeMarkdownFileManager.write(document: document, meta: payload.1, to: chapterURL)
            }
            return (sourceFile, sourceID)
        }

        let insertIndex: Int
        if let anchorSourceID,
           let anchorIndex = document.nodes.firstIndex(where: { $0.id.uuidString == anchorSourceID }) {
            let anchorLevel = document.nodes[anchorIndex].level
            if anchorLevel == 3,
               let anchorRange = h3PackageRange(in: document.nodes, sourceID: anchorSourceID) {
                insertIndex = anchorRange.end
            } else {
                insertIndex = anchorIndex + 1
            }
        } else if let lastMeaningfulIndex = document.nodes.lastIndex(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            insertIndex = lastMeaningfulIndex + 1
        } else {
            insertIndex = 0
        }

        document.nodes.insert(contentsOf: package, at: max(0, min(insertIndex, document.nodes.count)))
        _ = document.ensureTrailingBlankLine(defaultLevel: 1)
        try NodeMarkdownFileManager.write(document: document, meta: payload.1, to: chapterURL)
        return (sourceFile, sourceID)
    }

    // 新包的H3 UUID从创建起就是母本UUID；入库只补来源信息，永不换身份证。
    private static func normalizedNewPackageForInsertion(
        _ packageNodes: [NodeMarkdownNode]
    ) -> [NodeMarkdownNode] {
        var package = NodeMarkdownPackageCleaner.cleanPackage(packageNodes)
        if package.isEmpty {
            let now = Date()
            package = [
                NodeMarkdownNode(
                    level: 3,
                    text: "",
                    cache: NodeMarkdownCacheCodec.encode(mtime: now),
                    mtimeCache: now
                )
            ]
        }
        package[0].level = 3
        package[0].sourceID = ""
        package[0].sourceFile = ""
        return package
    }

    private static func buildUpdateChapterTargets(student: TeachingStudentItem) throws -> [TeachingCourseUpdateChapterTarget] {
        let effective = try resolveEffectiveSettings(student: student)
        let folderIDs = try selectedLessonPlanFolders(effectiveSettings: effective)
        var targets: [TeachingCourseUpdateChapterTarget] = []
        for folderID in folderIDs {
            let folderURL = try lessonFolderURL(for: folderID)
            let chapterURLs = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            for chapterURL in chapterURLs {
                let payload = try NodeMarkdownFileManager.read(fileURL: chapterURL)
                let anchors = payload.0.nodes.compactMap { node -> TeachingCourseUpdateAnchorTarget? in
                    guard node.level == 1 || node.level == 2 || node.level == 3 else { return nil }
                    let title = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = "H\(node.level)-\(node.id.uuidString.prefix(8))"
                    let prefix = String(repeating: "　", count: max(0, node.level - 1))
                    let display = "\(prefix)H\(node.level) \(title.isEmpty ? fallback : title)"
                    return TeachingCourseUpdateAnchorTarget(sourceID: node.id.uuidString, displayName: display)
                }
                let relative = "\(folderID)/\(chapterURL.lastPathComponent)"
                targets.append(
                    TeachingCourseUpdateChapterTarget(
                        relativePath: relative,
                        displayName: relative,
                        anchors: anchors
                    )
                )
            }
        }
        return targets
    }

    private static func exportNotebookExportsIfPossible(
        student: TeachingStudentItem,
        notebookURL: URL,
        document: NodeMarkdownDocument
    ) async throws -> String? {
        let effective = try resolveEffectiveSettings(student: student)
        guard let syncBase = effective.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines), !syncBase.isEmpty else {
            return nil
        }

        let style = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        let baseName = "随堂笔记_\(student.name)"
        let exportData = try await MainActor.run {
            let pdfData = try NodeMarkdownPDFExporter.renderData(
                sourceFileURL: notebookURL,
                document: document,
                style: style
            )
            let h1PDFData = try NodeMarkdownPDFExporter.renderData(
                sourceFileURL: notebookURL,
                document: document,
                style: style,
                paginationMode: .h1StartsNewPage
            )
            let splitPDFs = try NodeMarkdownH1FileSectionBuilder.build(
                document: document,
                sourceBaseName: baseName
            ).map { section in
                TeachingNotebookSplitPDF(
                    fileName: section.fileBaseName + ".PDF",
                    data: try NodeMarkdownPDFExporter.renderData(
                        sourceFileURL: notebookURL,
                        document: section.document,
                        style: style,
                        paginationMode: .natural
                    )
                )
            }
            let htmlData = NodeMarkdownHTMLExporter.renderData(
                sourceFileURL: notebookURL,
                embeddedPDFData: pdfData
            )
            return TeachingNotebookExportPayload(
                pdf: pdfData,
                h1PDF: h1PDFData,
                splitPDFs: splitPDFs,
                html: htmlData
            )
        }

        let transactionID = UUID().uuidString
        let exportedPaths = try TeachingSecurityScopedAccess.withWritableAccess(
            toPath: syncBase,
            allowInteractiveRecovery: true
        ) { writableBaseURL in
            let pdfFolderURL: URL
            if writableBaseURL.lastPathComponent == "1-教案PDF" {
                pdfFolderURL = writableBaseURL
            } else {
                pdfFolderURL = writableBaseURL.appendingPathComponent("1-教案PDF", isDirectory: true)
            }
            let pdfTargetURL = pdfFolderURL.appendingPathComponent("\(baseName).PDF", isDirectory: false)
            try TeachingCoursePDFExporter.writeNotebookPDFData(
                sourceFileURL: notebookURL,
                destinationURL: pdfTargetURL,
                pdfData: exportData.pdf
            )
            let h1PDFTargetURL = pdfFolderURL.appendingPathComponent("\(baseName)_分H1.PDF", isDirectory: false)
            try TeachingCoursePDFExporter.writeNotebookPDFData(
                sourceFileURL: notebookURL,
                destinationURL: h1PDFTargetURL,
                pdfData: exportData.h1PDF
            )
            let splitPDFDirectoryURL = pdfFolderURL.appendingPathComponent("\(baseName)_分文件", isDirectory: true)
            try replaceSplitPDFDirectory(
                at: splitPDFDirectoryURL,
                files: exportData.splitPDFs
            )
            let htmlTargetURL = pdfFolderURL.appendingPathComponent("\(baseName).HTML", isDirectory: false)
            try FileManager.default.createDirectory(at: htmlTargetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try exportData.html.write(to: htmlTargetURL, options: .atomic)
            return (
                pdf: pdfTargetURL.path,
                h1PDF: h1PDFTargetURL.path,
                splitPDFDirectory: splitPDFDirectoryURL.path,
                html: htmlTargetURL.path
            )
        }

        try? appendTransactionLog(
            transactionID: transactionID,
            operation: "finishClassExportPDFAndHTML",
            student: student,
            phase: "exported-manual-channel",
            detail: "PDF=\(exportedPaths.pdf); 分H1 PDF=\(exportedPaths.h1PDF); 分文件PDF=\(exportedPaths.splitPDFDirectory); HTML=\(exportedPaths.html)"
        )
        return exportedPaths.pdf
    }

    /// 先在同级临时目录生成完整文件集，再整体换入正式目录；旧H1文件不会残留，失败也不会留下半套结果。
    private static func replaceSplitPDFDirectory(
        at destinationURL: URL,
        files: [TeachingNotebookSplitPDF]
    ) throws {
        guard !files.isEmpty else {
            throw NSError(
                domain: "TeachingCourseWorkflowService",
                code: -41,
                userInfo: [NSLocalizedDescriptionKey: "PDF分文件导出为空。"]
            )
        }

        let fileManager = FileManager.default
        let parentURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let stagingURL = parentURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )
        let backupURL = parentURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).backup",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        for file in files {
            let safeName = URL(fileURLWithPath: file.fileName).lastPathComponent
            guard !safeName.isEmpty, safeName == file.fileName, !file.data.isEmpty else {
                throw NSError(
                    domain: "TeachingCourseWorkflowService",
                    code: -42,
                    userInfo: [NSLocalizedDescriptionKey: "PDF分文件内容或文件名无效：\(file.fileName)"]
                )
            }
            try file.data.write(
                to: stagingURL.appendingPathComponent(safeName, isDirectory: false),
                options: .atomic
            )
        }

        let hadPreviousDirectory = fileManager.fileExists(atPath: destinationURL.path)
        if hadPreviousDirectory {
            try fileManager.moveItem(at: destinationURL, to: backupURL)
        }
        do {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            if hadPreviousDirectory {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if hadPreviousDirectory,
               !fileManager.fileExists(atPath: destinationURL.path),
               fileManager.fileExists(atPath: backupURL.path) {
                do {
                    try fileManager.moveItem(at: backupURL, to: destinationURL)
                } catch let restoreError {
                    throw NSError(
                        domain: "TeachingCourseWorkflowService",
                        code: -43,
                        userInfo: [
                            NSLocalizedDescriptionKey: "PDF分文件换入失败，旧目录保留在\(backupURL.lastPathComponent)：\(restoreError.localizedDescription)",
                            NSUnderlyingErrorKey: error
                        ]
                    )
                }
            }
            throw error
        }
    }

    private static func runStudentFolderTransaction<T>(
        student: TeachingStudentItem,
        operation: String,
        work: () async throws -> T
    ) async throws -> T {
        let studentFolder = try studentFolderURL(for: student)
        let writeKey = studentFolder.standardizedFileURL.path
        await TeachingCourseWriteCoordinator.shared.acquire(key: writeKey)
        let transactionID = UUID().uuidString

        do {
            try appendTransactionLog(
                transactionID: transactionID,
                operation: operation,
                student: student,
                phase: "started",
                detail: "serializedWriteQueue=acquired"
            )
            let value = try await work()
            try appendTransactionLog(
                transactionID: transactionID,
                operation: operation,
                student: student,
                phase: "succeeded",
                detail: "committed"
            )
            await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
            return value
        } catch {
            try? appendTransactionLog(
                transactionID: transactionID,
                operation: operation,
                student: student,
                phase: "failed",
                detail: "rollback=suspended, reason=\(error.localizedDescription)"
            )
            await TeachingCourseWriteCoordinator.shared.release(key: writeKey)
            throw error
        }
    }

    private static func sourceWriteKeys(
        document: NodeMarkdownDocument,
        placementTarget: TeachingCourseUpdatePlacementTarget?
    ) throws -> [String] {
        var keys: Set<String> = []
        for node in document.nodes where node.level == 3 {
            let sourceFile = node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSourceFile: String
            if !sourceFile.isEmpty {
                effectiveSourceFile = sourceFile
            } else if let recovered = try existingSourceFile(containingPackageID: node.id) {
                effectiveSourceFile = recovered
            } else {
                continue
            }
            guard let sourceURL = try sourceURLFromRelative(effectiveSourceFile) else { continue }
            keys.insert(sourceURL.standardizedFileURL.path)
            keys.insert(sourceURL.deletingLastPathComponent().standardizedFileURL.path)
        }
        if let target = placementTarget,
           let targetURL = try sourceURLFromRelative(target.sourceFile) {
            keys.insert(targetURL.standardizedFileURL.path)
            keys.insert(targetURL.deletingLastPathComponent().standardizedFileURL.path)
        }
        let collectorURL = try lessonPlanRootURL()
            .appendingPathComponent("上课收集", isDirectory: true)
            .appendingPathComponent("上课收集.CSV", isDirectory: false)
        keys.insert(collectorURL.standardizedFileURL.path)
        keys.insert(collectorURL.deletingLastPathComponent().standardizedFileURL.path)
        return keys.sorted()
    }

    private static func acquireWriteKeys(_ keys: [String]) async {
        for key in keys.sorted() {
            await TeachingCourseWriteCoordinator.shared.acquire(key: key)
        }
    }

    private static func releaseWriteKeys(_ keys: [String]) async {
        for key in keys.sorted().reversed() {
            await TeachingCourseWriteCoordinator.shared.release(key: key)
        }
    }

    private static func captureStudentFolderSnapshot(studentFolderURL: URL) throws -> TeachingCourseFolderSnapshot {
        let fileManager = FileManager.default
        let folderExists = fileManager.fileExists(atPath: studentFolderURL.path)
        guard folderExists else {
            return TeachingCourseFolderSnapshot(folderExisted: false, fileDataByRelativePath: [:], directoryRelativePaths: [])
        }

        let allURLs = try fileManager.contentsOfDirectory(
            at: studentFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var fileDataByRelativePath: [String: Data] = [:]
        var directoryRelativePaths: [String] = [""]

        var queue = allURLs
        while !queue.isEmpty {
            let url = queue.removeFirst()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let relativePath = url.path.replacingOccurrences(of: studentFolderURL.path + "/", with: "")
            if values.isDirectory == true {
                directoryRelativePaths.append(relativePath)
                let children = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                queue.append(contentsOf: children)
                continue
            }
            if values.isRegularFile == true {
                let data = try Data(contentsOf: url)
                fileDataByRelativePath[relativePath] = data
            }
        }

        return TeachingCourseFolderSnapshot(
            folderExisted: true,
            fileDataByRelativePath: fileDataByRelativePath,
            directoryRelativePaths: directoryRelativePaths.sorted()
        )
    }

    private static func restoreStudentFolderSnapshot(
        _ snapshot: TeachingCourseFolderSnapshot,
        studentFolderURL: URL
    ) throws {
        let fileManager = FileManager.default
        let folderExistsNow = fileManager.fileExists(atPath: studentFolderURL.path)

        if !snapshot.folderExisted {
            if folderExistsNow {
                try fileManager.removeItem(at: studentFolderURL)
            }
            return
        }

        if !folderExistsNow {
            try fileManager.createDirectory(at: studentFolderURL, withIntermediateDirectories: true)
        }

        let currentFiles = try collectRegularFilesRecursively(root: studentFolderURL)
        for fileURL in currentFiles {
            let relativePath = fileURL.path.replacingOccurrences(of: studentFolderURL.path + "/", with: "")
            if snapshot.fileDataByRelativePath[relativePath] == nil {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        for relativePath in snapshot.directoryRelativePaths {
            let directoryURL: URL = {
                if relativePath.isEmpty { return studentFolderURL }
                return studentFolderURL.appendingPathComponent(relativePath, isDirectory: true)
            }()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        for (relativePath, data) in snapshot.fileDataByRelativePath {
            let targetURL = studentFolderURL.appendingPathComponent(relativePath, isDirectory: false)
            let parent = targetURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
        }
    }

    private static func collectRegularFilesRecursively(root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        var files: [URL] = []
        var queue: [URL] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let values = try current.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                let children = try fileManager.contentsOfDirectory(
                    at: current,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                queue.append(contentsOf: children)
            } else if values.isRegularFile == true {
                files.append(current)
            }
        }
        return files
    }

    private static func buildIssueMap(
        students: [TeachingStudentItem],
        reportsByStudent: [String: TeachingCourseConsistencySummary]?
    ) throws -> [UUID: [TeachingCourseConsistencyIssue]] {
        var issueMap: [UUID: [TeachingCourseConsistencyIssue]] = [:]
        for student in students {
            let issues: [TeachingCourseConsistencyIssue]
            if let report = reportsByStudent?[student.name] {
                issues = report.issueItems
            } else {
                issues = try checkStudentConsistency(student: student).issueItems
            }
            issueMap[student.id] = issues
        }
        return issueMap
    }

    private static func buildConsistencyReports(
        students: [TeachingStudentItem]
    ) throws -> [String: TeachingCourseConsistencySummary] {
        var reports: [String: TeachingCourseConsistencySummary] = [:]
        for student in students {
            reports[student.name] = try checkStudentConsistency(student: student)
        }
        return reports
    }

    private static func collectExternalRepairPaths(
        studentByID: [UUID: TeachingStudentItem],
        issueMapByStudentID: [UUID: [TeachingCourseConsistencyIssue]]
    ) throws -> Set<String> {
        var paths: Set<String> = []
        for (studentID, issues) in issueMapByStudentID {
            guard let student = studentByID[studentID] else { continue }
            for issue in issues {
                switch issue.code {
                case .missingLessonFolder:
                    if let folderID = issue.context?.trimmingCharacters(in: .whitespacesAndNewlines), !folderID.isEmpty {
                        let folderURL = try lessonFolderURL(for: folderID)
                        paths.insert(folderURL.path)
                    }
                case .missingSyncPDFFolder:
                    if let path = issue.context?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                        paths.insert(path)
                    } else {
                        let effective = try resolveEffectiveSettings(student: student)
                        if let syncBasePath = effective.syncBaseFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines), !syncBasePath.isEmpty {
                            let baseURL = URL(fileURLWithPath: syncBasePath, isDirectory: true)
                            let pdfFolderURL: URL = {
                                if baseURL.lastPathComponent == "1-教案PDF" {
                                    return baseURL
                                }
                                return baseURL.appendingPathComponent("1-教案PDF", isDirectory: true)
                            }()
                            paths.insert(pdfFolderURL.path)
                        }
                    }
                default:
                    break
                }
            }
        }
        return paths
    }

    private static func applyConsistencyFixes(
        student: TeachingStudentItem,
        issues: [TeachingCourseConsistencyIssue],
        strategy: TeachingCourseRepairStrategy
    ) throws -> (fixed: Int, skipped: Int) {
        guard !issues.isEmpty else { return (0, 0) }
        let fileManager = FileManager.default
        var fixed = 0
        var skipped = 0
        var shouldProvision = false

        for issue in issues {
            switch issue.code {
            case .missingStudentFolder, .missingNotebook, .missingStudentInfo:
                shouldProvision = true
                fixed += 1
            case .corruptedNotebook:
                switch strategy {
                case .conservative:
                    skipped += 1
                case .standard, .aggressive:
                    let notebookFile = try notebookURL(for: student)
                    if fileManager.fileExists(atPath: notebookFile.path) {
                        try? fileManager.removeItem(at: notebookFile)
                    }
                    shouldProvision = true
                    fixed += 1
                }
            case .corruptedStudentInfo:
                switch strategy {
                case .conservative:
                    skipped += 1
                case .standard, .aggressive:
                    let studentInfo = try studentInfoFileURL(student: student)
                    if fileManager.fileExists(atPath: studentInfo.path) {
                        try? fileManager.removeItem(at: studentInfo)
                    }
                    shouldProvision = true
                    fixed += 1
                }
            case .missingLessonFolder:
                if let folderID = issue.context?.trimmingCharacters(in: .whitespacesAndNewlines), !folderID.isEmpty {
                    let folderURL = try lessonFolderURL(for: folderID)
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    fixed += 1
                } else {
                    skipped += 1
                }
            case .missingSyncPDFFolder:
                if let path = issue.context?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                    let target = URL(fileURLWithPath: path, isDirectory: true)
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    fixed += 1
                } else {
                    skipped += 1
                }
            case .missingSyncBasePath, .notebookFileNameMismatch, .notebookDuplicateSourceID:
                skipped += 1
            case .notebookMetaTypeMismatch:
                let notebookFile = try notebookURL(for: student)
                if fileManager.fileExists(atPath: notebookFile.path),
                   var payload = try? NodeMarkdownFileManager.read(fileURL: notebookFile) {
                    payload.1.type = "nodemarkdown"
                    try NodeMarkdownFileManager.write(document: payload.0, meta: payload.1, to: notebookFile)
                    fixed += 1
                } else {
                    skipped += 1
                }
            case .notebookBrokenSourceFile, .notebookBrokenSourceID:
                switch strategy {
                case .conservative, .standard:
                    skipped += 1
                case .aggressive:
                    let notebookFile = try notebookURL(for: student)
                    if fileManager.fileExists(atPath: notebookFile.path),
                       var payload = try? NodeMarkdownFileManager.read(fileURL: notebookFile) {
                        let target = issue.context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        var changed = false
                        for index in payload.0.nodes.indices where payload.0.nodes[index].level == 3 {
                            if issue.code == .notebookBrokenSourceFile,
                               payload.0.nodes[index].sourceFile == target {
                                payload.0.nodes[index].sourceFile = ""
                                payload.0.nodes[index].sourceID = ""
                                changed = true
                            }
                            if issue.code == .notebookBrokenSourceID,
                               payload.0.nodes[index].sourceID == target {
                                payload.0.nodes[index].sourceFile = ""
                                payload.0.nodes[index].sourceID = ""
                                changed = true
                            }
                        }
                        if changed {
                            try NodeMarkdownFileManager.write(document: payload.0, meta: payload.1, to: notebookFile)
                            fixed += 1
                        } else {
                            skipped += 1
                        }
                    } else {
                        skipped += 1
                    }
                }
            }
        }

        if strategy == .aggressive, !issues.isEmpty {
            shouldProvision = true
        }
        if shouldProvision {
            let defaults = try TeachingStudentSettingsStore.loadStudentSystemSettings()
            let profileOverride = try TeachingStudentSettingsStore.loadStudentProfile(studentID: student.id)
            try TeachingStudentProvisioningService.provisionArchiveSkeleton(
                for: student,
                defaultSettings: defaults,
                profileOverride: profileOverride
            )
        }
        return (fixed, skipped)
    }

    private static func appendTransactionLog(
        transactionID: String,
        operation: String,
        student: TeachingStudentItem,
        phase: String,
        detail: String
    ) throws {
        let systemFolder = try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: systemFolder, withIntermediateDirectories: true)
        let logURL = systemFolder.appendingPathComponent("course-transactions.log", isDirectory: false)
        let entry = TeachingCourseTransactionLogEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            transactionID: transactionID,
            operation: operation,
            studentID: student.id.uuidString,
            studentName: student.name,
            phase: phase,
            detail: detail
        )
        let lineData = try JSONEncoder().encode(entry)
        let line = String(data: lineData, encoding: .utf8) ?? "{}"
        let payload = "\(line)\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = payload.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try payload.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private static func appendRepairAuditBatch(
        batchID: String,
        strategy: TeachingCourseRepairStrategy,
        studentByID: [UUID: TeachingStudentItem],
        studentIssueMapByID: [UUID: [TeachingCourseConsistencyIssue]],
        studentSnapshots: [String: TeachingCourseFolderSnapshot],
        externalSnapshots: [String: TeachingCourseFolderSnapshot],
        summary: TeachingCourseConsistencyFixSummary
    ) throws {
        let auditDirectory = try repairAuditDirectoryURL()
        try FileManager.default.createDirectory(at: auditDirectory, withIntermediateDirectories: true)

        var studentNameByID: [String: String] = [:]
        var issueMessagesByStudentID: [String: [String]] = [:]
        for (studentID, issues) in studentIssueMapByID {
            guard let student = studentByID[studentID] else { continue }
            studentNameByID[studentID.uuidString] = student.name
            issueMessagesByStudentID[studentID.uuidString] = issues.map(\.message)
        }

        let batch = TeachingCourseRepairAuditBatch(
            batchID: batchID,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            strategy: strategy.rawValue,
            summary: summary,
            studentNameByID: studentNameByID,
            issueMessagesByStudentID: issueMessagesByStudentID,
            studentSnapshotsByID: studentSnapshots,
            externalSnapshotsByPath: externalSnapshots
        )
        let batchData = try JSONEncoder().encode(batch)
        let batchURL = try repairAuditBatchURL(batchID: batchID)
        try batchData.write(to: batchURL, options: .atomic)

        let pointer = TeachingCourseRepairAuditPointer(latestBatchID: batchID)
        let pointerData = try JSONEncoder().encode(pointer)
        let latestURL = try latestRepairAuditPointerURL()
        try pointerData.write(to: latestURL, options: .atomic)
    }

    private static func repairAuditDirectoryURL() throws -> URL {
        try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("course-repair-audit", isDirectory: true)
    }

    private static func repairAuditBatchURL(batchID: String) throws -> URL {
        try repairAuditDirectoryURL().appendingPathComponent("\(batchID).json", isDirectory: false)
    }

    private static func latestRepairAuditPointerURL() throws -> URL {
        try repairAuditDirectoryURL().appendingPathComponent("latest.json", isDirectory: false)
    }

    private static func listRepairAuditBatchIDsSortedDescending() throws -> [String] {
        let directoryURL = try repairAuditDirectoryURL()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension.lowercased() == "json" && $0.lastPathComponent != "latest.json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0 > $1 }
    }

    private struct TeachingCourseRepairAuditPointer: Codable {
        var latestBatchID: String
    }

    private struct TeachingCourseRepairAuditBatch: Codable {
        var batchID: String
        var timestamp: String
        var strategy: String
        var summary: TeachingCourseConsistencyFixSummary
        var studentNameByID: [String: String]
        var issueMessagesByStudentID: [String: [String]]
        var studentSnapshotsByID: [String: TeachingCourseFolderSnapshot]
        var externalSnapshotsByPath: [String: TeachingCourseFolderSnapshot]
    }

    private struct TeachingCourseInsertUndoSnapshot: Codable {
        var notebookData: Data
        var createdAt: Date
    }

    private struct TeachingCourseInsertUndoStack: Codable {
        var snapshots: [TeachingCourseInsertUndoSnapshot]
    }

    private static func persistInsertUndoSnapshot(student: TeachingStudentItem, notebookURL: URL) throws {
        guard FileManager.default.fileExists(atPath: notebookURL.path) else { return }
        let snapshot = TeachingCourseInsertUndoSnapshot(
            notebookData: try Data(contentsOf: notebookURL),
            createdAt: Date()
        )
        let snapshotURL = try insertUndoSnapshotURL(for: student)
        let parent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var stack: TeachingCourseInsertUndoStack
        if FileManager.default.fileExists(atPath: snapshotURL.path),
           let data = try? Data(contentsOf: snapshotURL),
           let decoded = try? JSONDecoder().decode(TeachingCourseInsertUndoStack.self, from: data) {
            stack = decoded
        } else {
            stack = TeachingCourseInsertUndoStack(snapshots: [])
        }
        stack.snapshots.append(snapshot)
        let maxUndoDepth = 12
        if stack.snapshots.count > maxUndoDepth {
            stack.snapshots = Array(stack.snapshots.suffix(maxUndoDepth))
        }
        let data = try JSONEncoder().encode(stack)
        try data.write(to: snapshotURL, options: .atomic)
    }

    private static func insertUndoSnapshotURL(for student: TeachingStudentItem) throws -> URL {
        let folder = try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
            .appendingPathComponent("course-insert-undo", isDirectory: true)
        return folder.appendingPathComponent("\(student.id.uuidString).json", isDirectory: false)
    }
}
