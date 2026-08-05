// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

/// 结构编辑后的焦点不用全文字符位置保存，而是绑定Node UUID与Node内偏移。
/// Enter、Backspace、Tab、撤销引起前文长度变化时，焦点仍属于原定Node。
struct NodeMarkdownTextKit2FocusAnchor {
    let nodeID: String
    let fallbackRowIndex: Int
    let contentOffset: Int
    let selectionLength: Int
}

extension NodeMarkdownTextKit2Coordinator {
    func rememberFocus(
        in textView: NodeMarkdownTextKit2TextView,
        selection: NSRange? = nil
    ) {
        let targetSelection = selection ?? textView.selectedRange()
        guard let rowIndex = rowIndex(for: targetSelection.location),
              rowMetadata.indices.contains(rowIndex),
              rowLayouts.indices.contains(rowIndex) else {
            pendingFocusAnchor = nil
            return
        }
        let contentRange = rowLayouts[rowIndex].contentRange
        pendingFocusAnchor = NodeMarkdownTextKit2FocusAnchor(
            nodeID: rowMetadata[rowIndex].nodeID,
            fallbackRowIndex: rowIndex,
            contentOffset: max(0, targetSelection.location - contentRange.location),
            selectionLength: targetSelection.length
        )
    }

    @discardableResult
    func restoreRememberedFocus(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        guard let anchor = pendingFocusAnchor else { return false }
        let rowIndex = rowMetadata.firstIndex { !$0.nodeID.isEmpty && $0.nodeID == anchor.nodeID }
            ?? (rowLayouts.indices.contains(anchor.fallbackRowIndex) ? anchor.fallbackRowIndex : nil)
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else {
            pendingFocusAnchor = nil
            return false
        }

        let contentRange = rowLayouts[rowIndex].contentRange
        let location = contentRange.location + min(anchor.contentOffset, contentRange.length)
        let length = min(anchor.selectionLength, max(0, NSMaxRange(contentRange) - location))
        let restoredSelection = NSRange(location: location, length: length)

        isApplyingStyleUpdate = true
        textView.setSelectedRange(textView.clampedEditableSelection(restoredSelection))
        isApplyingStyleUpdate = false
        enterEditingRow(rowIndex, from: textView)
        reportActiveRowIfNeeded(from: textView)
        return true
    }

    func forgetRememberedFocus() {
        pendingFocusAnchor = nil
    }

    private func rowIndex(for location: Int) -> Int? {
        guard !rowLayouts.isEmpty else { return nil }
        let documentLength = NSMaxRange(rowLayouts.last?.range ?? NSRange(location: 0, length: 0))
        let safeLocation = max(0, min(location, documentLength))
        if let exact = lineIndexForLocation(safeLocation) {
            return exact
        }
        if safeLocation == documentLength {
            return rowLayouts.indices.last
        }
        return nil
    }
}
#endif
