import Foundation

// MARK: - NodeMarkdown旧管线保存事务

/// 父页不需要知道NSTextView或Coordinator的存在。保存、关闭、同步和导出只调用这一个入口，
/// 旧管线必须在调用返回前把UUID、level、content和Source信息提交给父文档。
@MainActor
final class NodeMarkdownLegacyDraftCommitController {
    private var commitAction: (() -> Void)?
    private var focusRowEndAction: ((Int) -> Void)?

    func install(
        commit action: @escaping () -> Void,
        focusRowEnd: @escaping (Int) -> Void
    ) {
        commitAction = action
        focusRowEndAction = focusRowEnd
    }

    func commitPendingEditing() {
        commitAction?()
    }

    func focusAtEnd(ofRow rowIndex: Int) {
        focusRowEndAction?(rowIndex)
    }
}

/// 结构编辑不能分别上报正文和行元数据。每一行的正文、UUID、层级和来源信息
/// 必须在同一个值中产生、传递和解析，否则异步解析可能把新正文配到旧身份上。
struct NodeMarkdownLegacyDocumentSnapshot: Equatable {
    struct Row: Equatable {
        let nodeID: String
        let level: Int
        let content: String
        let sourceID: String
        let sourceFile: String

        var metadata: NodeMarkdownTextKitRowMetadata {
            NodeMarkdownTextKitRowMetadata(
                nodeID: nodeID,
                level: level,
                sourceID: sourceID,
                sourceFile: sourceFile
            )
        }
    }

    let sessionID: UUID
    let revision: UInt64
    let rows: [Row]

    var plainText: String {
        rows.map(\.content).joined(separator: "\n")
    }

    var rowMetadata: [NodeMarkdownTextKitRowMetadata] {
        rows.map(\.metadata)
    }
}

/// 活动行暂存始终携带完整Node身份。正文、层级和母本来源必须一起提交。
struct NodeMarkdownLegacyEditingNodeDraft: Equatable {
    let nodeID: String
    var level: Int
    var content: String
    var sourceID: String
    var sourceFile: String

