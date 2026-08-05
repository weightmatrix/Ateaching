// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif

#if os(macOS)
final class NodeMarkdownTextKit2Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>
    var workingDirectoryURL: URL?
    var documentStyle: NodeMarkdownDocumentStyle
    var activeRowIndex: Int?
    var activeMatchLocationInRow: Int?
    var editingRowIndex: Int?
    var searchQuery: String
    var rowMetadata: [NodeMarkdownTextKitRowMetadata]
    var quickInputSettings: MarkdownQuickInputSettings
    var rowCharacterRanges: [NSRange] = []
    var rowLayouts: [NodeMarkdownTextKit2RowLayout] = []
    var lastLayoutTextSnapshot = ""
    var lastLayoutDocumentStyleIdentity: NodeMarkdownDocumentStyleRecord?
    var lastLayoutRowMetadataSnapshot: [NodeMarkdownTextKitRowMetadata] = []
    var lastAppliedSearchQuery = ""
    var lastAppliedActiveRowIndex: Int?
    var lastAppliedActiveMatchLocationInRow: Int?
    var lastAppliedEditingRowIndex: Int?
    var lastReportedActiveRowIndex: Int?
    var lastReportedFocusLocation: NodeMarkdownTextFocusLocation?
    var lastScrolledActiveRowIndex: Int?
    var lastExternalTextSyncToken: Int
    var editingParagraphStyleCache: [Int: NSParagraphStyle] = [:]
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
    var onInputSessionStateChange: ((Bool) -> Void)?
    var isApplyingExternalText = false
    var isApplyingStyleUpdate = false
    var shouldRefreshCurrentRowAfterTextChange = true
    var pendingTextEditImpact: EditorDeletionImpact = .document
    var pendingTextEditAffectedRange: NSRange?
    var pendingTextEditCharacterDelta = 0
    var pendingProjectedRowMetadata: [NodeMarkdownTextKitRowMetadata]?
    var pendingProjectedSourceText: String?
    /// 原生编辑会话期间，TextKit2正文与行元数据是唯一权威；SwiftUI回写只能确认，不能反向覆盖。
    var isLocalEditingSessionActive = false
    var localEditRevision: UInt64 = 0
    var lastAcknowledgedLocalRevision: UInt64 = 0
    var lastPublishedLocalText: String?
    /// 是否存在已从原生编辑器发布、但尚未由SwiftUI绑定回送确认的正文。
    /// 第一响应者和输入会话状态不能代替这个判断，否则首次载入会被空初始文本阻断。
    var hasUnacknowledgedLocalText: Bool {
        lastPublishedLocalText != nil
    }
    var pendingFocusAnchor: NodeMarkdownTextKit2FocusAnchor?
    private weak var textView: NodeMarkdownTextKit2TextView?

    init(
        text: Binding<String>,
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
        self.text = text
        self.workingDirectoryURL = workingDirectoryURL
        self.documentStyle = documentStyle
        self.activeRowIndex = activeRowIndex
        self.activeMatchLocationInRow = activeMatchLocationInRow
        self.editingRowIndex = editingRowIndex
        self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rowMetadata = rowMetadata
        self.quickInputSettings = quickInputSettings
        lastExternalTextSyncToken = externalTextSyncToken
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
    }

    func attach(_ textView: NodeMarkdownTextKit2TextView) {
        self.textView = textView
        if rowCharacterRanges.isEmpty {
            rebuildRowLayouts(from: textView)
        }
    }

}
#endif
