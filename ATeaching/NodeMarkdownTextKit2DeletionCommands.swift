// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func handleDeleteBackward(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        rebuildRowLayoutsIfNeeded(from: textView)
        let sourceText = textView.documentString() as NSString
        let selection = textView.selectedRange()
        guard sourceText.length > 0 else { return false }
        if hasDeletionSelection(in: textView) {
            return blocksCompleteProtectedH3Deletion(in: textView)
        }

        guard let currentLineIndex = currentRowIndex(in: textView),
              rowLayouts.indices.contains(currentLineIndex) else { return false }
        let currentContentRange = rowLayouts[currentLineIndex].contentRange
        guard selection.location <= currentContentRange.location else { return false }
        if currentLineIndex == 0 { return true }
        if rowLayouts.indices.contains(currentLineIndex), rowLayouts[currentLineIndex].isProtectedH3 {
            showProtectedH3Alert()
            return true
        }

        let previousContentRange = rowLayouts[currentLineIndex - 1].contentRange
        let previousContent = sourceText.substring(with: previousContentRange)
        let currentContent = sourceText.substring(with: currentContentRange)
        let replaceStart = previousContentRange.location
        let replaceEnd = NSMaxRange(currentContentRange)
        let replaceRange = NSRange(location: replaceStart, length: max(0, replaceEnd - replaceStart))
        let newCursor = previousContentRange.location + (previousContent as NSString).length
        guard let previousID = UUID(uuidString: rowMetadata[currentLineIndex - 1].nodeID),
              let currentID = UUID(uuidString: rowMetadata[currentLineIndex].nodeID) else { return false }
        commitActiveNodeSession(reason: "合并Node事务前", notifyExternal: false)
        let transaction = NodeMarkdownTransaction(
            baseRevision: documentState.revision,
            steps: [.joinNodes(leftID: previousID, rightID: currentID)],
            label: "Join Nodes"
        )
        guard documentState.dispatch(transaction) != nil else {
            if documentState.lastTransactionError == .protectedNode(previousID)
                || documentState.lastTransactionError == .protectedNode(currentID) {
                showProtectedH3Alert()
                return true
            }
            return false
        }
        registerCoreTransactionUndo(in: textView)
        rowMetadata = documentState.snapshot.rowMetadata
        isApplyingStyleUpdate = true
        textView.replaceSourceText(
            in: replaceRange,
            with: previousContent + currentContent,
            selectedRange: NSRange(location: newCursor, length: 0),
            documentStyle: documentStyle
        )
        isApplyingStyleUpdate = false
        let value = textView.documentString()
        rebuildRowLayouts(from: textView, value: value, applyStyles: false)
        refreshRowStyles(
            in: textView,
            rows: Set([currentLineIndex - 1, currentLineIndex])
        )
        localEditRevision &+= 1
        lastPublishedLocalText = value
        scheduleDocumentSnapshotPublication()
        syncEditingRowWithSelection(in: textView)
        return true
    }

    func handleDeleteForward(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        if hasDeletionSelection(in: textView) {
            return blocksCompleteProtectedH3Deletion(in: textView)
        }
        guard let row = currentRowIndex(in: textView),
              rowLayouts.indices.contains(row),
              rowLayouts.indices.contains(row + 1),
              textView.selectedRange().location >= NSMaxRange(rowLayouts[row].contentRange),
              rowLayouts[row + 1].isProtectedH3 else { return false }
        showProtectedH3Alert()
        return true
    }

    private func hasDeletionSelection(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        textView.selectedRanges.contains { $0.rangeValue.length > 0 }
    }
}
#endif
