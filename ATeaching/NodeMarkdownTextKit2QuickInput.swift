// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    func applyQuickInputIfNeeded(documentStyle: NodeMarkdownDocumentStyle) -> Bool {
        guard !isApplyingQuickInputReplacement else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let nsText = documentString() as NSString
        let caret = max(0, min(selection.location, nsText.length))
        let prefix = nsText.substring(to: caret)

        if applyPairQuickInputIfNeeded(prefix: prefix, caret: caret, documentStyle: documentStyle) {
            return true
        }

        for candidate in quickInputSingleCandidates() {
            guard !candidate.trigger.isEmpty else { continue }
            guard candidate.replacement != candidate.trigger else { continue }
            guard prefix.hasSuffix(candidate.trigger) else { continue }

            let triggerLength = (candidate.trigger as NSString).length
            let replacementLength = (candidate.replacement as NSString).length
            let start = caret - triggerLength
            guard start >= 0 else { continue }

            replaceQuickInputText(
                in: NSRange(location: start, length: triggerLength),
                with: candidate.replacement,
                selectedRange: NSRange(location: start + replacementLength, length: 0),
                documentStyle: documentStyle
            )
            return true
        }
        return false
    }

    private func applyPairQuickInputIfNeeded(
        prefix: String,
        caret: Int,
        documentStyle: NodeMarkdownDocumentStyle
    ) -> Bool {
        let nsPrefix = prefix as NSString

        for pairRule in quickInputPairCandidates() {
            let openTrigger = pairRule.openTrigger
            let closeTrigger = pairRule.closeTrigger
            guard !openTrigger.isEmpty, !closeTrigger.isEmpty else { continue }
            guard pairRule.openReplacement != openTrigger || pairRule.closeReplacement != closeTrigger else { continue }
            guard prefix.hasSuffix(closeTrigger) else { continue }

            let closeLength = (closeTrigger as NSString).length
            let openLength = (openTrigger as NSString).length
            let closeStart = caret - closeLength
            guard closeStart >= 0 else { continue }

            let searchRange = NSRange(location: 0, length: closeStart)
            let openRange = nsPrefix.range(of: openTrigger, options: .backwards, range: searchRange)
            guard openRange.location != NSNotFound else { continue }

            let contentStart = openRange.location + openLength
            guard contentStart <= closeStart else { continue }
            let contentLength = closeStart - contentStart
            let content = nsPrefix.substring(with: NSRange(location: contentStart, length: contentLength))
            let replacement = pairRule.openReplacement + content + pairRule.closeReplacement

            replaceQuickInputText(
                in: NSRange(location: openRange.location, length: caret - openRange.location),
                with: replacement,
                selectedRange: NSRange(location: openRange.location + (replacement as NSString).length, length: 0),
                documentStyle: documentStyle
            )
            return true
        }

        return false
    }

    private func replaceQuickInputText(
        in range: NSRange,
        with replacement: String,
        selectedRange: NSRange,
        documentStyle: NodeMarkdownDocumentStyle
    ) {
        guard let safeRange = range.clamped(toLength: nodeTextStorage.length) else { return }
        let replacementText = NSAttributedString(string: replacement, attributes: Self.baseAttributes(for: documentStyle))
        isApplyingQuickInputReplacement = true
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.replaceCharacters(in: safeRange, with: replacementText)
        }
        if let projected = projectedSourceText(replacing: safeRange, with: replacement) {
            commitProjectedSourceText(projected)
        } else {
            rebuildSourceTextSnapshotFromStorage()
        }
        if let safeSelection = selectedRange.clamped(toLength: nodeTextStorage.length) {
            self.selectedRange = safeSelection
        }
        isApplyingQuickInputReplacement = false
    }

    private func quickInputSingleCandidates() -> [(trigger: String, replacement: String)] {
        quickInputSettings.singleRules
            .map { ($0.trigger, $0.replacement) }
            .sorted {
                ($0.trigger as NSString).length > ($1.trigger as NSString).length
            }
    }

    private func quickInputPairCandidates() -> [MarkdownPairShortcutRule] {
        quickInputSettings.pairRules.sorted {
            let lhsClose = ($0.closeTrigger as NSString).length
            let rhsClose = ($1.closeTrigger as NSString).length
            if lhsClose != rhsClose {
                return lhsClose > rhsClose
            }
            return ($0.openTrigger as NSString).length > ($1.openTrigger as NSString).length
        }
    }
}
#endif
