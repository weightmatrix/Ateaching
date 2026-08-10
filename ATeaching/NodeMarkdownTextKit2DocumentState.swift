// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

/// TextKit2新管线唯一的Node值。正文、身份、层级和母本来源不再分开传递。
struct NodeMarkdownTextKit2Node: Equatable, Identifiable {
    let id: UUID
    var level: Int
    var content: String
    var sourceID: String
    var sourceFile: String

    init(
        id: UUID,
        level: Int,
        content: String,
        sourceID: String,
        sourceFile: String
    ) {
        self.id = id
        self.level = level
        self.content = content
        self.sourceID = sourceID
        self.sourceFile = sourceFile
    }

    var metadata: NodeMarkdownTextKitRowMetadata {
        NodeMarkdownTextKitRowMetadata(
            nodeID: id.uuidString,
            level: level,
            sourceID: sourceID,
            sourceFile: sourceFile
        )
    }

    var isProtectedH3: Bool { metadata.isProtectedH3 }
}

struct NodeMarkdownTextKit2DocumentSnapshot: Equatable {
    let revision: UInt64
    let nodes: [NodeMarkdownTextKit2Node]

    var plainText: String { nodes.map(\.content).joined(separator: "\n") }
    var rowMetadata: [NodeMarkdownTextKitRowMetadata] { nodes.map(\.metadata) }
}

/// 新管线的文档核心。所有Node操作在这里一次性更新节点数组和UUID索引。
/// UI只消费快照，绝不能再自行拼接正文与metadata。
final class NodeMarkdownTextKit2DocumentState {
    enum ValidationError: Equatable, CustomStringConvertible {
        case rowCount(text: Int, metadata: Int)
        case invalidNodeID(row: Int)
        case duplicateNodeID(row: Int, id: UUID)
        case invalidLevel(row: Int, level: Int)
        case incompleteSource(row: Int)
        case sourceOnNonH3(row: Int, level: Int)

        var description: String {
            switch self {
            case let .rowCount(text, metadata):
                return "正文行数\(text)与Node元数据行数\(metadata)不一致"
            case let .invalidNodeID(row):
                return "第\(row + 1)行缺少有效UUID"
            case let .duplicateNodeID(row, id):
                return "第\(row + 1)行UUID重复：\(id.uuidString)"
            case let .invalidLevel(row, level):
                return "第\(row + 1)行层级\(level)不在1至12之间"
            case let .incompleteSource(row):
                return "第\(row + 1)行的SourceID与SourceFile没有成对存在"
            case let .sourceOnNonH3(row, level):
                return "第\(row + 1)行带有母本来源，但层级是\(level)而不是H3"
            }
        }
    }

    private(set) var revision: UInt64 = 0
    private(set) var nodes: [NodeMarkdownTextKit2Node] = []
    private(set) var rowByID: [UUID: Int] = [:]
    private(set) var lastValidationError: ValidationError?

    init(text: String, rowMetadata: [NodeMarkdownTextKitRowMetadata]) {
        _ = replace(text: text, rowMetadata: rowMetadata, incrementsRevision: false)
    }

    var snapshot: NodeMarkdownTextKit2DocumentSnapshot {
        NodeMarkdownTextKit2DocumentSnapshot(revision: revision, nodes: nodes)
    }

    func row(for id: UUID) -> Int? { rowByID[id] }

    func node(at row: Int) -> NodeMarkdownTextKit2Node? {
        guard nodes.indices.contains(row) else { return nil }
        return nodes[row]
    }

    @discardableResult
    func replace(
        text: String,
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        incrementsRevision: Bool = true
    ) -> Bool {
        let lines = Self.lines(in: text)
        guard let validatedIDs = Self.validate(lines: lines, rowMetadata: rowMetadata) else {
            lastValidationError = Self.validationError(lines: lines, rowMetadata: rowMetadata)
            return false
        }
        var assigned = Set<UUID>()
        var rebuilt: [NodeMarkdownTextKit2Node] = []
        rebuilt.reserveCapacity(lines.count)

        for index in lines.indices {
            let metadata = rowMetadata[index]
            let id = validatedIDs[index]
            assigned.insert(id)
            rebuilt.append(
                NodeMarkdownTextKit2Node(
                    id: id,
                    level: metadata.level,
                    content: lines[index],
                    sourceID: metadata.sourceID,
                    sourceFile: metadata.sourceFile
                )
            )
        }

        nodes = rebuilt
        lastValidationError = nil
        rebuildIndex()
        if incrementsRevision { revision &+= 1 }
        assertInvariants()
        return true
    }

