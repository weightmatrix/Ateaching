// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Representable {
    func makeCoordinator() -> NodeMarkdownTextKit2Coordinator {
        NodeMarkdownTextKit2Coordinator(
            text: $text,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow,
            editingRowIndex: editingRowIndex,
            searchQuery: searchQuery,
            rowMetadata: rowMetadata,
            externalTextSyncToken: externalTextSyncToken,
            quickInputSettings: quickInputSettings,
            draftCommitController: draftCommitController,
            onTextChange: onTextChange,
            onTextChangeWithRowMetadata: onTextChangeWithRowMetadata,
            onRequestInsertImageAtRow: onRequestInsertImageAtRow,
            onRequestDeleteNodePackageAtRow: onRequestDeleteNodePackageAtRow,
            onRequestCutNodePackageAtRow: onRequestCutNodePackageAtRow,
            onRequestPasteNodePackageAfterRow: onRequestPasteNodePackageAfterRow,
            canPasteNodePackage: canPasteNodePackage,
            onRequestDeleteProtectedH3AtRow: onRequestDeleteProtectedH3AtRow,
            onRequestOpenDrawingBoardAtRow: onRequestOpenDrawingBoardAtRow,
            onActiveRowChange: onActiveRowChange,
            onFocusLocationChange: onFocusLocationChange,
            onDocumentSnapshot: onDocumentSnapshot,
            onCommitEditingNode: onCommitEditingNode,
            onEditingDraftDirtyChange: onEditingDraftDirtyChange,
            onInputSessionStateChange: onInputSessionStateChange
        )
    }
}
#endif
