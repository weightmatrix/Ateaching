// PIPELINE MARKER: NodeMarkdown ProseMirror-style runtime contracts.
import Foundation

/// Every transaction declares what became invalid. Consumers must use this set
/// instead of inferring refresh scope from changed strings or row counts.
struct NodeMarkdownTransactionImpact: Equatable {
    let contentNodeIDs: Set<UUID>
    let layoutNodeIDs: Set<UUID>
    let insertedNodeIDs: Set<UUID>
    let deletedNodeIDs: Set<UUID>
    let structuralRange: Range<Int>?
    let numberingStartRow: Int?

    static let none = NodeMarkdownTransactionImpact(
        contentNodeIDs: [],
        layoutNodeIDs: [],
        insertedNodeIDs: [],
        deletedNodeIDs: [],
        structuralRange: nil,
        numberingStartRow: nil
    )

    var isStructural: Bool { structuralRange != nil }
}

/// Deterministic transaction traces are intentionally model-only. They can be
/// replayed without AppKit to prove that unrelated Node identities never change.
struct NodeMarkdownReplayFrame: Equatable {
    let revision: UInt64
    let nodes: [NodeMarkdownTextKit2Node]
    let nodeRevisions: [UUID: UInt64]
}

enum NodeMarkdownTransactionReplayer {
    static func replay(
        text: String,
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        stepBatches: [[NodeMarkdownTransactionStep]]
    ) -> [NodeMarkdownReplayFrame]? {
        let state = NodeMarkdownTextKit2DocumentState(text: text, rowMetadata: rowMetadata)
        var frames = [frame(from: state)]
        for (index, steps) in stepBatches.enumerated() {
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: steps,
                recordsHistory: false,
                label: "Replay \(index)"
            )
            guard state.dispatch(transaction) != nil else { return nil }
            frames.append(frame(from: state))
        }
        return frames
    }

    private static func frame(from state: NodeMarkdownTextKit2DocumentState) -> NodeMarkdownReplayFrame {
        let snapshot = state.snapshot
        return NodeMarkdownReplayFrame(
            revision: snapshot.revision,
            nodes: snapshot.nodes,
            nodeRevisions: snapshot.nodeRevisions
        )
    }
}

enum NodeMarkdownRuntimeInvariant {
    static func duplicateNodeID(in nodes: [NodeMarkdownTextKit2Node]) -> UUID? {
        var seen = Set<UUID>()
        for node in nodes where !seen.insert(node.id).inserted { return node.id }
        return nil
    }

    static func rowIndexIsValid(
        nodes: [NodeMarkdownTextKit2Node],
        rowByID: [UUID: Int]
    ) -> Bool {
        guard rowByID.count == nodes.count else { return false }
        return nodes.enumerated().allSatisfy { rowByID[$0.element.id] == $0.offset }
    }
}
