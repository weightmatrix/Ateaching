// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

private struct NodeMarkdownTextKit2VisualViewportAnchor {
    let nodeID: String
    let verticalOffset: CGFloat
    let horizontalOrigin: CGFloat
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
        let diagnosticStart = NodeMarkdownDiagnostic35.now()
        defer { recordDiagnostic35Duration("Coordinator同步", since: diagnosticStart) }
        recordDiagnostic35Count("Coordinator同步次数")
        NodeMarkdownDiagnostic31.record(
            "synchronize进入 external/storage=\((externalText as NSString).length)/\(textView.nodeTextStorage.length) token=\(externalTextSyncToken)/\(lastExternalTextSyncToken) localRevision=\(localEditRevision)/\(lastAcknowledgedLocalRevision) unack=\(hasUnacknowledgedLocalText) pendingFocus=\(pendingFocusAnchor != nil)",
            in: textView,
            rowLayouts: rowLayouts
        )
        let markedRange = textView.markedRange()
        let hasActiveComposition = textView.hasActiveInputMethodComposition
        NodeMarkdownTextKit2Diagnostics.log("同步入口：外部应用中=\(isApplyingExternalText)，markedRange=\(NSStringFromRange(markedRange))，有效输入法组合=\(hasActiveComposition)，storage长度=\(textView.nodeTextStorage.length)，外部长度=\((externalText as NSString).length)。")
        guard !isApplyingExternalText else {
            NodeMarkdownTextKit2Diagnostics.log("同步退出：正在安装外部正文。")
            return
        }
        let mustInstallInitialDocument = textView.nodeTextStorage.length == 0 && !externalText.isEmpty
        guard !hasActiveComposition || mustInstallInitialDocument else {
            NodeMarkdownTextKit2Diagnostics.log("同步暂缓：输入法正在组合非空文字。")
            updateTypingAttributes(for: textView)
            return
        }

        let currentText = textView.documentString()
        let hasExplicitExternalSync = externalTextSyncToken != lastExternalTextSyncToken
        let diagnostic41: NodeMarkdownDiagnostic41.Transaction? = {
            guard hasExplicitExternalSync || currentText != externalText else { return nil }
            return beginDiagnostic41(
                "SwiftUI同步 token=\(externalTextSyncToken)/\(lastExternalTextSyncToken) current/external=\((currentText as NSString).length)/\((externalText as NSString).length)",
                in: textView
            )
        }()
        NodeMarkdownTextKit2Diagnostics.log("同步判定：当前长度=\((currentText as NSString).length)，外部长度=\((externalText as NSString).length)，明确外部同步=\(hasExplicitExternalSync)，存在未确认本地正文=\(hasUnacknowledgedLocalText)，有效输入法组合=\(hasActiveComposition)。")
        let viewportAnchor: NodeMarkdownTextKit2VisualViewportAnchor? = {
            guard hasExplicitExternalSync,
                  !currentText.isEmpty else { return nil }
            return captureVisualViewportAnchor(
                in: textView,
                metadata: lastLayoutRowMetadataSnapshot
            )
        }()
        if currentText == externalText {
            recordDiagnostic35Count("同步正文相同")
            NodeMarkdownDiagnostic31.record("synchronize分支=正文相同", in: textView, rowLayouts: rowLayouts)
            NodeMarkdownTextKit2Diagnostics.log("同步分支=正文相同，不替换TextStorage。")
            if lastPublishedLocalText == externalText {
                lastAcknowledgedLocalRevision = localEditRevision
                lastPublishedLocalText = nil
            }
            _ = consumeExternalTextSyncToken(externalTextSyncToken)
            rebuildRowLayoutsIfNeeded(from: textView)
            // 正文没有被替换，TextKit当前选区就是唯一真实焦点。
            forgetRememberedFocus()
        } else if hasUnacknowledgedLocalText && !hasExplicitExternalSync {
            recordDiagnostic35Count("同步保留本地")
            NodeMarkdownDiagnostic31.record("synchronize分支=保留本地正文", in: textView, rowLayouts: rowLayouts)
            NodeMarkdownTextKit2Diagnostics.log("同步分支=保留未确认本地正文，拒绝迟到的普通外部回写。")
            // 只有真正发布且尚未被SwiftUI确认的正文才能阻止外部回写。
            // NSTextView刚挂入窗口时可能已经获得焦点；“正在编辑”不等于“正文已经改变”，
            // 否则磁盘正文首次载入会被空的初始文本挡住，Mac端只剩一块空白编辑器。
            // 本地字符事务已经同步更新当前Node与行坐标。迟到的SwiftUI视图刷新
            // 既没有新正文，也没有外部同步令牌，绝不能借机重建全文或重刷样式。
            // 结构事务和明确外部替换均走其他分支，并继续保留完整重建能力。
            // 迟到的SwiftUI回写不能用输入前记录的行内偏移覆盖原生输入焦点。
            forgetRememberedFocus()
        } else {
            recordDiagnostic35Count("同步全文安装")
            NodeMarkdownDiagnostic31.record("synchronize分支=安装外部正文", in: textView, rowLayouts: rowLayouts)
            NodeMarkdownTextKit2Diagnostics.log("同步分支=安装外部正文。")
            _ = consumeExternalTextSyncToken(externalTextSyncToken)
            let selectedRanges = textView.selectedRanges
            installDocument(
                externalText,
                metadata: rowMetadata,
                in: textView,
                preserving: selectedRanges,
                reason: "synchronize外部替换"
            )
            restoreRememberedFocus(in: textView)
        }