    var isProtectedH3: Bool {
        level == 3
            && !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 旧管线一次活动Node编辑的唯一事实。
///
/// 正文已经不携带层级前缀，因此活动Node的身份、业务字段和TextKit字符范围必须
/// 同生共灭。普通打字期间只同步当前行的真实范围；后续Node只根据这一处范围差
/// 平移，不能再从全文长度差猜测活动行，也不能由样式刷新改写业务字段。
struct NodeMarkdownLegacyActiveNodeTransaction {
    let rowIndex: Int
    private(set) var stableRange: NSRange
    private(set) var currentRange: NSRange
    private(set) var baselineDraft: NodeMarkdownLegacyEditingNodeDraft
    var draft: NodeMarkdownLegacyEditingNodeDraft

    init(
        rowIndex: Int,
        range: NSRange,
        draft: NodeMarkdownLegacyEditingNodeDraft
    ) {
        self.rowIndex = rowIndex
        stableRange = range
        currentRange = range
        baselineDraft = draft
        self.draft = draft
    }

    var characterDelta: Int {
        currentRange.length - stableRange.length
    }

    var isDirty: Bool {
        draft != baselineDraft
    }

    mutating func synchronizeRange(in source: NSString) -> Bool {
        guard rowIndex >= 0, stableRange.location <= source.length else { return false }
        if stableRange.location == source.length {
            currentRange = NSRange(location: source.length, length: 0)
            return true
        }
        let resolved = source.lineRange(
            for: NSRange(location: stableRange.location, length: 0)
        )
        guard resolved.location == stableRange.location,
              NSMaxRange(resolved) <= source.length else { return false }
        currentRange = resolved
        return true
    }

    mutating func rebase(to range: NSRange) {
        stableRange = range
        currentRange = range
    }

    mutating func markCommitted() {
        baselineDraft = draft
    }

    func effectiveRange(at row: Int, stableRanges: [NSRange]) -> NSRange? {
        NodeMarkdownLegacyRowRangeIndex.effectiveRange(
            at: row,
            in: stableRanges,
            editedRow: rowIndex,
            characterDelta: characterDelta
        )
    }

    func rowIndex(containing location: Int, stableRanges: [NSRange]) -> Int? {
        NodeMarkdownLegacyRowRangeIndex.rowIndex(
            containing: location,
            in: stableRanges,
            editedRow: rowIndex,
            characterDelta: characterDelta
        )
    }
}

enum NodeMarkdownLegacyStructurePolicy {
    static func insertedLevel(after source: NodeMarkdownTextKitRowMetadata) -> Int {
        source.isProtectedH3 ? 4 : max(1, min(12, source.level))
    }

    /// 有母本来源的H3是包根，不允许被回车拆开。回车只在完整H3后建立空H4。
    static func insertsEmptyChildInsteadOfSplitting(
        _ source: NodeMarkdownTextKitRowMetadata
    ) -> Bool {
        source.isProtectedH3
    }
}

/// 结构编辑只改变发生编辑的边界。插入新行时，旧行的身份数组按位置整体后移；
/// 删除换行时，只回收被合并行的身份。边界之后每个Node的UUID、层级和Source信息
/// 必须逐项保持不变，禁止根据邻行样式或正文重新推断。
enum NodeMarkdownLegacyMetadataProjection {
    static func insertingRows(
        count: Int,
        after sourceRow: Int,
        into metadata: [NodeMarkdownTextKitRowMetadata],
        insertedLevel: Int
    ) -> [NodeMarkdownTextKitRowMetadata] {
        guard count > 0 else { return metadata }
        var result = metadata
        let insertionIndex = max(0, min(result.count, sourceRow + 1))
        result.insert(
            contentsOf: (0..<count).map { _ in .fresh(level: insertedLevel) },
            at: insertionIndex
        )
        return result
    }

    static func removingRows(
        count: Int,
        after sourceRow: Int,
        from metadata: [NodeMarkdownTextKitRowMetadata]
    ) -> [NodeMarkdownTextKitRowMetadata] {
        guard count > 0, !metadata.isEmpty else { return metadata }
        var result = metadata
        let removalStart = max(0, min(result.count, sourceRow + 1))
        let removalEnd = min(result.count, removalStart + count)
        if removalStart < removalEnd {
            result.removeSubrange(removalStart..<removalEnd)
        }
        return result
    }
}

/// TextKit缓冲区不再保存`### `等层级前缀，所以每行必须单独携带Node身份与层级。
struct NodeMarkdownTextKitRowMetadata: Equatable {
    let nodeID: String
    let level: Int
    let sourceID: String
    let sourceFile: String

    /// 只有完整关联母本的H3才受结构保护。空来源H3就是普通行，可以改层级、合并和删除。
    var isProtectedH3: Bool {
        level == 3
            && !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = NodeMarkdownTextKitRowMetadata(
        nodeID: "",
        level: 7,
        sourceID: "",
        sourceFile: ""
    )

    static func fresh(level: Int) -> NodeMarkdownTextKitRowMetadata {
        NodeMarkdownTextKitRowMetadata(
            nodeID: UUID().uuidString,
            level: max(1, min(12, level)),
            sourceID: "",
            sourceFile: ""
        )
    }

    func changingLevel(to newLevel: Int) -> NodeMarkdownTextKitRowMetadata {
        let safeLevel = max(1, min(12, newLevel))
        return NodeMarkdownTextKitRowMetadata(
            nodeID: nodeID,
            level: safeLevel,
            sourceID: safeLevel == 3 ? sourceID : "",
            sourceFile: safeLevel == 3 ? sourceFile : ""
        )
    }

    /// 只有Node身份和层级参与文字布局。Source字段用于同步与H3保护，
    /// 它们变化时不得让TextKit误判为需要重新排版。
    func hasSameLayoutIdentity(as other: NodeMarkdownTextKitRowMetadata) -> Bool {
        nodeID == other.nodeID && level == other.level
    }

    static func collectionsHaveSameLayoutIdentity(
        _ lhs: [NodeMarkdownTextKitRowMetadata],
        _ rhs: [NodeMarkdownTextKitRowMetadata]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { current, other in
            current.hasSameLayoutIdentity(as: other)
        }
    }
}
