// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

struct NodeMarkdownTextKit2QuickInputEdit {
    let sourceBeforeReplacement: NSString
    let range: NSRange
    let replacement: String

    var characterDelta: Int {
        (replacement as NSString).length - range.length
    }

    var changesLineStructure: Bool {
        let removed = sourceBeforeReplacement.substring(with: range)
        return removed.contains("\n")
            || removed.contains("\r")
            || replacement.contains("\n")
            || replacement.contains("\r")
    }
}

extension NodeMarkdownTextKit2TextView {
    func applyQuickInputIfNeeded(
        documentStyle: NodeMarkdownDocumentStyle
    ) -> NodeMarkdownTextKit2QuickInputEdit? {
        guard !isApplyingQuickInputReplacement else { return nil }
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }

        let nsText = documentString() as NSString
        guard selection.exact(toLength: nsText.length) != nil else {
            NodeMarkdownTextKit2Diagnostics.log("跳过快捷替换：选区不在真实正文内。")
            return nil
        }
        let caret = selection.location
        let prefix = nsText.substring(to: caret)

        if let edit = applyPairQuickInputIfNeeded(
            prefix: prefix,
            caret: caret,
            documentStyle: documentStyle
        ) {
            return edit
        }

        for candidate in quickInputSingleCandidates() {
            guard !candidate.trigger.isEmpty else { continue }
            guard candidate.replacement != candidate.trigger else { continue }
            guard prefix.hasSuffix(candidate.trigger) else { continue }

            let triggerLength = (candidate.trigger as NSString).length
            let replacementLength = (candidate.replacement as NSString).length
            let start = caret - triggerLength
            guard start >= 0 else { continue }

            return replaceQuickInputText(
                in: NSRange(location: start, length: triggerLength),
                with: candidate.replacement,
                selectedRange: NSRange(location: start + replacementLength, length: 0),
                documentStyle: documentStyle
            )
        }
        return nil
    }

    private func applyPairQuickInputIfNeeded(
        prefix: String,
        caret: Int,
        documentStyle: NodeMarkdownDocumentStyle
    ) -> NodeMarkdownTextKit2QuickInputEdit? {
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

            return replaceQuickInputText(
                in: NSRange(location: openRange.location, length: caret - openRange.location),
                with: replacement,
                selectedRange: NSRange(location: openRange.location + (replacement as NSString).length, length: 0),
                documentStyle: documentStyle
            )
        }

        return nil
    }

    private func replaceQuickInputText(
        in range: NSRange,
        with replacement: String,
        selectedRange: NSRange,
        documentStyle: NodeMarkdownDocumentStyle
    ) -> NodeMarkdownTextKit2QuickInputEdit? {
        let sourceBeforeReplacement = documentString() as NSString
        guard let safeRange = range.exact(toLength: nodeTextStorage.length),
              safeRange.exact(toLength: sourceBeforeReplacement.length) != nil else { return nil }
        guard let projected = projectedSourceText(replacing: safeRange, with: replacement) else {
            return nil
        }
        let projectedLength = (projected as NSString).length
        guard let safeSelection = selectedRange.exact(toLength: projectedLength) else {
            return nil
        }
        let edit = NodeMarkdownTextKit2QuickInputEdit(
            sourceBeforeReplacement: sourceBeforeReplacement,
            range: safeRange,
            replacement: replacement
        )
        let replacementText = NSAttributedString(string: replacement, attributes: typingAttributes)
        isApplyingQuickInputReplacement = true
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.replaceCharacters(in: safeRange, with: replacementText)
        }
        commitProjectedSourceText(projected)
        self.selectedRange = safeSelection
        isApplyingQuickInputReplacement = false
        return edit
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
