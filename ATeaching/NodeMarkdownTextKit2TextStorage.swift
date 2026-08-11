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
        NodeMarkdownTextKit2Diagnostics.log("TextStorage准备替换全文，输入UTF16长度=\((value as NSString).length)，替换前storage长度=\(nodeTextStorage.length)。")
        let attributed = NSAttributedString(string: value)
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.setAttributedString(attributed)
        }
        nodeSourceTextSnapshot = value
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "TextStorage全文替换完成",
            textView: self,
            bindingText: value
        )

        if let selectedRanges {
            let textLength = (value as NSString).length
            if selectedRanges.allSatisfy({ $0.rangeValue.exact(toLength: textLength) != nil }) {
                let before = selectedRange()
                self.selectedRanges = selectedRanges
                if let requested = selectedRanges.first?.rangeValue {
                    NodeMarkdownDiagnostic31.recordSelectionWrite(
                        "replaceDocumentText恢复选区",
                        before: before,
                        requested: requested,
                        in: self,
                        rowLayouts: nodeMarkdownRowLayouts
                    )
                }
            } else {
                NodeMarkdownTextKit2Diagnostics.log("全文替换后不恢复旧选区：旧选区不在新文档真实范围内。")
            }
        }
    }

    func replaceSourceText(
        in range: NSRange,
        with replacement: String,
        selectedRange: NSRange,
        documentStyle: NodeMarkdownDocumentStyle
    ) {
        guard let safeRange = range.exact(toLength: nodeTextStorage.length),
              let projected = projectedSourceText(replacing: safeRange, with: replacement),
              selectedRange.exact(toLength: (projected as NSString).length) != nil else {
            NodeMarkdownTextKit2Diagnostics.log("拒绝替换正文：替换范围不在真实TextStorage内。")
            return
        }
        let replacementText = NSAttributedString(
            string: replacement,
            attributes: typingAttributes
        )
        nodeTextContentStorage.performEditingTransaction {
            nodeTextStorage.replaceCharacters(in: safeRange, with: replacementText)
        }
        nodeSourceTextSnapshot = projected
        let before = self.selectedRange()
        self.selectedRange = selectedRange
        NodeMarkdownDiagnostic31.recordSelectionWrite(
            "replaceSourceText写选区",
            before: before,
            requested: selectedRange,
            in: self,
            rowLayouts: nodeMarkdownRowLayouts
        )
    }

    func documentString() -> String {
        assertSingleTextStorage()
        return nodeSourceTextSnapshot
    }

    func commitProjectedSourceText(_ value: String) {
        nodeSourceTextSnapshot = value
    }

    func projectedSourceText(replacing range: NSRange, with replacement: String) -> String? {
        let source = nodeSourceTextSnapshot as NSString
        guard let safeRange = range.exact(toLength: source.length) else { return nil }
        return source.replacingCharacters(in: safeRange, with: replacement)
    }

    func assertSourceSnapshotMatchesStorage(file: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        let reconstructed = sourceTextPreservingAttachmentTokens(from: nodeTextStorage)
        assert(reconstructed == nodeSourceTextSnapshot, "TextKit2 source snapshot diverged from canonical text storage", file: file, line: line)
        #endif
    }

    func sourceSnapshotMatchesStorage() -> Bool {
        sourceTextPreservingAttachmentTokens(from: nodeTextStorage) == nodeSourceTextSnapshot
    }

    func displayedAttributedString() -> NSAttributedString {
        assertSingleTextStorage()
        return NSAttributedString(attributedString: nodeTextStorage)
    }

    /// 渲染态只把源码首字符临时换成附件占位符；回到源码态时也只做1:1原位恢复。
    /// 该操作不改变UTF-16长度、换行和任何选择位置。
    func restoreAttachmentSourceAnchors(in requestedRange: NSRange) {
        guard let safeRange = requestedRange.exact(toLength: nodeTextStorage.length) else {
            NodeMarkdownTextKit2Diagnostics.log("拒绝恢复附件源码锚点：请求范围与真实TextStorage不一致。")
            return
        }
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

    private func sourceTextPreservingAttachmentTokens(from attributedString: NSAttributedString) -> String? {
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
                let nextIndex = NSMaxRange(effectiveRange)
                guard effectiveRange.location == index,
                      nextIndex > index,
                      nextIndex <= nsText.length else { return nil }
                index = nextIndex
                continue
            }
            guard effectiveRange.location == index,
                  effectiveRange.length > 0,
                  NSMaxRange(effectiveRange) <= nsText.length else { return nil }
            output.append(nsText.substring(with: effectiveRange))
            index = NSMaxRange(effectiveRange)
        }
        return output
    }

}
#endif
