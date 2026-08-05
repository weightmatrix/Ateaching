// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

let nodeMarkdownTextKit2AttachmentSourceTokenKey = NSAttributedString.Key("NodeMarkdownTextKit2AttachmentSourceToken")

extension NodeMarkdownTextKit2TextView {
    func replaceDocumentText(
        _ value: String,
        documentStyle: NodeMarkdownDocumentStyle,
        selectedRanges: [NSValue]? = nil
    ) {
        let attributed = NSAttributedString(
            string: value,
            attributes: Self.baseAttributes(for: documentStyle)
        )
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.setAttributedString(attributed)
        }
        nodeSourceTextSnapshot = value

        if let selectedRanges {
            let textLength = (value as NSString).length
            self.selectedRanges = selectedRanges.compactMap { value in
                guard let range = value.rangeValue.clamped(toLength: textLength) else { return nil }
                return NSValue(range: range)
            }
        }
    }

    func replaceSourceText(
        in range: NSRange,
        with replacement: String,
        selectedRange: NSRange,
        documentStyle: NodeMarkdownDocumentStyle
    ) {
        guard let safeRange = range.clamped(toLength: nodeTextStorage.length) else { return }
        let replacementText = NSAttributedString(
            string: replacement,
            attributes: Self.baseAttributes(for: documentStyle)
        )
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.replaceCharacters(in: safeRange, with: replacementText)
        }
        replaceSourceTextSnapshot(in: safeRange, with: replacement)
        if let safeSelection = selectedRange.clamped(toLength: nodeTextStorage.length) {
            self.selectedRange = safeSelection
        }
    }

    func documentString() -> String {
        assertSingleTextStorage()
        return nodeSourceTextSnapshot
    }

    func commitProjectedSourceText(_ value: String) {
        nodeSourceTextSnapshot = value
    }

    func rebuildSourceTextSnapshotFromStorage() {
        nodeSourceTextSnapshot = sourceTextPreservingAttachmentTokens(from: nodeTextStorage)
    }

    func projectedSourceText(replacing range: NSRange, with replacement: String) -> String? {
        let source = nodeSourceTextSnapshot as NSString
        guard let safeRange = range.clamped(toLength: source.length) else { return nil }
        return source.replacingCharacters(in: safeRange, with: replacement)
    }

    func assertSourceSnapshotMatchesStorage(file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        let reconstructed = sourceTextPreservingAttachmentTokens(from: nodeTextStorage)
        assert(reconstructed == nodeSourceTextSnapshot, "TextKit2 source snapshot diverged from canonical text storage", file: file, line: line)
        #endif
    }

    func displayedAttributedString() -> NSAttributedString {
        assertSingleTextStorage()
        return NSAttributedString(attributedString: nodeTextStorage)
    }

    /// 渲染态只把源码首字符临时换成附件占位符；回到源码态时也只做1:1原位恢复。
    /// 该操作不改变UTF-16长度、换行和任何选择位置。
    func restoreAttachmentSourceAnchors(in requestedRange: NSRange) {
        let fullRange = NSRange(location: 0, length: nodeTextStorage.length)
        let safeRange = NSIntersectionRange(requestedRange, fullRange)
        guard safeRange.length > 0 else { return }

        struct Replacement {
            let range: NSRange
            let character: String
        }
        var replacements: [Replacement] = []
        nodeTextStorage.enumerateAttribute(
            nodeMarkdownTextKit2AttachmentSourceTokenKey,
            in: safeRange,
            options: []
        ) { value, effectiveRange, _ in
            guard let token = value as? String, !token.isEmpty else { return }
            let tokenText = token as NSString
            guard tokenText.length > 0,
                  effectiveRange.location >= safeRange.location,
                  effectiveRange.location < NSMaxRange(safeRange) else { return }
            replacements.append(
                Replacement(
                    range: NSRange(location: effectiveRange.location, length: 1),
                    character: tokenText.substring(with: NSRange(location: 0, length: 1))
                )
            )
        }
        for replacement in replacements.reversed() {
            let current = (nodeTextStorage.string as NSString).substring(with: replacement.range)
            if current != replacement.character {
                nodeTextStorage.replaceCharacters(in: replacement.range, with: replacement.character)
            }
        }
    }

    private func sourceTextPreservingAttachmentTokens(from attributedString: NSAttributedString) -> String {
        let nsText = attributedString.string as NSString
        guard nsText.length > 0 else { return "" }

        var output = String()
        output.reserveCapacity(nsText.length)
        var index = 0
        while index < nsText.length {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = attributedString.attributes(at: index, effectiveRange: &effectiveRange)
            if let token = attributes[nodeMarkdownTextKit2AttachmentSourceTokenKey] as? String,
               !token.isEmpty {
                output.append(token)
                let tokenLength = max(1, (token as NSString).length)
                index = min(nsText.length, effectiveRange.location + tokenLength)
                continue
            }
            output.append(nsText.substring(with: effectiveRange))
            index = effectiveRange.location + max(1, effectiveRange.length)
        }
        return output
    }

    private func replaceSourceTextSnapshot(in range: NSRange, with replacement: String) {
        guard let projected = projectedSourceText(replacing: range, with: replacement) else {
            rebuildSourceTextSnapshotFromStorage()
            return
        }
        nodeSourceTextSnapshot = projected
    }
}
#endif
