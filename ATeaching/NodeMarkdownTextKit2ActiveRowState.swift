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
        onActiveRowChange?(rowIndex)
    }

    private func reportFocusLocation(rowIndex: Int?, from textView: NodeMarkdownTextKit2TextView) {
        let nsText = textView.documentString() as NSString
        let selection = textView.selectedRange()
        let safeLocation = max(0, min(selection.location, nsText.length))
        let safeLength = max(0, min(selection.length, nsText.length - safeLocation))
        let column = rowIndex.flatMap { index -> Int? in
            guard rowCharacterRanges.indices.contains(index) else { return nil }
            return max(0, safeLocation - rowCharacterRanges[index].location)
        }
        reportFocusLocation(
            NodeMarkdownTextFocusLocation(
                rowIndex: rowIndex,
                location: safeLocation,
                length: safeLength,
                column: column
            )
        )
    }

    private func reportFocusLocation(_ focusLocation: NodeMarkdownTextFocusLocation?) {
        guard focusLocation != lastReportedFocusLocation else { return }
        lastReportedFocusLocation = focusLocation
        onFocusLocationChange?(focusLocation)
    }

    private func validRowIndex(_ rowIndex: Int?) -> Int? {
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else { return nil }
        return rowIndex
    }

    private func rowsForEditingTransition(previousRowIndex: Int?, currentRowIndex: Int?) -> Set<Int> {
        var rows = Set<Int>()
        rows.formUnion(rowsAround(previousRowIndex))
        rows.formUnion(rowsAround(currentRowIndex))
        return rows.filter { rowLayouts.indices.contains($0) }
    }

    private func rowsAround(_ rowIndex: Int?) -> Set<Int> {
        guard let rowIndex else { return [] }
        var rows: Set<Int> = [rowIndex]
        if rowIndex > 0 {
            rows.insert(rowIndex - 1)
        }
        rows.insert(rowIndex + 1)
        return rows
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

        refreshRowStyles(in: textView, rows: targetRows)
    }
}
#endif
