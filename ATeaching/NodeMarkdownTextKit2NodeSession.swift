// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func beginNodeSessionIfNeeded(at row: Int) {
        guard let node = documentState.node(at: row) else { return }
        if activeNodeSession?.nodeID == node.id {
            lifecycleState = .editing(nodeID: node.id, revision: documentState.revision)
            return
        }
        commitActiveNodeSession()
        activeNodeSession = NodeMarkdownTextKit2ActiveNodeSession(node: node)
        lifecycleState = .editing(nodeID: node.id, revision: documentState.revision)
        onEditingDraftDirtyChange?(false)
    }

    func synchronizeActiveNodeSession() {
        guard var session = activeNodeSession,
              let row = documentState.row(for: session.nodeID),
              let node = documentState.node(at: row) else { return }
        let wasDirty = session.isDirty
        session.draft = node
        activeNodeSession = session
        if wasDirty != session.isDirty {
            onEditingDraftDirtyChange?(session.isDirty)
        }
    }

    func commitActiveNodeSession() {
        guard let session = activeNodeSession else { return }
        if session.isDirty {
            onCommitEditingNode?(
                NodeMarkdownLegacyEditingNodeDraft(
                    nodeID: session.draft.id.uuidString,
                    level: session.draft.level,
                    content: session.draft.content,
                    sourceID: session.draft.sourceID,
                    sourceFile: session.draft.sourceFile
                )
            )
        }
        activeNodeSession = nil
        lifecycleState = .ready(revision: documentState.revision)
        onEditingDraftDirtyChange?(false)
    }

    func publishDocumentSnapshot() {
        documentSnapshotRevision &+= 1
        onDocumentSnapshot?(
            NodeMarkdownLegacyDocumentSnapshot(
                sessionID: documentSnapshotSessionID,
                revision: documentSnapshotRevision,
                rows: documentState.snapshotRows()
            )
        )
    }
}
#endif
