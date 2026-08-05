// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    func update(
        externalText: String,
        workingDirectoryURL: URL?,
        documentStyle: NodeMarkdownDocumentStyle,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?,
        editingRowIndex: Int?,
        searchQuery: String,
        rowMetadata: [NodeMarkdownTextKitRowMetadata],
        externalTextSyncToken: Int,
        quickInputSettings: MarkdownQuickInputSettings,
        onTextChange: ((String) -> Void)?,
        onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?,
        onRequestInsertImageAtRow: ((Int) -> String?)?,
        onRequestDeleteNodePackageAtRow: ((Int) -> Void)?,
        onRequestCutNodePackageAtRow: ((Int) -> Void)?,
        onRequestPasteNodePackageAfterRow: ((Int) -> Void)?,
        canPasteNodePackage: (() -> Bool)?,
        onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?,
        onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?,
        onActiveRowChange: ((Int?) -> Void)?,
        onFocusLocationChange: ((NodeMarkdownTextFocusLocation?) -> Void)?,
        onInputSessionStateChange: ((Bool) -> Void)?
    ) {
        self.workingDirectoryURL = workingDirectoryURL
        self.documentStyle = documentStyle
        self.activeRowIndex = activeRowIndex
        self.activeMatchLocationInRow = activeMatchLocationInRow
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if externalText == lastPublishedLocalText {
            lastAcknowledgedLocalRevision = localEditRevision
            lastPublishedLocalText = nil
            self.rowMetadata = rowMetadata
        } else if !hasUnacknowledgedLocalText {
            // 焦点本身不能冻结外部行信息。首次载入时NSTextView可能已经是第一响应者，
            // 但只要没有待确认的本地正文，层级、H3保护和编辑行就必须与正文一起接收。
            self.editingRowIndex = editingRowIndex
            self.rowMetadata = rowMetadata
        }
        self.quickInputSettings = quickInputSettings
        self.onTextChange = onTextChange
        self.onTextChangeWithRowMetadata = onTextChangeWithRowMetadata
        self.onRequestInsertImageAtRow = onRequestInsertImageAtRow
        self.onRequestDeleteNodePackageAtRow = onRequestDeleteNodePackageAtRow
        self.onRequestCutNodePackageAtRow = onRequestCutNodePackageAtRow
        self.onRequestPasteNodePackageAfterRow = onRequestPasteNodePackageAfterRow
        self.canPasteNodePackage = canPasteNodePackage
        self.onRequestDeleteProtectedH3AtRow = onRequestDeleteProtectedH3AtRow
        self.onRequestOpenDrawingBoardAtRow = onRequestOpenDrawingBoardAtRow
        self.onActiveRowChange = onActiveRowChange
        self.onFocusLocationChange = onFocusLocationChange
        self.onInputSessionStateChange = onInputSessionStateChange
        _ = externalTextSyncToken
    }
}
#endif
