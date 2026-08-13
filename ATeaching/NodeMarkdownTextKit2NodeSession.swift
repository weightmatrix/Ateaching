// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// NSTextView的选区通知可能晚于第一笔文字修改。输入事务必须先用实际修改范围
    /// 锁定Node，确保会话基线来自修改前的documentState，而不是修改后的TextStorage。
    func prepareNodeSessionForTextChange(affectedRange: NSRange) {
        guard let row = lineIndexForRange(affectedRange),
              let node = documentState.node(at: row) else { return }
        guard activeNodeSession?.nodeID != node.id else { return }

        NodeMarkdownDiagnostic26.log(
            "输入前锁定 Node=\(NodeMarkdownDiagnostic26.shortID(node.id.uuidString)) "
                + "row=\(row) range={\(affectedRange.location),\(affectedRange.length)}"
        )
        beginNodeSessionIfNeeded(at: row)
    }

    func beginNodeSessionIfNeeded(at row: Int) {
        guard let node = documentState.node(at: row) else { return }
        if activeNodeSession?.nodeID == node.id {
            lifecycleState = .editing(nodeID: node.id, revision: documentState.revision)
            return
        }
        commitActiveNodeSession(reason: "切换Node")
        activeNodeSession = NodeMarkdownTextKit2ActiveNodeSession(node: node)
        lifecycleState = .editing(nodeID: node.id, revision: documentState.revision)
        onEditingDraftDirtyChange?(false)
        NodeMarkdownDiagnostic26.log(
            "会话开始 Node=\(NodeMarkdownDiagnostic26.shortID(node.id.uuidString)) "
                + "level=\(node.level) SourceID空=\(node.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) "
                + "SourceFile空=\(node.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) "
                + "基线=\(NodeMarkdownDiagnostic26.textSummary(node.content))"
        )
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
            NodeMarkdownDiagnostic26.log(
                "会话变化 Node=\(NodeMarkdownDiagnostic26.shortID(session.nodeID.uuidString)) "
                    + "dirty=\(session.isDirty) level \(session.baseline.level)->\(session.draft.level) "
                    + "文字 \(NodeMarkdownDiagnostic26.textSummary(session.baseline.content)) -> "
                    + "\(NodeMarkdownDiagnostic26.textSummary(session.draft.content))"
            )
        }
    }

    func commitActiveNodeSession(
        reason: String,
        keepingSession: Bool = false,
        notifyExternal: Bool = true
    ) {
        guard let session = activeNodeSession else { return }
        let isSourceLessH3 = session.draft.level == 3
            && session.draft.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && session.draft.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // 会话内的dirty只负责即时显示，不能作为是否交给外层的闸门。
        // AppKit可能先送文字修改、后送选区通知；即使基线曾经建立得过晚，
        // 外层仍可按UUID与持久文档做最终比较，避免漏保存和漏收脏包。
        let shouldCommit = notifyExternal
        NodeMarkdownDiagnostic26.log(
            "会话提交 原因=\(reason) Node=\(NodeMarkdownDiagnostic26.shortID(session.nodeID.uuidString)) "
                + "dirty=\(session.isDirty) 无来源H3=\(isSourceLessH3) 发送外层=\(shouldCommit) "
                + "level \(session.baseline.level)->\(session.draft.level) "
                + "文字 \(NodeMarkdownDiagnostic26.textSummary(session.baseline.content)) -> "
                + "\(NodeMarkdownDiagnostic26.textSummary(session.draft.content))"
        )
        if shouldCommit {
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
        if keepingSession,
           let row = documentState.row(for: session.nodeID),
           let committedNode = documentState.node(at: row) {
            activeNodeSession = NodeMarkdownTextKit2ActiveNodeSession(node: committedNode)
            lifecycleState = .editing(nodeID: committedNode.id, revision: documentState.revision)
            NodeMarkdownDiagnostic26.log(
                "会话重建基线 Node=\(NodeMarkdownDiagnostic26.shortID(committedNode.id.uuidString)) "
                    + "新基线=\(NodeMarkdownDiagnostic26.textSummary(committedNode.content))"
            )
        } else {
            activeNodeSession = nil
            lifecycleState = .ready(revision: documentState.revision)
        }
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

    /// Structural edits remain authoritative in DocumentState immediately, while the
    /// SwiftUI projection is coalesced until the command has returned. This prevents a
    /// parent view update from re-entering TextKit in the middle of Enter/Tab handling.
    func scheduleDocumentSnapshotPublication() {
        pendingStructuralSnapshotGeneration &+= 1
        let generation = pendingStructuralSnapshotGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.pendingStructuralSnapshotGeneration == generation else { return }
            self.publishDocumentSnapshot()
        }
    }
}
#endif
