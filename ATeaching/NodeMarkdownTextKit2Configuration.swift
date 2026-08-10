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
        onDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?,
        onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?,
        onEditingDraftDirtyChange: ((Bool) -> Void)?,
        onInputSessionStateChange: ((Bool) -> Void)?
    ) {
        let incomingMetadataChanged = rowMetadata != self.rowMetadata
        let incomingValidationError = NodeMarkdownTextKit2DocumentState.validationError(
            text: externalText,
            rowMetadata: rowMetadata
        )
        let incomingDocumentIsValid = incomingValidationError == nil
        self.workingDirectoryURL = workingDirectoryURL
        self.documentStyle = documentStyle
        self.activeRowIndex = activeRowIndex
        self.activeMatchLocationInRow = activeMatchLocationInRow
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if externalText == lastPublishedLocalText {
            lastAcknowledgedLocalRevision = localEditRevision
            lastPublishedLocalText = nil
            if incomingDocumentIsValid {
                self.rowMetadata = rowMetadata
            }
        } else if !hasUnacknowledgedLocalText, incomingDocumentIsValid {
            // 焦点本身不能冻结外部行信息。首次载入时NSTextView可能已经是第一响应者，
            // 但只要没有待确认的本地正文，层级、H3保护和编辑行就必须与正文一起接收。
            self.editingRowIndex = editingRowIndex
            self.rowMetadata = rowMetadata
        }
        if incomingMetadataChanged, !hasUnacknowledgedLocalText, incomingDocumentIsValid {
            if documentState.replace(text: externalText, rowMetadata: rowMetadata) {
                self.rowMetadata = documentState.snapshot.rowMetadata
            }
        } else if incomingMetadataChanged, let incomingValidationError {
            NodeMarkdownTextKit2Diagnostics.log("拒绝接收Node元数据：\(incomingValidationError.description)。")
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
        self.onDocumentSnapshot = onDocumentSnapshot
        self.onCommitEditingNode = onCommitEditingNode
        self.onEditingDraftDirtyChange = onEditingDraftDirtyChange
        self.onInputSessionStateChange = onInputSessionStateChange
        _ = externalTextSyncToken
    }
}
#endif
