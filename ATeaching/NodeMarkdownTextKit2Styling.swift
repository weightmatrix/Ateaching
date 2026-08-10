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
        guard !hasActiveInputMethodComposition else { return }
        let currentText = documentString()
        let textLength = (currentText as NSString).length
        let nsText = currentText as NSString
        let selectedRanges = self.selectedRanges
        let fullRange = NSRange(location: 0, length: nodeTextStorage.length)
        guard rowLayouts.allSatisfy({ $0.range.exact(toLength: textLength) != nil }),
              selectedRanges.allSatisfy({ $0.rangeValue.exact(toLength: textLength) != nil }) else {
            NodeMarkdownTextKit2Diagnostics.log("拒绝全文样式事务：行范围或选区与真实正文不一致。")
            return
        }
        nodeTextContentStorage.performEditingTransaction {
            restoreAttachmentSourceAnchors(in: fullRange)
            for layout in rowLayouts {
                let exactRange = layout.range
                if exactRange.length > 0 {
                    nodeTextStorage.setAttributes([:], range: exactRange)
                }
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
        self.selectedRanges = selectedRanges
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
        guard !hasActiveInputMethodComposition else { return }
        guard let rowIndex, rowLayouts.indices.contains(rowIndex) else { return }
        let currentText = documentString()
        let textLength = (currentText as NSString).length
        let layout = rowLayouts[rowIndex]
        guard let rowRange = layout.range.exact(toLength: textLength), rowRange.length > 0 else { return }

        let nsText = currentText as NSString
        let selectedRanges = self.selectedRanges
        guard selectedRanges.allSatisfy({ $0.rangeValue.exact(toLength: textLength) != nil }) else {
            NodeMarkdownTextKit2Diagnostics.log("拒绝单行样式事务：选区与真实正文不一致。")
            return
        }
        nodeTextContentStorage.performEditingTransaction {
            restoreAttachmentSourceAnchors(in: rowRange)
            nodeTextStorage.setAttributes([:], range: rowRange)
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
        self.selectedRanges = selectedRanges
    }

}
#endif
