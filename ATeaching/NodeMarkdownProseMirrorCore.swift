// PIPELINE MARKER: NodeMarkdown ProseMirror-style core.
import Foundation

struct NodeMarkdownProseMirrorIndex: Equatable {
    private(set) var rowByID: [UUID: Int] = [:]
    private(set) var parentRows: [Int?] = []
    private(set) var subtreeEnds: [Int] = []
    private(set) var owningH3Rows: [Int?] = []
    private(set) var h3RangeByID: [UUID: Range<Int>] = [:]
    private(set) var numberingPaths: [[Int]] = []

    init(nodes: [NodeMarkdownTextKit2Node]) {
        rebuild(nodes: nodes)
    }

    mutating func rebuild(nodes: [NodeMarkdownTextKit2Node]) {
        rowByID.removeAll(keepingCapacity: true)
        parentRows = Array(repeating: nil, count: nodes.count)
        subtreeEnds = Array(repeating: nodes.count, count: nodes.count)
        owningH3Rows = Array(repeating: nil, count: nodes.count)
        numberingPaths = Array(repeating: [], count: nodes.count)
        h3RangeByID.removeAll(keepingCapacity: true)
        var openRows = Array<Int?>(repeating: nil, count: 13)
        var activeH3: Int?
        var numberingCounters = Array(repeating: 0, count: 13)

        for (row, node) in nodes.enumerated() {
            rowByID[node.id] = row
            for level in node.level...12 {
                if let open = openRows[level] {
                    subtreeEnds[open] = row
                    openRows[level] = nil
                }
            }
            if node.level > 1 {
                for level in stride(from: node.level - 1, through: 1, by: -1) {
                    if let parent = openRows[level] {
                        parentRows[row] = parent
                        break
                    }
                }
            }
            openRows[node.level] = row
            switch node.level {
            case 1, 2: activeH3 = nil
            case 3: activeH3 = row
            default: break
            }
            owningH3Rows[row] = activeH3
            numberingCounters[node.level] += 1
            if node.level < 12 {
                for level in (node.level + 1)...12 { numberingCounters[level] = 0 }
            }
            numberingPaths[row] = (1...node.level).compactMap {
                numberingCounters[$0] > 0 ? numberingCounters[$0] : nil
            }
        }
        for level in 1...12 {
            if let open = openRows[level] { subtreeEnds[open] = nodes.count }
        }
        for (row, node) in nodes.enumerated() where node.level == 3 {
            h3RangeByID[node.id] = row..<subtreeEnds[row]
        }
    }

    func row(for nodeID: UUID) -> Int? { rowByID[nodeID] }
    func parentRow(of row: Int) -> Int? {
        parentRows.indices.contains(row) ? parentRows[row] : nil
    }
    func subtreeRange(startingAt row: Int) -> Range<Int>? {
        subtreeEnds.indices.contains(row) ? row..<subtreeEnds[row] : nil
    }
    func owningH3Row(for row: Int) -> Int? {
        owningH3Rows.indices.contains(row) ? owningH3Rows[row] : nil
    }
    func packageRange(rootID: UUID) -> Range<Int>? { h3RangeByID[rootID] }
    func numberingPath(for row: Int) -> [Int]? {
        numberingPaths.indices.contains(row) ? numberingPaths[row] : nil
    }

    func numberingText(for row: Int) -> String? {
        numberingPath(for: row)?.map(String.init).joined(separator: ".")
    }
}

struct NodeMarkdownNodePosition: Equatable {
    let nodeID: UUID
    let utf16Offset: Int
}

struct NodeMarkdownNodeSelection: Equatable {
    let anchor: NodeMarkdownNodePosition
    let head: NodeMarkdownNodePosition

    init(anchor: NodeMarkdownNodePosition, head: NodeMarkdownNodePosition? = nil) {
        self.anchor = anchor
        self.head = head ?? anchor
    }
}

enum NodeMarkdownTransactionStep: Equatable {
    case replaceNode(nodeID: UUID, node: NodeMarkdownTextKit2Node)
    case replaceText(nodeID: UUID, range: NSRange, replacement: String)
    case setLevel(nodeID: UUID, level: Int)
    case insertNodes(row: Int, nodes: [NodeMarkdownTextKit2Node])
    case deleteNodes(nodeIDs: [UUID])
    case splitNode(nodeID: UUID, offset: Int, newNodeID: UUID, newLevel: Int)
    case joinNodes(leftID: UUID, rightID: UUID)
    case moveNodes(nodeIDs: [UUID], destinationRow: Int)
}

extension NodeMarkdownTransactionStep {
    var isSingleNodeContentMutation: Bool {
        switch self {
        case .replaceNode, .replaceText, .setLevel:
            return true
        case .insertNodes, .deleteNodes, .splitNode, .joinNodes, .moveNodes:
            return false
        }
    }
}

