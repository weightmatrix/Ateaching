import Foundation

struct TeachingCoursePackageStateSummary: Hashable {
    var dirtyPackageCount: Int
    var newPackageCount: Int
    var sourceUpdatePackageCount: Int = 0
    var conflictPackageCount: Int = 0
}

enum TeachingCoursePackageStateEngine {
    static func summarizePreviewState(
        notebookDocument: NodeMarkdownDocument,
        resolveSourceURL: (String) throws -> URL?,
        loadSourceDocument: (URL) throws -> NodeMarkdownDocument
    ) throws -> TeachingCoursePackageStateSummary {
        let ranges = TeachingCoursePackageContentSignature.packageRanges(in: notebookDocument.nodes)
        var dirty = 0
        var newPackages = 0
        var sourceUpdates = 0
        let conflicts = 0
        var sourceCache: [String: NodeMarkdownDocument] = [:]

        for range in ranges {
            guard notebookDocument.nodes.indices.contains(range.start) else { continue }
            let rootNode = notebookDocument.nodes[range.start]
            let sourceID = rootNode.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceFile = rootNode.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
            if TeachingCoursePackageContentSignature.isCollectableNewPackageRoot(rootNode) {
                newPackages += 1
                continue
            }
            guard !sourceID.isEmpty, !sourceFile.isEmpty else { continue }
            guard let sourceURL = try resolveSourceURL(sourceFile) else {
                continue
            }
            let sourceDocument: NodeMarkdownDocument
            if let cached = sourceCache[sourceURL.path] {
                sourceDocument = cached
            } else {
                let loaded = try loadSourceDocument(sourceURL)
                sourceCache[sourceURL.path] = loaded
                sourceDocument = loaded
            }
            guard let sourceRange = TeachingCoursePackageContentSignature.packageRange(
                in: sourceDocument.nodes,
                sourceID: sourceID
            ) else {
                continue
            }
            let notebookDigest = TeachingCoursePackageContentSignature.digest(
                Array(notebookDocument.nodes[range.start..<range.end])
            )
            let sourceDigest = TeachingCoursePackageContentSignature.digest(
                Array(sourceDocument.nodes[sourceRange.start..<sourceRange.end])
            )
            if notebookDigest != sourceDigest {
                // 上课期间母本不会被修改，母本有更新机制暂停。
                // 上课中所有差异统一归为脏包（随堂→母本方向）。
                // 未来若需恢复母本→随堂检测：比较 sourceRoot.mtimeCache > rootNode.mtimeCache
                dirty += 1
            }
        }

        return TeachingCoursePackageStateSummary(
            dirtyPackageCount: dirty,
            newPackageCount: newPackages,
            sourceUpdatePackageCount: sourceUpdates,
            conflictPackageCount: conflicts
        )
    }

}
