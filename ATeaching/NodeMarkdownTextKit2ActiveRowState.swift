// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func reportActiveRowIfNeeded(from textView: NodeMarkdownTextKit2TextView) {
        let rowIndex = currentRowIndex(in: textView)
        reportActiveRow(rowIndex)
        reportFocusLocation(rowIndex: rowIndex, from: textView)
    }

    func enterEditingRowIfNeeded(from textView: NodeMarkdownTextKit2TextView) {
        rebuildRowLayoutsIfNeeded(from: textView)
        enterEditingRow(currentRowIndex(in: textView), from: textView)
    }

    func enterEditingRow(_ rowIndex: Int?, from textView: NodeMarkdownTextKit2TextView) {
        let normalizedRowIndex = validRowIndex(rowIndex)
        textView.nodeMarkdownEditingRowIndex = normalizedRowIndex

        if let normalizedRowIndex {
            beginNodeSessionIfNeeded(at: normalizedRowIndex)
        } else {
            commitActiveNodeSession()
        }

        guard normalizedRowIndex != editingRowIndex else {
            reportActiveRow(normalizedRowIndex)
            reportFocusLocation(rowIndex: normalizedRowIndex, from: textView)
            return
        }

        let previousRowIndex = editingRowIndex
        if let previousRowIndex, previousRowIndex != normalizedRowIndex {
            editingParagraphStyleCache.removeValue(forKey: previousRowIndex)
        }
        editingRowIndex = normalizedRowIndex
        refreshRowsForEditingTransition(
            in: textView,
            previousRowIndex: previousRowIndex,
            currentRowIndex: normalizedRowIndex
        )
        reportActiveRow(normalizedRowIndex)
        reportFocusLocation(rowIndex: normalizedRowIndex, from: textView)
    }

    func clearEditingRow(in textView: NodeMarkdownTextKit2TextView) {
        commitActiveNodeSession()
        let previousRowIndex = editingRowIndex
        editingRowIndex = nil
        editingParagraphStyleCache.removeAll(keepingCapacity: true)
        textView.nodeMarkdownEditingRowIndex = nil
        refreshRowsForEditingTransition(
            in: textView,
            previousRowIndex: previousRowIndex,
            currentRowIndex: nil
        )
        reportActiveRow(nil)
        reportFocusLocation(nil)
    }

    func scrollToActiveRowIfNeeded(in textView: NodeMarkdownTextKit2TextView) {
        guard let activeRowIndex,
              activeRowIndex != lastScrolledActiveRowIndex,
              rowCharacterRanges.indices.contains(activeRowIndex) else { return }
        lastScrolledActiveRowIndex = activeRowIndex
        textView.scrollRangeToVisible(rowCharacterRanges[activeRowIndex])
    }

    private func reportActiveRow(_ rowIndex: Int?) {
        guard rowIndex != lastReportedActiveRowIndex else { return }
        lastReportedActiveRowIndex = rowIndex
        // synchronize由updateNSView调用，不能在SwiftUI更新视图期间同步回写状态。
        // 只投递最后仍然有效的行，连续选区变化不会把过期行再写回界面层。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastReportedActiveRowIndex == rowIndex else { return }
            self.onActiveRowChange?(rowIndex)
        }
    }

    private func reportFocusLocation(rowIndex: Int?, from textView: NodeMarkdownTextKit2TextView) {
        let nsText = textView.documentString() as NSString
        let selection = textView.selectedRange()
        guard let exactSelection = selection.exact(toLength: nsText.length) else {
            reportFocusLocation(nil)
            return
        }
        let column = rowIndex.flatMap { index -> Int? in
            guard rowCharacterRanges.indices.contains(index) else { return nil }
            let offset = exactSelection.location - rowCharacterRanges[index].location
            return offset >= 0 ? offset : nil
        }
        reportFocusLocation(
            NodeMarkdownTextFocusLocation(
                rowIndex: rowIndex,
                location: exactSelection.location,
                length: exactSelection.length,
                column: column
            )
        )
    }

    private func reportFocusLocation(_ focusLocation: NodeMarkdownTextFocusLocation?) {
        guard focusLocation != lastReportedFocusLocation else { return }
        lastReportedFocusLocation = focusLocation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastReportedFocusLocation == focusLocation else { return }
            self.onFocusLocationChange?(focusLocation)
        }
    }

    private func validRowIndex(_ rowIndex: Int?) -> Int? {
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else { return nil }
        return rowIndex
    }

    private func rowsForEditingTransition(previousRowIndex: Int?, currentRowIndex: Int?) -> Set<Int> {
        // 编辑状态只改变离开的行和进入的行。相邻Node没有任何状态变化，
        // 不得恢复其附件源码或重挂样式，否则会使背景条、高亮和公式短暂消失。
        return Set([previousRowIndex, currentRowIndex].compactMap { $0 })
            .filter { rowLayouts.indices.contains($0) }
    }

    private func refreshRowsForEditingTransition(
        in textView: NodeMarkdownTextKit2TextView,
        previousRowIndex: Int?,
        currentRowIndex: Int?
    ) {
        let targetRows = rowsForEditingTransition(
            previousRowIndex: previousRowIndex,
            currentRowIndex: currentRowIndex
        )
        guard !targetRows.isEmpty else { return }

        NodeMarkdownTextKit2Diagnostics.log("编辑行切换：旧行=\(previousRowIndex.map(String.init) ?? "nil")，新行=\(currentRowIndex.map(String.init) ?? "nil")，仅刷新行=\(targetRows.sorted())。")
        refreshRowStyles(in: textView, rows: targetRows)
    }
}
#endif
