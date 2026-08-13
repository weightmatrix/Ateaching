// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    private struct StructuralViewportAnchor {
        let rowIndex: Int
        let offsetFromViewportTop: CGFloat
    }

    func performLocalNewlineTransaction(
        in textView: NodeMarkdownTextKit2TextView,
        sourceRow: Int,
        splitOffset: Int,
        replacementRange: NSRange,
        replacement: String,
        newCursor: Int,
        newLevel: Int,
        preservesSourceNodeContent: Bool
    ) -> Bool {
        guard rowLayouts.indices.contains(sourceRow),
              rowMetadata.indices.contains(sourceRow),
              documentState.node(at: sourceRow) != nil,
              replacementRange.exact(toLength: textView.nodeTextStorage.length) != nil else { return false }

        let scrollView = textView.enclosingScrollView
        let viewportAnchor = structuralViewportAnchor(
            for: sourceRow,
            in: textView,
            scrollView: scrollView
        )
        textView.suppressesAutomaticSelectionScrolling = true
        defer {
            restoreViewportAfterStructuralEdit(
                viewportAnchor,
                scrollView: scrollView,
                textView: textView
            )
        }

        // The structural snapshot below already contains the committed leading Node.
        // Notifying the parent here would serialize the entire document before the split
        // and then parse it again when the structural snapshot arrives.
        commitActiveNodeSession(reason: "回车结构事务前", notifyExternal: false)
        let newNodeID = UUID()
        let stateUpdated: Bool
        if preservesSourceNodeContent {
            stateUpdated = documentState.insertNode(
                NodeMarkdownTextKit2Node(
                    id: newNodeID,
                    level: newLevel,
                    content: "",
                    sourceID: "",
                    sourceFile: ""
                ),
                at: sourceRow + 1
            ) != nil
        } else {
            stateUpdated = documentState.splitNode(
                at: sourceRow,
                utf16Offset: splitOffset,
                newNodeID: newNodeID,
                newLevel: newLevel
            )
        }
        guard stateUpdated else { return false }
        registerCoreTransactionUndo(in: textView)
        rowMetadata = documentState.snapshot.rowMetadata

        let replacementAttributes = textView.typingAttributes(
            for: rowLayouts[sourceRow],
            documentStyle: documentStyle
        )
        isApplyingStyleUpdate = true
        let replaced = textView.replaceSourceTextWithoutSelecting(
            in: replacementRange,
            with: NSAttributedString(string: replacement, attributes: replacementAttributes)
        )
        isApplyingStyleUpdate = false
        guard replaced else { return false }

        let value = textView.documentString()
        if !updateRowLayoutsAfterSplit(in: textView, sourceRow: sourceRow, value: value) {
            // This is a correctness fallback for a violated seam contract, not the normal path.
            NodeMarkdownDiagnostic41.event(
                "回车局部接缝验证失败，执行安全完整布局 sourceRow=\(sourceRow) nodes=\(rowMetadata.count)"
            )
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        }

        let targetRow = sourceRow + 1
        let previousEditingRow = editingRowIndex
        editingRowIndex = targetRow
        textView.nodeMarkdownEditingRowIndex = targetRow
        refreshRowStyles(
            in: textView,
            rows: Set([previousEditingRow, sourceRow, targetRow, targetRow + 1].compactMap { $0 })
        )
        updateTypingAttributesForRow(targetRow, in: textView)

        let requestedSelection = NSRange(location: newCursor, length: 0)
        guard let selection = textView.clampedEditableSelection(requestedSelection) else { return false }
        isApplyingStyleUpdate = true
        textView.setSelectedRange(selection)
        isApplyingStyleUpdate = false
        updateTypingAttributes(for: textView)
        beginNodeSessionIfNeeded(at: targetRow)
        synchronizeActiveNodeSession()
        reportActiveRowIfNeeded(from: textView)

        localEditRevision &+= 1
        lastPublishedLocalText = value
        scheduleDocumentSnapshotPublication()
        return true
    }

    private func updateTypingAttributesForRow(
        _ row: Int,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        guard rowLayouts.indices.contains(row) else { return }
        let attributes = textView.typingAttributes(
            for: rowLayouts[row],
            documentStyle: documentStyle
        )
        textView.nodeMarkdownTypingAttributes = attributes
        textView.typingAttributes = attributes
    }

    private func restoreViewportAfterStructuralEdit(
        _ anchor: StructuralViewportAnchor?,
        scrollView: NSScrollView?,
        textView: NodeMarkdownTextKit2TextView
    ) {
        guard let anchor, let scrollView else {
            textView.suppressesAutomaticSelectionScrolling = false
            return
        }
        let restore = { [weak self, weak textView, weak scrollView] in
            guard let self, let textView, let scrollView,
                  self.rowLayouts.indices.contains(anchor.rowIndex),
                  let rowY = self.layoutFragmentMinY(
                    for: self.rowLayouts[anchor.rowIndex],
                    in: textView
                  ) else { return }
            let clipView = scrollView.contentView
            var bounds = clipView.bounds
            bounds.origin.y = rowY - anchor.offsetFromViewportTop
            clipView.setBoundsOrigin(clipView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(clipView)
        }
        restore()
        DispatchQueue.main.async { [weak textView] in
            restore()
            DispatchQueue.main.async {
                restore()
                textView?.suppressesAutomaticSelectionScrolling = false
            }
        }
    }

    private func structuralViewportAnchor(
        for rowIndex: Int,
        in textView: NodeMarkdownTextKit2TextView,
        scrollView: NSScrollView?
    ) -> StructuralViewportAnchor? {
        guard rowLayouts.indices.contains(rowIndex),
              let viewportTop = scrollView?.contentView.bounds.minY,
              let rowY = layoutFragmentMinY(for: rowLayouts[rowIndex], in: textView) else {
            return nil
        }
        return StructuralViewportAnchor(
            rowIndex: rowIndex,
            offsetFromViewportTop: rowY - viewportTop
        )
    }

    private func layoutFragmentMinY(
        for rowLayout: NodeMarkdownTextKit2RowLayout,
        in textView: NodeMarkdownTextKit2TextView
    ) -> CGFloat? {
        let documentStart = textView.nodeTextContentStorage.documentRange.location
        guard let location = textView.nodeTextContentStorage.location(
            documentStart,
            offsetBy: rowLayout.range.location
        ),
        let fragment = textView.nodeTextLayoutManager.textLayoutFragment(for: location) else {
            return nil
        }
        return textView.textContainerOrigin.y + fragment.layoutFragmentFrame.minY
    }

    /// 图片文件已经由父页面落盘；正文链接仍必须作为当前行的本地编辑写入。
    /// 这与普通输入共用焦点、撤销、离行渲染和发布链，不触发外部全文同步。
    func applyPreparedImageText(
        _ updatedRowText: String,
        at rowIndex: Int,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        rebuildRowLayoutsIfNeeded(from: textView)
        guard rowLayouts.indices.contains(rowIndex) else { return }
        let contentRange = rowLayouts[rowIndex].contentRange
        let endLocation = contentRange.location + (updatedRowText as NSString).length
        let selectedRange = NSRange(location: endLocation, length: 0)
        let scrollView = textView.enclosingScrollView
        let originalOrigin = scrollView?.contentView.bounds.origin
        textView.suppressesAutomaticSelectionScrolling = true

        replaceSourceText(
            in: textView,
            range: contentRange,
            replacement: updatedRowText,
            selectedRange: selectedRange
        )
        enterEditingRow(rowIndex, from: textView)
        restoreImagePasteViewport(
            origin: originalOrigin,
            scrollView: scrollView,
            textView: textView
        )
    }

    private func restoreImagePasteViewport(
        origin: NSPoint?,
        scrollView: NSScrollView?,
        textView: NodeMarkdownTextKit2TextView
    ) {
        guard let origin, let scrollView else {
            textView.suppressesAutomaticSelectionScrolling = false
            return
        }
        let restore = { [weak scrollView] in
            guard let scrollView else { return }
            let clipView = scrollView.contentView
            var bounds = clipView.bounds
            bounds.origin = origin
            clipView.setBoundsOrigin(clipView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(clipView)
        }
        restore()
        DispatchQueue.main.async { [weak textView] in
            restore()
            DispatchQueue.main.async {
                restore()
                textView?.suppressesAutomaticSelectionScrolling = false
            }
        }
    }

    func replaceSourceText(
        in textView: NodeMarkdownTextKit2TextView,
        range: NSRange,
        replacement: String,
        selectedRange: NSRange,
        updatedRowMetadata: [NodeMarkdownTextKitRowMetadata]? = nil
    ) {
        // 结构操作会创建或移动Node。旧Node草稿必须先按UUID提交，
        // 否则新行的行号会在旧Node数组上解析，导致焦点和H3归属错位。
        if updatedRowMetadata != nil {
            commitActiveNodeSession(reason: "结构事务前")
        }
        registerUndoSnapshot(for: textView)
        if let updatedRowMetadata {
            rowMetadata = updatedRowMetadata
        }
        isApplyingStyleUpdate = true
        textView.replaceSourceText(in: range, with: replacement, selectedRange: selectedRange, documentStyle: documentStyle)
        isApplyingStyleUpdate = false
        let value = textView.documentString()
        rebuildRowLayouts(from: textView, value: value)
        // 先让新正文、UUID和层级成为唯一Node文档，再按新UUID恢复焦点。
        // 这保证新行第一次输入时，活动草稿就是新行本身。
        publishTextChange(value, structural: updatedRowMetadata != nil)
        rememberFocus(in: textView, selection: selectedRange)
        restoreRememberedFocus(in: textView)
        reportActiveRowIfNeeded(from: textView)
        updateTypingAttributes(for: textView)
        validateTextKit2State(in: textView, deep: true)
    }

    func registerUndoSnapshot(for textView: NodeMarkdownTextKit2TextView) {
        guard let undoManager = textView.undoManager else { return }
        let snapshot = textView.documentString()
        let selection = textView.selectedRange()
        let metadataSnapshot = rowMetadata
        undoManager.registerUndo(withTarget: self) { [weak textView] target in
            guard let textView else { return }
            target.restoreUndoSnapshot(
                snapshot,
                rowMetadata: metadataSnapshot,
                selection: selection,
                in: textView
            )
        }
        undoManager.setActionName("NodeMarkdown Edit")
    }

    func registerCoreTransactionUndo(in textView: NodeMarkdownTextKit2TextView) {
        guard documentState.canUndo, let undoManager = textView.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak textView] target in
            guard let textView else { return }
            target.performCoreTransactionUndo(in: textView)
        }
        undoManager.setActionName("NodeMarkdown Structure")
    }

    private func performCoreTransactionUndo(in textView: NodeMarkdownTextKit2TextView) {
        guard documentState.undo() != nil else { return }
        installCoreDocumentProjection(in: textView)
        textView.undoManager?.registerUndo(withTarget: self) { [weak textView] target in
            guard let textView else { return }
            target.performCoreTransactionRedo(in: textView)
        }
        textView.undoManager?.setActionName("NodeMarkdown Structure")
    }

    private func performCoreTransactionRedo(in textView: NodeMarkdownTextKit2TextView) {
        guard documentState.redo() != nil else { return }
        installCoreDocumentProjection(in: textView)
        textView.undoManager?.registerUndo(withTarget: self) { [weak textView] target in
            guard let textView else { return }
            target.performCoreTransactionUndo(in: textView)
        }
        textView.undoManager?.setActionName("NodeMarkdown Structure")
    }

    private func installCoreDocumentProjection(in textView: NodeMarkdownTextKit2TextView) {
        let snapshot = documentState.snapshot
        let selectedRanges = textView.selectedRanges
        rowMetadata = snapshot.rowMetadata
        isApplyingStyleUpdate = true
        textView.replaceDocumentText(
            snapshot.plainText,
            documentStyle: documentStyle,
            selectedRanges: selectedRanges
        )
        isApplyingStyleUpdate = false
        rebuildRowLayouts(from: textView, value: snapshot.plainText)
        localEditRevision &+= 1
        lastPublishedLocalText = snapshot.plainText
        scheduleDocumentSnapshotPublication()
        syncEditingRowWithSelection(in: textView)
    }

    private func restoreUndoSnapshot(
        _ snapshot: String,
        rowMetadata metadataSnapshot: [NodeMarkdownTextKitRowMetadata],
        selection: NSRange,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        let redoSnapshot = textView.documentString()
        let redoSelection = textView.selectedRange()
        let redoMetadata = rowMetadata
        textView.undoManager?.registerUndo(withTarget: self) { [weak textView] target in
            guard let textView else { return }
            target.restoreUndoSnapshot(
                redoSnapshot,
                rowMetadata: redoMetadata,
                selection: redoSelection,
                in: textView
            )
        }

        isApplyingStyleUpdate = true
        rowMetadata = metadataSnapshot
        textView.replaceDocumentText(
            snapshot,
            documentStyle: documentStyle,
            selectedRanges: [NSValue(range: selection)]
        )
        isApplyingStyleUpdate = false
        let value = textView.documentString()
        rebuildRowLayouts(from: textView, value: value)
        rememberFocus(in: textView, selection: selection)
        restoreRememberedFocus(in: textView)
        textView.needsDisplay = true
        reportActiveRowIfNeeded(from: textView)
        publishTextChange(value, structural: true)
        updateTypingAttributes(for: textView)
        validateTextKit2State(in: textView, deep: true)
    }

    func publishTextChange(_ value: String, structural: Bool = false) {
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("publishTextChange内部", since: diagnosticStart) }
        localEditRevision &+= 1
        lastPublishedLocalText = value
        let nodeUpdateStart = NodeMarkdownDiagnostic35.now()
        let updatedIncrementally: Bool = {
            guard !structural,
                  let row = currentRowIndexForPublishedText(),
                  rowLayouts.indices.contains(row),
                  rowMetadata.indices.contains(row),
                  documentState.nodes.count == rowLayouts.count else { return false }
            let source = value as NSString
            let contentRange = rowLayouts[row].contentRange
            guard let safeRange = contentRange.exact(toLength: source.length) else { return false }
            return documentState.updateRow(
                row,
                content: source.substring(with: safeRange),
                metadata: rowMetadata[row]
            )
        }()
        recordDiagnostic35Duration("Node单行状态更新", since: nodeUpdateStart)
        if !updatedIncrementally {
            recordDiagnostic35Count("Node全文替换")
            recordDiagnostic35Count("Node全文替换处理Node", amount: rowMetadata.count)
            guard documentState.replace(text: value, rowMetadata: rowMetadata) else {
                NodeMarkdownTextKit2Diagnostics.log(
                    "拒绝发布Node文档：\(documentState.lastValidationError?.description ?? "Node数据契约失败")。"
                )
                return
            }
            rowMetadata = documentState.snapshot.rowMetadata
        } else {
            recordDiagnostic35Count("Node单行更新")
        }
        synchronizeActiveNodeSession()
        if structural, onDocumentSnapshot != nil {
            publishDocumentSnapshot()
        } else if onDocumentSnapshot != nil {
            // 普通输入只保留活动Node草稿。离行或保存时按UUID提交，禁止每键构造全文快照。
            return
        } else if let onTextChangeWithRowMetadata {
            onTextChangeWithRowMetadata(value, rowMetadata)
        } else {
            text.wrappedValue = value
            onTextChange?(value)
        }
    }

    private func currentRowIndexForPublishedText() -> Int? {
        guard let textView else { return activeNodeSession.flatMap { documentState.row(for: $0.nodeID) } }
        return currentRowIndex(in: textView)
    }
}
#endif
