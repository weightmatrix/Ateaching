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
    let documentID: UUID
    let revision: UInt64
    let nodes: [NodeMarkdownTextKit2Node]
    let nodeRevisions: [UUID: UInt64]

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

    let documentID = UUID()
    private(set) var revision: UInt64 = 0
    private(set) var nodes: [NodeMarkdownTextKit2Node] = []
    private(set) var rowByID: [UUID: Int] = [:]
    private(set) var nodeRevisions: [UUID: UInt64] = [:]
    private(set) var structuralIndex = NodeMarkdownProseMirrorIndex(nodes: [])
    private(set) var lastValidationError: ValidationError?
    private(set) var lastTransactionError: NodeMarkdownTransactionError?
    private var undoHistory: [NodeMarkdownHistoryEntry] = []
    private var redoHistory: [NodeMarkdownHistoryEntry] = []
    private let historyLimit = 500
    private var allowsProtectedHistoryMutation = false

    init(text: String, rowMetadata: [NodeMarkdownTextKitRowMetadata]) {
        _ = replace(text: text, rowMetadata: rowMetadata, incrementsRevision: false)
    }

    var snapshot: NodeMarkdownTextKit2DocumentSnapshot {
        NodeMarkdownTextKit2DocumentSnapshot(
            documentID: documentID,
            revision: revision,
            nodes: nodes,
            nodeRevisions: nodeRevisions
        )
    }

    func nodeRevision(for id: UUID) -> UInt64 { nodeRevisions[id, default: 0] }

    func row(for id: UUID) -> Int? { rowByID[id] }

    func parentRow(of row: Int) -> Int? { structuralIndex.parentRow(of: row) }
    func subtreeRange(startingAt row: Int) -> Range<Int>? {
        structuralIndex.subtreeRange(startingAt: row)
    }
    func owningH3Row(for row: Int) -> Int? { structuralIndex.owningH3Row(for: row) }
    func packageRange(rootID: UUID) -> Range<Int>? { structuralIndex.packageRange(rootID: rootID) }
    func numberingPath(for row: Int) -> [Int]? { structuralIndex.numberingPath(for: row) }
    func numberingText(for row: Int) -> String? { structuralIndex.numberingText(for: row) }

    func node(at row: Int) -> NodeMarkdownTextKit2Node? {
        guard nodes.indices.contains(row) else { return nil }
        return nodes[row]
    }

    var canUndo: Bool { !undoHistory.isEmpty }
    var canRedo: Bool { !redoHistory.isEmpty }

    @discardableResult
    func dispatch(_ transaction: NodeMarkdownTransaction) -> NodeMarkdownTransactionResult? {
        guard transaction.baseRevision == revision else {
            lastTransactionError = .staleRevision(expected: revision, received: transaction.baseRevision)
            return nil
        }
        guard !transaction.steps.isEmpty else {
            return NodeMarkdownTransactionResult(
                transactionID: transaction.id,
                revisionBefore: revision,
                revisionAfter: revision,
                affectedNodeIDs: [],
                structural: false,
                positionMap: NodeMarkdownPositionMap(),
                mappedSelection: transaction.selectionAfter ?? transaction.selectionBefore,
                impact: .none
            )
        }

        // Single-Node typing is deliberately allocation-free with respect to document size.
        // Structural/multi-step transactions keep one rollback snapshot because they are rare.
        let needsRollbackSnapshot = transaction.steps.count != 1
            || !transaction.steps.allSatisfy(\.isSingleNodeContentMutation)
        let rollbackNodes = needsRollbackSnapshot ? nodes : nil
        let rollbackIndex = needsRollbackSnapshot ? rowByID : nil
        let rollbackStructuralIndex = needsRollbackSnapshot ? structuralIndex : nil
        let rollbackNodeRevisions = needsRollbackSnapshot ? nodeRevisions : nil
        let revisionBefore = revision
        let impactStartRow = earliestAffectedRow(for: transaction.steps)
        let insertedNodeIDs = insertedNodeIDs(in: transaction.steps)
        let deletedNodeIDs = deletedNodeIDs(in: transaction.steps)
        let contentNodeIDs = contentNodeIDs(in: transaction.steps)
        var inverseSteps: [NodeMarkdownTransactionStep] = []
        var affectedNodeIDs = Set<UUID>()
        var structural = false
        var positionMap = NodeMarkdownPositionMap()

        do {
            for step in transaction.steps {
                let applied = try applyStep(step)
                inverseSteps.insert(contentsOf: applied.inverseSteps, at: 0)
                affectedNodeIDs.formUnion(applied.affectedNodeIDs)
                structural = structural || applied.structural
                if let mapOperation = applied.mapOperation {
                    positionMap.append(mapOperation)
                }
            }
        } catch let error as NodeMarkdownTransactionError {
            if let rollbackNodes, let rollbackIndex, let rollbackStructuralIndex, let rollbackNodeRevisions {
                nodes = rollbackNodes
                rowByID = rollbackIndex
                structuralIndex = rollbackStructuralIndex
                nodeRevisions = rollbackNodeRevisions
            }
            lastTransactionError = error
            return nil
        } catch {
            if let rollbackNodes, let rollbackIndex, let rollbackStructuralIndex, let rollbackNodeRevisions {
                nodes = rollbackNodes
                rowByID = rollbackIndex
                structuralIndex = rollbackStructuralIndex
                nodeRevisions = rollbackNodeRevisions
            }
            lastTransactionError = .invalidStructure(error.localizedDescription)
            return nil
        }

        revision &+= 1
        deletedNodeIDs.forEach { nodeRevisions[$0] = nil }
        for id in affectedNodeIDs where rowByID[id] != nil {
            nodeRevisions[id, default: 0] &+= 1
        }
        lastTransactionError = nil
        if transaction.recordsHistory {
            undoHistory.append(
                NodeMarkdownHistoryEntry(
                    undoSteps: inverseSteps,
                    redoSteps: transaction.steps,
                    selectionBefore: transaction.selectionBefore,
                    selectionAfter: transaction.selectionAfter,
                    label: transaction.label
                )
            )
            if undoHistory.count > historyLimit {
                undoHistory.removeFirst(undoHistory.count - historyLimit)
            }
            redoHistory.removeAll(keepingCapacity: true)
        }
        if structural { repairIndicesIfNeeded() }
        let structuralRange: Range<Int>? = structural ? {
            let lower = max(0, min(impactStartRow ?? 0, nodes.count))
            return lower..<nodes.count
        }() : nil
        var layoutNodeIDs = affectedNodeIDs.subtracting(deletedNodeIDs)
        if let start = impactStartRow {
            for row in max(0, start - 1)...min(nodes.count - 1, start + 1) where nodes.indices.contains(row) {
                layoutNodeIDs.insert(nodes[row].id)
            }
        }
        let impact = NodeMarkdownTransactionImpact(
            contentNodeIDs: contentNodeIDs,
            layoutNodeIDs: layoutNodeIDs,
            insertedNodeIDs: insertedNodeIDs,
            deletedNodeIDs: deletedNodeIDs,
            structuralRange: structuralRange,
            numberingStartRow: structural ? max(0, impactStartRow ?? 0) : nil
        )
        return NodeMarkdownTransactionResult(
            transactionID: transaction.id,
            revisionBefore: revisionBefore,
            revisionAfter: revision,
            affectedNodeIDs: affectedNodeIDs,
            structural: structural,
            positionMap: positionMap,
            mappedSelection: transaction.selectionAfter ?? positionMap.map(transaction.selectionBefore),
            impact: impact
        )
    }

    @discardableResult
    func undo() -> NodeMarkdownTransactionResult? {
        guard let entry = undoHistory.popLast() else { return nil }
        allowsProtectedHistoryMutation = true
        defer { allowsProtectedHistoryMutation = false }
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: entry.undoSteps,
            selectionBefore: entry.selectionAfter,
            selectionAfter: entry.selectionBefore,
            recordsHistory: false,
            label: "Undo \(entry.label)"
        )
        guard let result = dispatch(transaction) else {
            undoHistory.append(entry)
            return nil
        }
        redoHistory.append(entry)
        return result
    }

    @discardableResult
    func redo() -> NodeMarkdownTransactionResult? {
        guard let entry = redoHistory.popLast() else { return nil }
        allowsProtectedHistoryMutation = true
        defer { allowsProtectedHistoryMutation = false }
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: entry.redoSteps,
            selectionBefore: entry.selectionBefore,
            selectionAfter: entry.selectionAfter,
            recordsHistory: false,
            label: "Redo \(entry.label)"
        )
        guard let result = dispatch(transaction) else {
            redoHistory.append(entry)
            return nil
        }
        undoHistory.append(entry)
        return result
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

        let oldNodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let oldRevisions = nodeRevisions
        nodes = rebuilt
        nodeRevisions = Dictionary(uniqueKeysWithValues: rebuilt.map { node in
            let oldRevision = oldRevisions[node.id, default: 0]
            let next = oldNodesByID[node.id] == node ? oldRevision : oldRevision &+ 1
            return (node.id, max(1, next))
        })
        lastValidationError = nil
        lastTransactionError = nil
        rebuildIndex()
        undoHistory.removeAll(keepingCapacity: true)
        redoHistory.removeAll(keepingCapacity: true)
        if incrementsRevision { revision &+= 1 }
        repairIndicesIfNeeded()
        return true
    }

    @discardableResult
    func updateNode(id: UUID, transform: (inout NodeMarkdownTextKit2Node) -> Void) -> Bool {
        guard let row = rowByID[id], nodes.indices.contains(row) else { return false }
        var replacement = nodes[row]
        transform(&replacement)
        guard replacement != nodes[row] else { return false }
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: [.replaceNode(nodeID: id, node: replacement)],
            recordsHistory: false,
            label: "Update Node"
        )
        guard dispatch(transaction) != nil else { return false }
        repairUpdatedNodeIndexIfNeeded(at: row)
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
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: [.insertNodes(row: requestedRow, nodes: [node])],
            label: "Insert Node"
        )
        return dispatch(transaction) == nil ? nil : requestedRow
    }

    /// Splits one Node without reparsing the document. The original UUID remains on the
    /// leading half and the newly-created UUID owns the trailing half.
    @discardableResult
    func splitNode(
        at row: Int,
        utf16Offset: Int,
        newNodeID: UUID,
        newLevel: Int
    ) -> Bool {
        guard nodes.indices.contains(row) else { return false }
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: [
                .splitNode(
                    nodeID: nodes[row].id,
                    offset: utf16Offset,
                    newNodeID: newNodeID,
                    newLevel: newLevel
                )
            ],
            label: "Split Node"
        )
        return dispatch(transaction) != nil
    }

    @discardableResult
    func removeNodes(in requestedRows: IndexSet) -> [NodeMarkdownTextKit2Node] {
        guard requestedRows.allSatisfy({ nodes.indices.contains($0) }),
              requestedRows.count < nodes.count else { return [] }
        let rows = Array(requestedRows)
        guard !rows.isEmpty else { return [] }
        let removed = rows.map { nodes[$0] }
        let transaction = NodeMarkdownTransaction(
            baseRevision: revision,
            steps: [.deleteNodes(nodeIDs: removed.map(\.id))],
            label: "Delete Nodes"
        )
        return dispatch(transaction) == nil ? [] : removed
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

    private struct AppliedStep {
        let inverseSteps: [NodeMarkdownTransactionStep]
        let affectedNodeIDs: Set<UUID>
        let structural: Bool
        let mapOperation: NodeMarkdownPositionMapOperation?
    }

    private func applyStep(_ step: NodeMarkdownTransactionStep) throws -> AppliedStep {
        switch step {
        case let .replaceNode(nodeID, replacement):
            guard let row = rowByID[nodeID], nodes.indices.contains(row) else {
                throw NodeMarkdownTransactionError.missingNode(nodeID)
            }
            guard replacement.id == nodeID else {
                throw NodeMarkdownTransactionError.invalidStructure("替换Node不得改变UUID")
            }
            try validateNode(replacement)
            let original = nodes[row]
            if original.isProtectedH3,
               (replacement.level != 3
                || replacement.sourceID != original.sourceID
                || replacement.sourceFile != original.sourceFile) {
                throw NodeMarkdownTransactionError.protectedNode(nodeID)
            }
            nodes[row] = replacement
            if original.level != replacement.level {
                structuralIndex.rebuild(nodes: nodes)
            }
            return AppliedStep(
                inverseSteps: [.replaceNode(nodeID: nodeID, node: original)],
                affectedNodeIDs: [nodeID],
                structural: original.level != replacement.level,
                mapOperation: .replaceText(
                    nodeID: nodeID,
                    oldRange: NSRange(location: 0, length: (original.content as NSString).length),
                    insertedLength: (replacement.content as NSString).length
                )
            )

        case let .replaceText(nodeID, range, replacement):
            guard let row = rowByID[nodeID], nodes.indices.contains(row) else {
                throw NodeMarkdownTransactionError.missingNode(nodeID)
            }
            let source = nodes[row].content as NSString
            guard range.location != NSNotFound,
                  range.location >= 0,
                  range.length >= 0,
                  NSMaxRange(range) <= source.length else {
                throw NodeMarkdownTransactionError.invalidRange(nodeID: nodeID, range: range)
            }
            let removed = source.substring(with: range)
            nodes[row].content = source.replacingCharacters(in: range, with: replacement)
            let insertedLength = (replacement as NSString).length
            return AppliedStep(
                inverseSteps: [.replaceText(
                    nodeID: nodeID,
                    range: NSRange(location: range.location, length: insertedLength),
                    replacement: removed
                )],
                affectedNodeIDs: [nodeID],
                structural: false,
                mapOperation: .replaceText(nodeID: nodeID, oldRange: range, insertedLength: insertedLength)
            )

        case let .setLevel(nodeID, level):
            guard (1...12).contains(level) else {
                throw NodeMarkdownTransactionError.invalidLevel(level)
            }
            guard let row = rowByID[nodeID], nodes.indices.contains(row) else {
                throw NodeMarkdownTransactionError.missingNode(nodeID)
            }
            let originalLevel = nodes[row].level
            if nodes[row].isProtectedH3, level != 3 {
                throw NodeMarkdownTransactionError.protectedNode(nodeID)
            }
            if !nodes[row].sourceID.isEmpty || !nodes[row].sourceFile.isEmpty,
               level != 3 {
                throw NodeMarkdownTransactionError.protectedNode(nodeID)
            }
            nodes[row].level = level
            if originalLevel != level {
                structuralIndex.rebuild(nodes: nodes)
            }
            return AppliedStep(
                inverseSteps: [.setLevel(nodeID: nodeID, level: originalLevel)],
                affectedNodeIDs: [nodeID],
                structural: originalLevel != level,
                mapOperation: nil
            )

        case let .insertNodes(requestedRow, insertedNodes):
            guard (0...nodes.count).contains(requestedRow), !insertedNodes.isEmpty else {
                throw NodeMarkdownTransactionError.invalidStructure("插入Node的位置或内容无效")
            }
            var seen = Set<UUID>()
            for node in insertedNodes {
                try validateNode(node)
                guard rowByID[node.id] == nil, seen.insert(node.id).inserted else {
                    throw NodeMarkdownTransactionError.duplicateNode(node.id)
                }
            }
            nodes.insert(contentsOf: insertedNodes, at: requestedRow)
            rebuildIndex(startingAt: requestedRow)
            return AppliedStep(
                inverseSteps: [.deleteNodes(nodeIDs: insertedNodes.map(\.id))],
                affectedNodeIDs: Set(insertedNodes.map(\.id)),
                structural: true,
                mapOperation: nil
            )

        case let .deleteNodes(nodeIDs):
            guard !nodeIDs.isEmpty else {
                throw NodeMarkdownTransactionError.invalidStructure("删除Node列表为空")
            }
            let rows = try nodeIDs.map { id -> Int in
                guard let row = rowByID[id] else { throw NodeMarkdownTransactionError.missingNode(id) }
                return row
            }.sorted()
            guard rows.count < nodes.count else {
                throw NodeMarkdownTransactionError.invalidStructure("文档必须保留至少一个Node")
            }
            guard zip(rows, rows.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else {
                throw NodeMarkdownTransactionError.invalidStructure("一次删除必须是连续Node范围")
            }
            let firstRow = rows[0]
            let removed = rows.map { nodes[$0] }
            if !allowsProtectedHistoryMutation, removed.contains(where: \.isProtectedH3) {
                throw NodeMarkdownTransactionError.protectedNode(removed.first(where: \.isProtectedH3)!.id)
            }
            let removedIDs = Set(removed.map(\.id))
            let fallbackID = nodes.indices.contains(rows.last! + 1)
                ? nodes[rows.last! + 1].id
                : (firstRow > 0 ? nodes[firstRow - 1].id : nil)
            nodes.removeSubrange(firstRow..<(firstRow + removed.count))
            rebuildIndex(startingAt: firstRow)
            return AppliedStep(
                inverseSteps: [.insertNodes(row: firstRow, nodes: removed)],
                affectedNodeIDs: removedIDs,
                structural: true,
                mapOperation: .delete(nodeIDs: removedIDs, fallbackID: fallbackID)
            )

        case let .splitNode(nodeID, offset, newNodeID, newLevel):
            guard (1...12).contains(newLevel) else {
                throw NodeMarkdownTransactionError.invalidLevel(newLevel)
            }
            guard let row = rowByID[nodeID], nodes.indices.contains(row) else {
                throw NodeMarkdownTransactionError.missingNode(nodeID)
            }
            guard rowByID[newNodeID] == nil else {
                throw NodeMarkdownTransactionError.duplicateNode(newNodeID)
            }
            let original = nodes[row]
            let source = original.content as NSString
            guard (0...source.length).contains(offset) else {
                throw NodeMarkdownTransactionError.invalidRange(
                    nodeID: nodeID,
                    range: NSRange(location: offset, length: 0)
                )
            }
            nodes[row].content = source.substring(to: offset)
            let trailing = NodeMarkdownTextKit2Node(
                id: newNodeID,
                level: newLevel,
                content: source.substring(from: offset),
                sourceID: "",
                sourceFile: ""
            )
            nodes.insert(trailing, at: row + 1)
            rebuildIndex(startingAt: row)
            return AppliedStep(
                inverseSteps: [.joinNodes(leftID: nodeID, rightID: newNodeID)],
                affectedNodeIDs: [nodeID, newNodeID],
                structural: true,
                mapOperation: .split(sourceID: nodeID, offset: offset, trailingID: newNodeID)
            )

        case let .joinNodes(leftID, rightID):
            guard let leftRow = rowByID[leftID], let rightRow = rowByID[rightID] else {
                throw NodeMarkdownTransactionError.missingNode(rowByID[leftID] == nil ? leftID : rightID)
            }
            guard rightRow == leftRow + 1 else {
                throw NodeMarkdownTransactionError.invalidStructure("只能合并相邻Node")
            }
            if !allowsProtectedHistoryMutation,
               nodes[leftRow].isProtectedH3 || nodes[rightRow].isProtectedH3 {
                throw NodeMarkdownTransactionError.protectedNode(
                    nodes[leftRow].isProtectedH3 ? leftID : rightID
                )
            }
            let left = nodes[leftRow]
            let right = nodes[rightRow]
            let leftLength = (left.content as NSString).length
            nodes[leftRow].content += right.content
            nodes.remove(at: rightRow)
            rebuildIndex(startingAt: leftRow)
            return AppliedStep(
                inverseSteps: [
                    .replaceNode(nodeID: leftID, node: left),
                    .insertNodes(row: rightRow, nodes: [right])
                ],
                affectedNodeIDs: [leftID, rightID],
                structural: true,
                mapOperation: .join(leftID: leftID, leftLength: leftLength, rightID: rightID)
            )

        case let .moveNodes(nodeIDs, destinationRow):
            guard !nodeIDs.isEmpty else {
                throw NodeMarkdownTransactionError.invalidStructure("移动Node列表为空")
            }
            let rows = try nodeIDs.map { id -> Int in
                guard let row = rowByID[id] else { throw NodeMarkdownTransactionError.missingNode(id) }
                return row
            }.sorted()
            guard zip(rows, rows.dropFirst()).allSatisfy({ $1 == $0 + 1 }),
                  (0...nodes.count).contains(destinationRow) else {
                throw NodeMarkdownTransactionError.invalidStructure("移动范围或目标位置无效")
            }
            let originalRow = rows[0]
            let moving = Array(nodes[originalRow..<(originalRow + rows.count)])
            nodes.removeSubrange(originalRow..<(originalRow + rows.count))
            let adjustedDestination = destinationRow > originalRow
                ? destinationRow - rows.count
                : destinationRow
            let insertionRow = max(0, min(adjustedDestination, nodes.count))
            nodes.insert(contentsOf: moving, at: insertionRow)
            rebuildIndex(startingAt: min(originalRow, insertionRow))
            return AppliedStep(
                inverseSteps: [.moveNodes(nodeIDs: nodeIDs, destinationRow: originalRow)],
                affectedNodeIDs: Set(nodeIDs),
                structural: true,
                mapOperation: nil
            )
        }
    }

    private func earliestAffectedRow(for steps: [NodeMarkdownTransactionStep]) -> Int? {
        steps.compactMap { step in
            switch step {
            case let .replaceNode(nodeID, _), let .replaceText(nodeID, _, _), let .setLevel(nodeID, _):
                return rowByID[nodeID]
            case let .insertNodes(row, _):
                return row
            case let .deleteNodes(nodeIDs), let .moveNodes(nodeIDs, _):
                return nodeIDs.compactMap { rowByID[$0] }.min()
            case let .splitNode(nodeID, _, _, _):
                return rowByID[nodeID]
            case let .joinNodes(leftID, rightID):
                return [rowByID[leftID], rowByID[rightID]].compactMap { $0 }.min()
            }
        }.min()
    }

    private func insertedNodeIDs(in steps: [NodeMarkdownTransactionStep]) -> Set<UUID> {
        steps.reduce(into: Set<UUID>()) { result, step in
            switch step {
            case let .insertNodes(_, nodes): result.formUnion(nodes.map(\.id))
            case let .splitNode(_, _, newNodeID, _): result.insert(newNodeID)
            default: break
            }
        }
    }

    private func deletedNodeIDs(in steps: [NodeMarkdownTransactionStep]) -> Set<UUID> {
        steps.reduce(into: Set<UUID>()) { result, step in
            switch step {
            case let .deleteNodes(nodeIDs): result.formUnion(nodeIDs)
            case let .joinNodes(_, rightID): result.insert(rightID)
            default: break
            }
        }
    }

    private func contentNodeIDs(in steps: [NodeMarkdownTransactionStep]) -> Set<UUID> {
        steps.reduce(into: Set<UUID>()) { result, step in
            switch step {
            case let .replaceNode(nodeID, _), let .replaceText(nodeID, _, _): result.insert(nodeID)
            case let .splitNode(nodeID, _, newNodeID, _):
                result.insert(nodeID)
                result.insert(newNodeID)
            case let .joinNodes(leftID, _): result.insert(leftID)
            case let .insertNodes(_, nodes): result.formUnion(nodes.map(\.id))
            default: break
            }
        }
    }

    private func validateNode(_ node: NodeMarkdownTextKit2Node) throws {
        guard (1...12).contains(node.level) else {
            throw NodeMarkdownTransactionError.invalidLevel(node.level)
        }
        let hasSourceID = !node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSourceFile = !node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasSourceID == hasSourceFile else {
            throw NodeMarkdownTransactionError.invalidStructure("SourceID与SourceFile必须成对存在")
        }
        guard !hasSourceID || node.level == 3 else {
            throw NodeMarkdownTransactionError.invalidStructure("只有H3可以持有母本来源")
        }
    }

    private func rebuildIndex(startingAt start: Int = 0) {
        if start <= 0 {
            rowByID.removeAll(keepingCapacity: true)
        } else {
            rowByID = rowByID.filter { $0.value < start }
        }
        for row in max(0, start)..<nodes.count { rowByID[nodes[row].id] = row }
        structuralIndex.rebuild(nodes: nodes)
    }

    @discardableResult
    private func repairIndicesIfNeeded() -> Bool {
        guard !nodes.isEmpty,
              NodeMarkdownRuntimeInvariant.duplicateNodeID(in: nodes) == nil else {
            lastTransactionError = .invalidStructure("Node文档不变量失败：文档为空或UUID重复")
            return false
        }
        guard NodeMarkdownRuntimeInvariant.rowIndexIsValid(nodes: nodes, rowByID: rowByID) else {
            rebuildIndex()
            return NodeMarkdownRuntimeInvariant.rowIndexIsValid(nodes: nodes, rowByID: rowByID)
        }
        return true
    }

    /// 单Node内容修改不会增删、换位或改UUID。逐键扫描全部Node既不能增加
    /// 这类事务的证明力，又让Debug输入速度随文档增长；这里只证明被改Node与索引仍一致。
    private func repairUpdatedNodeIndexIfNeeded(at row: Int) {
        guard nodes.indices.contains(row), rowByID.count == nodes.count,
              rowByID[nodes[row].id] == row else {
            rebuildIndex()
            return
        }
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
