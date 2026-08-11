// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct NodeMarkdownTextFocusLocation: Equatable {
    let rowIndex: Int?
    let location: Int
    let length: Int
    let column: Int?
}

// MARK: - NodeMarkdown TextKit 2 Editor - Step 4 - NodeMarkdown row layout foundation
struct NodeMarkdownTextKit2Editor: View {
    @Binding var text: String
    let workingDirectoryURL: URL?
    let documentStyle: NodeMarkdownDocumentStyle
    let activeRowIndex: Int?
    let activeMatchLocationInRow: Int?
    let editingRowIndex: Int?
    let searchQuery: String
    let rowMetadata: [NodeMarkdownTextKitRowMetadata]
    let externalTextSyncToken: Int
    let quickInputSettings: MarkdownQuickInputSettings
    let draftCommitController: NodeMarkdownLegacyDraftCommitController?
    var onTextChange: ((String) -> Void)?
    var onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?
    var onRequestInsertImageAtRow: ((Int) -> String?)?
    var onRequestDeleteNodePackageAtRow: ((Int) -> Void)?
    var onRequestCutNodePackageAtRow: ((Int) -> Void)?
    var onRequestPasteNodePackageAfterRow: ((Int) -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?
    var onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?
    var onActiveRowChange: ((Int?) -> Void)?
    var onFocusLocationChange: ((NodeMarkdownTextFocusLocation?) -> Void)?
    var onDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?
    var onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?
    var onEditingDraftDirtyChange: ((Bool) -> Void)?
    var onRequestSave: (() -> Void)?
    var onInputSessionStateChange: ((Bool) -> Void)?

    var body: some View {
        #if os(macOS)
        NodeMarkdownTextKit2Representable(
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
            onRequestSave: onRequestSave,
            onInputSessionStateChange: onInputSessionStateChange
        )
        #else
        let displayStyle = documentStyle.platformDisplayStyle
        TextEditor(text: $text)
            .font(.system(size: CGFloat(displayStyle.style(forLevel: 7).fontSize), design: .monospaced))
            .onChange(of: text) { _, newValue in
                onTextChange?(newValue)
            }
        #endif
    }
}

#if os(macOS)
struct NodeMarkdownTextKit2Representable: NSViewRepresentable {
    @Binding var text: String
    let workingDirectoryURL: URL?
    let documentStyle: NodeMarkdownDocumentStyle
    let activeRowIndex: Int?
    let activeMatchLocationInRow: Int?
    let editingRowIndex: Int?
    let searchQuery: String
    let rowMetadata: [NodeMarkdownTextKitRowMetadata]
    let externalTextSyncToken: Int
    let quickInputSettings: MarkdownQuickInputSettings
    let draftCommitController: NodeMarkdownLegacyDraftCommitController?
    var onTextChange: ((String) -> Void)?
    var onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?
    var onRequestInsertImageAtRow: ((Int) -> String?)?
    var onRequestDeleteNodePackageAtRow: ((Int) -> Void)?
    var onRequestCutNodePackageAtRow: ((Int) -> Void)?
    var onRequestPasteNodePackageAfterRow: ((Int) -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?
    var onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?
    var onActiveRowChange: ((Int?) -> Void)?
    var onFocusLocationChange: ((NodeMarkdownTextFocusLocation?) -> Void)?
    var onDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?
    var onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?
    var onEditingDraftDirtyChange: ((Bool) -> Void)?
    var onRequestSave: (() -> Void)?
    var onInputSessionStateChange: ((Bool) -> Void)?
}
#endif
