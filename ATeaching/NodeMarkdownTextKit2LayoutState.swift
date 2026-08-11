// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func rebuildRowRanges(from textView: NodeMarkdownTextKit2TextView) {
        rebuildRowLayouts(from: textView)
    }

    func rebuildRowLayoutsIfNeeded(from textView: NodeMarkdownTextKit2TextView) {
        let value = textView.documentString()
        let textChanged = value != lastLayoutTextSnapshot
        let styleChanged = lastLayoutDocumentStyleIdentity != documentStyle.renderIdentity
        let layoutMetadataChanged = !NodeMarkdownTextKitRowMetadata.collectionsHaveSameLayoutIdentity(
            rowMetadata,
            lastLayoutRowMetadataSnapshot
        )
        guard textChanged || styleChanged || layoutMetadataChanged else {
            // SourceID/SourceFile已经进入Coordinator，但它们不改变任何视觉属性。
            lastLayoutRowMetadataSnapshot = rowMetadata
            return
        }
        rebuildRowLayouts(from: textView, value: value)
    }

    func rebuildRowLayouts(from textView: NodeMarkdownTextKit2TextView) {
        rebuildRowLayouts(from: textView, value: textView.documentString())
    }

    func rebuildRowLayouts(
        from textView: NodeMarkdownTextKit2TextView,
        value: String,
        applyStyles: Bool = true
    ) {
        if let error = NodeMarkdownTextKit2DocumentState.validationError(
            text: value,
            rowMetadata: rowMetadata
        ) {
            NodeMarkdownTextKit2Diagnostics.log("拒绝重建行布局：\(error.description)。")
            return
        }
        editingParagraphStyleCache.removeAll(keepingCapacity: true)
        rowLayouts = Self.makeRowLayouts(
            in: value,
            documentStyle: documentStyle,
            rowMetadata: rowMetadata
        )
        rowCharacterRanges = rowLayouts.map(\.range)
        lastLayoutTextSnapshot = value
        lastLayoutDocumentStyleIdentity = documentStyle.renderIdentity
        lastLayoutRowMetadataSnapshot = rowMetadata
        textView.nodeMarkdownRowLayouts = rowLayouts
        NodeMarkdownTextKit2Diagnostics.log("行布局重建完成，正文UTF16长度=\((value as NSString).length)，rowLayouts=\(rowLayouts.count)，metadata=\(rowMetadata.count)，applyStyles=\(applyStyles)。")
        if applyStyles {
            applyRowStyles(to: textView)
        }
        updateTypingAttributes(for: textView)
    }

    func updateRowLayoutsAfterCharacterEdit(
        in textView: NodeMarkdownTextKit2TextView,
        value: String,
        affectedRange: NSRange
    ) -> Bool {
        guard !rowLayouts.isEmpty, !rowCharacterRanges.isEmpty else { return false }
        let nsText = value as NSString
        guard nsText.length > 0 else {
            rebuildRowLayouts(from: textView, value: value, applyStyles: false)
            return true
        }

        guard affectedRange.exact(toLength: nsText.length) != nil else { return false }
        let anchor = affectedRange.location == nsText.length
            ? nsText.length - 1
            : affectedRange.location
        guard let rowIndex = lineIndexForLocation(anchor), rowLayouts.indices.contains(rowIndex) else {
            return false
        }

        let lineRange = nsText.lineRange(for: NSRange(location: anchor, length: 0))
        guard let rebuiltLayout = Self.makeRowLayout(
            rowIndex: rowIndex,
            lineRange: lineRange,
            source: nsText,
            previousLayout: rowIndex > 0 && rowLayouts.indices.contains(rowIndex - 1) ? rowLayouts[rowIndex - 1] : nil,
            documentStyle: documentStyle,
            rowMetadata: rowMetadata
        ) else {
            return false
        }

        let previousLayout = rowLayouts[rowIndex]
        if previousLayout.level != rebuiltLayout.level || previousLayout.prefix != rebuiltLayout.prefix {
            editingParagraphStyleCache.removeValue(forKey: rowIndex)
            editingParagraphStyleCache.removeValue(forKey: rowIndex + 1)
        }
        guard let reconciledLayouts = NodeMarkdownTextKit2RowLayoutReconciler.replacingRow(
            in: rowLayouts,
            rowIndex: rowIndex,
            with: rebuiltLayout,
            documentLength: nsText.length
        ) else { return false }
        rowLayouts = reconciledLayouts
        rowCharacterRanges = reconciledLayouts.map(\.range)

        lastLayoutTextSnapshot = value
        lastLayoutDocumentStyleIdentity = documentStyle.renderIdentity
        lastLayoutRowMetadataSnapshot = rowMetadata
        textView.nodeMarkdownRowLayouts = rowLayouts
        updateTypingAttributes(for: textView)
        return true
    }

    func currentRowIndex(in textView: NodeMarkdownTextKit2TextView) -> Int? {
        let nsText = textView.documentString() as NSString
        if nsText.length == 0 {
            return rowLayouts.isEmpty ? nil : 0
        }
        let selection = textView.selectedRange()
        guard selection.exact(toLength: nsText.length) != nil else { return nil }
        let safeLocation = selection.location
        if safeLocation == nsText.length,
           let lastRange = rowCharacterRanges.last,
           lastRange.location == nsText.length,
           lastRange.length == 0 {
            return rowCharacterRanges.indices.last
        }
        let anchor = safeLocation == nsText.length ? max(0, nsText.length - 1) : safeLocation
        if let index = lineIndexForLocation(anchor) {
            return index
        }
        return nil
    }

    func lineIndexForRange(_ range: NSRange) -> Int? {
        guard range.location != NSNotFound,
              range.length >= 0,
              let index = lineIndexForLocation(range.location),
              rowCharacterRanges.indices.contains(index) else { return nil }
        let rowRange = rowCharacterRanges[index]
        guard range.location >= rowRange.location,
              NSMaxRange(range) <= NSMaxRange(rowRange) else { return nil }
        return index
    }

    func lineIndexForLocation(_ location: Int) -> Int? {
        guard !rowCharacterRanges.isEmpty else { return nil }
        if let lastRange = rowCharacterRanges.last,
           lastRange.length == 0,
           location == lastRange.location {
            return rowCharacterRanges.indices.last
        }
        var low = 0
        var high = rowCharacterRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = rowCharacterRanges[mid]
            if location < range.location {
                high = mid - 1
            } else if location >= NSMaxRange(range) {
                low = mid + 1
            } else {
                return mid
            }
        }
        return nil
    }

    private static func makeRowLayouts(
        in value: String,
        documentStyle: NodeMarkdownDocumentStyle,
        rowMetadata: [NodeMarkdownTextKitRowMetadata]
    ) -> [NodeMarkdownTextKit2RowLayout] {
        let nsText = value as NSString
        let renderContract = NodeMarkdownRenderContract.default
        if nsText.length == 0 {
            guard rowMetadata.count == 1 else { return [] }
            let level = rowMetadata[0].level
            let lineStyle = renderContract.lineStyle(
                level: level,
                prefix: "",
                documentStyle: documentStyle
            )
            return [NodeMarkdownTextKit2RowLayout(
                rowIndex: 0,
                range: NSRange(location: 0, length: 0),
                contentRange: NSRange(location: 0, length: 0),
                prefix: "",
                level: level,
                lineStyle: lineStyle,
                spacingBefore: 0,
                isProtectedH3: rowMetadata[0].isProtectedH3
            )]
        }
        var layouts: [NodeMarkdownTextKit2RowLayout] = []
        var cursor = 0
        while cursor < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let rowIndex = layouts.count
            if let layout = makeRowLayout(
                rowIndex: rowIndex,
                lineRange: lineRange,
                source: nsText,
                previousLayout: layouts.last,
                documentStyle: documentStyle,
                rowMetadata: rowMetadata,
                renderContract: renderContract
            ) {
                layouts.append(layout)
            }
            let next = NSMaxRange(lineRange)
            if next <= cursor { break }
            cursor = next
        }
        if value.hasSuffix("\n") {
            let rowIndex = layouts.count
            guard rowMetadata.indices.contains(rowIndex) else { return [] }
            let level = rowMetadata[rowIndex].level
            let lineStyle = renderContract.lineStyle(
                level: level,
                prefix: "",
                documentStyle: documentStyle
            )
            layouts.append(NodeMarkdownTextKit2RowLayout(
                rowIndex: rowIndex,
                range: NSRange(location: nsText.length, length: 0),
                contentRange: NSRange(location: nsText.length, length: 0),
                prefix: "",
                level: level,
                lineStyle: lineStyle,
                spacingBefore: spacingBeforeRow(
                    previousLayout: layouts.last,
                    currentLevel: level,
                    currentLineStyle: lineStyle
                ),
                isProtectedH3: rowMetadata[rowIndex].isProtectedH3
            ))
        }
        return layouts
    }

    private static func makeRowLayout(
        rowIndex: Int,
        lineRange: NSRange,
        source nsText: NSString,
        previousLayout: NodeMarkdownTextKit2RowLayout?,
        documentStyle: NodeMarkdownDocumentStyle,
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        renderContract: NodeMarkdownRenderContract = .default
    ) -> NodeMarkdownTextKit2RowLayout? {
        guard let safeRange = lineRange.exact(toLength: nsText.length),
              safeRange.length > 0 else { return nil }
        let lineText = nsText.substring(with: safeRange)
        let hasTrailingNewline = lineText.hasSuffix("\n")
        let prefix = ""
        guard rowMetadata.indices.contains(rowIndex) else { return nil }
        let level = rowMetadata[rowIndex].level
        let coreLength = max(0, safeRange.length - (hasTrailingNewline ? 1 : 0))
        let contentRange = NSRange(
            location: safeRange.location,
            length: coreLength
        )
        let lineStyle = renderContract.lineStyle(
            level: level,
            prefix: prefix,
            documentStyle: documentStyle
        )
        let isProtectedH3 = rowMetadata[rowIndex].isProtectedH3
        let spacingBefore = spacingBeforeRow(
            previousLayout: previousLayout,
            currentLevel: level,
            currentLineStyle: lineStyle
        )
        return NodeMarkdownTextKit2RowLayout(
            rowIndex: rowIndex,
            range: safeRange,
            contentRange: contentRange,
            prefix: prefix,
            level: level,
            lineStyle: lineStyle,
            spacingBefore: spacingBefore,
            isProtectedH3: isProtectedH3
        )
    }

    private static func spacingBeforeRow(
        previousLayout: NodeMarkdownTextKit2RowLayout?,
        currentLevel: Int,
        currentLineStyle: NodeMarkdownRenderContract.LineStyle
    ) -> CGFloat {
        NodeMarkdownRenderContract.interRowSpacing(
            previousLevel: previousLayout?.level,
            previousRoleStyle: previousLayout?.lineStyle.roleStyle,
            currentLevel: currentLevel,
            currentRoleStyle: currentLineStyle.roleStyle
        )
    }

}
#endif
