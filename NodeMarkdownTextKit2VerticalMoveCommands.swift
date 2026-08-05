// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func handleVerticalMove(in textView: NodeMarkdownTextKit2TextView, direction: Int) -> Bool {
        rebuildRowLayoutsIfNeeded(from: textView)
        let selection = textView.selectedRange()
        guard selection.length == 0,
              let currentRow = currentRowIndex(in: textView),
              rowLayouts.indices.contains(currentRow) else { return false }
        let targetRow = currentRow + (direction < 0 ? -1 : 1)
        guard rowLayouts.indices.contains(targetRow) else { return true }
        let currentContentRange = rowLayouts[currentRow].contentRange
        let targetContentRange = rowLayouts[targetRow].contentRange
        let currentOffset = max(0, selection.location - currentContentRange.location)
        let targetLocation = targetContentRange.location + min(currentOffset, targetContentRange.length)

        textView.setSelectedRange(NSRange(location: targetLocation, length: 0))
        reportActiveRowIfNeeded(from: textView)
        updateTypingAttributes(for: textView)
        return true
    }
}
#endif
