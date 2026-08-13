// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func handlePrimaryClick(in textView: NodeMarkdownTextKit2TextView) {
        onBeginEditing?()
        rebuildRowLayoutsIfNeeded(from: textView)
        // super.mouseDown已经设置第一响应者和真实点击选区。再次设置第一响应者
        // 会让NSTextView主动追踪插入点并改变视野。
        textView.normalizeSelectedRangesToEditableContent()
        guard let rowIndex = currentRowIndex(in: textView) else { return }
        enterEditingRow(rowIndex, from: textView)
        updateTypingAttributes(for: textView)
        reportActiveRowIfNeeded(from: textView)
    }

    func handleCancelOperation(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        refreshCurrentRowStyle(in: textView)
        // 先同步清除编辑行、父页面活动行和焦点位置，再交还第一响应者。
        // textDidEndEditing只负责幂等收尾，不再决定ESC后的插包锚点。
        clearEditingRow(in: textView)
        textView.window?.makeFirstResponder(nil)
        onInputSessionStateChange?(false)
        return true
    }

    func refreshCurrentRowStyle(in textView: NodeMarkdownTextKit2TextView) {
        recordDiagnostic35Count("局部样式入口-当前行")
        let rowIndex = currentRowIndex(in: textView)
        let rowsToRefresh: Set<Int> = {
            guard let rowIndex else { return [] }
            return Set([rowIndex, rowIndex + 1].filter { rowLayouts.indices.contains($0) })
        }()
        refreshRowStyles(in: textView, rows: rowsToRefresh)
    }

}
#endif
