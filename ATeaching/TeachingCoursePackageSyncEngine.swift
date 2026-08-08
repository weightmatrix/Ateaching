import Foundation

struct TeachingCoursePackageSyncConflictRecord: Hashable {
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

struct TeachingCoursePackageSyncExecutionResult {
    var notebookDocument: NodeMarkdownDocument
    var sourceDocumentCache: [String: (NodeMarkdownDocument, NodeMarkdownFileMeta)]
    var baselineMap: [String: String]
    var updatedSourcePackageCount: Int
    var collectedNewPackageCount: Int
    var conflictPackageCount: Int
    var conflictRecords: [TeachingCoursePackageSyncConflictRecord]
    var packageResults: [TeachingCourseSyncPackageResult]
}

enum TeachingCoursePackageSyncEngine {
    static func execute(
        student: TeachingStudentItem,
        notebookDocument: NodeMarkdownDocument,
        placementTarget: TeachingCourseUpdatePlacementTarget?,
        allowedNewPackageIDs: Set<String>?,
        baselineMap: [String: String],
        resolveSourceURL: (String) throws -> URL?,
        loadSourcePayload: (URL) throws -> (NodeMarkdownDocument, NodeMarkdownFileMeta),
        appendPackageToTargetOrCollector: ([NodeMarkdownNode], TeachingCourseUpdatePlacementTarget?) throws -> (sourceFile: String, sourceID: String)
    ) throws -> TeachingCoursePackageSyncExecutionResult {
        try NodeMarkdownIdentityPolicy.validateForSynchronization(notebookDocument)
        var notebookDocument = notebookDocument
        var sourceDocumentCache: [String: (NodeMarkdownDocument, NodeMarkdownFileMeta)] = [:]
        var updatedSourcePackageCount = 0
        var collectedNewPackageCount = 0
        let conflictPackageCount = 0
        var baselineMap = baselineMap
        let conflictRecords: [TeachingCoursePackageSyncConflictRecord] = []
        var packageResults: [TeachingCourseSyncPackageResult] = []

        let ranges = TeachingCoursePackageContentSignature.packageRanges(in: notebookDocument.nodes)
        for range in ranges.reversed() {
            guard notebookDocument.nodes.indices.contains(range.start) else { continue }
            let rootNode = notebookDocument.nodes[range.start]
            var packageNodes = NodeMarkdownPackageCleaner.cleanPackage(Array(notebookDocument.nodes[range.start..<range.end]))
            let sourceID = rootNode.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = rootNode.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)

            if TeachingCoursePackageContentSignature.isCollectableNewPackageRoot(rootNode) {
                if let allowedNewPackageIDs, !allowedNewPackageIDs.contains(rootNode.id.uuidString) {
                    packageResults.append(
                        TeachingCourseSyncPackageResult(
                            packageTitle: rootNode.text,
                            sourceFile: sourceFile,
                            sourceID: sourceID,
                            isNewPackage: true,
                            success: true,
                            reason: "new package skipped by selection"
                        )
                    )
                    continue
                }
                packageNodes = NodeMarkdownPackageCleaner.cleanPackage(packageNodes)
                packageNodes[0].sourceID = ""
                packageNodes[0].sourceFile = ""
                let recoveryTarget: TeachingCourseUpdatePlacementTarget? = {
                    guard sourceID.isEmpty, !sourceFile.isEmpty else { return placementTarget }
                    return TeachingCourseUpdatePlacementTarget(
                        sourceFile: sourceFile,
                        anchorSourceID: nil
                    )
                }()
                let collectorRef = try appendPackageToTargetOrCollector(packageNodes, recoveryTarget)
                guard collectorRef.sourceID.caseInsensitiveCompare(rootNode.id.uuidString) == .orderedSame else {
                    throw NSError(
                        domain: "TeachingCoursePackageSyncEngine",
                        code: 7801,
                        userInfo: [NSLocalizedDescriptionKey: "新包入库返回了不同的UUID，已停止回写。"]
                    )
                }
                packageNodes[0].sourceID = collectorRef.sourceID
                packageNodes[0].sourceFile = collectorRef.sourceFile
                let collectorKey = syncBaselineKey(sourceFile: collectorRef.sourceFile, sourceID: collectorRef.sourceID)
                baselineMap[collectorKey] = TeachingCoursePackageContentSignature.digest(packageNodes)
                notebookDocument.nodes.replaceSubrange(range.start..<range.end, with: packageNodes)
                collectedNewPackageCount += 1
                packageResults.append(
                    TeachingCourseSyncPackageResult(
                        packageTitle: packageNodes[0].text,
                        sourceFile: packageNodes[0].sourceFile,
                        sourceID: packageNodes[0].sourceID,
                        isNewPackage: true,
                        success: true,
                        reason: sourceID.isEmpty && sourceFile.isEmpty
                            ? "new package collected"
                            : "incomplete source link repaired and collected"
                    )
                )
                continue
            }

            if sourceID.isEmpty || sourceFile.isEmpty {
                packageResults.append(
                    TeachingCourseSyncPackageResult(
                        packageTitle: rootNode.text,
                        sourceFile: sourceFile,
                        sourceID: sourceID,
                        isNewPackage: false,
                        success: false,
                        reason: "incomplete source link requires repair"
                    )
                )
                continue
            }

            guard let sourceURL = try resolveSourceURL(sourceFile) else {
                packageResults.append(
                    TeachingCourseSyncPackageResult(
                        packageTitle: rootNode.text,
                        sourceFile: sourceFile,
                        sourceID: sourceID,
                        isNewPackage: false,
                        success: false,
                        reason: "source file not found"
                    )
                )
                continue
            }

            let cacheKey = sourceURL.path
            let sourcePayload: (NodeMarkdownDocument, NodeMarkdownFileMeta)
            if let cached = sourceDocumentCache[cacheKey] {
                sourcePayload = cached
            } else {
                sourcePayload = try loadSourcePayload(sourceURL)
            }

            var sourceDocument = sourcePayload.0
            let sourceMeta = sourcePayload.1
            guard let sourceRange = TeachingCoursePackageContentSignature.packageRange(
                in: sourceDocument.nodes,
                sourceID: sourceID
            ) else {
                packageResults.append(
                    TeachingCourseSyncPackageResult(
                        packageTitle: rootNode.text,
                        sourceFile: sourceFile,
                        sourceID: sourceID,
                        isNewPackage: false,
                        success: false,
                        reason: "source H3 not found by SourceID"
                    )
                )
                continue
            }

            let sourcePackage = Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
            let notebookDigest = TeachingCoursePackageContentSignature.digest(packageNodes)
            let sourceDigest = TeachingCoursePackageContentSignature.digest(sourcePackage)
            let baselineKey = syncBaselineKey(sourceFile: sourceFile, sourceID: sourceID)

            if notebookDigest == sourceDigest {
                baselineMap[baselineKey] = sourceDigest
                packageResults.append(
                    TeachingCourseSyncPackageResult(
                        packageTitle: rootNode.text,
                        sourceFile: sourceFile,
                        sourceID: sourceID,
                        isNewPackage: false,
                        success: true,
                        reason: "package content unchanged"
                    )
                )
                continue
            }

            guard let sourceRoot = sourcePackage.first else { continue }
            // 上课期间母本有更新机制暂停：不再因为 source.mtime > notebook.mtime 而跳过。
            // 上课中教师不会修改母本，双方差异一律按随堂→母本方向处理。
            // 若需恢复母本→随堂保护，取消下面注释：
            // if sourceRoot.mtimeCache > rootNode.mtimeCache {
            //     packageResults.append(...)
            //     continue
            // }

            packageNodes = NodeMarkdownPackageCleaner.cleanPackage(packageNodes)
            let notebookContentDigest = TeachingCoursePackageContentSignature.digest(packageNodes)
            var sourceReplacement = packageNodes
            if !sourceReplacement.isEmpty {
                sourceReplacement[0].id = sourceRoot.id
                sourceReplacement[0].sourceID = sourceRoot.sourceID
                sourceReplacement[0].sourceFile = sourceRoot.sourceFile
            }
            sourceDocument.nodes.replaceSubrange(sourceRange.start..<sourceRange.end, with: sourceReplacement)
            sourceDocumentCache[cacheKey] = (sourceDocument, sourceMeta)
            updatedSourcePackageCount += 1
            baselineMap[baselineKey] = notebookContentDigest
            packageResults.append(
                TeachingCourseSyncPackageResult(
                    packageTitle: packageNodes[0].text,
                    sourceFile: sourceFile,
                    sourceID: sourceID,
                    isNewPackage: false,
                    success: true,
                    reason: "notebook H3 modification time won"
                )
            )
        }

        return TeachingCoursePackageSyncExecutionResult(
            notebookDocument: notebookDocument,
            sourceDocumentCache: sourceDocumentCache,
            baselineMap: baselineMap,
            updatedSourcePackageCount: updatedSourcePackageCount,
            collectedNewPackageCount: collectedNewPackageCount,
            conflictPackageCount: conflictPackageCount,
            conflictRecords: conflictRecords,
            packageResults: packageResults
        )
    }

    private static func syncBaselineKey(sourceFile: String, sourceID: String) -> String {
        "\(sourceFile)#\(sourceID)"
    }

}