    @discardableResult
    func updateNode(id: UUID, transform: (inout NodeMarkdownTextKit2Node) -> Void) -> Bool {
        guard let row = rowByID[id], nodes.indices.contains(row) else { return false }
        let original = nodes[row]
        transform(&nodes[row])
        guard (1...12).contains(nodes[row].level) else {
            nodes[row] = original
            return false
        }
        if original.isProtectedH3 {
            nodes[row].level = 3
            nodes[row].sourceID = original.sourceID
            nodes[row].sourceFile = original.sourceFile
        }
        let hasSourceID = !nodes[row].sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSourceFile = !nodes[row].sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSourceID == hasSourceFile,
              !hasSourceID || nodes[row].level == 3 else {
            nodes[row] = original
            return false
        }
        guard nodes[row] != original else { return false }
        revision &+= 1
        assertInvariants()
        return true
    }

    @discardableResult
    func updateRow(
        _ row: Int,
        content: String,
        metadata: NodeMarkdownTextKitRowMetadata
    ) -> Bool {
        guard nodes.indices.contains(row),
              nodes[row].id.uuidString == metadata.nodeID else { return false }
        return updateNode(id: nodes[row].id) { node in
            node.content = content
            node.level = metadata.level
            node.sourceID = metadata.sourceID
            node.sourceFile = metadata.sourceFile
        }
    }

    @discardableResult
    func insertNode(_ node: NodeMarkdownTextKit2Node, at requestedRow: Int) -> Int? {
        guard rowByID[node.id] == nil,
              (1...12).contains(node.level),
              (0...nodes.count).contains(requestedRow) else { return nil }
        nodes.insert(node, at: requestedRow)
        revision &+= 1
        rebuildIndex(startingAt: requestedRow)
        assertInvariants()
        return requestedRow
    }

    @discardableResult
    func removeNodes(in requestedRows: IndexSet) -> [NodeMarkdownTextKit2Node] {
        guard requestedRows.allSatisfy({ nodes.indices.contains($0) }),
              requestedRows.count < nodes.count else { return [] }
        let rows = Array(requestedRows)
        guard !rows.isEmpty else { return [] }
        let removed = rows.map { nodes[$0] }
        for row in rows.sorted(by: >) { nodes.remove(at: row) }
        revision &+= 1
        rebuildIndex()
        assertInvariants()
        return removed
    }

    func snapshotRows() -> [NodeMarkdownLegacyDocumentSnapshot.Row] {
        nodes.map {
            NodeMarkdownLegacyDocumentSnapshot.Row(
                nodeID: $0.id.uuidString,
                level: $0.level,
                content: $0.content,
                sourceID: $0.sourceID,
                sourceFile: $0.sourceFile
            )
        }
    }

    private func rebuildIndex(startingAt start: Int = 0) {
        if start <= 0 {
            rowByID.removeAll(keepingCapacity: true)
        } else {
            rowByID = rowByID.filter { $0.value < start }
        }
        for row in max(0, start)..<nodes.count { rowByID[nodes[row].id] = row }
    }

    private func assertInvariants(file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        assert(!nodes.isEmpty, "TextKit2 document must contain at least one Node", file: file, line: line)
        assert(rowByID.count == nodes.count, "TextKit2 Node UUID index diverged", file: file, line: line)
        assert(Set(nodes.map(\.id)).count == nodes.count, "TextKit2 document contains duplicate UUIDs", file: file, line: line)
        for (row, node) in nodes.enumerated() {
            assert(rowByID[node.id] == row, "TextKit2 UUID index points at wrong row", file: file, line: line)
        }
        #endif
    }

    private static func lines(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    static func validationError(
        text: String,
        rowMetadata: [NodeMarkdownTextKitRowMetadata]
    ) -> ValidationError? {
        validationError(lines: lines(in: text), rowMetadata: rowMetadata)
    }

    private static func validate(
        lines: [String],
        rowMetadata: [NodeMarkdownTextKitRowMetadata]
    ) -> [UUID]? {
        guard validationError(lines: lines, rowMetadata: rowMetadata) == nil else { return nil }
        return rowMetadata.compactMap { UUID(uuidString: $0.nodeID) }
    }

    private static func validationError(
        lines: [String],
        rowMetadata: [NodeMarkdownTextKitRowMetadata]
    ) -> ValidationError? {
        guard lines.count == rowMetadata.count else {
            return .rowCount(text: lines.count, metadata: rowMetadata.count)
        }
        var assigned = Set<UUID>()
        for (row, metadata) in rowMetadata.enumerated() {
            guard let id = UUID(uuidString: metadata.nodeID) else {
                return .invalidNodeID(row: row)
            }
            guard assigned.insert(id).inserted else {
                return .duplicateNodeID(row: row, id: id)
            }
            guard (1...12).contains(metadata.level) else {
                return .invalidLevel(row: row, level: metadata.level)
            }
            let hasSourceID = !metadata.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasSourceFile = !metadata.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasSourceID == hasSourceFile else {
                return .incompleteSource(row: row)
            }
            guard !hasSourceID || metadata.level == 3 else {
                return .sourceOnNonH3(row: row, level: metadata.level)
            }
        }
        return nil
    }
}
