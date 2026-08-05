// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#if canImport(SwiftMath)
import SwiftMath
#endif

extension NodeMarkdownTextKit2TextView {
    func applyNodeMarkdownStyles(
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        documentStyle: NodeMarkdownDocumentStyle,
        baseDirectoryURL: URL?,
        searchQuery: String,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?,
        editingRowIndex: Int?
    ) {
        nodeMarkdownEditingRowIndex = editingRowIndex
        guard markedRange().location == NSNotFound else { return }
        let currentText = documentString()
        let textLength = (currentText as NSString).length
        let nsText = currentText as NSString
        let selectedRanges = self.selectedRanges
        let fullRange = NSRange(location: 0, length: nodeTextStorage.length)
        let baseAttributes = Self.baseAttributes(for: documentStyle)

        nodeTextContentStorage.performEditingTransaction {
            restoreAttachmentSourceAnchors(in: fullRange)
            if fullRange.length > 0 {
                nodeTextStorage.setAttributes(baseAttributes, range: fullRange)
            }
            for layout in rowLayouts {
                applyNodeMarkdownStyle(
                    to: nodeTextStorage,
                    source: nsText,
                    layout: layout,
                    documentStyle: documentStyle,
                    baseDirectoryURL: baseDirectoryURL,
                    searchQuery: searchQuery,
                    activeRowIndex: activeRowIndex,
                    activeMatchLocationInRow: activeMatchLocationInRow,
                    editingRowIndex: editingRowIndex,
                    textLength: textLength
                )
            }
        }
        self.selectedRanges = selectedRanges.compactMap { value in
            guard let range = value.rangeValue.clamped(toLength: textLength) else { return nil }
            return NSValue(range: range)
        }
        setNeedsDisplay(bounds)
    }

    func refreshNodeMarkdownRowStyle(
        rowIndex: Int?,
        rowLayouts: [NodeMarkdownTextKit2RowLayout],
        documentStyle: NodeMarkdownDocumentStyle,
        baseDirectoryURL: URL?,
        searchQuery: String,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?,
        editingRowIndex: Int?
    ) {
        nodeMarkdownEditingRowIndex = editingRowIndex
        guard markedRange().location == NSNotFound else { return }
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else { return }
        let currentText = documentString()
        let textLength = (currentText as NSString).length
        let layout = rowLayouts[rowIndex]
        guard let rowRange = layout.range.clamped(toLength: textLength), rowRange.length > 0 else { return }

        let nsText = currentText as NSString
        let selectedRanges = self.selectedRanges
        let baseAttributes = Self.baseAttributes(for: documentStyle)
        nodeTextContentStorage.performEditingTransaction {
            restoreAttachmentSourceAnchors(in: rowRange)
            nodeTextStorage.setAttributes(baseAttributes, range: rowRange)
            applyNodeMarkdownStyle(
                to: nodeTextStorage,
                source: nsText,
                layout: layout,
                documentStyle: documentStyle,
                baseDirectoryURL: baseDirectoryURL,
                searchQuery: searchQuery,
                activeRowIndex: activeRowIndex,
                activeMatchLocationInRow: activeMatchLocationInRow,
                editingRowIndex: editingRowIndex,
                textLength: textLength
            )
        }
        self.selectedRanges = selectedRanges.compactMap { value in
            guard let range = value.rangeValue.clamped(toLength: textLength) else { return nil }
            return NSValue(range: range)
        }
        setNeedsDisplay(bounds)
    }

}
#endif
