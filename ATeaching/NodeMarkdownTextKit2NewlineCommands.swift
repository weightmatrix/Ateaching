// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func handleInsertNewline(in textView: NodeMarkdownTextKit2TextView) -> Bool {
        rebuildRowLayoutsIfNeeded(from: textView)
        let sourceText = textView.documentString() as NSString
        let selection = textView.selectedRange()
        guard selection.length == 0,
              let sourceRowIndex = currentRowIndex(in: textView),
              rowLayouts.indices.contains(sourceRowIndex) else { return false }

        let coreRange = rowLayouts[sourceRowIndex].contentRange
        if rowMetadata.indices.contains(sourceRowIndex),
           NodeMarkdownLegacyStructurePolicy.insertsEmptyChildInsteadOfSplitting(rowMetadata[sourceRowIndex]) {
            return insertEmptyH4AfterProtectedH3(
                in: textView,
                sourceRowIndex: sourceRowIndex,
                sourceText: sourceText
            )
        }
        let lineCoreNSString = sourceText.substring(with: coreRange) as NSString
        let contentStart = coreRange.location
        guard selection.location >= contentStart,
              selection.location <= NSMaxRange(coreRange) else { return false }
        let splitOffset = selection.location - contentStart
        guard splitOffset <= lineCoreNSString.length else { return false }
        let left = lineCoreNSString.substring(with: NSRange(location: 0, length: splitOffset))
        let right = lineCoreNSString.substring(from: splitOffset)

        let newCursor = coreRange.location + (left as NSString).length + 1
        guard rowMetadata.indices.contains(sourceRowIndex) else { return false }
        return performLocalNewlineTransaction(
            in: textView,
            sourceRow: sourceRowIndex,
            splitOffset: splitOffset,
            replacementRange: coreRange,
            replacement: left + "\n" + right,
            newCursor: newCursor,
            newLevel: rowMetadata[sourceRowIndex].level,
            preservesSourceNodeContent: false
        )
    }

    private func insertEmptyH4AfterProtectedH3(
        in textView: NodeMarkdownTextKit2TextView,
        sourceRowIndex: Int,
        sourceText: NSString
    ) -> Bool {
        let lineRange = rowLayouts[sourceRowIndex].range
        let rawLine = sourceText.substring(with: lineRange)
        let hasTrailingNewline = rawLine.hasSuffix("\n")
        let insertionLocation = NSMaxRange(lineRange)
        let cursor = hasTrailingNewline ? insertionLocation : insertionLocation + 1
        return performLocalNewlineTransaction(
            in: textView,
            sourceRow: sourceRowIndex,
            splitOffset: (sourceText.substring(with: rowLayouts[sourceRowIndex].contentRange) as NSString).length,
            replacementRange: NSRange(location: insertionLocation, length: 0),
            replacement: "\n",
            newCursor: cursor,
            newLevel: 4,
            preservesSourceNodeContent: true
        )
    }
}
#endif
