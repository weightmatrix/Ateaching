// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func applyRowStyles(to textView: NodeMarkdownTextKit2TextView) {
        guard !isApplyingExternalText,
              !textView.hasActiveInputMethodComposition else {
            NodeMarkdownTextKit2Diagnostics.log("跳过全文样式，isApplyingExternalText=\(isApplyingExternalText)，有效输入法组合=\(textView.hasActiveInputMethodComposition)。")
            return
        }
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("全文样式", since: diagnosticStart) }
        recordDiagnostic35Count("全文样式次数")
        recordDiagnostic35Count("全文样式处理Node", amount: rowLayouts.count)
        NodeMarkdownTextKit2Diagnostics.log("开始应用全文样式，rowLayouts=\(rowLayouts.count)，storage长度=\(textView.nodeTextStorage.length)。")
        isApplyingStyleUpdate = true
        textView.applyNodeMarkdownStyles(
            rowLayouts: rowLayouts,
            documentStyle: documentStyle,
            baseDirectoryURL: workingDirectoryURL,
            searchQuery: searchQuery,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow,
            editingRowIndex: editingRowIndex
        )
        isApplyingStyleUpdate = false
        lastAppliedSearchQuery = searchQuery
        lastAppliedActiveRowIndex = activeRowIndex
        lastAppliedActiveMatchLocationInRow = activeMatchLocationInRow
        lastAppliedEditingRowIndex = editingRowIndex
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "全文样式应用完成",
            textView: textView,
            metadataCount: rowMetadata.count,
            rowLayoutCount: rowLayouts.count
        )
    }

    func refreshSearchHighlightsIfNeeded(in textView: NodeMarkdownTextKit2TextView) {
        let searchQueryChanged = searchQuery != lastAppliedSearchQuery
        guard searchQueryChanged
                || activeRowIndex != lastAppliedActiveRowIndex
                || activeMatchLocationInRow != lastAppliedActiveMatchLocationInRow
                || editingRowIndex != lastAppliedEditingRowIndex else { return }

        if searchQueryChanged {
            recordDiagnostic35Count("样式入口-搜索全文")
            // 搜索词改变会影响任意行，只有这一种状态变化需要全篇重新应用搜索标记。
            applyRowStyles(to: textView)
            return
        }

        var rows = Set<Int>()
        [lastAppliedActiveRowIndex, activeRowIndex, lastAppliedEditingRowIndex, editingRowIndex]
            .compactMap { $0 }
            .forEach { rows.insert($0) }
        recordDiagnostic35Count("局部样式入口-搜索或编辑状态")
        refreshRowStyles(in: textView, rows: rows)
        lastAppliedSearchQuery = searchQuery
        lastAppliedActiveRowIndex = activeRowIndex
        lastAppliedActiveMatchLocationInRow = activeMatchLocationInRow
        lastAppliedEditingRowIndex = editingRowIndex
    }

    func refreshRowStyles(in textView: NodeMarkdownTextKit2TextView, rows: Set<Int>) {
        let validRows = rows.filter { rowLayouts.indices.contains($0) }.sorted()
        guard !validRows.isEmpty,
              !textView.hasActiveInputMethodComposition else { return }
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("局部样式", since: diagnosticStart) }
        recordDiagnostic35Count("局部样式次数")
        recordDiagnostic35Count("局部样式处理Node", amount: validRows.count)
        isApplyingStyleUpdate = true
        defer { isApplyingStyleUpdate = false }
        for rowIndex in validRows {
            textView.refreshNodeMarkdownRowStyle(
                rowIndex: rowIndex,
                rowLayouts: rowLayouts,
                documentStyle: documentStyle,
                baseDirectoryURL: workingDirectoryURL,
                searchQuery: searchQuery,
                activeRowIndex: activeRowIndex,
                activeMatchLocationInRow: activeMatchLocationInRow,
                editingRowIndex: editingRowIndex
            )
        }
        textView.invalidateNodeMarkdownDecorationsAfterRowStyleChange(rows: validRows)
    }

    func updateTypingAttributes(for textView: NodeMarkdownTextKit2TextView) {
        guard let attributes = typingAttributes(
            forLocation: textView.selectedRange().location,
            in: textView
        ) else { return }
        textView.nodeMarkdownTypingAttributes = attributes
        textView.typingAttributes = attributes
    }

    func applyTypingAttributesToMarkedText(in textView: NodeMarkdownTextKit2TextView) {
        let markedRange = textView.markedRange()
        guard markedRange.location != NSNotFound, markedRange.length > 0 else { return }
        guard let attributes = typingAttributes(forLocation: markedRange.location, in: textView) else {
            return
        }
        textView.nodeMarkdownTypingAttributes = attributes
        textView.typingAttributes = attributes
        // 输入法可能在setMarkedText内再次写入自己的大字号和蓝色。
        // 以TextStorage中的真实marked range为准复写受控属性，其他输入法标记保留。
        textView.enforceCanonicalAttributesOnMarkedText(attributes)
    }

    private func typingAttributes(
        forLocation location: Int,
        in textView: NodeMarkdownTextKit2TextView
    ) -> [NSAttributedString.Key: Any]? {
        let nsText = textView.documentString() as NSString
        guard nsText.length > 0 else {
            guard rowLayouts.count == 1 else { return nil }
            return textView.typingAttributes(for: rowLayouts[0], documentStyle: documentStyle)
        }
        guard NSRange(location: location, length: 0).exact(toLength: nsText.length) != nil else {
            return nil
        }
        let safeLocation = location
        if safeLocation == nsText.length,
           let lastRange = rowCharacterRanges.last,
           lastRange.location == nsText.length,
           lastRange.length == 0,
           let lastLayout = rowLayouts.last {
            return textView.typingAttributes(for: lastLayout, documentStyle: documentStyle)
        }
        let anchor = safeLocation == nsText.length ? max(0, nsText.length - 1) : safeLocation
        guard let rowIndex = lineIndexForLocation(anchor),
              rowLayouts.indices.contains(rowIndex) else { return nil }
        let layout = rowLayouts[rowIndex]
        let attributes = textView.typingAttributes(for: layout, documentStyle: documentStyle)
        guard layout.rowIndex == editingRowIndex else {
            return attributes
        }
        if let paragraph = editingParagraphStyleCache[layout.rowIndex] {
            return attributes.merging([.paragraphStyle: paragraph], uniquingKeysWith: { _, new in new })
        }
        if let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
            editingParagraphStyleCache[layout.rowIndex] = paragraph
        }
        return attributes
    }
}
#endif
