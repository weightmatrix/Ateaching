// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

private struct NodeMarkdownTextKit2VisualViewportAnchor {
    let nodeID: String
    let verticalOffset: CGFloat
    let fallbackOrigin: NSPoint
}

extension NodeMarkdownTextKit2Coordinator {
    func hasPendingExternalTextSync(_ token: Int) -> Bool {
        token != lastExternalTextSyncToken
    }

    func synchronize(
        _ textView: NodeMarkdownTextKit2TextView,
        externalText: String,
        externalTextSyncToken: Int
    ) {
        applyBaseStyle(to: textView)
        guard !isApplyingExternalText else { return }
        guard textView.markedRange().location == NSNotFound else {
            updateTypingAttributes(for: textView)
            return
        }

        let currentText = textView.documentString()
        let hasExplicitExternalSync = externalTextSyncToken != lastExternalTextSyncToken
        let viewportAnchor: NodeMarkdownTextKit2VisualViewportAnchor? = {
            guard hasExplicitExternalSync,
                  !currentText.isEmpty else { return nil }
            return captureVisualViewportAnchor(
                in: textView,
                metadata: lastLayoutRowMetadataSnapshot
            )
        }()
        if currentText == externalText {
            if lastPublishedLocalText == externalText {
                lastAcknowledgedLocalRevision = localEditRevision
                lastPublishedLocalText = nil
            }
            _ = consumeExternalTextSyncToken(externalTextSyncToken)
            rebuildRowLayoutsIfNeeded(from: textView)
            restoreRememberedFocus(in: textView)
        } else if hasUnacknowledgedLocalText && !hasExplicitExternalSync {
            // 只有真正发布且尚未被SwiftUI确认的正文才能阻止外部回写。
            // NSTextView刚挂入窗口时可能已经获得焦点；“正在编辑”不等于“正文已经改变”，
            // 否则磁盘正文首次载入会被空的初始文本挡住，Mac端只剩一块空白编辑器。
            rebuildRowLayoutsIfNeeded(from: textView)
            restoreRememberedFocus(in: textView)
        } else {
            _ = consumeExternalTextSyncToken(externalTextSyncToken)
            isApplyingExternalText = true
            let selectedRanges = textView.selectedRanges
            textView.replaceDocumentText(externalText, documentStyle: documentStyle, selectedRanges: selectedRanges)
            isApplyingExternalText = false
            rebuildRowLayouts(from: textView)
            restoreRememberedFocus(in: textView)
            validateTextKit2State(in: textView, deep: true)
        }

        reportActiveRowIfNeeded(from: textView)
        if let viewportAnchor {
            restoreVisualViewportAnchor(viewportAnchor, in: textView)
        } else if hasExplicitExternalSync {
            // 保存状态、工具栏状态等普通SwiftUI更新不属于导航命令。
            // 只有真正替换整篇正文且无法恢复原视野时，才允许定位活动行。
            scrollToActiveRowIfNeeded(in: textView)
        }
        refreshSearchHighlightsIfNeeded(in: textView)
        updateTypingAttributes(for: textView)
    }

    private func captureVisualViewportAnchor(
        in textView: NodeMarkdownTextKit2TextView,
        metadata: [NodeMarkdownTextKitRowMetadata]
    ) -> NodeMarkdownTextKit2VisualViewportAnchor? {
        guard let scrollView = textView.enclosingScrollView,
              !rowCharacterRanges.isEmpty else { return nil }
        let clipView = scrollView.contentView
        let source = textView.documentString() as NSString
        let point = NSPoint(
            x: textView.visibleRect.minX + 2,
            y: textView.visibleRect.minY + 2
        )
        let characterIndex = min(source.length, textView.characterIndexForInsertion(at: point))
        guard let firstVisibleRow = lineIndexForLocation(characterIndex) else { return nil }
        let candidateRows = firstVisibleRow..<min(rowCharacterRanges.count, firstVisibleRow + 12)
        let anchorRow = candidateRows.first { row in
            guard metadata.indices.contains(row), rowCharacterRanges.indices.contains(row) else { return false }
            let range = rowCharacterRanges[row]
            guard range.location <= source.length, NSMaxRange(range) <= source.length else { return false }
            return !source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? firstVisibleRow
        guard metadata.indices.contains(anchorRow),
              !metadata[anchorRow].nodeID.isEmpty,
              let rowRect = visualRect(forRow: anchorRow, in: textView) else { return nil }
        return NodeMarkdownTextKit2VisualViewportAnchor(
            nodeID: metadata[anchorRow].nodeID,
            verticalOffset: rowRect.minY - clipView.bounds.minY,
            fallbackOrigin: clipView.bounds.origin
        )
    }

    private func restoreVisualViewportAnchor(
        _ anchor: NodeMarkdownTextKit2VisualViewportAnchor,
        in textView: NodeMarkdownTextKit2TextView
    ) {
        guard let scrollView = textView.enclosingScrollView else { return }
        let clipView = scrollView.contentView
        guard let row = rowMetadata.firstIndex(where: { $0.nodeID == anchor.nodeID }),
              let rowRect = visualRect(forRow: row, in: textView) else {
            clipView.setBoundsOrigin(anchor.fallbackOrigin)
            scrollView.reflectScrolledClipView(clipView)
            return
        }
        var proposedBounds = clipView.bounds
        proposedBounds.origin = NSPoint(
            x: anchor.fallbackOrigin.x,
            y: rowRect.minY - anchor.verticalOffset
        )
        let constrained = clipView.constrainBoundsRect(proposedBounds)
        clipView.setBoundsOrigin(constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func visualRect(
        forRow row: Int,
        in textView: NodeMarkdownTextKit2TextView
    ) -> NSRect? {
        guard rowCharacterRanges.indices.contains(row),
              let window = textView.window else { return nil }
        let screenRect = textView.firstRect(
            forCharacterRange: rowCharacterRanges[row],
            actualRange: nil
        )
        guard !screenRect.isNull, !screenRect.isEmpty else { return nil }
        let windowRect = window.convertFromScreen(screenRect)
        return textView.convert(windowRect, from: nil)
    }

    private func consumeExternalTextSyncToken(_ token: Int) -> Bool {
        guard token != lastExternalTextSyncToken else { return false }
        lastExternalTextSyncToken = token
        return true
    }
}
#endif
