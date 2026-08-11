// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

/// 结构编辑后的焦点不用全文字符位置保存，而是绑定Node UUID与Node内偏移。
/// Enter、Backspace、Tab、撤销引起前文长度变化时，焦点仍属于原定Node。
struct NodeMarkdownTextKit2FocusAnchor {
    let nodeID: String
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
        guard let lastRange = rowLayouts.last?.range else {
            pendingFocusAnchor = nil
            return
        }
        let documentLength = NSMaxRange(lastRange)
        guard targetSelection.exact(toLength: documentLength) != nil,
              targetSelection.location >= contentRange.location,
              NSMaxRange(targetSelection) <= NSMaxRange(contentRange) else {
            pendingFocusAnchor = nil
            return
        }
        pendingFocusAnchor = NodeMarkdownTextKit2FocusAnchor(
            nodeID: rowMetadata[rowIndex].nodeID,
            contentOffset: targetSelection.location - contentRange.location,
            selectionLength: targetSelection.length
        )
    }

    @discardableResult
    func restoreRememberedFocus(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        guard let anchor = pendingFocusAnchor else { return false }
        // 焦点锚点只属于一次结构事务。普通输入后的SwiftUI回写不能反复使用旧锚点。
        pendingFocusAnchor = nil
        let rowIndex = rowMetadata.firstIndex { $0.nodeID == anchor.nodeID }
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else {
            return false
        }

        let contentRange = rowLayouts[rowIndex].contentRange
        guard anchor.contentOffset >= 0,
              anchor.contentOffset <= contentRange.length else {
            return false
        }
        let location = contentRange.location + anchor.contentOffset
        guard anchor.selectionLength >= 0,
              anchor.selectionLength <= NSMaxRange(contentRange) - location else {
            return false
        }
        let length = anchor.selectionLength
        let restoredSelection = NSRange(location: location, length: length)

        isApplyingStyleUpdate = true
        guard let editableSelection = textView.clampedEditableSelection(restoredSelection) else {
            isApplyingStyleUpdate = false
            return false
        }
        let selectionBeforeRestore = textView.selectedRange()
        textView.setSelectedRange(editableSelection)
        NodeMarkdownDiagnostic31.recordSelectionWrite(
            "restoreRememberedFocus Node=\(String(anchor.nodeID.prefix(8))) offset=\(anchor.contentOffset)",
            before: selectionBeforeRestore,
            requested: editableSelection,
            in: textView,
            rowLayouts: rowLayouts
        )
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
        guard let lastRange = rowLayouts.last?.range else { return nil }
        let documentLength = NSMaxRange(lastRange)
        guard NSRange(location: location, length: 0).exact(toLength: documentLength) != nil else {
            return nil
        }
        if let exact = lineIndexForLocation(location) {
            return exact
        }
        if location == documentLength,
           NSMaxRange(lastRange) == documentLength {
            return rowLayouts.indices.last
        }
        return nil
    }
}
#endif
