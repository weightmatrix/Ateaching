// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func applyBaseStyle(to textView: NodeMarkdownTextKit2TextView) {
        let baseStyle = documentStyle.style(forLevel: 7)
        let font = NSFont(name: baseStyle.fontName, size: baseStyle.fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: baseStyle.fontSize, weight: .regular)
        textView.font = font
        textView.textColor = NSColor(baseStyle.renderedColor)
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.foregroundColor] = NSColor(baseStyle.renderedColor)
    }

    func applyRowStyles(to textView: NodeMarkdownTextKit2TextView) {
        guard !isApplyingExternalText,
              textView.markedRange().location == NSNotFound else { return }
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
    }

    func refreshSearchHighlightsIfNeeded(in textView: NodeMarkdownTextKit2TextView) {
        let searchQueryChanged = searchQuery != lastAppliedSearchQuery
        guard searchQueryChanged
                || activeRowIndex != lastAppliedActiveRowIndex
                || activeMatchLocationInRow != lastAppliedActiveMatchLocationInRow
                || editingRowIndex != lastAppliedEditingRowIndex else { return }

        if searchQueryChanged {
            // 搜索词改变会影响任意行，只有这一种状态变化需要全篇重新应用搜索标记。
            applyRowStyles(to: textView)
            return
        }

        var rows = Set<Int>()
        [lastAppliedActiveRowIndex, activeRowIndex, lastAppliedEditingRowIndex, editingRowIndex]
            .compactMap { $0 }
            .forEach { rows.insert($0) }
        refreshRowStyles(in: textView, rows: rows)
        lastAppliedSearchQuery = searchQuery
        lastAppliedActiveRowIndex = activeRowIndex
        lastAppliedActiveMatchLocationInRow = activeMatchLocationInRow
        lastAppliedEditingRowIndex = editingRowIndex
    }

    func refreshRowStyles(in textView: NodeMarkdownTextKit2TextView, rows: Set<Int>) {
        let validRows = rows.filter { rowLayouts.indices.contains($0) }.sorted()
        guard !validRows.isEmpty,
              textView.markedRange().location == NSNotFound else { return }
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
    }

    func updateTypingAttributes(for textView: NodeMarkdownTextKit2TextView) {
        let attributes = typingAttributes(forLocation: textView.selectedRange().location, in: textView)
        textView.typingAttributes = attributes
    }

    func applyTypingAttributesToMarkedText(in textView: NodeMarkdownTextKit2TextView) {
        let markedRange = textView.markedRange()
        guard markedRange.location != NSNotFound, markedRange.length > 0 else { return }
        let attributes = typingAttributes(forLocation: markedRange.location, in: textView)
        // 只影响后续输入属性，不触碰输入法正在管理的组合文本。
        textView.typingAttributes = attributes
    }

    private func typingAttributes(
        forLocation location: Int,
        in textView: NodeMarkdownTextKit2TextView
    ) -> [NSAttributedString.Key: Any] {
        let nsText = textView.documentString() as NSString
        guard nsText.length > 0 else {
            return textView.defaultTypingAttributes(documentStyle: documentStyle)
        }
        let safeLocation = max(0, min(location, nsText.length))
        if safeLocation == nsText.length,
           let lastRange = rowCharacterRanges.last,
           lastRange.location == nsText.length,
           lastRange.length == 0,
           let lastLayout = rowLayouts.last {
            return textView.typingAttributes(for: lastLayout, documentStyle: documentStyle)
        }
        let anchor = safeLocation == nsText.length ? max(0, nsText.length - 1) : safeLocation
        let layout: NodeMarkdownTextKit2RowLayout?
        if let rowIndex = lineIndexForLocation(anchor), rowLayouts.indices.contains(rowIndex) {
            layout = rowLayouts[rowIndex]
        } else {
            let lineRange = nsText.lineRange(for: NSRange(location: anchor, length: 0))
            layout = rowLayouts.first { $0.range == lineRange }
        }
        guard let layout else {
            return textView.defaultTypingAttributes(documentStyle: documentStyle)
        }
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