        reportActiveRowIfNeeded(from: textView)
        if let viewportAnchor {
            restoreVisualViewportAnchor(viewportAnchor, in: textView)
        }
        refreshSearchHighlightsIfNeeded(in: textView)
        scrollToActiveRowIfNeeded(in: textView)
        updateTypingAttributes(for: textView)
        if let diagnostic41 {
            finishDiagnostic41(diagnostic41, in: textView)
        }
        NodeMarkdownDiagnostic31.record(
            "synchronize完成 pendingFocus=\(pendingFocusAnchor != nil) editingRow=\(editingRowIndex.map(String.init) ?? "nil")",
            in: textView,
            rowLayouts: rowLayouts
        )
    }

    private func captureVisualViewportAnchor(
        in textView: NodeMarkdownTextKit2TextView,
        metadata: [NodeMarkdownTextKitRowMetadata]
    ) -> NodeMarkdownTextKit2VisualViewportAnchor? {
        guard let scrollView = textView.enclosingScrollView,
              !rowCharacterRanges.isEmpty,
              let viewportRange = textView.nodeTextLayoutManager.textViewportLayoutController.viewportRange else {
            return nil
        }
        let clipView = scrollView.contentView
        let documentStart = textView.nodeMarkdownTextContentStorage.documentRange.location
        let viewportStart = textView.nodeMarkdownTextContentStorage.offset(
            from: documentStart,
            to: viewportRange.location
        )
        let viewportEnd = textView.nodeMarkdownTextContentStorage.offset(
            from: documentStart,
            to: viewportRange.endLocation
        )
        guard let firstVisibleRow = lineIndexForLocation(viewportStart),
              let lastVisibleRow = lineIndexForLocation(viewportEnd),
              firstVisibleRow <= lastVisibleRow else { return nil }
        let anchor: (row: Int, rect: NSRect)? = (firstVisibleRow...lastVisibleRow).lazy.compactMap { row in
            guard metadata.indices.contains(row),
                  self.rowCharacterRanges.indices.contains(row),
                  UUID(uuidString: metadata[row].nodeID) != nil,
                  let rowRect = self.visualRect(forRow: row, in: textView),
                  rowRect.intersects(textView.visibleRect) else { return nil }
            return (row, rowRect)
        }.first
        guard let anchor else { return nil }
        return NodeMarkdownTextKit2VisualViewportAnchor(
            nodeID: metadata[anchor.row].nodeID,
            verticalOffset: anchor.rect.minY - clipView.bounds.minY,
            horizontalOrigin: clipView.bounds.minX
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
            return
        }
        var proposedBounds = clipView.bounds
        proposedBounds.origin = NSPoint(
            x: anchor.horizontalOrigin,
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
