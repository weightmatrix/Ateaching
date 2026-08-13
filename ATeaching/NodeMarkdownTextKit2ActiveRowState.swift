// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

enum NodeMarkdownTextKit2NavigationPolicy {
    static let targetTopPadding: CGFloat = 16

    static func targetRow(
        requestToken: Int,
        lastHandledToken: Int,
        activeRowIndex: Int?,
        rowCount: Int
    ) -> Int? {
        guard requestToken != lastHandledToken,
              let activeRowIndex,
              activeRowIndex >= 0,
              activeRowIndex < rowCount else { return nil }
        return activeRowIndex
    }

    static func requestedVisibleOriginY(targetMinY: CGFloat, topPadding: CGFloat = targetTopPadding) -> CGFloat {
        targetMinY - max(0, topPadding)
    }
}

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
            commitActiveNodeSession(reason: "选区离开有效Node")
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
        commitActiveNodeSession(reason: "ESC/文本视图失焦")
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
        guard let activeRowIndex = NodeMarkdownTextKit2NavigationPolicy.targetRow(
            requestToken: navigationRequestToken,
            lastHandledToken: lastHandledNavigationRequestToken,
            activeRowIndex: activeRowIndex,
            rowCount: rowCharacterRanges.count
        ) else { return }
        let handledToken = navigationRequestToken
        let transaction = beginDiagnostic41("搜索/目录定位 row=\(activeRowIndex) token=\(handledToken)", in: textView)
        lastHandledNavigationRequestToken = handledToken
        textView.scrollRangeToVisible(rowCharacterRanges[activeRowIndex])
        alignNavigationTargetNearTop(
            token: handledToken,
            row: activeRowIndex,
            stage: "同步顶部定位",
            in: textView
        )
        scheduleNavigationTargetAlignment(
            stage: "下一主循环顶部复测",
            delay: 0,
            token: handledToken,
            row: activeRowIndex,
            textView: textView
        )
        finishDiagnostic41(transaction, in: textView, stage: "定位调度完成")
        scheduleNavigationTargetAlignment(
            stage: "延迟80ms顶部复测",
            delay: 0.08,
            token: handledToken,
            row: activeRowIndex,
            textView: textView
        )
    }

    private func scheduleNavigationTargetAlignment(
        stage: String,
        delay: TimeInterval,
        token: Int,
        row: Int,
        textView: NodeMarkdownTextKit2TextView
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak textView] in
            guard let self, let textView,
                  token == self.navigationRequestToken,
                  token == self.lastHandledNavigationRequestToken else { return }
            self.alignNavigationTargetNearTop(
                token: token,
                row: row,
                stage: stage,
                in: textView
            )
        }
    }

    private func alignNavigationTargetNearTop(
        token: Int,
        row: Int,
        stage: String,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        guard token == navigationRequestToken,
              token == lastHandledNavigationRequestToken,
              rowCharacterRanges.indices.contains(row),
              let scrollView = textView.enclosingScrollView,
              let targetRect = navigationVisualRect(for: rowCharacterRanges[row], in: textView) else { return }

        let clipView = scrollView.contentView
        var proposedBounds = clipView.bounds
        proposedBounds.origin.y = NodeMarkdownTextKit2NavigationPolicy.requestedVisibleOriginY(
            targetMinY: targetRect.minY
        )
        let constrainedBounds = clipView.constrainBoundsRect(proposedBounds)
        if abs(constrainedBounds.origin.y - clipView.bounds.origin.y) > 0.5 {
            clipView.setBoundsOrigin(constrainedBounds.origin)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    private func navigationVisualRect(
        for range: NSRange,
        in textView: NodeMarkdownTextKit2TextView
    ) -> NSRect? {
        guard let exactRange = range.exact(toLength: textView.nodeTextStorage.length),
              let window = textView.window else { return nil }
        let screenRect = textView.firstRect(forCharacterRange: exactRange, actualRange: nil)
        guard !screenRect.isNull, !screenRect.isEmpty else { return nil }
        return textView.convert(window.convertFromScreen(screenRect), from: nil)
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
        guard onFocusLocationChange != nil else { return }
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
        guard onFocusLocationChange != nil else {
            lastReportedFocusLocation = nil
            return
        }
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

        recordDiagnostic35Count("局部样式入口-编辑行切换")
        NodeMarkdownTextKit2Diagnostics.log("编辑行切换：旧行=\(previousRowIndex.map(String.init) ?? "nil")，新行=\(currentRowIndex.map(String.init) ?? "nil")，仅刷新行=\(targetRows.sorted())。")
        refreshRowStyles(in: textView, rows: targetRows)
    }
}
#endif
