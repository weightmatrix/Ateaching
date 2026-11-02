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

// MARK: - In-place edit command channel
//
// 父页面(插入画图、随堂插入H3包)需要把一次“本行/局部结构”修改交给
// ProseMirror 事务就地完成，而不是重新解析整篇文档。每个请求带唯一 id，
// Coordinator 只应用一次，避免 SwiftUI 重复 update 时重复执行。
enum NodeMarkdownInPlaceEditCommand: Equatable {
    /// 替换单个 Node 的正文（画图插入）。执行后发布快照，让父页面据此重建文档。
    case replaceNodeText(nodeID: UUID, content: String)
    /// 将 ProseMirror 状态就地同步到目标 Node 序列（随堂插入H3包）。
    /// 父页面已经自行更新 document/textKitDraft，因此这里不发布快照。
    case synchronize(nodes: [NodeMarkdownTextKit2Node])
}

struct NodeMarkdownInPlaceEditRequest: Equatable {
    let id: UUID
    let command: NodeMarkdownInPlaceEditCommand
    let diagnosticID: String?

    init(id: UUID = UUID(), command: NodeMarkdownInPlaceEditCommand, diagnosticID: String? = nil) {
        self.id = id
        self.command = command
        self.diagnosticID = diagnosticID
    }
}

// MARK: - NodeMarkdown TextKit 2 Editor - Step 4 - NodeMarkdown row layout foundation
struct NodeMarkdownTextKit2Editor: View {
    @Binding var text: String
    let workingDirectoryURL: URL?
    let documentStyle: NodeMarkdownDocumentStyle
    let activeRowIndex: Int?
    let navigationRequestToken: Int
    let activeMatchLocationInRow: Int?
    let editingRowIndex: Int?
    let searchQuery: String
    let rowMetadata: [NodeMarkdownTextKitRowMetadata]
    let externalTextSyncToken: Int
    let quickInputSettings: MarkdownQuickInputSettings
    let draftCommitController: NodeMarkdownLegacyDraftCommitController?
    var inPlaceEditRequest: NodeMarkdownInPlaceEditRequest? = nil
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
    var onBeginEditing: (() -> Void)?

    var body: some View {
        #if os(macOS)
        NodeMarkdownProseMirrorRepresentable(
            text: $text,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            activeRowIndex: activeRowIndex,
            navigationRequestToken: navigationRequestToken,
            activeMatchLocationInRow: activeMatchLocationInRow,
            editingRowIndex: editingRowIndex,
            searchQuery: searchQuery,
            rowMetadata: rowMetadata,
            externalTextSyncToken: externalTextSyncToken,
            quickInputSettings: quickInputSettings,
            draftCommitController: draftCommitController,
            inPlaceEditRequest: inPlaceEditRequest,
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
            onInputSessionStateChange: onInputSessionStateChange,
            onBeginEditing: onBeginEditing
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
    let navigationRequestToken: Int
    let activeMatchLocationInRow: Int?
    let editingRowIndex: Int?
    let searchQuery: String
    let rowMetadata: [NodeMarkdownTextKitRowMetadata]
    let externalTextSyncToken: Int
    let quickInputSettings: MarkdownQuickInputSettings
    let draftCommitController: NodeMarkdownLegacyDraftCommitController?
    var inPlaceEditRequest: NodeMarkdownInPlaceEditRequest? = nil
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
    var onBeginEditing: (() -> Void)?
}
#endif
