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

        let replacement = left + "\n" + right
        let newCursor = coreRange.location + (left as NSString).length + 1
        var nextMetadata = rowMetadata
        guard nextMetadata.indices.contains(sourceRowIndex) else { return false }
        let inheritedLevel = nextMetadata[sourceRowIndex].level
        let insertionIndex = sourceRowIndex + 1
        guard (0...nextMetadata.count).contains(insertionIndex) else { return false }
        nextMetadata.insert(
            .fresh(level: inheritedLevel),
            at: insertionIndex
        )
        replaceSourceText(
            in: textView,
            range: coreRange,
            replacement: replacement,
            selectedRange: NSRange(location: newCursor, length: 0),
            updatedRowMetadata: nextMetadata
        )
        ensureCaretVisibleAfterNewline(in: textView, location: newCursor)
        return true
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
        var nextMetadata = rowMetadata
        let insertionIndex = sourceRowIndex + 1
        guard (0...nextMetadata.count).contains(insertionIndex) else { return false }
        nextMetadata.insert(.fresh(level: 4), at: insertionIndex)
        replaceSourceText(
            in: textView,
            range: NSRange(location: insertionLocation, length: 0),
            replacement: "\n",
            selectedRange: NSRange(location: cursor, length: 0),
            updatedRowMetadata: nextMetadata
        )
        return true
    }

    private func ensureCaretVisibleAfterNewline(in textView: NodeMarkdownTextKit2TextView, location: Int) {
        let range = NSRange(location: location, length: 0)
        guard range.exact(toLength: (textView.documentString() as NSString).length) != nil else { return }
        textView.scrollRangeToVisible(range)
        DispatchQueue.main.async { [weak textView] in
            textView?.scrollRangeToVisible(range)
        }
    }
}
#endif
