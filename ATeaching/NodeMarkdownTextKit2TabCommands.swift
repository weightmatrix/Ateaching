// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// TextKit2编辑缓冲区只有Content。Tab只改行元数据中的level，不替换文字。
    func handleTabCommand(in textView: NodeMarkdownTextKit2TextView, increaseLevel: Bool) -> Bool {
        let sourceText = textView.documentString() as NSString
        guard sourceText.length > 0 else { return false }
        let selection = textView.selectedRange()
        if selection.length > 0 {
            return changeLevelsForSelection(
                in: textView,
                selection: selection,
                increaseLevel: increaseLevel
            )
        }

        guard selection.exact(toLength: sourceText.length) != nil else { return false }
        let anchor = selection.location == sourceText.length
            ? sourceText.length - 1
            : selection.location
        let lineRange = sourceText.lineRange(for: NSRange(location: anchor, length: 0))
        guard let rowIndex = lineIndexForRange(lineRange), rowMetadata.indices.contains(rowIndex) else {
            return false
        }
        if rowMetadata[rowIndex].isProtectedH3 {
            return insertProtectedH3Sibling(
                in: textView,
                rowIndex: rowIndex,
                lineRange: lineRange,
                below: increaseLevel
            )
        }

        registerUndoSnapshot(for: textView)
        let currentLevel = rowMetadata[rowIndex].level
        let nextLevel = increaseLevel ? min(12, currentLevel + 1) : max(1, currentLevel - 1)
        rowMetadata[rowIndex] = rowMetadata[rowIndex].changingLevel(to: nextLevel)
        rebuildRowLayouts(from: textView)
        rememberFocus(in: textView, selection: selection)
        restoreRememberedFocus(in: textView)
        publishTextChange(textView.documentString(), structural: true)
        return true
    }

    private func changeLevelsForSelection(
        in textView: NodeMarkdownTextKit2TextView,
        selection: NSRange,
        increaseLevel: Bool
    ) -> Bool {
        let sourceText = textView.documentString() as NSString
        let fullLineRange = sourceText.lineRange(for: selection)
        var changed = false
        registerUndoSnapshot(for: textView)
        for index in rowCharacterRanges.indices {
            guard NSIntersectionRange(fullLineRange, rowCharacterRanges[index]).length > 0,
                  rowMetadata.indices.contains(index),
                  !rowMetadata[index].isProtectedH3 else { continue }
            let currentLevel = rowMetadata[index].level
            let nextLevel = increaseLevel ? min(12, currentLevel + 1) : max(1, currentLevel - 1)
            rowMetadata[index] = rowMetadata[index].changingLevel(to: nextLevel)
            changed = true
        }
        guard changed else { return true }
        rebuildRowLayouts(from: textView)
        rememberFocus(in: textView, selection: selection)
        restoreRememberedFocus(in: textView)
        publishTextChange(textView.documentString(), structural: true)
        return true
    }

    private func insertProtectedH3Sibling(
        in textView: NodeMarkdownTextKit2TextView,
        rowIndex: Int,
        lineRange: NSRange,
        below: Bool
    ) -> Bool {
        let rawLine = (textView.documentString() as NSString).substring(with: lineRange)
        let hasTrailingNewline = rawLine.hasSuffix("\n")
        let level = below ? 4 : 2
        let insertionLocation: Int
        let replacement: String
        let cursor: Int
        let metadataIndex: Int

        if below {
            insertionLocation = NSMaxRange(lineRange)
            replacement = "\n"
            cursor = hasTrailingNewline ? insertionLocation : insertionLocation + 1
            metadataIndex = rowIndex + 1
        } else {
            insertionLocation = lineRange.location
            replacement = "\n"
            cursor = insertionLocation
            metadataIndex = rowIndex
        }

        var nextMetadata = rowMetadata
        guard (0...nextMetadata.count).contains(metadataIndex) else { return false }
        nextMetadata.insert(.fresh(level: level), at: metadataIndex)
        replaceSourceText(
            in: textView,
            range: NSRange(location: insertionLocation, length: 0),
            replacement: replacement,
            selectedRange: NSRange(location: cursor, length: 0),
            updatedRowMetadata: nextMetadata
        )
        return true
    }
}
#endif
