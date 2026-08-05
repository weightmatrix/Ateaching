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
        let lineCoreNSString = sourceText.substring(with: coreRange) as NSString
        let contentStart = coreRange.location
        let caretInLineCore = max(contentStart, min(selection.location, NSMaxRange(coreRange)))
        let splitOffset = max(0, caretInLineCore - contentStart)
        let left = lineCoreNSString.substring(with: NSRange(location: 0, length: min(splitOffset, lineCoreNSString.length)))
        let right = lineCoreNSString.substring(from: min(splitOffset, lineCoreNSString.length))

        let replacement = left + "\n" + right
        let newCursor = coreRange.location + (left as NSString).length + 1
        var nextMetadata = rowMetadata
        let inheritedLevel = nextMetadata.indices.contains(sourceRowIndex)
            ? nextMetadata[sourceRowIndex].level
            : 7
        nextMetadata.insert(
            .fresh(level: inheritedLevel),
            at: min(nextMetadata.count, sourceRowIndex + 1)
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

    private func ensureCaretVisibleAfterNewline(in textView: NodeMarkdownTextKit2TextView, location: Int) {
        let range = NSRange(location: max(0, min(location, (textView.documentString() as NSString).length)), length: 0)
        textView.scrollRangeToVisible(range)
        DispatchQueue.main.async { [weak textView] in
            textView?.scrollRangeToVisible(range)
        }
    }
}
#endif
