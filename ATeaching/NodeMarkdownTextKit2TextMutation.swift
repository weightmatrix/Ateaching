// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
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
        registerUndoSnapshot(for: textView)
        if let updatedRowMetadata {
            rowMetadata = updatedRowMetadata
        }
        isApplyingStyleUpdate = true
        textView.replaceSourceText(in: range, with: replacement, selectedRange: selectedRange, documentStyle: documentStyle)
        isApplyingStyleUpdate = false
        let value = textView.documentString()
        rebuildRowLayouts(from: textView, value: value)
        rememberFocus(in: textView, selection: selectedRange)
        restoreRememberedFocus(in: textView)
        reportActiveRowIfNeeded(from: textView)
        publishTextChange(value, structural: updatedRowMetadata != nil)
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
        localEditRevision &+= 1
        lastPublishedLocalText = value
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
        if !updatedIncrementally {
            guard documentState.replace(text: value, rowMetadata: rowMetadata) else {
                NodeMarkdownTextKit2Diagnostics.log(
                    "拒绝发布Node文档：\(documentState.lastValidationError?.description ?? "Node数据契约失败")。"
                )
                return
            }
            rowMetadata = documentState.snapshot.rowMetadata
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