struct NodeMarkdownTransaction: Equatable {
    let id: UUID
    let baseRevision: UInt64
    let steps: [NodeMarkdownTransactionStep]
    let selectionBefore: NodeMarkdownNodeSelection?
    let selectionAfter: NodeMarkdownNodeSelection?
    let recordsHistory: Bool
    let label: String

    init(
        id: UUID = UUID(),
        baseRevision: UInt64,
        steps: [NodeMarkdownTransactionStep],
        selectionBefore: NodeMarkdownNodeSelection? = nil,
        selectionAfter: NodeMarkdownNodeSelection? = nil,
        recordsHistory: Bool = true,
        label: String
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.steps = steps
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.recordsHistory = recordsHistory
        self.label = label
    }
}

enum NodeMarkdownPositionMapOperation: Equatable {
    case replaceText(nodeID: UUID, oldRange: NSRange, insertedLength: Int)
    case split(sourceID: UUID, offset: Int, trailingID: UUID)
    case join(leftID: UUID, leftLength: Int, rightID: UUID)
    case delete(nodeIDs: Set<UUID>, fallbackID: UUID?)
}

struct NodeMarkdownPositionMap: Equatable {
    private(set) var operations: [NodeMarkdownPositionMapOperation] = []

    mutating func append(_ operation: NodeMarkdownPositionMapOperation) {
        operations.append(operation)
    }

    func map(_ position: NodeMarkdownNodePosition) -> NodeMarkdownNodePosition? {
        var mapped: NodeMarkdownNodePosition? = position
        for operation in operations {
            guard let current = mapped else { return nil }
            switch operation {
            case let .replaceText(nodeID, oldRange, insertedLength):
                guard current.nodeID == nodeID else { continue }
                let oldEnd = NSMaxRange(oldRange)
                let offset: Int
                if current.utf16Offset <= oldRange.location {
                    offset = current.utf16Offset
                } else if current.utf16Offset <= oldEnd {
                    offset = oldRange.location + insertedLength
                } else {
                    offset = current.utf16Offset + insertedLength - oldRange.length
                }
                mapped = NodeMarkdownNodePosition(nodeID: nodeID, utf16Offset: max(0, offset))
            case let .split(sourceID, offset, trailingID):
                guard current.nodeID == sourceID, current.utf16Offset > offset else { continue }
                mapped = NodeMarkdownNodePosition(
                    nodeID: trailingID,
                    utf16Offset: current.utf16Offset - offset
                )
            case let .join(leftID, leftLength, rightID):
                guard current.nodeID == rightID else { continue }
                mapped = NodeMarkdownNodePosition(
                    nodeID: leftID,
                    utf16Offset: leftLength + current.utf16Offset
                )
            case let .delete(nodeIDs, fallbackID):
                guard nodeIDs.contains(current.nodeID) else { continue }
                mapped = fallbackID.map { NodeMarkdownNodePosition(nodeID: $0, utf16Offset: 0) }
            }
        }
        return mapped
    }

    func map(_ selection: NodeMarkdownNodeSelection?) -> NodeMarkdownNodeSelection? {
        guard let selection,
              let anchor = map(selection.anchor),
              let head = map(selection.head) else { return nil }
        return NodeMarkdownNodeSelection(anchor: anchor, head: head)
    }
}

struct NodeMarkdownTransactionResult: Equatable {
    let transactionID: UUID
    let revisionBefore: UInt64
    let revisionAfter: UInt64
    let affectedNodeIDs: Set<UUID>
    let structural: Bool
    let positionMap: NodeMarkdownPositionMap
    let mappedSelection: NodeMarkdownNodeSelection?
    let impact: NodeMarkdownTransactionImpact
}

enum NodeMarkdownTransactionError: Error, Equatable, CustomStringConvertible {
    case staleRevision(expected: UInt64, received: UInt64)
    case missingNode(UUID)
    case duplicateNode(UUID)
    case invalidRange(nodeID: UUID, range: NSRange)
    case invalidLevel(Int)
    case protectedNode(UUID)
    case invalidStructure(String)

    var description: String {
        switch self {
        case let .staleRevision(expected, received):
            return "事务版本过期：当前\(expected)，收到\(received)"
        case let .missingNode(id): return "找不到Node：\(id.uuidString)"
        case let .duplicateNode(id): return "Node UUID重复：\(id.uuidString)"
        case let .invalidRange(id, range):
            return "Node \(id.uuidString) 的范围无效：\(NSStringFromRange(range))"
        case let .invalidLevel(level): return "层级\(level)不在1至12之间"
        case let .protectedNode(id): return "受保护H3不可执行该结构操作：\(id.uuidString)"
        case let .invalidStructure(message): return message
        }
    }
}

struct NodeMarkdownHistoryEntry: Equatable {
    let undoSteps: [NodeMarkdownTransactionStep]
    let redoSteps: [NodeMarkdownTransactionStep]
    let selectionBefore: NodeMarkdownNodeSelection?
    let selectionAfter: NodeMarkdownNodeSelection?
    let label: String
}
