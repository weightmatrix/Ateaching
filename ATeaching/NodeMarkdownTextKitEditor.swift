// PIPELINE MARKER: NodeMarkdown legacy pipeline (non-TextKit2 split pipeline).
import SwiftUI

#if os(macOS)
import AppKit
#endif

#if canImport(SwiftMath)
import SwiftMath
import CoreText
#endif

private let nodeMarkdownHighlightBackgroundColorKey = NSAttributedString.Key("NodeMarkdownHighlightBackgroundColor")
private let nodeMarkdownSearchHighlightRestoreKey = NSAttributedString.Key("NodeMarkdownSearchHighlightRestore")
#if os(macOS)
private let nodeMarkdownInlineRenderPayloadKey = NSAttributedString.Key("NodeMarkdownInlineRenderPayload")

/// 旧管线的公式和图片只携带绘制信息，绝不替换正文字符。
/// NSTextStorage.string始终是真实Node源码，滚动和样式刷新没有恢复源码这一步。
private final class NodeMarkdownInlineRenderPayload: NSObject {
    let image: NSImage
    let size: NSSize
    let horizontalInset: CGFloat
    let centersOnLineAxis: Bool

    init(
        image: NSImage,
        size: NSSize,
        horizontalInset: CGFloat = 0,
        centersOnLineAxis: Bool = false
    ) {
        self.image = image
        self.size = size
        self.horizontalInset = max(0, horizontalInset)
        self.centersOnLineAxis = centersOnLineAxis
    }
}
#endif

// MARK: - TextKit2编辑器容器 - v1 - 迁移第一步纯文本原生编辑骨架
struct NodeMarkdownTextKitEditor: View {
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
    let legacyDraftCommitController: NodeMarkdownLegacyDraftCommitController?
    var onTextChange: ((String) -> Void)?
    var onRequestInsertImageAtRow: ((Int) -> String?)?
    var onRequestDeleteNodePackageAtRow: ((Int) -> Void)?
    var onRequestCutNodePackageAtRow: ((Int) -> Void)?
    var onRequestPasteNodePackageAfterRow: ((Int) -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?
    var onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?
    var onActiveRowChange: ((Int?) -> Void)?
    var onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?
    var onLegacyDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?
    var onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?
    var onEditingDraftDirtyChange: ((Bool) -> Void)?
    var onInputSessionStateChange: ((Bool) -> Void)?

    var body: some View {
        #if os(macOS)
        if NodeMarkdownFeatureFlags.textKit2EditorEnabled {
            NodeMarkdownTextKit2Editor(
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
                onTextChange: onTextChange,
                onRequestInsertImageAtRow: onRequestInsertImageAtRow,
                onRequestDeleteNodePackageAtRow: onRequestDeleteNodePackageAtRow,
                onRequestCutNodePackageAtRow: onRequestCutNodePackageAtRow,
                onRequestPasteNodePackageAfterRow: onRequestPasteNodePackageAfterRow,
                canPasteNodePackage: canPasteNodePackage,
                onRequestDeleteProtectedH3AtRow: onRequestDeleteProtectedH3AtRow,
                onRequestOpenDrawingBoardAtRow: onRequestOpenDrawingBoardAtRow,
                onActiveRowChange: onActiveRowChange,
                onFocusLocationChange: nil,
                onInputSessionStateChange: onInputSessionStateChange
            )
        } else {
            NodeMarkdownTextKitRepresentable(
                text: $text,
                workingDirectoryURL: workingDirectoryURL,
                documentStyle: documentStyle,
                activeRowIndex: activeRowIndex,
                activeMatchLocationInRow: activeMatchLocationInRow,
                searchQuery: searchQuery,
                rowMetadata: rowMetadata,
                externalTextSyncToken: externalTextSyncToken,
                quickInputSettings: quickInputSettings,
                draftCommitController: legacyDraftCommitController,
                onTextChange: onTextChange,
                onRequestInsertImageAtRow: onRequestInsertImageAtRow,
                onRequestDeleteNodePackageAtRow: onRequestDeleteNodePackageAtRow,
                onRequestCutNodePackageAtRow: onRequestCutNodePackageAtRow,
                onRequestPasteNodePackageAfterRow: onRequestPasteNodePackageAfterRow,
                canPasteNodePackage: canPasteNodePackage,
                onRequestDeleteProtectedH3AtRow: onRequestDeleteProtectedH3AtRow,
                onRequestOpenDrawingBoardAtRow: onRequestOpenDrawingBoardAtRow,
                onActiveRowChange: onActiveRowChange,
                onTextChangeWithRowMetadata: onTextChangeWithRowMetadata,
                onLegacyDocumentSnapshot: onLegacyDocumentSnapshot,
                onCommitEditingNode: onCommitEditingNode,
                onEditingDraftDirtyChange: onEditingDraftDirtyChange,
                onInputSessionStateChange: onInputSessionStateChange
            )
        }
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
private struct NodeMarkdownTextKitRepresentable: NSViewRepresentable {
    @Binding var text: String
    let workingDirectoryURL: URL?
    let documentStyle: NodeMarkdownDocumentStyle
    let activeRowIndex: Int?
    let activeMatchLocationInRow: Int?
    let searchQuery: String
    let rowMetadata: [NodeMarkdownTextKitRowMetadata]
    let externalTextSyncToken: Int
    let quickInputSettings: MarkdownQuickInputSettings
    let draftCommitController: NodeMarkdownLegacyDraftCommitController?
    var onTextChange: ((String) -> Void)?
    var onRequestInsertImageAtRow: ((Int) -> String?)?
    var onRequestDeleteNodePackageAtRow: ((Int) -> Void)?
    var onRequestCutNodePackageAtRow: ((Int) -> Void)?
    var onRequestPasteNodePackageAfterRow: ((Int) -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?
    var onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?
    var onActiveRowChange: ((Int?) -> Void)?
    var onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?
    var onLegacyDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?
    var onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?
    var onEditingDraftDirtyChange: ((Bool) -> Void)?
    var onInputSessionStateChange: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            workingDirectoryURL: workingDirectoryURL,
            documentStyle: documentStyle,
            activeRowIndex: activeRowIndex,
            activeMatchLocationInRow: activeMatchLocationInRow,
            searchQuery: searchQuery,
            rowMetadata: rowMetadata,
            quickInputSettings: quickInputSettings,
            onTextChange: onTextChange,
            onRequestInsertImageAtRow: onRequestInsertImageAtRow,
            onRequestDeleteNodePackageAtRow: onRequestDeleteNodePackageAtRow,
            onRequestCutNodePackageAtRow: onRequestCutNodePackageAtRow,
            onRequestPasteNodePackageAfterRow: onRequestPasteNodePackageAfterRow,
            canPasteNodePackage: canPasteNodePackage,
            onRequestDeleteProtectedH3AtRow: onRequestDeleteProtectedH3AtRow,
            onRequestOpenDrawingBoardAtRow: onRequestOpenDrawingBoardAtRow,
            onActiveRowChange: onActiveRowChange,
            onTextChangeWithRowMetadata: onTextChangeWithRowMetadata,
            onLegacyDocumentSnapshot: onLegacyDocumentSnapshot,
            onCommitEditingNode: onCommitEditingNode,
            onEditingDraftDirtyChange: onEditingDraftDirtyChange,
            onInputSessionStateChange: onInputSessionStateChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        #if DEBUG
        NodeMarkdownLegacyRegressionSuite.runOnce()
        #endif
        // 旧管线必须是单一TextKit 1对象链。NSTextView会丢弃预连接的
        // NSTextLayoutManager并暗中重建NSLayoutManager，显式连接才能保证IME与渲染共用同一存储。
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NodeMarkdownStyledTextView(frame: .zero, textContainer: textContainer)
        assert(textView.textStorage === textStorage, "Legacy NodeMarkdown must keep its explicit NSTextStorage.")
        assert(textView.layoutManager === layoutManager, "Legacy NodeMarkdown must keep its explicit NSLayoutManager.")
        layoutManager.delegate = textView
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.nodeDocumentStyle = documentStyle
        textView.nodeRowLevels = rowMetadata.map(\.level)
        context.coordinator.primeExternalTextSyncToken(externalTextSyncToken)
        draftCommitController?.install(
            commit: { [weak coordinator = context.coordinator, weak textView] in
                guard let coordinator, let textView else { return }
                coordinator.commitPendingEditingForPersistence(in: textView)
            },
            focusRowEnd: { [weak coordinator = context.coordinator, weak textView] rowIndex in
                guard let coordinator, let textView else { return }
                coordinator.focusAtEnd(ofRow: rowIndex, in: textView)
            }
        )
        textView.imageBaseDirectoryURL = context.coordinator.workingDirectoryURL
        context.coordinator.applyStyle(to: textView)
        textView.onRequestInsertImage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            guard let updatedRowText = coordinator.requestInsertImage(at: rowIndex) else { return }
            coordinator.applyPreparedImageText(updatedRowText, at: rowIndex, in: textView)
        }
        textView.onRequestDeleteNodePackage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            coordinator.prepareDestructiveExternalOperation(in: textView)
            coordinator.requestDeleteNodePackage(at: rowIndex)
        }
        textView.onRequestCutNodePackage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            coordinator.prepareStructuralFocusForExternalOperation(
                at: rowIndex,
                in: textView,
                targetNodeSurvives: false
            )
            coordinator.requestCutNodePackage(at: rowIndex)
        }
        textView.onRequestPasteNodePackage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            coordinator.prepareStructuralFocusForExternalOperation(
                at: rowIndex,
                in: textView,
                targetNodeSurvives: true
            )
            coordinator.requestPasteNodePackage(after: rowIndex)
        }
        textView.canPasteNodePackage = { [weak coordinator = context.coordinator] in
            coordinator?.canPasteNodePackage() ?? false
        }
        textView.canCutNodePackage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return false }
            return coordinator.canMutateNodePackage(at: rowIndex)
        }
        textView.canDeleteNodePackage = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return false }
            return coordinator.canMutateNodePackage(at: rowIndex)
        }
        textView.canDeleteProtectedH3 = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return false }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return false }
            return coordinator.isProtectedH3PackageRoot(at: rowIndex)
        }
        textView.onRequestDeleteProtectedH3 = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            coordinator.prepareDestructiveExternalOperation(in: textView)
            coordinator.requestDeleteProtectedH3(at: rowIndex)
        }
        textView.onHandleTabCommand = { [weak coordinator = context.coordinator, weak textView] increaseLevel in
            guard let coordinator, let textView else { return false }
            return coordinator.handleTabCommandFromView(textView, increaseLevel: increaseLevel)
        }
        textView.onRequestOpenDrawingBoard = { [weak coordinator = context.coordinator, weak textView] in
            guard let coordinator, let textView else { return }
            guard let rowIndex = coordinator.currentRowIndex(in: textView) else { return }
            coordinator.requestOpenDrawingBoard(at: rowIndex)
        }
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NodeMarkdownStyledTextView else { return }
        // marked text是AppKit正在管理的未提交事务。候选期的SwiftUI回刷
        // 不得在同步判断之前修改样式、行元数据或自绘层级。
        guard !context.coordinator.isMarkedTextCompositionActive(in: textView) else { return }
        context.coordinator.isProgrammaticUpdate = true
        defer { context.coordinator.isProgrammaticUpdate = false }
        let hasExternalTextSync = context.coordinator.hasPendingExternalTextSync(externalTextSyncToken)
        if hasExternalTextSync {
            context.coordinator.prepareForExternalDocumentReplacement()
        }
        let didChangeDocumentStyle = context.coordinator.updateDocumentStyle(documentStyle)
        let changedMetadataRows = context.coordinator.updateRowMetadata(rowMetadata)
        context.coordinator.updateActiveRowIndex(activeRowIndex, in: textView)
        context.coordinator.updateActiveMatchLocationInRow(activeMatchLocationInRow, in: textView)
        context.coordinator.updateSearchQuery(searchQuery, in: textView)
        context.coordinator.updateQuickInputSettings(quickInputSettings)
        textView.nodeDocumentStyle = documentStyle
        textView.nodeRowLevels = context.coordinator.rowLevelsSnapshot()
        textView.imageBaseDirectoryURL = context.coordinator.workingDirectoryURL
        if hasExternalTextSync {
            let viewportAnchor = context.coordinator.captureVisualViewportAnchor(in: textView)
            context.coordinator.acceptExternalTextSyncToken(externalTextSyncToken)
            context.coordinator.performPreservingVisibleOrigin(in: textView) {
                let previousSelection = textView.selectedRanges
                textView.string = text
                let textLength = (text as NSString).length
                let restoredRanges = previousSelection.map { value in
                    let range = value.rangeValue
                    let location = max(0, min(range.location, textLength))
                    let maxLength = max(0, textLength - location)
                    let length = max(0, min(range.length, maxLength))
                    return NSValue(range: NSRange(location: location, length: length))
                }
                textView.selectedRanges = restoredRanges
                let adjustedSelection = context.coordinator.clampedSelectionRangeForExternalUpdate(
                    textView.selectedRange(),
                    in: textView
                )
                if adjustedSelection != textView.selectedRange() {
                    textView.setSelectedRange(adjustedSelection)
                }
                context.coordinator.rebuildRowsAndRenderEntireDocument(in: textView, source: .externalUpdate)
            }
            context.coordinator.restoreVisualViewportAnchor(viewportAnchor, in: textView)
            _ = context.coordinator.consumeStructuralFocusAnchor(in: textView)
        } else if didChangeDocumentStyle {
            context.coordinator.renderEntireDocument(in: textView, source: .styleChanged)
        } else if !changedMetadataRows.isEmpty {
            context.coordinator.renderRowsAffectedByLayout(changedMetadataRows, in: textView)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        guard let textView = nsView.documentView as? NodeMarkdownStyledTextView else { return }
        coordinator.commitPendingEditingForPersistence(in: textView)
        textView.isHidden = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private static let renderContract = NodeMarkdownRenderContract.default
        private static let leadingPadding = renderContract.layout.leadingPadding
        private static let levelIndentStep = renderContract.layout.levelIndentStep
        private static let markerWidth = renderContract.layout.markerWidth
        private static let markerGap = renderContract.layout.markerGap
        private static var regexCache: [String: NSRegularExpression] = [:]
        private struct CachedLinePrefix {
            let lineText: String
            let prefix: String
            let level: Int
        }
        struct VisualViewportAnchor {
            let nodeID: String
            let verticalOffset: CGFloat
            let fallbackOrigin: NSPoint
        }
        private struct FontCacheKey: Hashable {
            let fontName: String
            let size: Int
            let isBold: Bool
        }
        private struct ParagraphCacheKey: Hashable {
            let level: Int
            let previousLevel: Int
            let prefix: String
            let fontName: String
            let fontSize: Int
            let spacingBefore: Int
            let peerSpacing: Int
            let previousSpacingAfter: Int
        }
        private struct CachedRegexMatch {
            let fullRange: NSRange
            let innerRange: NSRange
        }
        private struct CachedLineRegex {
            let lineText: String
            let version: Int
            let matchesByPattern: [String: [CachedRegexMatch]]
        }
        private final class SearchHighlightRestore: NSObject {
            let backgroundColor: NSColor?

            init(backgroundColor: NSColor?) {
                self.backgroundColor = backgroundColor
            }
        }
        private struct FormulaAttachmentCacheKey: Hashable {
            let latex: String
            let mode: Int
            let fontSize: Int
            let red: Int
            let green: Int
            let blue: Int
            let alpha: Int
        }
        private enum EditorLifecycleState {
            case idle
            case editing
        }
        enum EditingRowMode {
            case infer
            case none
            case row(Int)
        }
        private enum StyleRefreshRequest {
            case incremental(
                rows: Set<Int>,
                delay: TimeInterval,
                forceRenderedRows: Set<Int> = [],
                editingRowMode: EditingRowMode = .infer
            )
        }
        enum RenderTriggerSource: String {
            case textChanged
            case selectionChanged
            case endEditing
            case externalUpdate
            case styleChanged
            case searchChanged
        }
        private struct RenderTraceEvent {
            let source: RenderTriggerSource
            let requestKind: String
            let dirtyRows: Int
            let delay: TimeInterval
            let revision: Int
            let durationMs: Double?
            let droppedAsStale: Bool
            let droppedAsEditing: Bool
        }
        private struct LineLayout {
            let range: NSRange
            let prefix: String
            let level: Int
        }
        private struct LineStyleAttributes {
            let font: NSFont
            let textColor: NSColor
            let paragraph: NSParagraphStyle
            let isUnderline: Bool
            let allowsInlineRender: Bool

            func replacingParagraph(_ value: NSParagraphStyle) -> LineStyleAttributes {
                LineStyleAttributes(
                    font: font,
                    textColor: textColor,
                    paragraph: value,
                    isUnderline: isUnderline,
                    allowsInlineRender: allowsInlineRender
                )
            }

            var attributes: [NSAttributedString.Key: Any] {
                [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]
            }
        }
        private final class RenderCoordinator {
            private var pendingIncrementalStyleWorkItem: DispatchWorkItem?
            private var styleRequestRevision: Int = 0

            func beginEditingSession() {
                styleRequestRevision &+= 1
            }

            func suspendForMarkedTextComposition() {
                pendingIncrementalStyleWorkItem?.cancel()
                pendingIncrementalStyleWorkItem = nil
                styleRequestRevision &+= 1
            }

            func schedule(
                request: StyleRefreshRequest,
                source: RenderTriggerSource,
                contentRevision: NodeMarkdownLegacyRenderRevision,
                isContentRevisionCurrent: @escaping (NodeMarkdownLegacyRenderRevision) -> Bool,
                onTrace: @escaping (RenderTraceEvent) -> Void,
                apply: @escaping (StyleRefreshRequest) -> Void
            ) {
                switch request {
                case let .incremental(rows, delay, forceRenderedRows, editingRowMode):
                    guard !rows.isEmpty else { return }
                    pendingIncrementalStyleWorkItem?.cancel()
                    styleRequestRevision &+= 1
                    let revision = styleRequestRevision
                    onTrace(
                        RenderTraceEvent(
                            source: source,
                            requestKind: "incremental.schedule",
                            dirtyRows: rows.count,
                            delay: delay,
                            revision: revision,
                            durationMs: nil,
                            droppedAsStale: false,
                            droppedAsEditing: false
                        )
                    )
                    let workItem = DispatchWorkItem {
                        guard revision == self.styleRequestRevision,
                              isContentRevisionCurrent(contentRevision) else {
                            onTrace(
                                RenderTraceEvent(
                                    source: source,
                                    requestKind: "incremental.drop",
                                    dirtyRows: rows.count,
                                    delay: delay,
                                    revision: revision,
                                    durationMs: nil,
                                    droppedAsStale: true,
                                    droppedAsEditing: false
                                )
                            )
                            return
                        }
                        let started = CFAbsoluteTimeGetCurrent()
                        self.pendingIncrementalStyleWorkItem = nil
                        apply(.incremental(
                            rows: rows,
                            delay: 0,
                            forceRenderedRows: forceRenderedRows,
                            editingRowMode: editingRowMode
                        ))
                        let durationMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
                        onTrace(
                            RenderTraceEvent(
                                source: source,
                                requestKind: "incremental.apply",
                                dirtyRows: rows.count,
                                delay: delay,
                                revision: revision,
                                durationMs: durationMs,
                                droppedAsStale: false,
                                droppedAsEditing: false
                            )
                        )
                    }
                    pendingIncrementalStyleWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                }
            }
        }
        private struct PendingEdit {
            let affectedRange: NSRange
            let replacementLength: Int
            let insertedNewlineCount: Int
            let deletedNewlineCount: Int
            let deletionImpact: EditorDeletionImpact
            let deletionDiagnosis: EditorDeletionDiagnosis?
            let preStartAnchor: Int
            let preEndAnchor: Int
            let preStartRowSnapshot: Int?
            let preEndRowSnapshot: Int?
            let projectedRowMetadata: [NodeMarkdownTextKitRowMetadata]
        }

        @Binding private var text: String
        let workingDirectoryURL: URL?
        private var documentStyle: NodeMarkdownDocumentStyle
        private var documentStyleIdentity: NodeMarkdownDocumentStyleRecord
        private var activeRowIndex: Int?
        private var activeMatchLocationInRow: Int?
        private var searchQuery: String
        private var rowMetadata: [NodeMarkdownTextKitRowMetadata]
        private var quickInputSettings: MarkdownQuickInputSettings
        private var rowCharacterRanges: [NSRange] = []
        private var editorLifecycleState: EditorLifecycleState = .idle
        private let renderCoordinator = RenderCoordinator()
        private var lastSelectionRowIndex: Int?
        private var lastPublishedActiveRowIndex: Int?
        private var hasPublishedActiveRowIndex = false
        private var lastExternalTextSyncToken = 0
        private var documentContentRevision: UInt64 = 0
        private var styleRevision: UInt64 = 0
        private var searchRevision: UInt64 = 0
        private var wasMarkedTextComposing = false
        private var markedTextCompositionRowIndex: Int?
        private var linePrefixCache: [Int: CachedLinePrefix] = [:]
        private var fontCache: [FontCacheKey: NSFont] = [:]
        private var paragraphStyleCache: [ParagraphCacheKey: NSParagraphStyle] = [:]
        private var editingParagraphStyleCache: [Int: NSParagraphStyle] = [:]
        private var lineRegexCache: [Int: CachedLineRegex] = [:]
        private var rowRegexDirtyVersions: [Int: Int] = [:]
        private var regexDirtyVersionCounter: Int = 0
        private var imeCommitSelectionGuardUntil: CFAbsoluteTime = 0
        private var imageSizeCache: [String: CGSize] = [:]
        #if canImport(SwiftMath)
        private var formulaAttachmentImageCache: [FormulaAttachmentCacheKey: NSImage] = [:]
        #endif
        private var pendingEdit: PendingEdit?
        private var focusTransaction = NodeMarkdownLegacyFocusTransaction()
        private var lastConsumedEditChangedStructure = false
        private var lastConsumedEditNetRowDelta = 0
        private var lastConsumedEditStartRow: Int?
        private var lastConsumedEditNetCharacterDelta = 0
        private var lastConsumedDeletionImpact: EditorDeletionImpact = .character
        private var pendingAttachmentDirtyRows: Set<Int> = []
        private var editedRowsDuringSession: Set<Int> = []
        private var activeSourceModeRowIndex: Int?
        private var isApplyingQuickInputReplacement = false
        private let onTextChange: ((String) -> Void)?
        private let onRequestInsertImageAtRow: ((Int) -> String?)?
        private let onRequestDeleteNodePackageAtRow: ((Int) -> Void)?
        private let onRequestCutNodePackageAtRow: ((Int) -> Void)?
        private let onRequestPasteNodePackageAfterRow: ((Int) -> Void)?
        private let canPasteNodePackageHandler: (() -> Bool)?
        private let onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?
        private let onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?
        private let onActiveRowChange: ((Int?) -> Void)?
        private let onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?
        private let onLegacyDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?
        private let onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?
        private let onEditingDraftDirtyChange: ((Bool) -> Void)?
        private let onInputSessionStateChange: ((Bool) -> Void)?
        /// 活动Node事务同时拥有身份、业务字段和TextKit行坐标。
        /// 普通打字期间不再由四组松散变量分别猜测当前Node。
        private var activeNodeTransaction: NodeMarkdownLegacyActiveNodeTransaction?
        private var hasUncommittedEditingNodeDraft = false
        private let documentSnapshotSessionID = UUID()
        private var documentSnapshotRevision: UInt64 = 0
        var isProgrammaticUpdate = false

        private static var isPerformanceProfilingEnabled: Bool {
            #if DEBUG
            NodeMarkdownFeatureFlags.performanceProfilingEnabled
            #else
            false
            #endif
        }
        private static var isRenderTraceEnabled: Bool {
            #if DEBUG
            NodeMarkdownFeatureFlags.renderTraceEnabled
            #else
            false
            #endif
        }
        private static var isRenderSmokeEnabled: Bool {
            #if DEBUG
            NodeMarkdownFeatureFlags.renderSmokeEnabled
            #else
            false
            #endif
        }
        private static var isLayoutJitterDebugEnabled: Bool {
            #if DEBUG
            TeachingDebugLogStore.isLayoutJitterLogsEnabled()
            #else
            false
            #endif
        }

        private var isInActiveEditingSession: Bool {
            editorLifecycleState == .editing
        }

        private func profileDuration(
            _ scope: String,
            start: CFAbsoluteTime,
            details: @autoclosure () -> String = ""
        ) {
            guard Self.isPerformanceProfilingEnabled else { return }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let resolvedDetails = details()
            let detailText = resolvedDetails.isEmpty ? "" : " | \(resolvedDetails)"
            let message = "[NodeMarkdown][Perf] \(scope): \(String(format: "%.2f", elapsedMs))ms\(detailText)"
            print(message)
            TeachingDebugLogStore.append(message, category: "NodeMarkdown")
        }

        private func logRenderTrace(_ event: RenderTraceEvent) {
            if Self.isRenderSmokeEnabled {
                NodeMarkdownRenderSmokeRecorder.shared.recordTrace(
                    source: event.source.rawValue,
                    requestKind: event.requestKind,
                    droppedAsStale: event.droppedAsStale,
                    droppedAsEditing: event.droppedAsEditing
                )
            }
            guard Self.isRenderTraceEnabled else { return }
            let duration = event.durationMs.map { String(format: "%.2fms", $0) } ?? "-"
            print(
                "[NodeMarkdown][RenderTrace] source=\(event.source.rawValue)"
                    + " request=\(event.requestKind)"
                    + " dirtyRows=\(event.dirtyRows)"
                    + " delay=\(String(format: "%.3f", event.delay))"
                    + " revision=\(event.revision)"
                    + " duration=\(duration)"
                    + " staleDrop=\(event.droppedAsStale)"
                    + " editingDrop=\(event.droppedAsEditing)"
            )
            TeachingDebugLogStore.append(
                "source=\(event.source.rawValue) request=\(event.requestKind) dirtyRows=\(event.dirtyRows) delay=\(String(format: "%.3f", event.delay)) revision=\(event.revision) staleDrop=\(event.droppedAsStale) editingDrop=\(event.droppedAsEditing)",
                category: "NodeMarkdown.RenderTrace"
            )
        }

        private func logLayoutJitter(_ message: String) {
            guard Self.isLayoutJitterDebugEnabled else { return }
            let text = "[NodeMarkdown][JitterDebug] \(message)"
            print(text)
            TeachingDebugLogStore.append(text, category: "NodeMarkdown.JitterDebug")
        }

        private func updateRowCharacterRangesAfterCharacterEdit(in textView: NSTextView) {
            guard lastConsumedEditNetCharacterDelta != 0 else { return }
            guard !lastConsumedEditChangedStructure, lastConsumedEditNetRowDelta == 0 else { return }
            guard lastConsumedDeletionImpact == .character else { return }
            guard let editedRow = lastConsumedEditStartRow,
                  activeNodeTransaction?.rowIndex == editedRow,
                  synchronizeActiveNodeRange(in: textView) else {
                rebuildRowCharacterRanges(from: textView)
                return
            }
        }

        private func rebuildRowCharacterRanges(from textView: NSTextView) {
            editingParagraphStyleCache.removeAll(keepingCapacity: true)
            let source = textView.textStorage?.mutableString ?? NSMutableString(string: textView.string)
            rowCharacterRanges = NodeMarkdownLegacyRowRangeIndex.rebuild(from: source)
            if var transaction = activeNodeTransaction,
               rowCharacterRanges.indices.contains(transaction.rowIndex) {
                transaction.rebase(to: rowCharacterRanges[transaction.rowIndex])
                activeNodeTransaction = transaction
            }
            pruneLinePrefixCache(validRowCount: rowCharacterRanges.count)
            pruneLineRegexCache(validRowCount: rowCharacterRanges.count)
            publishActiveNodeGeometry(to: textView)
        }

        private func effectiveRowRange(at row: Int) -> NSRange? {
            if let transaction = activeNodeTransaction {
                return transaction.effectiveRange(at: row, stableRanges: rowCharacterRanges)
            }
            return NodeMarkdownLegacyRowRangeIndex.effectiveRange(
                at: row,
                in: rowCharacterRanges,
                editedRow: nil,
                characterDelta: 0
            )
        }

        @discardableResult
        private func synchronizeActiveNodeRange(in textView: NSTextView) -> Bool {
            guard var transaction = activeNodeTransaction,
                  let source = textView.textStorage?.mutableString,
                  transaction.synchronizeRange(in: source) else { return false }
            activeNodeTransaction = transaction
            publishActiveNodeGeometry(to: textView)
            return true
        }

        private func publishActiveNodeGeometry(to textView: NSTextView) {
            guard let styledView = textView as? NodeMarkdownStyledTextView else { return }
            styledView.rowCharacterRanges = rowCharacterRanges
            styledView.transientEditedRowIndex = activeNodeTransaction?.rowIndex
            styledView.transientCharacterDelta = activeNodeTransaction?.characterDelta ?? 0
        }

        private func rowsIncludingFollowingParagraph(for rows: Set<Int>) -> Set<Int> {
            var result = rows
            for row in rows where row >= 0 {
                result.insert(row + 1)
                editingParagraphStyleCache.removeValue(forKey: row)
                editingParagraphStyleCache.removeValue(forKey: row + 1)
            }
            return result.filter { rowCharacterRanges.indices.contains($0) }
        }

        private func registerUndoSnapshot(for textView: NSTextView) {
            guard let undoManager = textView.undoManager else { return }
            let snapshot = sourceTextPreservingAttachmentTokens(from: textView)
            let selection = textView.selectedRange()
            let metadataSnapshot = rowMetadata
            undoManager.registerUndo(withTarget: self) { [weak textView] target in
                guard let textView else { return }
                target.restoreUndoSnapshot(
                    snapshot,
                    rowMetadata: metadataSnapshot,
                    selection: selection,
                    in: textView
                )
            }
            undoManager.setActionName("NodeMarkdown Edit")
        }

        private func restoreUndoSnapshot(
            _ snapshot: String,
            rowMetadata metadataSnapshot: [NodeMarkdownTextKitRowMetadata],
            selection: NSRange,
            in textView: NSTextView
        ) {
            discardEditingNodeDraft()
            let redoSnapshot = sourceTextPreservingAttachmentTokens(from: textView)
            let redoSelection = textView.selectedRange()
            let redoMetadata = rowMetadata
            textView.undoManager?.registerUndo(withTarget: self) { [weak textView] target in
                guard let textView else { return }
                target.restoreUndoSnapshot(
                    redoSnapshot,
                    rowMetadata: redoMetadata,
                    selection: redoSelection,
                    in: textView
                )
            }

            isProgrammaticUpdate = true
            textView.string = snapshot
            noteDocumentMutation()
            rowMetadata = normalizedRowMetadata(metadataSnapshot, forPlainText: snapshot)
            rebuildRowCharacterRanges(from: textView)
            setSelectionIfNeeded(textView, range: clampedSelectionRange(for: selection, in: textView))
            pendingEdit = nil
            focusTransaction.cancel()
            pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
            renderEntireDocument(in: textView, source: .textChanged)
            isProgrammaticUpdate = false
            let preserved = sourceTextPreservingAttachmentTokens(from: textView)
            publishTextChange(preserved)
            notifyActiveRowChange(currentRowIndex(in: textView))
        }

        init(
            text: Binding<String>,
            workingDirectoryURL: URL?,
            documentStyle: NodeMarkdownDocumentStyle,
            activeRowIndex: Int?,
            activeMatchLocationInRow: Int?,
            searchQuery: String,
            rowMetadata: [NodeMarkdownTextKitRowMetadata],
            quickInputSettings: MarkdownQuickInputSettings,
            onTextChange: ((String) -> Void)?,
            onRequestInsertImageAtRow: ((Int) -> String?)?,
            onRequestDeleteNodePackageAtRow: ((Int) -> Void)?,
            onRequestCutNodePackageAtRow: ((Int) -> Void)?,
            onRequestPasteNodePackageAfterRow: ((Int) -> Void)?,
            canPasteNodePackage: (() -> Bool)?,
            onRequestDeleteProtectedH3AtRow: ((Int) -> Void)?,
            onRequestOpenDrawingBoardAtRow: ((Int) -> Void)?,
            onActiveRowChange: ((Int?) -> Void)?,
            onTextChangeWithRowMetadata: ((String, [NodeMarkdownTextKitRowMetadata]) -> Void)?,
            onLegacyDocumentSnapshot: ((NodeMarkdownLegacyDocumentSnapshot) -> Void)?,
            onCommitEditingNode: ((NodeMarkdownLegacyEditingNodeDraft) -> Void)?,
            onEditingDraftDirtyChange: ((Bool) -> Void)?,
            onInputSessionStateChange: ((Bool) -> Void)?
        ) {
            _text = text
            self.workingDirectoryURL = workingDirectoryURL
            self.documentStyle = documentStyle
            self.documentStyleIdentity = documentStyle.renderIdentity
            self.activeRowIndex = activeRowIndex
            self.activeMatchLocationInRow = activeMatchLocationInRow
            self.searchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            self.rowMetadata = rowMetadata
            self.quickInputSettings = quickInputSettings
            self.onTextChange = onTextChange
            self.onRequestInsertImageAtRow = onRequestInsertImageAtRow
            self.onRequestDeleteNodePackageAtRow = onRequestDeleteNodePackageAtRow
            self.onRequestCutNodePackageAtRow = onRequestCutNodePackageAtRow
            self.onRequestPasteNodePackageAfterRow = onRequestPasteNodePackageAfterRow
            self.canPasteNodePackageHandler = canPasteNodePackage
            self.onRequestDeleteProtectedH3AtRow = onRequestDeleteProtectedH3AtRow
            self.onRequestOpenDrawingBoardAtRow = onRequestOpenDrawingBoardAtRow
            self.onActiveRowChange = onActiveRowChange
            self.onTextChangeWithRowMetadata = onTextChangeWithRowMetadata
            self.onLegacyDocumentSnapshot = onLegacyDocumentSnapshot
            self.onCommitEditingNode = onCommitEditingNode
            self.onEditingDraftDirtyChange = onEditingDraftDirtyChange
            self.onInputSessionStateChange = onInputSessionStateChange
        }

        private var currentRenderRevision: NodeMarkdownLegacyRenderRevision {
            NodeMarkdownLegacyRenderRevision(
                document: documentContentRevision,
                style: styleRevision,
                search: searchRevision
            )
        }

        private func noteDocumentMutation() {
            documentContentRevision &+= 1
        }

        @discardableResult
        func updateDocumentStyle(_ value: NodeMarkdownDocumentStyle) -> Bool {
            let identity = value.renderIdentity
            guard documentStyleIdentity != identity else {
                documentStyle = value
                return false
            }
            fontCache.removeAll(keepingCapacity: true)
            paragraphStyleCache.removeAll(keepingCapacity: true)
            documentStyle = value
            documentStyleIdentity = identity
            styleRevision &+= 1
            return true
        }

        private func resolvePrefixAndLevel(for lineText: String, rowIndex: Int) -> (prefix: String, level: Int) {
            if let cached = linePrefixCache[rowIndex],
               cached.lineText == lineText,
               (!rowMetadata.indices.contains(rowIndex) || cached.level == rowMetadata[rowIndex].level) {
                return (cached.prefix, cached.level)
            }
            let prefix = ""
            let level = rowMetadata.indices.contains(rowIndex)
                ? max(1, min(12, rowMetadata[rowIndex].level))
                : 7
            linePrefixCache[rowIndex] = CachedLinePrefix(lineText: lineText, prefix: prefix, level: level)
            return (prefix, level)
        }

        private func pruneLinePrefixCache(validRowCount: Int) {
            guard validRowCount >= 0 else { return }
            linePrefixCache = linePrefixCache.filter { $0.key >= 0 && $0.key < validRowCount }
        }

        private func pruneLineRegexCache(validRowCount: Int) {
            guard validRowCount >= 0 else { return }
            lineRegexCache = lineRegexCache.filter { $0.key >= 0 && $0.key < validRowCount }
            rowRegexDirtyVersions = rowRegexDirtyVersions.filter { $0.key >= 0 && $0.key < validRowCount }
        }

        private func regexDirtyVersion(for rowIndex: Int) -> Int {
            rowRegexDirtyVersions[rowIndex] ?? 0
        }

        private func markRegexDirty(rows: Set<Int>) {
            guard !rows.isEmpty else { return }
            regexDirtyVersionCounter &+= 1
            let version = regexDirtyVersionCounter
            for row in rows where row >= 0 {
                rowRegexDirtyVersions[row] = version
            }
        }

        private func cachedRegexMatches(
            for pattern: String,
            in lineText: String,
            rowIndex: Int
        ) -> [CachedRegexMatch] {
            let dirtyVersion = regexDirtyVersion(for: rowIndex)
            if let cachedLine = lineRegexCache[rowIndex],
               cachedLine.lineText == lineText,
               cachedLine.version == dirtyVersion {
                if let cachedMatches = cachedLine.matchesByPattern[pattern] {
                    return cachedMatches
                }
            }

            let regex: NSRegularExpression
            if let cached = Self.regexCache[pattern] {
                regex = cached
            } else {
                guard let compiled = try? NSRegularExpression(pattern: pattern) else { return [] }
                Self.regexCache[pattern] = compiled
                regex = compiled
            }

            let fullRange = NSRange(location: 0, length: (lineText as NSString).length)
            let matches = regex.matches(in: lineText, options: [], range: fullRange).compactMap { result -> CachedRegexMatch? in
                let innerRange = firstCapturedRange(in: result)
                guard innerRange.location != NSNotFound, innerRange.length > 0 else { return nil }
                return CachedRegexMatch(fullRange: result.range, innerRange: innerRange)
            }

            var matchesByPattern: [String: [CachedRegexMatch]] = [:]
            if let cachedLine = lineRegexCache[rowIndex], cachedLine.lineText == lineText {
                matchesByPattern = cachedLine.matchesByPattern
            }
            matchesByPattern[pattern] = matches
            lineRegexCache[rowIndex] = CachedLineRegex(
                lineText: lineText,
                version: dirtyVersion,
                matchesByPattern: matchesByPattern
            )
            return matches
        }

        private func resolvedFont(for style: NodeMarkdownRoleStyle) -> NSFont {
            let key = FontCacheKey(
                fontName: style.fontName,
                size: Int(style.fontSize.rounded()),
                isBold: style.isBold
            )
            if let cached = fontCache[key] {
                return cached
            }
            var font = NSFont(name: style.fontName, size: style.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: .regular)
            if style.isBold {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            fontCache[key] = font
            return font
        }

        private func resolvedParagraphStyle(
            level: Int,
            previousLevel: Int?,
            prefix: String,
            font: NSFont,
            roleStyle: NodeMarkdownRoleStyle,
            previousStyle: NodeMarkdownRoleStyle?
        ) -> NSParagraphStyle {
            let key = ParagraphCacheKey(
                level: level,
                previousLevel: previousLevel ?? -1,
                prefix: prefix,
                fontName: font.fontName,
                fontSize: Int(font.pointSize.rounded()),
                spacingBefore: Int(roleStyle.paragraphSpacingBefore.rounded()),
                peerSpacing: Int(roleStyle.peerLineSpacing.rounded()),
                previousSpacingAfter: Int((previousStyle?.paragraphSpacingAfter ?? 0).rounded())
            )
            if let cached = paragraphStyleCache[key] {
                return cached
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            let markerX = Self.leadingPadding
                + CGFloat(max(0, level - 1)) * Self.levelIndentStep
            let targetContentX = markerX + max(1, font.pointSize)
            let prefixWidth = (prefix as NSString).size(withAttributes: [.font: font]).width
            paragraph.firstLineHeadIndent = max(0, targetContentX - prefixWidth)
            paragraph.headIndent = targetContentX
            paragraph.paragraphSpacingBefore = NodeMarkdownRenderContract.interRowSpacing(
                previousLevel: previousLevel,
                previousRoleStyle: previousStyle,
                currentLevel: level,
                currentRoleStyle: roleStyle
            )
            paragraph.paragraphSpacing = 0
            paragraph.lineSpacing = max(0, CGFloat(roleStyle.peerLineSpacing))
            paragraph.minimumLineHeight = max(0, font.ascender - font.descender + 4)
            paragraphStyleCache[key] = paragraph
            return paragraph
        }

        private func lineStyleAttributes(
            for line: LineLayout,
            previousLine: LineLayout?,
            allowsInlineRender: Bool,
            rowIndex: Int? = nil,
            locksEditingParagraph: Bool = false
        ) -> LineStyleAttributes {
            let roleStyle = Self.renderContract.lineStyle(
                level: line.level,
                prefix: line.prefix,
                documentStyle: documentStyle
            ).roleStyle
            let font = resolvedFont(for: roleStyle)
            let previousStyle = previousLine.map { documentStyle.style(forLevel: $0.level) }
            let attributes = LineStyleAttributes(
                font: font,
                textColor: NSColor(roleStyle.renderedColor),
                paragraph: resolvedParagraphStyle(
                    level: line.level,
                    previousLevel: previousLine?.level,
                    prefix: line.prefix,
                    font: font,
                    roleStyle: roleStyle,
                    previousStyle: previousStyle
                ),
                isUnderline: roleStyle.isUnderline,
                allowsInlineRender: allowsInlineRender
            )
            guard locksEditingParagraph, let rowIndex else {
                return attributes
            }
            guard rowIndex >= 0 else {
                return attributes
            }
            if let lockedParagraph = editingParagraphStyleCache[rowIndex] {
                return attributes.replacingParagraph(lockedParagraph)
            }
            editingParagraphStyleCache[rowIndex] = attributes.paragraph
            return attributes
        }

        func updateActiveRowIndex(_ value: Int?, in textView: NSTextView) {
            guard activeRowIndex != value else { return }
            activeRowIndex = value
            searchRevision &+= 1
            refreshSearchHighlights(in: textView)
            scrollToActiveRowIfNeeded(in: textView)
        }

        func updateSearchQuery(_ value: String, in textView: NSTextView) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard searchQuery != normalized else { return }
            searchQuery = normalized
            searchRevision &+= 1
            refreshSearchHighlights(in: textView)
        }

        func updateActiveMatchLocationInRow(_ value: Int?, in textView: NSTextView) {
            guard activeMatchLocationInRow != value else { return }
            activeMatchLocationInRow = value
            searchRevision &+= 1
            refreshSearchHighlights(in: textView)
        }

        func updateRowMetadata(_ value: [NodeMarkdownTextKitRowMetadata]) -> Set<Int> {
            var resolved = value
            let currentIDs = rowMetadata.map(\.nodeID).filter { !$0.isEmpty }
            let incomingIDs = value.map(\.nodeID).filter { !$0.isEmpty }
            let currentHasStableIdentity = !currentIDs.isEmpty && Set(currentIDs).count == currentIDs.count
            let incomingHasStableIdentity = !incomingIDs.isEmpty
                && incomingIDs.count == value.count
                && Set(incomingIDs).count == incomingIDs.count

            // 无源码前缀后，缺失身份的第7级占位元数据没有资格覆盖一份完整Node快照。
            if currentHasStableIdentity, !value.isEmpty, !incomingHasStableIdentity {
                return []
            }
            if let draft = activeNodeTransaction?.draft,
               let index = resolved.firstIndex(where: { $0.nodeID == draft.nodeID }) {
                resolved[index] = NodeMarkdownTextKitRowMetadata(
                    nodeID: draft.nodeID,
                    level: draft.level,
                    sourceID: draft.sourceID,
                    sourceFile: draft.sourceFile
                )
            }
            guard rowMetadata != resolved else { return [] }
            let oldMetadata = rowMetadata
            rowMetadata = resolved
            let upperBound = max(oldMetadata.count, resolved.count)
            return Set((0..<upperBound).filter { index in
                guard oldMetadata.indices.contains(index), resolved.indices.contains(index) else { return true }
                return !oldMetadata[index].hasSameLayoutIdentity(as: resolved[index])
            })
        }

        func rowLevelsSnapshot() -> [Int] {
            rowMetadata.map { max(1, min(12, $0.level)) }
        }

        func rebuildRowsAndRenderEntireDocument(in textView: NSTextView, source: RenderTriggerSource) {
            rebuildRowCharacterRanges(from: textView)
            renderEntireDocument(in: textView, source: source)
        }

        /// 样式切换、外部整篇替换等低频事务使用这一入口，保证屏内屏外采用同一代样式。
        func renderEntireDocument(in textView: NSTextView, source: RenderTriggerSource) {
            guard !rowCharacterRanges.isEmpty else { return }
            applyStyle(to: textView, targetRows: nil, source: source)
        }

        func renderRowsAffectedByLayout(_ rows: Set<Int>, in textView: NSTextView) {
            guard !rows.isEmpty, !rowCharacterRanges.isEmpty else { return }
            let visibleRows = visibleRowSet(
                in: textView,
                maxRowIndex: rowCharacterRanges.count - 1,
                overscan: 4
            )
            guard let plannedRows = NodeMarkdownLegacyRenderPolicy.rows(
                for: .layoutRows(rowsIncludingFollowingParagraph(for: rows)),
                rowCount: rowCharacterRanges.count,
                visibleRows: visibleRows
            ), !plannedRows.isEmpty else { return }
            applyStyle(to: textView, targetRows: plannedRows, source: .styleChanged)
        }

        func updateQuickInputSettings(_ value: MarkdownQuickInputSettings) {
            quickInputSettings = value
        }

        func primeExternalTextSyncToken(_ value: Int) {
            lastExternalTextSyncToken = value
        }

        func hasPendingExternalTextSync(_ value: Int) -> Bool {
            value != lastExternalTextSyncToken
        }

        func acceptExternalTextSyncToken(_ value: Int) {
            lastExternalTextSyncToken = value
            documentContentRevision &+= 1
        }

        /// 外部插包会替换整份文档；旧活动草稿和局部布局缓存不得再参与新行元数据的合并。
        func prepareForExternalDocumentReplacement() {
            discardEditingNodeDraft()
            editorLifecycleState = .idle
            pendingEdit = nil
            focusTransaction.cancel()
            activeSourceModeRowIndex = nil
            activeNodeTransaction = nil
            pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
            editedRowsDuringSession.removeAll(keepingCapacity: true)
            editingParagraphStyleCache.removeAll(keepingCapacity: true)
            linePrefixCache.removeAll(keepingCapacity: true)
            lineRegexCache.removeAll(keepingCapacity: true)
            rowRegexDirtyVersions.removeAll(keepingCapacity: true)
        }

        func applyStyle(
            to textView: NSTextView,
            targetRows: Set<Int>? = nil,
            source: RenderTriggerSource = .selectionChanged,
            forceRenderedRows: Set<Int> = [],
            editingRowMode: EditingRowMode = .infer
        ) {
            let profileStart = Self.isPerformanceProfilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
            guard !isMarkedTextCompositionActive(in: textView) else { return }
            guard let storage = textView.textStorage else { return }
            #if DEBUG
            let sourceBeforeRender = storage.string
            defer {
                assert(
                    storage.string == sourceBeforeRender,
                    "NodeMarkdown rendering must never mutate NSTextStorage.string."
                )
            }
            #endif
            let previousProgrammaticState = isProgrammaticUpdate
            isProgrammaticUpdate = true
            defer {
                isProgrammaticUpdate = previousProgrammaticState
            }
            if let styledTextView = textView as? NodeMarkdownStyledTextView {
                styledTextView.nodeRowLevels = rowMetadata.map(\.level)
            }
            let resolvedIncrementalRows: Set<Int>? = targetRows.map { requestedRows in
                let maxRowIndex = max(0, rowCharacterRanges.count - 1)
                let visibleRows = visibleRowSet(in: textView, maxRowIndex: maxRowIndex, overscan: 2)
                return NodeMarkdownLegacyRenderPolicy.incrementalRows(
                    requestedRows: requestedRows,
                    rowCount: rowCharacterRanges.count,
                    visibleRows: visibleRows,
                    expandsNeighbors: !isInActiveEditingSession
                )
            }
            let string = storage.mutableString
            let fullRange = NSRange(location: 0, length: string.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            let requestedIncremental = targetRows != nil
            let isIncremental = requestedIncremental
            defer {
                if Self.isPerformanceProfilingEnabled {
                    let targetCount = targetRows?.count ?? 0
                    profileDuration(
                        "applyStyle",
                        start: profileStart,
                        details: "mode=\(isIncremental ? "incremental" : "full"),targetRows=\(targetCount),textLength=\(string.length)"
                    )
                }
            }

            if isIncremental,
               let targetRows,
               let resolvedIncrementalRows,
               !rowCharacterRanges.isEmpty,
               string.length > 0 {
                let maxRowIndex = rowCharacterRanges.count - 1
                let effectiveRows = resolvedIncrementalRows
                #if DEBUG
                if isInActiveEditingSession {
                    let expandedRows = effectiveRows.subtracting(targetRows)
                    assert(expandedRows.isEmpty, "Rule#2 violated: editing period must not expand to neighbor rows.")
                }
                #endif
                guard !effectiveRows.isEmpty else { return }

                var lineCache: [Int: LineLayout] = [:]
                let lineForRow: (Int) -> LineLayout? = { rowIndex in
                    if let cached = lineCache[rowIndex] { return cached }
                    guard rowIndex >= 0, rowIndex <= maxRowIndex else { return nil }
                    guard let effectiveRange = self.effectiveRowRange(at: rowIndex) else { return nil }
                    guard effectiveRange.location <= string.length,
                          NSMaxRange(effectiveRange) <= string.length else { return nil }
                    let lineText = effectiveRange.length > 0 ? string.substring(with: effectiveRange) : ""
                    let resolved = self.resolvePrefixAndLevel(for: lineText, rowIndex: rowIndex)
                    let prefix = resolved.prefix
                    let level = resolved.level
                    let layout = LineLayout(range: effectiveRange, prefix: prefix, level: level)
                    lineCache[rowIndex] = layout
                    return layout
                }

                for row in effectiveRows {
                    _ = lineForRow(row)
                    if row > 0 { _ = lineForRow(row - 1) }
                }

                let editingRowIndex = resolvedEditingRowIndex(editingRowMode, in: textView)
                storage.beginEditing()
                for row in effectiveRows.sorted() {
                    guard let line = lineForRow(row) else { continue }
                    let previousLine = row > 0 ? lineForRow(row - 1) : nil
                    let isEditingRow = editingRowIndex == row && !forceRenderedRows.contains(row)
                    let styleAttributes = lineStyleAttributes(
                        for: line,
                        previousLine: previousLine,
                        allowsInlineRender: !isEditingRow,
                        rowIndex: row,
                        locksEditingParagraph: isEditingRow
                    )

                    storage.setAttributes(
                        [
                            .font: baseFont,
                            .foregroundColor: NSColor.labelColor
                        ],
                        range: line.range
                    )
                    storage.addAttributes(
                        styleAttributes.attributes,
                        range: line.range
                    )

                    let prefixLength = min(line.prefix.count, line.range.length)
                    let contentRange = NSRange(
                        location: line.range.location + prefixLength,
                        length: max(0, line.range.length - prefixLength)
                    )
                    if styleAttributes.allowsInlineRender {
                        applyInlineRichText(
                            in: storage,
                            source: string,
                            rowIndex: row,
                            lineRange: line.range,
                            prefixLength: prefixLength,
                            contentRange: contentRange,
                            baseFont: styleAttributes.font,
                            textColor: styleAttributes.textColor,
                            renderMode: true
                        )
                    }
                    applySearchHighlightAttributes(
                        in: storage,
                        source: string,
                        rowIndex: row,
                        line: line
                    )

                    if !line.prefix.isEmpty {
                        let prefixRange = NSRange(location: line.range.location, length: prefixLength)
                        storage.addAttributes(
                            [.foregroundColor: NSColor.clear],
                            range: prefixRange
                        )
                    }
                }
                storage.endEditing()
                if let styledView = textView as? NodeMarkdownStyledTextView {
                    styledView.rowCharacterRanges = rowCharacterRanges
                }
                updateTypingAttributes(for: textView)
                invalidateDisplayForRows(effectiveRows, in: textView)
                return
            }

            rowCharacterRanges = NodeMarkdownLegacyRowRangeIndex.rebuild(from: string)
            var lines: [LineLayout] = []
            lines.reserveCapacity(rowCharacterRanges.count)
            for lineRange in rowCharacterRanges {
                let lineText = lineRange.length > 0 ? string.substring(with: lineRange) : ""
                let resolved = resolvePrefixAndLevel(for: lineText, rowIndex: lines.count)
                let prefix = resolved.prefix
                let level = resolved.level
                lines.append(LineLayout(range: lineRange, prefix: prefix, level: level))
            }
            if var transaction = activeNodeTransaction,
               rowCharacterRanges.indices.contains(transaction.rowIndex) {
                transaction.rebase(to: rowCharacterRanges[transaction.rowIndex])
                activeNodeTransaction = transaction
            }
            pruneLinePrefixCache(validRowCount: lines.count)
            pruneLineRegexCache(validRowCount: lines.count)

            let editingRowIndex: Int? = {
                switch editingRowMode {
                case .infer:
                    break
                case .none:
                    return nil
                case let .row(row):
                    return lines.indices.contains(row) ? row : nil
                }
                guard isInActiveEditingSession || textView.window?.firstResponder === textView else { return nil }
                guard !lines.isEmpty else { return nil }
                let selection = textView.selectedRange()
                let textLength = string.length
                let safeLocation = max(0, min(selection.location, textLength))
                if let row = lineIndexForLocation(safeLocation), lines.indices.contains(row) { return row }
                if let lastSelectionRowIndex, lines.indices.contains(lastSelectionRowIndex) {
                    return lastSelectionRowIndex
                }
                return nil
            }()

            var effectiveRows = Set<Int>()
            if let targetRows {
                let shouldExpandNeighborRows = !isInActiveEditingSession
                for row in targetRows {
                    guard lines.indices.contains(row) else { continue }
                    effectiveRows.insert(row)
                    if shouldExpandNeighborRows {
                        if lines.indices.contains(row - 1) { effectiveRows.insert(row - 1) }
                        if lines.indices.contains(row + 1) { effectiveRows.insert(row + 1) }
                    }
                }
                let maxRowIndex = max(0, lines.count - 1)
                let visibleRows = visibleRowSet(in: textView, maxRowIndex: maxRowIndex, overscan: 2)
                if !visibleRows.isEmpty {
                    let filteredRows = effectiveRows.intersection(visibleRows)
                    if !filteredRows.isEmpty {
                        effectiveRows = filteredRows
                    }
                }
                #if DEBUG
                if isInActiveEditingSession {
                    let expandedRows = effectiveRows.subtracting(targetRows)
                    assert(expandedRows.isEmpty, "Rule#2 violated: editing period must not expand to neighbor rows.")
                }
                #endif
            }

            storage.beginEditing()
            if isIncremental {
                for row in effectiveRows where lines.indices.contains(row) {
                    storage.setAttributes(
                        [
                            .font: baseFont,
                            .foregroundColor: NSColor.labelColor
                        ],
                        range: lines[row].range
                    )
                }
            } else {
                storage.setAttributes(
                    [
                        .font: baseFont,
                        .foregroundColor: NSColor.labelColor
                    ],
                    range: fullRange
                )
            }

            for (index, line) in lines.enumerated() {
                if isIncremental && !effectiveRows.contains(index) {
                    continue
                }
                let previousLine = index > 0 ? lines[index - 1] : nil
                let isEditingRow = editingRowIndex == index && !forceRenderedRows.contains(index)
                let styleAttributes = lineStyleAttributes(
                    for: line,
                    previousLine: previousLine,
                    allowsInlineRender: !isEditingRow,
                    rowIndex: index,
                    locksEditingParagraph: isEditingRow
                )

                storage.addAttributes(
                    styleAttributes.attributes,
                    range: line.range
                )

                let prefixLength = min(line.prefix.count, line.range.length)
                let contentRange = NSRange(
                    location: line.range.location + prefixLength,
                    length: max(0, line.range.length - prefixLength)
                )
                if styleAttributes.allowsInlineRender {
                    applyInlineRichText(
                        in: storage,
                        source: string,
                        rowIndex: index,
                        lineRange: line.range,
                        prefixLength: prefixLength,
                        contentRange: contentRange,
                        baseFont: styleAttributes.font,
                        textColor: styleAttributes.textColor,
                        renderMode: true
                    )
                }

                applySearchHighlightAttributes(
                    in: storage,
                    source: string,
                    rowIndex: index,
                    line: line
                )

                if !line.prefix.isEmpty {
                    let prefixRange = NSRange(location: line.range.location, length: prefixLength)
                    storage.addAttributes(
                        [
                            .foregroundColor: NSColor.clear
                        ],
                        range: prefixRange
                    )
                }
            }

            storage.endEditing()
            if let styledView = textView as? NodeMarkdownStyledTextView {
                styledView.rowCharacterRanges = rowCharacterRanges
                styledView.transientEditedRowIndex = activeNodeTransaction?.rowIndex
                styledView.transientCharacterDelta = activeNodeTransaction?.characterDelta ?? 0
            }
            updateTypingAttributes(for: textView)
            if isIncremental {
                invalidateDisplayForRows(effectiveRows, in: textView)
            } else {
                textView.needsDisplay = true
            }
        }

        /// 搜索状态只改搜索高亮，不重新应用字体、段落、公式或图片。
        private func refreshSearchHighlights(in textView: NSTextView) {
            guard !isMarkedTextCompositionActive(in: textView),
                  let storage = textView.textStorage,
                  !rowCharacterRanges.isEmpty else { return }
            let maxRowIndex = rowCharacterRanges.count - 1
            let rows = visibleRowSet(in: textView, maxRowIndex: maxRowIndex, overscan: 2)
            guard !rows.isEmpty else { return }
            let source = storage.mutableString
            storage.beginEditing()
            for row in rows.sorted() {
                guard let range = effectiveRowRange(at: row),
                      range.location <= source.length,
                      NSMaxRange(range) <= source.length else { continue }
                clearSearchHighlightAttributes(in: storage, range: range)
                let lineText = range.length > 0 ? source.substring(with: range) : ""
                let resolved = resolvePrefixAndLevel(for: lineText, rowIndex: row)
                applySearchHighlightAttributes(
                    in: storage,
                    source: source,
                    rowIndex: row,
                    line: LineLayout(range: range, prefix: resolved.prefix, level: resolved.level)
                )
            }
            storage.endEditing()
            invalidateDisplayForRows(rows, in: textView)
        }

        private func clearSearchHighlightAttributes(in storage: NSTextStorage, range: NSRange) {
            var restorations: [(NSRange, SearchHighlightRestore)] = []
            storage.enumerateAttribute(
                nodeMarkdownSearchHighlightRestoreKey,
                in: range,
                options: []
            ) { value, effectiveRange, _ in
                guard let restore = value as? SearchHighlightRestore else { return }
                restorations.append((effectiveRange, restore))
            }
            for (effectiveRange, restore) in restorations {
                if let backgroundColor = restore.backgroundColor {
                    storage.addAttribute(.backgroundColor, value: backgroundColor, range: effectiveRange)
                } else {
                    storage.removeAttribute(.backgroundColor, range: effectiveRange)
                }
                storage.removeAttribute(nodeMarkdownSearchHighlightRestoreKey, range: effectiveRange)
            }
        }

        private func applySearchHighlightAttributes(
            in storage: NSTextStorage,
            source: NSString,
            rowIndex: Int,
            line: LineLayout
        ) {
            guard !searchQuery.isEmpty, line.range.length > 0 else { return }
            let prefixLength = min((line.prefix as NSString).length, line.range.length)
            let searchStart = line.range.location + prefixLength
            let searchRange = NSRange(
                location: searchStart,
                length: max(0, line.range.length - prefixLength)
            )
            var remaining = searchRange
            while remaining.length > 0 {
                let match = source.range(of: searchQuery, options: [.caseInsensitive], range: remaining)
                guard match.location != NSNotFound, match.length > 0 else { break }
                let matchLocationInRow = match.location - searchStart
                let isCurrentMatch = rowIndex == activeRowIndex
                    && matchLocationInRow == activeMatchLocationInRow
                let alpha: CGFloat = isCurrentMatch ? 0.58 : 0.34
                var originalBackgrounds: [(NSRange, NSColor?)] = []
                storage.enumerateAttribute(.backgroundColor, in: match, options: []) { value, subrange, _ in
                    originalBackgrounds.append((subrange, value as? NSColor))
                }
                for (subrange, backgroundColor) in originalBackgrounds {
                    storage.addAttribute(
                        nodeMarkdownSearchHighlightRestoreKey,
                        value: SearchHighlightRestore(backgroundColor: backgroundColor),
                        range: subrange
                    )
                }
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor(
                        red: 240.0 / 255.0,
                        green: 200.0 / 255.0,
                        blue: 71.0 / 255.0,
                        alpha: alpha
                    ),
                    range: match
                )
                let nextLocation = NSMaxRange(match)
                let end = NSMaxRange(searchRange)
                guard nextLocation < end else { break }
                remaining = NSRange(location: nextLocation, length: end - nextLocation)
            }
        }

        private func applyInlineRichText(
            in storage: NSTextStorage,
            source: NSString,
            rowIndex: Int,
            lineRange: NSRange,
            prefixLength: Int,
            contentRange: NSRange,
            baseFont: NSFont,
            textColor: NSColor,
            renderMode: Bool
        ) {
            let profileStart = Self.isPerformanceProfilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
            guard contentRange.length > 0 else { return }
            defer {
                if Self.isPerformanceProfilingEnabled {
                    profileDuration(
                        "applyInlineRichText",
                        start: profileStart,
                        details: "row=\(rowIndex),lineLength=\(lineRange.length)"
                    )
                }
            }
            let safePrefixLength = min(prefixLength, lineRange.length)
            let lineContentLength = max(0, lineRange.length - safePrefixLength)
            let lineText = source.substring(with: lineRange)
            let lineContentRange = NSRange(location: safePrefixLength, length: lineContentLength)
            var formulaFullRanges: [NSRange] = []
            var imageFullRanges: [NSRange] = []
            // Formula and image overlays are centered in the owning row. The row must reserve
            // the tallest rendered payload; otherwise tall fractions overlap adjacent nodes.
            var requiredInlineLineHeight: CGFloat = 0
            var requiredFormulaHeight: CGFloat = 0
            let highlightColor = NSColor(
                red: 240.0 / 255.0,
                green: 200.0 / 255.0,
                blue: 71.0 / 255.0,
                alpha: 0.46
            )

            func applyLineRegex(
                _ pattern: String,
                block: (NSRange, NSRange) -> Void
            ) {
                let matches = cachedRegexMatches(for: pattern, in: lineText, rowIndex: rowIndex)
                let contentEnd = lineContentRange.location + lineContentRange.length
                for match in matches {
                    let matchStart = match.fullRange.location
                    let matchEnd = match.fullRange.location + match.fullRange.length
                    guard matchStart >= lineContentRange.location, matchEnd <= contentEnd else { continue }
                    let absoluteFull = NSRange(
                        location: lineRange.location + match.fullRange.location,
                        length: match.fullRange.length
                    )
                    let absoluteInner = NSRange(
                        location: lineRange.location + match.innerRange.location,
                        length: match.innerRange.length
                    )
                    block(absoluteFull, absoluteInner)
                }
            }

            func overlapsFormula(_ range: NSRange) -> Bool {
                formulaFullRanges.contains { NSIntersectionRange($0, range).length > 0 }
            }

            func overlapsImage(_ range: NSRange) -> Bool {
                imageFullRanges.contains { NSIntersectionRange($0, range).length > 0 }
            }

            func applyInlineDelimiterStyle(fullRange: NSRange, innerRange: NSRange) {
                if renderMode {
                    applyDelimiterHide(in: storage, fullRange: fullRange, innerRange: innerRange)
                } else {
                    applyDelimiterFade(in: storage, fullRange: fullRange, innerRange: innerRange)
                }
            }

            func recordFormulaRender(
                fullRange: NSRange,
                innerRange: NSRange,
                latex: String,
                mode: NodeMarkdownFormulaRenderMode,
                isBlock: Bool,
                fontSize: CGFloat
            ) -> CGFloat? {
                guard renderMode else { return nil }
                return applyFormulaOverlayLayout(
                    in: storage,
                    range: fullRange,
                    latex: latex,
                    mode: mode,
                    isBlock: isBlock,
                    textColor: textColor,
                    fontSize: fontSize,
                    baseFont: baseFont
                )
            }

            applyLineRegex(#"\$\$([^$\n]+)\$\$"#) { fullRange, innerRange in
                if renderMode {
                    let formulaText = source.substring(with: innerRange)
                    let fontSize = max(baseFont.pointSize * 1.2, 18)
                    let renderedHeight = recordFormulaRender(
                        fullRange: fullRange,
                        innerRange: innerRange,
                        latex: formulaText,
                        mode: .display,
                        isBlock: true,
                        fontSize: fontSize
                    )
                    if let renderedHeight {
                        formulaFullRanges.append(fullRange)
                        requiredInlineLineHeight = max(requiredInlineLineHeight, renderedHeight)
                        requiredFormulaHeight = max(requiredFormulaHeight, renderedHeight)
                    } else {
                        return
                    }
                }
            }

            applyLineRegex(#"(?<!\$)\$([^$\n]+)\$(?!\$)"#) { fullRange, innerRange in
                if renderMode {
                    let formulaText = source.substring(with: innerRange)
                    let fontSize = max(baseFont.pointSize, 14)
                    let renderedHeight = recordFormulaRender(
                        fullRange: fullRange,
                        innerRange: innerRange,
                        latex: formulaText,
                        mode: .text,
                        isBlock: false,
                        fontSize: fontSize
                    )
                    if let renderedHeight {
                        formulaFullRanges.append(fullRange)
                        requiredInlineLineHeight = max(requiredInlineLineHeight, renderedHeight)
                        requiredFormulaHeight = max(requiredFormulaHeight, renderedHeight)
                    } else {
                        return
                    }
                }
            }

            applyLineRegex(#"\\\(([^)\n]+)\\\)"#) { fullRange, innerRange in
                if renderMode {
                    let formulaText = source.substring(with: innerRange)
                    let fontSize = max(baseFont.pointSize, 14)
                    let renderedHeight = recordFormulaRender(
                        fullRange: fullRange,
                        innerRange: innerRange,
                        latex: formulaText,
                        mode: .text,
                        isBlock: false,
                        fontSize: fontSize
                    )
                    if let renderedHeight {
                        formulaFullRanges.append(fullRange)
                        requiredInlineLineHeight = max(requiredInlineLineHeight, renderedHeight)
                        requiredFormulaHeight = max(requiredFormulaHeight, renderedHeight)
                    } else {
                        return
                    }
                }
            }

            applyLineRegex(#"\\\[([^\]\n]+)\\\]"#) { fullRange, innerRange in
                if renderMode {
                    let formulaText = source.substring(with: innerRange)
                    let fontSize = max(baseFont.pointSize * 1.2, 18)
                    let renderedHeight = recordFormulaRender(
                        fullRange: fullRange,
                        innerRange: innerRange,
                        latex: formulaText,
                        mode: .display,
                        isBlock: true,
                        fontSize: fontSize
                    )
                    if let renderedHeight {
                        formulaFullRanges.append(fullRange)
                        requiredInlineLineHeight = max(requiredInlineLineHeight, renderedHeight)
                        requiredFormulaHeight = max(requiredFormulaHeight, renderedHeight)
                    } else {
                        return
                    }
                }
            }

            if renderMode {
                let contentEnd = lineContentRange.location + lineContentRange.length
                let imageTokens = NodeMarkdownImageResourceManager.parseImageTokens(in: lineText)
                for token in imageTokens {
                    let tokenStart = token.sourceRange.location
                    let tokenEnd = token.sourceRange.location + token.sourceRange.length
                    guard tokenStart >= lineContentRange.location, tokenEnd <= contentEnd else { continue }
                    let fullRange = NSRange(
                        location: lineRange.location + token.sourceRange.location,
                        length: token.sourceRange.length
                    )
                    if overlapsFormula(fullRange) { continue }
                    let targetWidth = max(1, CGFloat(token.width))
                    let renderedHeight = applyImageOverlayLayout(
                        in: storage,
                        range: fullRange,
                        sourcePath: token.relativePath,
                        targetWidth: targetWidth,
                        baseFont: baseFont
                    )
                    if let renderedHeight {
                        imageFullRanges.append(fullRange)
                        requiredInlineLineHeight = max(requiredInlineLineHeight, renderedHeight)
                    }
                }
            }

            applyLineRegex(#"`([^`\n]+)`"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                let codeFont = NSFont.monospacedSystemFont(ofSize: max(11, baseFont.pointSize * 0.95), weight: .regular)
                storage.addAttributes(
                    [
                        .font: codeFont,
                        .backgroundColor: NSColor.textColor.withAlphaComponent(0.08)
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"\*\*([^*\n]+)\*\*|__([^_\n]+)__"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"<(?:strong|b)>([^<\n]+)</(?:strong|b)>"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"<(?:em|i)>([^<\n]+)</(?:em|i)>"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"~~([^~\n]+)~~"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"<(?:s|del)>([^<\n]+)</(?:s|del)>"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"==([^=\n]+)=="#) { fullRange, innerRange in
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        nodeMarkdownHighlightBackgroundColorKey: highlightColor
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"<mark>([^<\n]+)</mark>"#) { fullRange, innerRange in
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        nodeMarkdownHighlightBackgroundColorKey: highlightColor
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"<u>([^<\n]+)</u>"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.systemBlue
                    ],
                    range: innerRange
                )
            }

            applyLineRegex(#"\[([^\]\n]+)\]\(([^\)\n]+)\)"#) { fullRange, innerRange in
                if overlapsFormula(fullRange) || overlapsImage(fullRange) { return }
                applyInlineDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.systemBlue,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.systemBlue
                    ],
                    range: innerRange
                )
            }
            if requiredInlineLineHeight > 0 {
                let paragraphStyle: NSMutableParagraphStyle = {
                    if let existing = storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle {
                        return existing.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    }
                    return NSMutableParagraphStyle()
                }()
                let metrics = NodeMarkdownRenderContract.inlineVerticalMetrics(
                    fontAscender: baseFont.ascender,
                    fontDescender: baseFont.descender,
                    fontLeading: baseFont.leading,
                    existingMinimumLineHeight: paragraphStyle.minimumLineHeight,
                    renderedContentHeight: requiredInlineLineHeight
                )
                paragraphStyle.minimumLineHeight = metrics.lineHeight
                storage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
                if requiredFormulaHeight > 0, metrics.textBaselineOffset > 0 {
                    applyMeasuredTextBaselineOffset(
                        metrics.textBaselineOffset,
                        in: storage,
                        lineRange: lineRange,
                        excludedRanges: formulaFullRanges + imageFullRanges
                    )
                }
            }
        }

        private func applyMeasuredTextBaselineOffset(
            _ offset: CGFloat,
            in storage: NSTextStorage,
            lineRange: NSRange,
            excludedRanges: [NSRange]
        ) {
            guard offset > 0, lineRange.length > 0 else { return }
            let source = storage.string as NSString
            var lineEnd = min(NSMaxRange(lineRange), source.length)
            while lineEnd > lineRange.location {
                let scalar = source.character(at: lineEnd - 1)
                guard scalar == 10 || scalar == 13 else { break }
                lineEnd -= 1
            }
            guard lineEnd > lineRange.location else { return }
            let visibleLineRange = NSRange(
                location: lineRange.location,
                length: lineEnd - lineRange.location
            )
            let exclusions = excludedRanges
                .map { NSIntersectionRange($0, visibleLineRange) }
                .filter { $0.length > 0 }
                .sorted { $0.location < $1.location }
            var cursor = lineRange.location
            for exclusion in exclusions {
                if exclusion.location > cursor {
                    storage.addAttribute(
                        .baselineOffset,
                        value: offset,
                        range: NSRange(location: cursor, length: exclusion.location - cursor)
                    )
                }
                cursor = max(cursor, NSMaxRange(exclusion))
            }
            if cursor < lineEnd {
                storage.addAttribute(
                    .baselineOffset,
                    value: offset,
                    range: NSRange(location: cursor, length: lineEnd - cursor)
                )
            }
        }

        private func applyImageOverlayLayout(
            in storage: NSTextStorage,
            range: NSRange,
            sourcePath: String,
            targetWidth: CGFloat,
            baseFont: NSFont
        ) -> CGFloat? {
            guard range.length > 0 else { return nil }
            guard let imageURL = resolvedImageURL(from: sourcePath),
                  let image = NSImage(contentsOf: imageURL),
                  image.size.width > 0,
                  image.size.height > 0 else {
                return nil
            }

            let width = max(1, targetWidth)
            let height = max(1, width * (image.size.height / image.size.width))
            applyRenderHiddenToken(in: storage, range: range, baseFont: baseFont, targetAdvance: width)
            storage.addAttribute(
                nodeMarkdownInlineRenderPayloadKey,
                value: NodeMarkdownInlineRenderPayload(image: image, size: NSSize(width: width, height: height)),
                range: range
            )
            imageSizeCache[sourcePath] = image.size
            return height
        }

        private func resolvedImageURL(from sourcePath: String) -> URL? {
            if let directURL = URL(string: sourcePath), directURL.isFileURL {
                return directURL
            }
            if sourcePath.hasPrefix("/") {
                return URL(fileURLWithPath: sourcePath)
            }
            guard let workingDirectoryURL else { return nil }
            return workingDirectoryURL.appendingPathComponent(sourcePath).standardizedFileURL
        }

        private func applyRegex(
            _ pattern: String,
            in source: NSString,
            range: NSRange,
            block: (NSTextCheckingResult, NSRange) -> Void
        ) {
            let regex: NSRegularExpression
            if let cached = Self.regexCache[pattern] {
                regex = cached
            } else {
                guard let compiled = try? NSRegularExpression(pattern: pattern) else { return }
                Self.regexCache[pattern] = compiled
                regex = compiled
            }
            let matches = regex.matches(in: source as String, options: [], range: range)
            for match in matches {
                let innerRange = firstCapturedRange(in: match)
                guard innerRange.location != NSNotFound, innerRange.length > 0 else { continue }
                block(match, innerRange)
            }
        }

        private func firstCapturedRange(in result: NSTextCheckingResult) -> NSRange {
            guard result.numberOfRanges > 1 else { return NSRange(location: NSNotFound, length: 0) }
            for index in 1..<result.numberOfRanges {
                let range = result.range(at: index)
                if range.location != NSNotFound, range.length > 0 {
                    return range
                }
            }
            return NSRange(location: NSNotFound, length: 0)
        }

        private func applyDelimiterFade(in storage: NSTextStorage, fullRange: NSRange, innerRange: NSRange) {
            let leftLength = max(0, innerRange.location - fullRange.location)
            if leftLength > 0 {
                storage.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: NSRange(location: fullRange.location, length: leftLength)
                )
            }

            let fullEnd = fullRange.location + fullRange.length
            let innerEnd = innerRange.location + innerRange.length
            let rightLength = max(0, fullEnd - innerEnd)
            if rightLength > 0 {
                storage.addAttributes(
                    [.foregroundColor: NSColor.secondaryLabelColor],
                    range: NSRange(location: innerEnd, length: rightLength)
                )
            }
        }

        private func applyDelimiterHide(in storage: NSTextStorage, fullRange: NSRange, innerRange: NSRange) {
            let leftLength = max(0, innerRange.location - fullRange.location)
            if leftLength > 0 {
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                        .kern: -2.2
                    ],
                    range: NSRange(location: fullRange.location, length: leftLength)
                )
            }

            let fullEnd = fullRange.location + fullRange.length
            let innerEnd = innerRange.location + innerRange.length
            let rightLength = max(0, fullEnd - innerEnd)
            if rightLength > 0 {
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.clear,
                        .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                        .kern: -2.2
                    ],
                    range: NSRange(location: innerEnd, length: rightLength)
                )
            }
        }

        private func applyFormulaOverlayLayout(
            in storage: NSTextStorage,
            range: NSRange,
            latex: String,
            mode: NodeMarkdownFormulaRenderMode,
            isBlock: Bool,
            textColor: NSColor,
            fontSize: CGFloat,
            baseFont: NSFont
        ) -> CGFloat? {
            _ = isBlock
            guard range.length > 0 else { return nil }
            #if canImport(SwiftMath)
            guard let image = formulaAttachmentImage(
                latex: latex,
                mode: mode,
                textColor: textColor,
                fontSize: fontSize
            ) else { return nil }

            let renderScale = max(1, NodeMarkdownStyledTextView.formulaRenderScaleForAttachment)
            let width = image.size.width / renderScale
            let height = image.size.height / renderScale
            guard width > 0, height > 0 else { return nil }

            let characterWidth = max(
                baseFont.pointSize,
                ("字" as NSString).size(withAttributes: [.font: baseFont]).width
            )
            let horizontalInset = characterWidth * 0.5
            applyRenderHiddenToken(
                in: storage,
                range: range,
                baseFont: baseFont,
                targetAdvance: width + horizontalInset * 2
            )
            storage.addAttribute(
                nodeMarkdownInlineRenderPayloadKey,
                value: NodeMarkdownInlineRenderPayload(
                    image: image,
                    size: NSSize(width: width, height: height),
                    horizontalInset: horizontalInset,
                    centersOnLineAxis: true
                ),
                range: range
            )
            return height
            #else
            return nil
            #endif
        }

        #if canImport(SwiftMath)
        private func formulaAttachmentImage(
            latex: String,
            mode: NodeMarkdownFormulaRenderMode,
            textColor: NSColor,
            fontSize: CGFloat
        ) -> NSImage? {
            let normalizedLatex = normalizedFormulaLatex(latex)
            let normalizedColor = formulaRenderColor(from: textColor)
            let cacheKey = FormulaAttachmentCacheKey(
                latex: normalizedLatex,
                mode: mode == .display ? 1 : 0,
                fontSize: Int((fontSize * NodeMarkdownStyledTextView.formulaRenderScaleForAttachment).rounded()),
                red: Int((normalizedColor.redComponent * 255).rounded()),
                green: Int((normalizedColor.greenComponent * 255).rounded()),
                blue: Int((normalizedColor.blueComponent * 255).rounded()),
                alpha: Int((normalizedColor.alphaComponent * 255).rounded())
            )
            if let cached = formulaAttachmentImageCache[cacheKey] {
                return cached
            }
            let imageBuilder = MTMathImage(
                latex: normalizedLatex,
                fontSize: fontSize * NodeMarkdownStyledTextView.formulaRenderScaleForAttachment,
                textColor: normalizedColor,
                labelMode: mode == .display ? .display : .text,
                textAlignment: .left
            )
            imageBuilder.font?.fallbackFont = regularFormulaFallbackFont(size: fontSize * NodeMarkdownStyledTextView.formulaRenderScaleForAttachment)
            let result = imageBuilder.asImage()
            guard result.0 == nil, let image = result.1 else { return nil }
            formulaAttachmentImageCache[cacheKey] = image
            return image
        }

        private func formulaRenderColor(from textColor: NSColor) -> NSColor {
            let appearance = NSAppearance(named: .aqua)
            var resolved: NSColor?
            appearance?.performAsCurrentDrawingAppearance {
                resolved = textColor.usingColorSpace(.deviceRGB)
            }
            if resolved == nil {
                resolved = textColor.usingColorSpace(.deviceRGB)
            }
            return resolved ?? textColor
        }

        private func normalizedFormulaLatex(_ latex: String) -> String {
            NodeMarkdownFormulaLatexNormalizer.normalize(latex)
        }

        private func regularFormulaFallbackFont(size: CGFloat) -> CTFont {
            let preferred = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
            if CTFontGetGlyphCount(preferred) > 0 {
                return preferred
            }
            return CTFontCreateWithName("Helvetica" as CFString, size, nil)
        }
        #endif

        private func applyRenderHiddenToken(
            in storage: NSTextStorage,
            range: NSRange,
            baseFont: NSFont,
            targetAdvance: CGFloat? = nil
        ) {
            let tokenText = storage.mutableString.substring(with: range)
            let naturalAdvance = (tokenText as NSString).size(withAttributes: [.font: baseFont]).width
            let normalizedTargetAdvance: CGFloat = {
                guard let targetAdvance else { return naturalAdvance }
                return max(0.5, targetAdvance)
            }()
            let kern: CGFloat = {
                guard range.length > 1 else { return 0 }
                let residual = normalizedTargetAdvance - naturalAdvance
                return residual / CGFloat(range.length - 1)
            }()
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: baseFont,
                    .kern: kern,
                    .ligature: 0,
                    .expansion: 0
                ],
                range: range
            )
        }

        private func scrollToActiveRowIfNeeded(in textView: NSTextView) {
            guard let activeRowIndex,
                  let range = effectiveRowRange(at: activeRowIndex) else { return }
            textView.scrollRangeToVisible(range)
        }

        private func invalidateDisplayForRows(_ rows: Set<Int>, in textView: NSTextView) {
            guard !rows.isEmpty else { return }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                textView.needsDisplay = true
                return
            }
            for row in rows {
                guard let range = effectiveRowRange(at: row) else { continue }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { continue }
                var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                if rect.isEmpty { continue }
                rect.origin.x += textView.textContainerOrigin.x
                rect.origin.y += textView.textContainerOrigin.y
                textView.setNeedsDisplay(rect.insetBy(dx: -24, dy: -12))
            }
        }

        private func resolvedEditingRowIndex(_ mode: EditingRowMode, in textView: NSTextView) -> Int? {
            switch mode {
            case .infer:
                return currentRowIndex(in: textView)
            case .none:
                return nil
            case let .row(rowIndex):
                return rowIndex
            }
        }

        private func beginEditingSession(in textView: NSTextView) {
            _ = textView
            guard editorLifecycleState != .editing else { return }
            pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
            logLayoutJitter("beginEditingSession")
            editorLifecycleState = .editing
            notifyInputSessionStateChange(true)
            renderCoordinator.beginEditingSession()
            #if DEBUG
            if Self.isRenderSmokeEnabled {
                NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.typingContinuous)
            }
            #endif
        }

        private func endEditingSessionAndScheduleIdleRender(on textView: NSTextView) {
            _ = finishActiveNodeTransaction(in: textView, commit: true)
            editorLifecycleState = .idle
            notifyInputSessionStateChange(false)
            logLayoutJitter(
                "endEditingSession"
            )
            pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
            commitEditedRowsToRenderedState(on: textView)
            notifyActiveRowChange(nil)
            #if DEBUG
            if Self.isRenderSmokeEnabled {
                NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.blurSingleTransactionCommit)
            }
            #endif
            TeachingDebugLogStore.append(
                "visible-only-refresh-after-inline-edit",
                category: "NodeMarkdown.Perf"
            )
        }

        private func markEditedRows(_ rows: Set<Int>) {
            editedRowsDuringSession.formUnion(rows.filter { $0 >= 0 })
        }

        func performPreservingVisibleOrigin(in textView: NSTextView, _ updates: () -> Void) {
            guard let scrollView = textView.enclosingScrollView else {
                updates()
                return
            }
            let clipView = scrollView.contentView
            let originalOrigin = clipView.bounds.origin
            updates()
            restoreVisibleOrigin(originalOrigin, in: scrollView, clipView: clipView)
        }

        /// 全文确实发生结构变化时，以屏幕顶部第一个有效Node作为视觉锚点。
        /// 绝对Y坐标在上方删行后已经失去意义，UUID与屏内偏移才代表用户看到的位置。
        func captureVisualViewportAnchor(in textView: NSTextView) -> VisualViewportAnchor? {
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  !rowCharacterRanges.isEmpty else { return nil }
            let clipView = scrollView.contentView
            let fallbackOrigin = clipView.bounds.origin
            let containerOrigin = textView.textContainerOrigin
            let visibleLayoutRect = textView.visibleRect.offsetBy(
                dx: -containerOrigin.x,
                dy: -containerOrigin.y
            )
            let visibleGlyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleLayoutRect,
                in: textContainer
            )
            let visibleCharacterRange = layoutManager.characterRange(
                forGlyphRange: visibleGlyphRange,
                actualGlyphRange: nil
            )
            guard let firstVisibleRow = lineIndexForLocation(visibleCharacterRange.location) else { return nil }

            let source = textView.string as NSString
            let visibleRows = firstVisibleRow..<min(rowCharacterRanges.count, firstVisibleRow + 12)
            let anchorRow = visibleRows.first { row in
                guard rowMetadata.indices.contains(row), rowCharacterRanges.indices.contains(row) else { return false }
                let range = rowCharacterRanges[row]
                guard range.location <= source.length, NSMaxRange(range) <= source.length else { return false }
                return !source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? firstVisibleRow
            guard rowMetadata.indices.contains(anchorRow),
                  !rowMetadata[anchorRow].nodeID.isEmpty,
                  let rowRect = visualRect(forRow: anchorRow, in: textView) else { return nil }
            return VisualViewportAnchor(
                nodeID: rowMetadata[anchorRow].nodeID,
                verticalOffset: rowRect.minY - clipView.bounds.minY,
                fallbackOrigin: fallbackOrigin
            )
        }

        func restoreVisualViewportAnchor(_ anchor: VisualViewportAnchor?, in textView: NSTextView) {
            guard let anchor,
                  let scrollView = textView.enclosingScrollView else { return }
            let clipView = scrollView.contentView
            guard let row = rowMetadata.firstIndex(where: { $0.nodeID == anchor.nodeID }),
                  let rowRect = visualRect(forRow: row, in: textView) else {
                restoreVisibleOrigin(anchor.fallbackOrigin, in: scrollView, clipView: clipView)
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

        private func visualRect(forRow row: Int, in textView: NSTextView) -> NSRect? {
            guard rowCharacterRanges.indices.contains(row),
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return nil }
            let characterRange = rowCharacterRanges[row]
            layoutManager.ensureLayout(forCharacterRange: characterRange)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return rect
        }

        private func restoreVisibleOrigin(_ origin: NSPoint, in scrollView: NSScrollView, clipView: NSClipView) {
            guard clipView.bounds.origin != origin else { return }
            clipView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        private func enterRowSourceMode(on textView: NSTextView, row: Int?) {
            guard let row, row >= 0 else { return }
            guard rowCharacterRanges.indices.contains(row) else { return }
            if activeSourceModeRowIndex == row {
                beginEditingNodeDraftIfNeeded(row: row, in: textView)
                return
            }
            if let activeSourceModeRowIndex {
                let previousNodeID = activeNodeTransaction?.draft.nodeID
                _ = finishActiveNodeTransaction(in: textView, commit: true)
                let previousRow = previousNodeID.flatMap { nodeID in
                    rowMetadata.firstIndex(where: { $0.nodeID == nodeID })
                } ?? activeSourceModeRowIndex
                commitEditedRowsToRenderedState(on: textView, rows: [previousRow])
                editingParagraphStyleCache.removeValue(forKey: previousRow)
            }
            performPreservingVisibleOrigin(in: textView) {
                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }
                applyStyle(
                    to: textView,
                    targetRows: [row],
                    source: .selectionChanged,
                    editingRowMode: .row(row)
                )
            }
            activeSourceModeRowIndex = row
            beginEditingNodeDraftIfNeeded(row: row, in: textView)
        }

        private func beginEditingNodeDraftIfNeeded(row: Int, in textView: NSTextView) {
            guard rowMetadata.indices.contains(row),
                  let range = effectiveRowRange(at: row),
                  let content = sourceContent(at: row, in: textView) else { return }
            let metadata = rowMetadata[row]
            if var transaction = activeNodeTransaction,
               transaction.draft.nodeID == metadata.nodeID {
                transaction.draft.content = content
                activeNodeTransaction = transaction
                refreshEditingNodeDraftDirtyState()
                return
            }
            let draft = NodeMarkdownLegacyEditingNodeDraft(
                nodeID: metadata.nodeID,
                level: max(1, min(12, metadata.level)),
                content: content,
                sourceID: metadata.sourceID,
                sourceFile: metadata.sourceFile
            )
            activeNodeTransaction = NodeMarkdownLegacyActiveNodeTransaction(
                rowIndex: row,
                range: range,
                draft: draft
            )
            publishActiveNodeGeometry(to: textView)
            setEditingNodeDraftDirty(false)
        }

        private func updateEditingNodeDraftContent(row: Int?, in textView: NSTextView) {
            guard let row,
                  rowMetadata.indices.contains(row),
                  synchronizeActiveNodeRange(in: textView),
                  let content = sourceContent(at: row, in: textView) else { return }
            let metadata = rowMetadata[row]
            guard var transaction = activeNodeTransaction,
                  transaction.draft.nodeID == metadata.nodeID else {
                beginEditingNodeDraftIfNeeded(row: row, in: textView)
                return
            }
            transaction.draft.content = content
            transaction.draft.level = max(1, min(12, metadata.level))
            transaction.draft.sourceID = metadata.sourceID
            transaction.draft.sourceFile = metadata.sourceFile
            activeNodeTransaction = transaction
            refreshEditingNodeDraftDirtyState()
        }

        private func updateEditingNodeDraftLevel(row: Int, level: Int) {
            guard rowMetadata.indices.contains(row),
                  var transaction = activeNodeTransaction,
                  transaction.draft.nodeID == rowMetadata[row].nodeID else { return }
            transaction.draft.level = max(1, min(12, level))
            transaction.draft.sourceID = rowMetadata[row].sourceID
            transaction.draft.sourceFile = rowMetadata[row].sourceFile
            activeNodeTransaction = transaction
            refreshEditingNodeDraftDirtyState()
        }

        private func commitEditingNodeDraft() {
            guard var transaction = activeNodeTransaction else { return }
            if transaction.isDirty {
                onCommitEditingNode?(transaction.draft)
                transaction.markCommitted()
                activeNodeTransaction = transaction
            }
            setEditingNodeDraftDirty(false)
        }

        private func discardEditingNodeDraft() {
            activeNodeTransaction = nil
            setEditingNodeDraftDirty(false)
        }

        private func refreshEditingNodeDraftDirtyState() {
            setEditingNodeDraftDirty(activeNodeTransaction?.isDirty == true)
        }

        /// 离行和结构操作的统一出口：先从TextKit读取活动Node的完整正文，再提交，
        /// 最后才把当前字符范围固化为稳定行索引。下一Node永远不会参与本次读取。
        @discardableResult
        private func finishActiveNodeTransaction(
            in textView: NSTextView,
            commit: Bool
        ) -> Int? {
            let row = activeNodeTransaction?.rowIndex
            if let row {
                updateEditingNodeDraftContent(row: row, in: textView)
            }
            if commit {
                commitEditingNodeDraft()
            }
            activeNodeTransaction = nil
            setEditingNodeDraftDirty(false)
            rebuildRowCharacterRanges(from: textView)
            return row
        }

        private func setEditingNodeDraftDirty(_ isDirty: Bool) {
            guard hasUncommittedEditingNodeDraft != isDirty else { return }
            hasUncommittedEditingNodeDraft = isDirty
            onEditingDraftDirtyChange?(isDirty)
        }

        /// 保存事务的同步入口。不让NSTextView失焦，只把当前Node草稿提交给父文档，
        /// 然后以已提交内容重建基线，保存完成后可以在原焦点继续输入。
        func commitPendingEditingForPersistence(in textView: NSTextView) {
            // Command+S只提交数据，绝不承担“把焦点滚到可见处”的职责。
            // 草稿回写会同步触发SwiftUI与AppKit两轮布局。保存事务期间禁止
            // NSTextView为了选择区域自动滚动，并在两轮主队列布局后恢复原视野。
            let styledTextView = textView as? NodeMarkdownStyledTextView
            styledTextView?.suppressesAutomaticSelectionScrolling = true
            let scrollView = textView.enclosingScrollView
            let originalOrigin = scrollView?.contentView.bounds.origin
            performPreservingVisibleOrigin(in: textView) {
                if isMarkedTextCompositionActive(in: textView) {
                    textView.unmarkText()
                }
                let row = activeSourceModeRowIndex ?? currentRowIndex(in: textView)
                updateEditingNodeDraftContent(row: row, in: textView)
                commitEditingNodeDraft()
                if let row {
                    beginEditingNodeDraftIfNeeded(row: row, in: textView)
                }
            }
            preservePersistenceViewport(
                origin: originalOrigin,
                scrollView: scrollView,
                textView: styledTextView
            )
        }

        private func preservePersistenceViewport(
            origin: NSPoint?,
            scrollView: NSScrollView?,
            textView: NodeMarkdownStyledTextView?
        ) {
            guard let origin, let scrollView, let textView else {
                textView?.suppressesAutomaticSelectionScrolling = false
                return
            }
            let restore = {
                let clipView = scrollView.contentView
                clipView.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clipView)
            }
            restore()
            DispatchQueue.main.async { [weak scrollView, weak textView] in
                guard let scrollView, let textView else { return }
                let clipView = scrollView.contentView
                clipView.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clipView)
                DispatchQueue.main.async { [weak scrollView, weak textView] in
                    guard let scrollView, let textView else { return }
                    let clipView = scrollView.contentView
                    clipView.setBoundsOrigin(origin)
                    scrollView.reflectScrolledClipView(clipView)
                    textView.suppressesAutomaticSelectionScrolling = false
                }
            }
        }

        func focusAtEnd(ofRow rowIndex: Int, in textView: NSTextView) {
            guard let range = effectiveRowRange(at: rowIndex) else { return }
            let text = textView.string as NSString
            var end = min(NSMaxRange(range), text.length)
            while end > range.location {
                let character = text.substring(with: NSRange(location: end - 1, length: 1))
                guard character == "\n" || character == "\r" else { break }
                end -= 1
            }
            setSelectionIfNeeded(textView, range: NSRange(location: end, length: 0))
        }

        /// ESC不是丢弃编辑。先把当前Node草稿提交到文档，再退出源码状态；
        /// textDidEndEditing随后只负责结束会话，不会看到一份尚未提交的活动草稿。
        private func commitActiveDraftBeforeLeavingSourceMode(in textView: NSTextView) {
            if isMarkedTextCompositionActive(in: textView) {
                textView.unmarkText()
            }
            _ = finishActiveNodeTransaction(in: textView, commit: true)
            commitEditedRowsToRenderedState(on: textView)
            focusTransaction.cancel()
        }

        private func sourceContent(at row: Int, in textView: NSTextView) -> String? {
            guard let effectiveRange = effectiveRowRange(at: row),
                  let storage = textView.textStorage else { return nil }
            let source = storage.mutableString
            guard effectiveRange.location <= source.length,
                  NSMaxRange(effectiveRange) <= source.length else { return nil }
            var content = sourceTextPreservingAttachmentTokens(in: effectiveRange, storage: storage)
            if content.hasSuffix("\r\n") {
                content.removeLast(2)
            } else if content.hasSuffix("\n") || content.hasSuffix("\r") {
                content.removeLast()
            }
            return content
        }

        private func commitEditedRowsToRenderedState(on textView: NSTextView, rows explicitRows: Set<Int>? = nil) {
            let rows: Set<Int> = {
                if let explicitRows { return explicitRows }
                var rows = editedRowsDuringSession
                if let activeSourceModeRowIndex { rows.insert(activeSourceModeRowIndex) }
                return rows
            }()
            guard !rows.isEmpty else { return }
            performPreservingVisibleOrigin(in: textView) {
                isProgrammaticUpdate = true
                defer { isProgrammaticUpdate = false }
                applyStyle(
                    to: textView,
                    targetRows: rows,
                    source: .endEditing,
                    forceRenderedRows: rows,
                    editingRowMode: .none
                )
            }
            editedRowsDuringSession.subtract(rows)
            if let activeSourceModeRowIndex, rows.contains(activeSourceModeRowIndex) {
                editingParagraphStyleCache.removeValue(forKey: activeSourceModeRowIndex)
                self.activeSourceModeRowIndex = nil
            }
        }

        private func ensureEditingRowVisibleSourceAttributes(in textView: NSTextView, editingRow: Int?) {
            guard let editingRow,
                  let effectiveRange = effectiveRowRange(at: editingRow),
                  let storage = textView.textStorage else { return }
            let nsText = storage.mutableString
            guard nsText.length > 0 else { return }
            guard effectiveRange.location <= nsText.length,
                  NSMaxRange(effectiveRange) <= nsText.length else { return }
            if effectiveRange.length == 0 {
                updateTypingAttributes(for: textView)
                return
            }

            let selectedRanges = textView.selectedRanges
            isProgrammaticUpdate = true
            defer { isProgrammaticUpdate = false }
            applySourceLineAttributes(
                in: storage,
                range: effectiveRange,
                lineText: nsText.substring(with: effectiveRange)
            )
            textView.selectedRanges = selectedRanges
            textView.layoutManager?.invalidateDisplay(forCharacterRange: effectiveRange)
            textView.setNeedsDisplay(textView.visibleRect)
        }

        private func applySourceLineAttributes(in storage: NSTextStorage, range: NSRange, lineText: String) {
            let prefix = ""
            let rowIndex = lineIndexForRange(range)
            let level = rowMetadata.indices.contains(rowIndex) ? rowMetadata[rowIndex].level : 7
            let previousLine = previousLineLayout(before: range, source: storage.mutableString)
            let styleAttributes = lineStyleAttributes(
                for: LineLayout(range: range, prefix: prefix, level: level),
                previousLine: previousLine,
                allowsInlineRender: false,
                rowIndex: rowIndex,
                locksEditingParagraph: activeSourceModeRowIndex == rowIndex
            )
            storage.setAttributes(
                styleAttributes.attributes,
                range: range
            )
            let prefixLength = min((prefix as NSString).length, range.length)
            if prefixLength > 0 {
                storage.addAttribute(
                    .foregroundColor,
                    value: NSColor.clear,
                    range: NSRange(location: range.location, length: prefixLength)
                )
            }
        }

        private func scheduleTextChangedStyleRefresh(
            on textView: NSTextView,
            rows: Set<Int>,
            delay: TimeInterval,
            editingRow: Int?
        ) {
            scheduleStyleRefresh(
                on: textView,
                request: .incremental(
                    rows: rows,
                    delay: delay,
                    editingRowMode: editingRow.map { .row($0) } ?? .infer
                ),
                source: .textChanged
            )
        }

        private func scheduleStyleRefresh(
            on textView: NSTextView,
            request: StyleRefreshRequest,
            source: RenderTriggerSource
        ) {
            renderCoordinator.schedule(
                request: request,
                source: source,
                contentRevision: currentRenderRevision,
                isContentRevisionCurrent: { [weak self] revision in
                    guard let self else { return false }
                    return self.currentRenderRevision == revision
                },
                onTrace: { [weak self] event in
                    self?.logRenderTrace(event)
                },
                apply: { [weak self, weak textView] scheduledRequest in
                    guard let self, let textView else { return }
                    let applyUpdate = {
                        self.isProgrammaticUpdate = true
                        defer { self.isProgrammaticUpdate = false }
                        switch scheduledRequest {
                        case let .incremental(rows, _, forceRenderedRows, editingRowMode):
                            self.applyStyle(
                                to: textView,
                                targetRows: rows,
                                source: source,
                                forceRenderedRows: forceRenderedRows,
                                editingRowMode: editingRowMode
                            )
                        }
                    }
                    if self.editorLifecycleState == .editing || source == .textChanged {
                        self.performPreservingVisibleOrigin(in: textView, applyUpdate)
                    } else {
                        applyUpdate()
                    }
                }
            )
        }

        func sourceTextPreservingAttachmentTokens(from textView: NSTextView) -> String {
            textView.string
        }

        private func installStructuralFocusAnchor(
            row: Int,
            contentOffset: Int,
            projectedMetadata: [NodeMarkdownTextKitRowMetadata]
        ) {
            guard row >= 0, projectedMetadata.indices.contains(row) else {
                focusTransaction.cancel()
                return
            }
            focusTransaction.install(
                nodeID: projectedMetadata[row].nodeID,
                fallbackRow: row,
                contentOffset: max(0, contentOffset)
            )
        }

        /// 消费结构焦点锚点并返回最终字符位置。无论解析成功与否都先销毁锚点，
        /// 保证之后的样式刷新、父视图回写和主线程任务不能再次移动焦点。
        @discardableResult
        func consumeStructuralFocusAnchor(in textView: NSTextView) -> Int? {
            guard let resolved = focusTransaction.consume(metadata: rowMetadata) else { return nil }
            let row = resolved.row
            if !rowCharacterRanges.indices.contains(row) {
                rebuildRowCharacterRanges(from: textView)
            }
            guard rowCharacterRanges.indices.contains(row) else { return nil }

            let nsText = textView.string as NSString
            let rowRange = rowCharacterRanges[row]
            guard rowRange.location <= nsText.length else { return nil }
            let safeLength = min(rowRange.length, max(0, nsText.length - rowRange.location))
            var contentLength = safeLength
            if contentLength > 0 {
                let raw = nsText.substring(with: NSRange(location: rowRange.location, length: contentLength))
                if raw.hasSuffix("\r\n") {
                    contentLength = max(0, contentLength - 2)
                } else if raw.hasSuffix("\n") || raw.hasSuffix("\r") {
                    contentLength = max(0, contentLength - 1)
                }
            }
            let location = rowRange.location + min(resolved.contentOffset, contentLength)
            let previousProgrammaticState = isProgrammaticUpdate
            isProgrammaticUpdate = true
            setSelectionIfNeeded(textView, range: NSRange(location: location, length: 0))
            isProgrammaticUpdate = previousProgrammaticState
            return location
        }

        /// 结构事务只允许在最终焦点确定后滚动一次。
        func revealStructuralFocusOnce(_ location: Int?, in textView: NSTextView) {
            guard let location else { return }
            let textLength = (textView.string as NSString).length
            let safeLocation = max(0, min(location, textLength))
            textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
        }

        /// 包删除、剪切、粘贴和图片插入由父视图改写文档，因此在发出请求前
        /// 先把当前焦点转换成Node锚点。删除类操作使用行号回退，保留类操作使用UUID。
        func prepareStructuralFocusForExternalOperation(
            at row: Int,
            in textView: NSTextView,
            targetNodeSurvives: Bool
        ) {
            guard rowMetadata.indices.contains(row) else {
                focusTransaction.cancel()
                return
            }
            let contentOffset: Int = {
                guard rowCharacterRanges.indices.contains(row) else { return 0 }
                let rowRange = rowCharacterRanges[row]
                let selectionLocation = textView.selectedRange().location
                guard selectionLocation >= rowRange.location,
                      selectionLocation <= NSMaxRange(rowRange) else { return 0 }
                return selectionLocation - rowRange.location
            }()
            focusTransaction.install(
                nodeID: targetNodeSurvives ? rowMetadata[row].nodeID : "",
                fallbackRow: row,
                contentOffset: targetNodeSurvives ? contentOffset : 0
            )
        }

        /// 包删除不应把焦点转移到任意替代行。先提交活动Node，然后结束
        /// 编辑会话并丢弃结构焦点锚点；后续全文替换只恢复原滚动坐标。
        func prepareDestructiveExternalOperation(in textView: NSTextView) {
            commitPendingEditingForPersistence(in: textView)
            focusTransaction.cancel()
        }

        private func releaseStructuralFocusAnchorForUserAction() {
            focusTransaction.cancel()
        }

        private func restoredEditableEnd(for lineText: String, range: NSRange) -> Int {
            var trailingNewlineLength = 0
            if lineText.hasSuffix("\r\n") {
                trailingNewlineLength = 2
            } else if lineText.hasSuffix("\n") || lineText.hasSuffix("\r") {
                trailingNewlineLength = 1
            }
            return max(range.location, NSMaxRange(range) - trailingNewlineLength)
        }

        private func sourceTextPreservingAttachmentTokens(in range: NSRange, storage: NSTextStorage) -> String {
            let nsText = storage.mutableString
            let textLength = nsText.length
            let safeLocation = max(0, min(range.location, textLength))
            let safeEnd = max(safeLocation, min(NSMaxRange(range), textLength))
            guard safeEnd > safeLocation else { return "" }

            return nsText.substring(with: NSRange(location: safeLocation, length: safeEnd - safeLocation))
        }

        private func applyQuickInputIfNeeded(in textView: NSTextView) -> Bool {
            guard !isApplyingQuickInputReplacement else { return false }
            guard let storage = textView.textStorage else { return false }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let nsText = storage.mutableString
            let caret = max(0, min(selection.location, nsText.length))
            let prefixStart = max(0, caret - 8_192)
            let prefix = nsText.substring(with: NSRange(location: prefixStart, length: caret - prefixStart))

            if applyPairQuickInputIfNeeded(
                textView: textView,
                storage: storage,
                prefix: prefix,
                prefixStart: prefixStart,
                caret: caret
            ) {
                return true
            }

            for candidate in quickInputSingleCandidates() {
                guard !candidate.trigger.isEmpty else { continue }
                guard candidate.replacement != candidate.trigger else { continue }
                guard prefix.hasSuffix(candidate.trigger) else { continue }

                let triggerLength = (candidate.trigger as NSString).length
                let replacementLength = (candidate.replacement as NSString).length
                let start = caret - triggerLength
                guard start >= 0 else { continue }

                replaceQuickInputText(
                    in: NSRange(location: start, length: triggerLength),
                    with: candidate.replacement,
                    selectedRange: NSRange(location: start + replacementLength, length: 0),
                    textView: textView,
                    storage: storage
                )
                return true
            }
            return false
        }

        private func applyPairQuickInputIfNeeded(
            textView: NSTextView,
            storage: NSTextStorage,
            prefix: String,
            prefixStart: Int,
            caret: Int
        ) -> Bool {
            let nsPrefix = prefix as NSString

            for pairRule in quickInputPairCandidates() {
                let openTrigger = pairRule.openTrigger
                let closeTrigger = pairRule.closeTrigger
                guard !openTrigger.isEmpty, !closeTrigger.isEmpty else { continue }
                guard pairRule.openReplacement != openTrigger || pairRule.closeReplacement != closeTrigger else { continue }
                guard prefix.hasSuffix(closeTrigger) else { continue }

                let closeLength = (closeTrigger as NSString).length
                let openLength = (openTrigger as NSString).length
                let closeStart = caret - closeLength
                guard closeStart >= 0 else { continue }

                let localCloseStart = closeStart - prefixStart
                guard localCloseStart >= 0 else { continue }
                let searchRange = NSRange(location: 0, length: localCloseStart)
                let localOpenRange = nsPrefix.range(of: openTrigger, options: .backwards, range: searchRange)
                guard localOpenRange.location != NSNotFound else { continue }

                let localContentStart = localOpenRange.location + openLength
                guard localContentStart <= localCloseStart else { continue }
                let contentLength = localCloseStart - localContentStart
                let content = nsPrefix.substring(with: NSRange(location: localContentStart, length: contentLength))
                let replacement = pairRule.openReplacement + content + pairRule.closeReplacement
                let openLocation = prefixStart + localOpenRange.location

                replaceQuickInputText(
                    in: NSRange(location: openLocation, length: caret - openLocation),
                    with: replacement,
                    selectedRange: NSRange(location: openLocation + (replacement as NSString).length, length: 0),
                    textView: textView,
                    storage: storage
                )
                return true
            }

            return false
        }

        private func replaceQuickInputText(
            in range: NSRange,
            with replacement: String,
            selectedRange: NSRange,
            textView: NSTextView,
            storage: NSTextStorage
        ) {
            let nsText = storage.mutableString
            let safeLocation = max(0, min(range.location, nsText.length))
            let safeLength = max(0, min(range.length, nsText.length - safeLocation))
            let safeRange = NSRange(location: safeLocation, length: safeLength)

            registerPendingEdit(affectedRange: safeRange, replacement: replacement, in: nsText)
            isApplyingQuickInputReplacement = true
            isProgrammaticUpdate = true
            storage.beginEditing()
            storage.replaceCharacters(in: safeRange, with: replacement)
            storage.endEditing()
            let textLength = storage.length
            let safeSelection = NSRange(
                location: max(0, min(selectedRange.location, textLength)),
                length: 0
            )
            setSelectionIfNeeded(textView, range: safeSelection)
            isProgrammaticUpdate = false
            isApplyingQuickInputReplacement = false
        }

        private func quickInputSingleCandidates() -> [(trigger: String, replacement: String)] {
            quickInputSettings.singleRules
                .map { ($0.trigger, $0.replacement) }
                .sorted {
                    ($0.trigger as NSString).length > ($1.trigger as NSString).length
                }
        }

        private func quickInputPairCandidates() -> [MarkdownPairShortcutRule] {
            quickInputSettings.pairRules.sorted {
                let lhsClose = ($0.closeTrigger as NSString).length
                let rhsClose = ($1.closeTrigger as NSString).length
                if lhsClose != rhsClose {
                    return lhsClose > rhsClose
                }
                return ($0.openTrigger as NSString).length > ($1.openTrigger as NSString).length
            }
        }

        func textDidChange(_ notification: Notification) {
            let profileStart = Self.isPerformanceProfilingEnabled ? CFAbsoluteTimeGetCurrent() : 0
            guard !isProgrammaticUpdate,
                  let textView = notification.object as? NSTextView else {
                return
            }
            let pendingDeletionLog = pendingEdit?.deletionDiagnosis?.logSummary ?? "none"
            defer {
                if Self.isPerformanceProfilingEnabled {
                    profileDuration(
                        "textDidChange",
                        start: profileStart,
                        details: "selection=\(textView.selectedRange().location),length=\((textView.string as NSString).length),deletion=\(pendingDeletionLog)"
                    )
                }
            }
            beginEditingSession(in: textView)
            let isMarkedTextComposing = isMarkedTextCompositionActive(in: textView)
            defer {
                wasMarkedTextComposing = isMarkedTextComposing
            }
            if isMarkedTextComposing {
                handleMarkedTextComposition(in: textView)
                #if DEBUG
                if Self.isRenderSmokeEnabled {
                    NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.imeMarkedComposition)
                }
                #endif
                return
            }
            noteDocumentMutation()
            if applyQuickInputIfNeeded(in: textView) {
                updateTypingAttributes(for: textView)
            }
            let pendingEditBeforeConsume = pendingEdit
            let fallbackRow = pendingEditBeforeConsume?.preStartRowSnapshot ?? currentRowIndex(in: textView)
            if let pendingEditBeforeConsume {
                rowMetadata = pendingEditBeforeConsume.projectedRowMetadata
            }
            // AppKit已经完成字符写入。先让活动Node事务读取当前行的真实范围，
            // 再解释此次编辑属于哪一行，禁止使用上一按键留下的字符偏移。
            _ = synchronizeActiveNodeRange(in: textView)
            let targetRows = consumeEditedRows(in: textView, fallbackRow: fallbackRow)
            if wasMarkedTextComposing
                || pendingEditBeforeConsume == nil
                || lastConsumedEditChangedStructure
                || lastConsumedDeletionImpact != .character {
                rebuildRowCharacterRanges(from: textView)
            } else {
                updateRowCharacterRangesAfterCharacterEdit(in: textView)
            }
            let structuralFocusLocation = consumeStructuralFocusAnchor(in: textView)
            let currentRow = currentRowIndex(in: textView) ?? fallbackRow
            lastSelectionRowIndex = currentRow
            updateTypingAttributes(for: textView)
            enterRowSourceMode(on: textView, row: currentRow)
            let typingRows: Set<Int> = {
                if let currentRow {
                    return [currentRow]
                }
                return targetRows
            }()
            logLayoutJitter(
                "textDidChange currentRow=\(currentRow.map(String.init) ?? "nil") targetRows=\(targetRows.sorted()) typingRows=\(typingRows.sorted()) structureChanged=\(lastConsumedEditChangedStructure)"
            )
            markRegexDirty(rows: targetRows)
            if lastConsumedEditChangedStructure {
                let expandedRows: Set<Int>
                if let minimum = targetRows.min(), let maximum = targetRows.max(), minimum <= maximum {
                    expandedRows = Set(minimum...maximum)
                } else {
                    expandedRows = targetRows
                }
                pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
                let dirtyRows = rowsIncludingFollowingParagraph(for: expandedRows)
                markEditedRows(dirtyRows)
                ensureEditingRowVisibleSourceAttributes(in: textView, editingRow: currentRow)
                TeachingDebugLogStore.append(
                    "structure-change incremental expandedRows=\(expandedRows.count) targetRows=\(targetRows.count) dirtyRows=\(dirtyRows.count)",
                    category: "NodeMarkdown.Structure"
                )
                let rowsNeedingRefresh = dirtyRows.subtracting(currentRow.map { [$0] } ?? [])
                if !rowsNeedingRefresh.isEmpty {
                    scheduleTextChangedStyleRefresh(
                        on: textView,
                        rows: rowsNeedingRefresh,
                        delay: 0.01,
                        editingRow: currentRow
                    )
                }
            } else if !typingRows.isEmpty {
                pendingAttachmentDirtyRows.removeAll(keepingCapacity: true)
                let dirtyRows = typingRows
                markEditedRows(dirtyRows)
                #if DEBUG
                if Self.isRenderSmokeEnabled {
                    NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.typingSingleCharacter)
                }
                #endif
                let rowsNeedingRefresh = dirtyRows.subtracting(currentRow.map { [$0] } ?? [])
                if !rowsNeedingRefresh.isEmpty {
                    scheduleTextChangedStyleRefresh(
                        on: textView,
                        rows: rowsNeedingRefresh,
                        delay: 0.04,
                        editingRow: currentRow
                    )
                }
            }
            if wasMarkedTextComposing {
                markedTextCompositionRowIndex = nil
                #if DEBUG
                if Self.isRenderSmokeEnabled {
                    NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.imeCommitAfterMarkedText)
                }
                #endif
                imeCommitSelectionGuardUntil = CFAbsoluteTimeGetCurrent() + 0.12
            }
            let requiresStructuralPublish = lastConsumedEditChangedStructure
                || lastConsumedDeletionImpact != .character
                || targetRows.count > 1
            if requiresStructuralPublish {
                discardEditingNodeDraft()
                let preserved = sourceTextPreservingAttachmentTokens(from: textView)
                publishTextChange(preserved)
            } else {
                updateEditingNodeDraftContent(row: currentRow, in: textView)
            }
            restorePlainInsertionSelectionIfNeeded(
                pendingEditBeforeConsume,
                in: textView
            )
            revealStructuralFocusOnce(structuralFocusLocation, in: textView)
            lastSelectionRowIndex = currentRowIndex(in: textView)
            notifyActiveRowChange(lastSelectionRowIndex)
        }

        private func discardPendingEditForMarkedText() {
            pendingEdit = nil
            lastConsumedEditChangedStructure = false
            lastConsumedEditNetRowDelta = 0
            lastConsumedEditStartRow = nil
            lastConsumedEditNetCharacterDelta = 0
            lastConsumedDeletionImpact = .character
        }

        /// 拼音候选是一次未提交的字符事务，不是正式Node编辑。
        /// 期间只更新UTF-16行坐标；不切换源码行、不写段落样式、不提交草稿。
        /// 否则marked text上的局部段落属性会迫使TextKit重排后续全文。
        private func handleMarkedTextComposition(in textView: NSTextView) {
            discardPendingEditForMarkedText()
            renderCoordinator.suspendForMarkedTextComposition()

            let compositionRow = markedTextCompositionRowIndex
                ?? activeSourceModeRowIndex
                ?? lastSelectionRowIndex
                ?? markedTextRowIndex(in: textView)
            markedTextCompositionRowIndex = compositionRow
            lastSelectionRowIndex = compositionRow
            // 候选文字仍属于活动Node事务。直接读取该行此刻的真实范围，
            // 不用“全文当前长度-旧全文长度”推测，避免把下一Node算入活动行。
            _ = synchronizeActiveNodeRange(in: textView)
        }

        private func markedTextRowIndex(in textView: NSTextView) -> Int? {
            guard let nsText = textView.textStorage?.mutableString else { return nil }
            guard nsText.length > 0 else { return nil }
            let markedRange = textView.markedRange()
            guard markedRange.location != NSNotFound else { return nil }
            let location = max(0, min(markedRange.location, nsText.length))
            return lineIndexForLocation(location)
        }

        private func restorePlainInsertionSelectionIfNeeded(
            _ edit: PendingEdit?,
            in textView: NSTextView
        ) {
            guard let edit,
                  edit.insertedNewlineCount == 0,
                  edit.deletedNewlineCount == 0,
                  edit.affectedRange.length == 0,
                  edit.replacementLength > 0,
                  !isMarkedTextCompositionActive(in: textView) else { return }
            let target = NSRange(
                location: edit.affectedRange.location + edit.replacementLength,
                length: 0
            )
            setSelectionIfNeeded(
                textView,
                range: clampedSelectionRange(for: target, in: textView)
            )
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            beginEditingSession(in: textView)
            let rowIndex = currentRowIndex(in: textView)
            lastSelectionRowIndex = rowIndex
            enterRowSourceMode(on: textView, row: rowIndex)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isProgrammaticUpdate else { return }
            guard textView.window?.firstResponder !== textView else { return }
            endEditingSessionAndScheduleIdleRender(on: textView)
        }

        private func registerPendingEdit(affectedRange: NSRange, replacement: String, in sourceText: NSString) {
            let textLength = sourceText.length
            let safeAffectedLocation = max(0, min(affectedRange.location, textLength))
            let safeAffectedLength = max(0, min(affectedRange.length, max(0, textLength - safeAffectedLocation)))
            let safeAffectedRange = NSRange(location: safeAffectedLocation, length: safeAffectedLength)
            let preStartAnchor = safeAffectedRange.location
            let preEndAnchor = max(preStartAnchor, preStartAnchor + max(0, safeAffectedRange.length - 1))

            let snapshotAnchor: (Int) -> Int? = { anchor in
                guard textLength > 0 else { return nil }
                return self.lineIndexForLocation(max(0, min(anchor, textLength)))
            }

            let deletedNewlineCount: Int = {
                guard safeAffectedRange.length > 0 else { return 0 }
                let deletedText = sourceText.substring(with: safeAffectedRange)
                return deletedText.reduce(into: 0) { count, character in
                    if character == "\n" { count += 1 }
                }
            }()
            let insertedNewlineCount = replacement.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
            let deletionDiagnosis: EditorDeletionDiagnosis? = safeAffectedRange.length > 0 ? EditorDeletionClassifier.diagnoseDeletion(
                source: sourceText,
                affectedRange: safeAffectedRange,
                protectedPrefixLengthForLine: { _ in 0 }
            ) : nil
            let deletionImpact = deletionDiagnosis?.impact ?? .character
            pendingEdit = PendingEdit(
                affectedRange: safeAffectedRange,
                replacementLength: (replacement as NSString).length,
                insertedNewlineCount: insertedNewlineCount,
                deletedNewlineCount: deletedNewlineCount,
                deletionImpact: deletionImpact,
                deletionDiagnosis: deletionDiagnosis,
                preStartAnchor: preStartAnchor,
                preEndAnchor: preEndAnchor,
                preStartRowSnapshot: snapshotAnchor(preStartAnchor),
                preEndRowSnapshot: snapshotAnchor(preEndAnchor),
                projectedRowMetadata: projectedRowMetadata(
                    affectedRange: safeAffectedRange,
                    replacement: replacement,
                    sourceText: sourceText,
                    deletedNewlineCount: deletedNewlineCount,
                    insertedNewlineCount: insertedNewlineCount
                )
            )
        }

        // A structural edit moves surviving rows. Preserve identity by tracking which
        // pre-edit row still contributes characters to each post-edit row. One old
        // identity may be consumed only once, so splitting a row creates a new node.
        private func projectedRowMetadata(
            affectedRange: NSRange,
            replacement: String,
            sourceText: NSString,
            deletedNewlineCount: Int,
            insertedNewlineCount: Int
        ) -> [NodeMarkdownTextKitRowMetadata] {
            if deletedNewlineCount == 0, insertedNewlineCount == 0 {
                return rowMetadata
            }
            let projectedText = sourceText.replacingCharacters(in: affectedRange, with: replacement)

            let sourceRow = lineIndexForLocation(max(0, min(affectedRange.location, sourceText.length))) ?? 0
            let inheritedLevel = rowMetadata.indices.contains(sourceRow) ? rowMetadata[sourceRow].level : 7
            // 同一Node内回车无论是系统插入换行，还是本编辑器把整行拆成
            // “左侧 + 换行 + 右侧”，原Node身份都必须留在上半行。
            if deletedNewlineCount == 0, insertedNewlineCount > 0 {
                var result = rowMetadata
                let insertionIndex = min(result.count, sourceRow + 1)
                let insertedLevel = rowMetadata.indices.contains(sourceRow)
                    ? NodeMarkdownLegacyStructurePolicy.insertedLevel(after: rowMetadata[sourceRow])
                    : inheritedLevel
                let freshRows = (0..<insertedNewlineCount).map { _ in
                    NodeMarkdownTextKitRowMetadata.fresh(level: insertedLevel)
                }
                result.insert(contentsOf: freshRows, at: insertionIndex)
                return normalizedRowMetadata(result, forPlainText: projectedText)
            }
            if insertedNewlineCount == 0, deletedNewlineCount > 0 {
                var result = rowMetadata
                let removalStart = min(result.count, sourceRow + 1)
                let removalEnd = min(result.count, removalStart + deletedNewlineCount)
                if removalStart < removalEnd {
                    result.removeSubrange(removalStart..<removalEnd)
                }
                return normalizedRowMetadata(result, forPlainText: projectedText)
            }

            if sourceText.length == 0 {
                var metadata = Array(
                    repeating: NodeMarkdownTextKitRowMetadata.empty,
                    count: plainTextLineCount(projectedText)
                )
                if !metadata.isEmpty, let first = rowMetadata.first {
                    metadata[0] = first
                }
                return metadata
            }

            var ownerByUTF16Offset = Array<Int?>(repeating: nil, count: sourceText.length)
            let sourceLines = (sourceText as String).split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            var sourceOffset = 0
            for rowIndex in sourceLines.indices {
                let lineLength = (String(sourceLines[rowIndex]) as NSString).length
                let ownedLength = lineLength + (rowIndex < sourceLines.count - 1 ? 1 : 0)
                if ownedLength > 0, sourceOffset < ownerByUTF16Offset.count {
                    let end = min(ownerByUTF16Offset.count, sourceOffset + ownedLength)
                    for offset in sourceOffset..<end {
                        ownerByUTF16Offset[offset] = rowIndex
                    }
                }
                sourceOffset += ownedLength
            }

            ownerByUTF16Offset.replaceSubrange(
                affectedRange.location..<NSMaxRange(affectedRange),
                with: repeatElement(nil, count: (replacement as NSString).length)
            )

            let projectedLines = projectedText.split(separator: "\n", omittingEmptySubsequences: false)
            var result: [NodeMarkdownTextKitRowMetadata] = []
            result.reserveCapacity(projectedLines.count)
            var usedSourceRows: Set<Int> = []
            var projectedOffset = 0

            for rowIndex in projectedLines.indices {
                let lineLength = (String(projectedLines[rowIndex]) as NSString).length
                let ownedLength = lineLength + (rowIndex < projectedLines.count - 1 ? 1 : 0)
                let end = min(ownerByUTF16Offset.count, projectedOffset + ownedLength)
                var matchedSourceRow: Int?
                if projectedOffset < end {
                    for offset in projectedOffset..<end {
                        guard let sourceRow = ownerByUTF16Offset[offset],
                              !usedSourceRows.contains(sourceRow),
                              rowMetadata.indices.contains(sourceRow) else { continue }
                        matchedSourceRow = sourceRow
                        break
                    }
                }
                if let matchedSourceRow {
                    usedSourceRows.insert(matchedSourceRow)
                    result.append(rowMetadata[matchedSourceRow])
                } else {
                    result.append(.fresh(level: inheritedLevel))
                }
                projectedOffset += ownedLength
            }
            return result.isEmpty ? [.empty] : result
        }

        private func normalizedRowMetadata(
            _ metadata: [NodeMarkdownTextKitRowMetadata],
            forPlainText value: String
        ) -> [NodeMarkdownTextKitRowMetadata] {
            let lineCount = plainTextLineCount(value)
            return (0..<lineCount).map { index in
                if metadata.indices.contains(index) {
                    return metadata[index]
                }
                let inheritedLevel = metadata.last?.level
                    ?? rowMetadata.last?.level
                    ?? 7
                // 缺行代表结构事务中新建Node，必须有新UUID并继承邻近层级；
                // `.empty`会把无前缀文本永久写成第7级正文。
                return .fresh(level: inheritedLevel)
            }
        }

        private func plainTextLineCount(_ value: String) -> Int {
            max(1, value.split(separator: "\n", omittingEmptySubsequences: false).count)
        }

        private func consumeEditedRows(in textView: NSTextView, fallbackRow: Int?) -> Set<Int> {
            defer { pendingEdit = nil }
            guard let pendingEdit else {
                lastConsumedEditChangedStructure = false
                lastConsumedEditNetRowDelta = 0
                lastConsumedEditStartRow = nil
                lastConsumedEditNetCharacterDelta = 0
                lastConsumedDeletionImpact = .character
                return fallbackRow.map { [$0] } ?? []
            }

            let stringLength = textView.textStorage?.length ?? 0
            let safeStart = max(0, min(pendingEdit.affectedRange.location, stringLength))
            let replacementLength = max(0, pendingEdit.replacementLength)
            let safeEnd = max(
                safeStart,
                min(safeStart + max(0, replacementLength - 1), max(0, stringLength - 1))
            )

            let postStartRow = lineIndexForLocation(safeStart)
            let postEndRow = lineIndexForLocation(safeEnd)
            let netRowDelta = pendingEdit.insertedNewlineCount - pendingEdit.deletedNewlineCount
            lastConsumedEditChangedStructure = netRowDelta != 0
            lastConsumedEditNetRowDelta = netRowDelta
            lastConsumedEditNetCharacterDelta = replacementLength - pendingEdit.affectedRange.length
            lastConsumedDeletionImpact = pendingEdit.deletionImpact

            if netRowDelta == 0, pendingEdit.deletionImpact == .character {
                let editedRow = activeNodeTransaction?.rowIndex
                    ?? pendingEdit.preStartRowSnapshot
                    ?? postStartRow
                    ?? fallbackRow
                lastConsumedEditStartRow = editedRow
                return editedRow.map { [$0] } ?? []
            }

            let snapshotStartRow = pendingEdit.preStartRowSnapshot
            let snapshotEndRow: Int? = {
                guard let preEndRowSnapshot = pendingEdit.preEndRowSnapshot else { return nil }
                return max(0, preEndRowSnapshot + netRowDelta)
            }()

            var candidates: [Int] = []
            if let snapshotStartRow { candidates.append(snapshotStartRow) }
            if let snapshotEndRow { candidates.append(snapshotEndRow) }
            if let postStartRow { candidates.append(postStartRow) }
            if let postEndRow { candidates.append(postEndRow) }
            if let fallbackRow { candidates.append(fallbackRow) }

            guard let firstCandidate = candidates.first else { return [] }
            let resolvedStartRow = max(0, candidates.reduce(firstCandidate, min))
            lastConsumedEditStartRow = resolvedStartRow
            var resolvedEndRow = max(0, candidates.reduce(firstCandidate, max))

            let insertedNewlineExpansion = max(0, pendingEdit.insertedNewlineCount)
            resolvedEndRow = max(resolvedEndRow, resolvedStartRow + insertedNewlineExpansion)

            var rows = Set<Int>()
            if resolvedEndRow >= resolvedStartRow {
                for row in resolvedStartRow...resolvedEndRow {
                    rows.insert(row)
                }
            }
            return rows
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isProgrammaticUpdate else { return }
            if isMarkedTextCompositionActive(in: textView) {
                return
            }
            if CFAbsoluteTimeGetCurrent() < imeCommitSelectionGuardUntil {
                // 输入法确认后会在同一行内短暂搬动光标，只屏蔽这种抖动。
                // 真正跨行必须继续提交并刷新上一Node，否则第一次离行会看起来没有渲染。
                let guardedRow = currentRowIndex(in: textView)
                if guardedRow == lastSelectionRowIndex {
                    return
                }
            }
            releaseStructuralFocusAnchorForUserAction()
            if let activeRow = activeNodeTransaction?.rowIndex,
               lineIndexForLocation(textView.selectedRange().location) != activeRow {
                _ = finishActiveNodeTransaction(in: textView, commit: true)
            }
            let adjustedSelection = clampedSelectionRange(for: textView.selectedRange(), in: textView)
            if adjustedSelection != textView.selectedRange() {
                isProgrammaticUpdate = true
                textView.setSelectedRange(adjustedSelection)
                isProgrammaticUpdate = false
            }
            if textView.window?.firstResponder === textView {
                beginEditingSession(in: textView)
            }
            updateTypingAttributes(for: textView)
            let rowIndex = currentRowIndex(in: textView)
            if rowIndex == nil {
                commitEditedRowsToRenderedState(on: textView)
            }
            if rowIndex == lastSelectionRowIndex, textView.window?.firstResponder === textView {
                enterRowSourceMode(on: textView, row: rowIndex)
            }
            if rowIndex != lastSelectionRowIndex {
                #if DEBUG
                if Self.isRenderSmokeEnabled {
                    NodeMarkdownRenderSmokeRecorder.shared.recordScenario(.selectionRowSwitch)
                }
                #endif
                let previous = lastSelectionRowIndex
                lastSelectionRowIndex = rowIndex
                if isInActiveEditingSession, let rowIndex {
                    enterRowSourceMode(on: textView, row: rowIndex)
                } else {
                    var targetRows = rowsAround(rowIndex)
                    targetRows.formUnion(rowsAround(previous))
                    if !targetRows.isEmpty {
                        scheduleStyleRefresh(
                            on: textView,
                            request: .incremental(
                                rows: targetRows,
                                delay: 0.04,
                                editingRowMode: rowIndex.map { .row($0) } ?? .none
                            ),
                            source: .selectionChanged
                        )
                    }
                }
            }
            notifyActiveRowChange(rowIndex)
        }

        private func clampedSelectionRange(for range: NSRange, in textView: NSTextView) -> NSRange {
            guard let nsText = textView.textStorage?.mutableString else { return NSRange(location: 0, length: 0) }
            let textLength = nsText.length
            guard textLength > 0 else { return NSRange(location: 0, length: 0) }

            let start = max(0, min(range.location, textLength))
            let end = max(start, min(range.location + range.length, textLength))
            let clampedStart = max(start, editableBoundary(at: start, in: nsText))
            let clampedEnd = max(end, editableBoundary(at: end, in: nsText))
            let finalEnd = max(clampedStart, clampedEnd)
            return NSRange(location: clampedStart, length: finalEnd - clampedStart)
        }

        func clampedSelectionRangeForExternalUpdate(_ range: NSRange, in textView: NSTextView) -> NSRange {
            clampedSelectionRange(for: range, in: textView)
        }

        private func editableBoundary(at location: Int, in nsText: NSString) -> Int {
            guard nsText.length > 0 else { return 0 }
            let safeLocation = max(0, min(location, nsText.length))
            guard let row = lineIndexForLocation(safeLocation),
                  let range = effectiveRowRange(at: row) else { return safeLocation }
            return range.location
        }

        private func rowsAround(_ rowIndex: Int?) -> Set<Int> {
            guard let rowIndex else { return [] }
            var rows: Set<Int> = [rowIndex]
            if rowIndex > 0 { rows.insert(rowIndex - 1) }
            rows.insert(rowIndex + 1)
            return rows
        }

        private func visibleRowSet(in textView: NSTextView, maxRowIndex: Int, overscan: Int) -> Set<Int> {
            guard maxRowIndex >= 0 else { return [] }
            guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return [] }
            guard !rowCharacterRanges.isEmpty else { return [] }
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
            guard visibleGlyphRange.length > 0 else { return [] }
            let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
            let textLength = textView.textStorage?.length ?? 0
            guard textLength > 0 else { return [] }
            let startChar = max(0, min(visibleCharacterRange.location, textLength - 1))
            let endChar = max(startChar, min(visibleCharacterRange.location + max(0, visibleCharacterRange.length - 1), textLength - 1))
            guard let startRow = lineIndexForLocation(startChar) else { return [] }
            guard let endRow = lineIndexForLocation(endChar) else { return [] }
            let lower = max(0, min(startRow, endRow) - overscan)
            let upper = min(maxRowIndex, max(startRow, endRow) + overscan)
            guard lower <= upper else { return [] }
            return Set(lower...upper)
        }

        private func updateTypingAttributes(for textView: NSTextView) {
            guard let nsText = textView.textStorage?.mutableString else { return }
            guard nsText.length > 0 else { return }
            let selection = textView.selectedRange()
            let safeLocation = max(0, min(selection.location, nsText.length))
            textView.typingAttributes = typingAttributes(forLocation: safeLocation, in: textView)
        }

        private func typingAttributes(
            forLocation location: Int,
            excluding excludedRange: NSRange? = nil,
            in textView: NSTextView
        ) -> [NSAttributedString.Key: Any] {
            guard let nsText = textView.textStorage?.mutableString else { return [:] }
            guard nsText.length > 0 else {
                let line = LineLayout(range: NSRange(location: 0, length: 0), prefix: "", level: 7)
                let attributes = lineStyleAttributes(for: line, previousLine: nil, allowsInlineRender: false)
                return [
                    .font: attributes.font,
                    .foregroundColor: attributes.textColor,
                    .paragraphStyle: attributes.paragraph
                ]
            }

            let safeLocation = max(0, min(location, nsText.length))
            guard let rowIndex = lineIndexForLocation(safeLocation),
                  let lineRange = effectiveRowRange(at: rowIndex) else { return [:] }
            let prefix = ""
            let previousLine = previousLineLayout(before: lineRange, source: nsText)
            let level = rowMetadata.indices.contains(rowIndex) ? rowMetadata[rowIndex].level : 7
            let attributes = lineStyleAttributes(
                for: LineLayout(range: lineRange, prefix: prefix, level: level),
                previousLine: previousLine,
                allowsInlineRender: false,
                rowIndex: rowIndex,
                locksEditingParagraph: activeSourceModeRowIndex == rowIndex
            )

            return [
                .font: attributes.font,
                .foregroundColor: attributes.textColor,
                .paragraphStyle: attributes.paragraph
            ]
        }

        private func previousLineLayout(before lineRange: NSRange, source nsText: NSString) -> LineLayout? {
            guard lineRange.location > 0, nsText.length > 0 else { return nil }
            let previousAnchor = max(0, min(lineRange.location - 1, nsText.length - 1))
            let previousRange = nsText.lineRange(for: NSRange(location: previousAnchor, length: 0))
            guard previousRange.length > 0 else { return nil }
            let previousRowIndex = lineIndexForRange(previousRange)
            let previousLevel = rowMetadata.indices.contains(previousRowIndex) ? rowMetadata[previousRowIndex].level : 7
            return LineLayout(range: previousRange, prefix: "", level: previousLevel)
        }

        private func lineTextForStyleDetection(
            in lineRange: NSRange,
            excluding excludedRange: NSRange?,
            source nsText: NSString
        ) -> String {
            var lineText = nsText.substring(with: lineRange)
            guard let excludedRange else { return lineText }

            let intersection = NSIntersectionRange(lineRange, excludedRange)
            guard intersection.length > 0 else { return lineText }

            let localStart = max(0, intersection.location - lineRange.location)
            let localLength = min(intersection.length, max(0, (lineText as NSString).length - localStart))
            guard localLength > 0 else { return lineText }

            lineText = (lineText as NSString).replacingCharacters(
                in: NSRange(location: localStart, length: localLength),
                with: ""
            )
            return lineText
        }

        private func notifyActiveRowChange(_ rowIndex: Int?) {
            guard let onActiveRowChange else { return }
            guard !hasPublishedActiveRowIndex || lastPublishedActiveRowIndex != rowIndex else { return }
            hasPublishedActiveRowIndex = true
            lastPublishedActiveRowIndex = rowIndex
            DispatchQueue.main.async {
                onActiveRowChange(rowIndex)
            }
        }

        private func notifyInputSessionStateChange(_ isActive: Bool) {
            guard let onInputSessionStateChange else { return }
            DispatchQueue.main.async {
                onInputSessionStateChange(isActive)
            }
        }

        private func publishTextChange(_ value: String) {
            let metadata = rowMetadataSnapshot(forPlainText: value)
            if let onLegacyDocumentSnapshot {
                documentSnapshotRevision &+= 1
                let decodedLines = value
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map(String.init)
                let lines = decodedLines.isEmpty ? [""] : decodedLines
                let rows = lines.enumerated().map { index, content in
                    let identity = metadata[index]
                    return NodeMarkdownLegacyDocumentSnapshot.Row(
                        nodeID: identity.nodeID,
                        level: identity.level,
                        content: content,
                        sourceID: identity.sourceID,
                        sourceFile: identity.sourceFile
                    )
                }
                onLegacyDocumentSnapshot(
                    NodeMarkdownLegacyDocumentSnapshot(
                        sessionID: documentSnapshotSessionID,
                        revision: documentSnapshotRevision,
                        rows: rows
                    )
                )
            } else if let onTextChangeWithRowMetadata {
                onTextChangeWithRowMetadata(value, metadata)
            } else {
                text = value
                onTextChange?(value)
            }
        }

        private func rowMetadataSnapshot(forPlainText value: String) -> [NodeMarkdownTextKitRowMetadata] {
            let normalized = normalizedRowMetadata(rowMetadata, forPlainText: value)
            var seenIDs: Set<String> = []
            return normalized.map { metadata in
                let hasValidID = UUID(uuidString: metadata.nodeID) != nil
                guard hasValidID, seenIDs.insert(metadata.nodeID).inserted else {
                    // 同一份快照绝不允许两个Node共享身份。异常副本视为新Node，
                    // 且不继承H3母本来源，避免一份母本被两个本地包同时认领。
                    return .fresh(level: metadata.level)
                }
                return metadata
            }
        }

        func isMarkedTextCompositionActive(in textView: NSTextView) -> Bool {
            textView.hasMarkedText()
        }

        func shouldDeferExternalTextSync(in textView: NSTextView) -> Bool {
            guard textView.window?.firstResponder === textView else { return false }
            if isMarkedTextCompositionActive(in: textView) {
                return true
            }
            return editorLifecycleState == .editing
        }

        private func setSelectionIfNeeded(_ textView: NSTextView, range: NSRange) {
            if textView.selectedRange() != range {
                textView.setSelectedRange(range)
            }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard !isProgrammaticUpdate else { return true }
            if isMarkedTextCompositionActive(in: textView) {
                return true
            }
            releaseStructuralFocusAnchorForUserAction()
            let replacement = replacementString ?? ""
            guard let current = textView.textStorage?.mutableString else { return true }
            let deletionImpact: EditorDeletionImpact? = {
                guard replacement.isEmpty, affectedCharRange.length > 0 else { return nil }
                return EditorDeletionClassifier.classifyDeletion(
                    source: current,
                    affectedRange: affectedCharRange
                ) { _ in 0 }
            }()
            let deletesLineBreak: Bool = {
                guard affectedCharRange.length > 0,
                      let range = affectedCharRange.clamped(toLength: current.length),
                      range.length > 0 else { return false }
                let deleted = current.substring(with: range)
                return deleted.contains("\n") || deleted.contains("\r")
            }()
            let isStructuralEdit = replacement == "\n"
                || replacement == "\r"
                || deletesLineBreak
                || (deletionImpact != nil && deletionImpact != .character)
            if isStructuralEdit {
                _ = finishActiveNodeTransaction(in: textView, commit: true)
            }
            if affectedCharRange.length > 0,
               shouldBlockProtectedH3StructuralEdit(in: affectedCharRange, sourceText: current) {
                showProtectedH3SelectionDeleteAlert()
                return false
            }

            if (replacementString == "\n" || replacementString == "\r"), affectedCharRange.length == 0 {
                setSelectionIfNeeded(textView, range: NSRange(location: affectedCharRange.location, length: 0))
                return handleInsertNewline(in: textView)
            }
            if shouldInspectProtectedImageTokenEdit(
                in: current,
                affectedRange: affectedCharRange,
                replacement: replacement,
                deletionImpact: deletionImpact
            ), let imageTokenRange = protectedImageTokenEditRange(
                in: textView,
                affectedRange: affectedCharRange,
                replacement: replacement
            ) {
                registerPendingEdit(affectedRange: imageTokenRange, replacement: replacement, in: current)
                registerUndoSnapshot(for: textView)
                isProgrammaticUpdate = true
                textView.textStorage?.replaceCharacters(in: imageTokenRange, with: replacement)
                let cursor = imageTokenRange.location + (replacement as NSString).length
                setSelectionIfNeeded(textView, range: NSRange(location: cursor, length: 0))
                isProgrammaticUpdate = false
                textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
                return false
            }
            let safeLocation = max(0, min(affectedCharRange.location, current.length))
            let lineRange = current.lineRange(for: NSRange(location: safeLocation, length: 0))
            let prefix = ""
            let prefixBoundary = lineRange.location
            let editStart = affectedCharRange.location
            let editEnd = affectedCharRange.location + affectedCharRange.length
            let touchesPrefix = editStart < prefixBoundary && editEnd > lineRange.location
            if touchesPrefix {
                let shouldInsertAtBoundary = affectedCharRange.length == 0
                    && !replacement.isEmpty
                    && replacement != "\n"
                    && replacement != "\r"
                if shouldInsertAtBoundary {
                    let insertionRange = NSRange(location: prefixBoundary, length: 0)
                    registerPendingEdit(affectedRange: insertionRange, replacement: replacement, in: current)
                    registerUndoSnapshot(for: textView)
                    isProgrammaticUpdate = true
                    textView.textStorage?.replaceCharacters(in: insertionRange, with: replacement)
                    setSelectionIfNeeded(
                        textView,
                        range: NSRange(location: prefixBoundary + (replacement as NSString).length, length: 0)
                    )
                    isProgrammaticUpdate = false
                    textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
                } else {
                    setSelectionIfNeeded(textView, range: NSRange(location: prefixBoundary, length: 0))
                }
                return false
            }

            guard replacementString == "\n" || replacementString == "\r" else {
                if replacement.isEmpty,
                   affectedCharRange.length > 0,
                   deletionImpact != .character {
                    return handleStructuralDeletion(
                        in: textView,
                        affectedRange: affectedCharRange,
                        replacement: replacement,
                        sourceText: current
                    )
                }
                registerPendingEdit(affectedRange: affectedCharRange, replacement: replacement, in: current)
                return true
            }

            let insertion = "\n" + prefix
            registerPendingEdit(affectedRange: affectedCharRange, replacement: insertion, in: current)
            registerUndoSnapshot(for: textView)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: affectedCharRange, with: insertion)
            let cursor = affectedCharRange.location + insertion.count
            setSelectionIfNeeded(textView, range: NSRange(location: cursor, length: 0))
            isProgrammaticUpdate = false
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            return false
        }

        private func handleStructuralDeletion(
            in textView: NSTextView,
            affectedRange: NSRange,
            replacement: String,
            sourceText: NSString
        ) -> Bool {
            let safeRange = clampedRange(affectedRange, in: sourceText)
            guard safeRange.length > 0 else { return false }

            registerPendingEdit(affectedRange: safeRange, replacement: replacement, in: sourceText)
            if let projectedMetadata = pendingEdit?.projectedRowMetadata {
                let targetRow = pendingEdit?.preStartRowSnapshot
                    ?? lineIndexForLocation(safeRange.location)
                    ?? 0
                let rowStart = rowCharacterRanges.indices.contains(targetRow)
                    ? rowCharacterRanges[targetRow].location
                    : safeRange.location
                installStructuralFocusAnchor(
                    row: min(targetRow, max(0, projectedMetadata.count - 1)),
                    contentOffset: max(0, safeRange.location - rowStart),
                    projectedMetadata: projectedMetadata
                )
            }
            registerUndoSnapshot(for: textView)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: safeRange, with: replacement)
            rebuildRowCharacterRanges(from: textView)
            isProgrammaticUpdate = false
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            return false
        }

        private func clampedRange(_ range: NSRange, in sourceText: NSString) -> NSRange {
            let location = max(0, min(range.location, sourceText.length))
            let end = max(location, min(NSMaxRange(range), sourceText.length))
            return NSRange(location: location, length: end - location)
        }

        private func shouldInspectProtectedImageTokenEdit(
            in sourceText: NSString,
            affectedRange: NSRange,
            replacement: String,
            deletionImpact: EditorDeletionImpact?
        ) -> Bool {
            if deletionImpact == .line || deletionImpact == .structure || deletionImpact == .document {
                return true
            }
            if replacement.contains("\n") || replacement.contains("\r") {
                return true
            }
            guard sourceText.length > 0 else { return false }
            let safeLocation = max(0, min(affectedRange.location, sourceText.length))
            guard let row = lineIndexForLocation(safeLocation),
                  let lineRange = effectiveRowRange(at: row) else { return false }
            guard lineRange.length > 0 else { return false }
            let lineText = sourceText.substring(with: lineRange)
            return lineText.contains("![")
                || lineText.localizedCaseInsensitiveContains("<img")
                || lineText.contains("width=")
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                return handleInsertNewline(in: textView)
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                commitActiveDraftBeforeLeavingSourceMode(in: textView)
                // ESC的业务含义就是立即失焦。不能等待textDidEndEditing再异步
                // 通知父页面，否则随后点击“随堂”可能冻结到刚才的旧H3行。
                notifyActiveRowChange(nil)
                textView.window?.makeFirstResponder(nil)
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                return handleVerticalMove(in: textView, direction: -1)
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                return handleVerticalMove(in: textView, direction: 1)
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return handleTabCommand(in: textView, increaseLevel: true)
            }
            if commandSelector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:)) {
                return handleTabCommand(in: textView, increaseLevel: true)
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return handleTabCommand(in: textView, increaseLevel: false)
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                return handleDeleteBackward(in: textView)
            }
            return false
        }

        private func protectedImageTokenEditRange(
            in textView: NSTextView,
            affectedRange: NSRange,
            replacement: String
        ) -> NSRange? {
            let nsText = textView.string as NSString
            let textLength = nsText.length
            guard textLength > 0 else { return nil }

            var protectedRanges: [NSRange] = []

            let sourceProbeRange = protectedImageTokenSourceProbeRange(
                affectedRange: affectedRange,
                textLength: textLength,
                sourceText: nsText
            )
            if sourceProbeRange.length > 0 {
                let sourceProbeText = nsText.substring(with: sourceProbeRange)
                for token in NodeMarkdownImageResourceManager.parseImageTokens(in: sourceProbeText) {
                    let absoluteRange = NSRange(
                        location: sourceProbeRange.location + token.sourceRange.location,
                        length: token.sourceRange.length
                    )
                    if editRange(affectedRange, touchesTokenRange: absoluteRange) {
                        guard !imageWidthEditIsAllowed(
                            tokenSource: token.sourceText,
                            tokenRange: absoluteRange,
                            affectedRange: affectedRange,
                            replacement: replacement
                        ) else { continue }
                        protectedRanges.append(absoluteRange)
                    }
                }
            }

            guard let firstRange = protectedRanges.first else { return nil }
            let unionRange = protectedRanges.dropFirst().reduce(firstRange) { partialRange, nextRange in
                NSUnionRange(partialRange, nextRange)
            }
            return NSIntersectionRange(unionRange, NSRange(location: 0, length: textLength))
        }

        private func protectedImageTokenAttributeProbeRange(
            affectedRange: NSRange,
            textLength: Int
        ) -> NSRange {
            if affectedRange.length > 0 {
                let location = max(0, min(affectedRange.location, textLength))
                let end = max(location, min(NSMaxRange(affectedRange), textLength))
                return NSRange(location: location, length: end - location)
            }
            guard affectedRange.location < textLength else { return NSRange(location: 0, length: 0) }
            return NSRange(location: max(0, affectedRange.location), length: 1)
        }

        private func protectedImageTokenSourceProbeRange(
            affectedRange: NSRange,
            textLength: Int,
            sourceText: NSString
        ) -> NSRange {
            let safeLocation = max(0, min(affectedRange.location, textLength))
            let baseRange: NSRange
            if affectedRange.length > 0 {
                let location = max(0, min(affectedRange.location, textLength))
                let end = max(location, min(NSMaxRange(affectedRange), textLength))
                baseRange = NSRange(location: location, length: end - location)
            } else {
                baseRange = lineIndexForLocation(safeLocation)
                    .flatMap { effectiveRowRange(at: $0) }
                    ?? NSRange(location: safeLocation, length: 0)
            }
            if baseRange.length == 0 { return baseRange }
            return sourceText.lineRange(for: baseRange)
        }

        private func editRange(_ editRange: NSRange, touchesTokenRange tokenRange: NSRange) -> Bool {
            if editRange.length == 0 {
                return editRange.location > tokenRange.location && editRange.location < NSMaxRange(tokenRange)
            }
            return NSIntersectionRange(editRange, tokenRange).length > 0
        }

        private func imageWidthEditIsAllowed(
            tokenSource: String,
            tokenRange: NSRange,
            affectedRange: NSRange,
            replacement: String
        ) -> Bool {
            guard replacement.allSatisfy({ $0.isNumber }) || replacement.isEmpty else { return false }
            let nsToken = tokenSource as NSString
            let patterns = [
                #"width\s*=\s*[\"']?(\d+)"#,
                #"\{width\s*=\s*(\d+)\}"#
            ]
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let fullRange = NSRange(location: 0, length: nsToken.length)
                guard let match = regex.firstMatch(in: tokenSource, range: fullRange),
                      match.numberOfRanges > 1 else { continue }
                let widthRange = match.range(at: 1)
                guard widthRange.location != NSNotFound, widthRange.length > 0 else { continue }
                let absoluteWidthRange = NSRange(location: tokenRange.location + widthRange.location, length: widthRange.length)
                if affectedRange.length == 0 {
                    return affectedRange.location >= absoluteWidthRange.location
                        && affectedRange.location <= NSMaxRange(absoluteWidthRange)
                }
                return NSIntersectionRange(affectedRange, absoluteWidthRange).length == affectedRange.length
            }
            return false
        }

        private func handleInsertNewline(in textView: NSTextView) -> Bool {
            guard !isProgrammaticUpdate else { return false }
            if activeNodeTransaction != nil {
                _ = finishActiveNodeTransaction(in: textView, commit: true)
            }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let nsText = textView.string as NSString

            let safeLocation = max(0, min(selection.location, nsText.length))
            guard let sourceRowIndex = lineIndexForLocation(safeLocation)
                ?? lineIndexByScanningCurrentText(location: safeLocation, in: textView) else {
                return false
            }
            guard let lineRange = effectiveRowRange(at: sourceRowIndex) else { return false }
            let lineRaw = nsText.substring(with: lineRange)
            let hasTrailingNewline = lineRaw.hasSuffix("\n")
            let coreLength = max(0, lineRange.length - (hasTrailingNewline ? 1 : 0))
            let coreRange = NSRange(location: lineRange.location, length: coreLength)
            let lineCore = nsText.substring(with: coreRange)
            if rowMetadata.indices.contains(sourceRowIndex),
               NodeMarkdownLegacyStructurePolicy.insertsEmptyChildInsteadOfSplitting(
                   rowMetadata[sourceRowIndex]
               ) {
                return insertEmptyChildAfterProtectedH3(
                    sourceRowIndex: sourceRowIndex,
                    insertionLocation: lineRange.location + coreLength,
                    in: textView,
                    sourceText: nsText
                )
            }
            let prefix = ""
            let lineCoreNSString = lineCore as NSString
            let prefixLength = min((prefix as NSString).length, lineCoreNSString.length)
            let contentStart = lineRange.location + prefixLength
            let caretInLineCore = max(contentStart, min(safeLocation, lineRange.location + coreLength))
            let splitOffset = max(0, caretInLineCore - contentStart)
            let contentText = lineCoreNSString.substring(from: prefixLength)
            let contentNSString = contentText as NSString
            let left = contentNSString.substring(with: NSRange(location: 0, length: splitOffset))
            let right = contentNSString.substring(from: splitOffset)

            let currentLine = prefix + left
            let nextLine = prefix + right
            let replacement = currentLine + "\n" + nextLine

            registerPendingEdit(affectedRange: coreRange, replacement: replacement, in: nsText)
            let targetRowIndex = sourceRowIndex + 1
            if let projectedMetadata = pendingEdit?.projectedRowMetadata {
                installStructuralFocusAnchor(
                    row: targetRowIndex,
                    contentOffset: 0,
                    projectedMetadata: projectedMetadata
                )
            }
            registerUndoSnapshot(for: textView)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: coreRange, with: replacement)
            rebuildRowCharacterRanges(from: textView)
            isProgrammaticUpdate = false
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            return true
        }

        /// 受保护H3的回车是“建立子节点”，不是“拆分标题”。原H3正文、UUID和
        /// Source信息完全不动；新H4使用新UUID，焦点只进入新行。
        private func insertEmptyChildAfterProtectedH3(
            sourceRowIndex: Int,
            insertionLocation: Int,
            in textView: NSTextView,
            sourceText: NSString
        ) -> Bool {
            let replacementRange = NSRange(location: insertionLocation, length: 0)
            let replacement = "\n"

            registerPendingEdit(
                affectedRange: replacementRange,
                replacement: replacement,
                in: sourceText
            )
            let targetRowIndex = sourceRowIndex + 1
            if let projectedMetadata = pendingEdit?.projectedRowMetadata {
                installStructuralFocusAnchor(
                    row: targetRowIndex,
                    contentOffset: 0,
                    projectedMetadata: projectedMetadata
                )
            }
            registerUndoSnapshot(for: textView)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: replacementRange, with: replacement)
            rebuildRowCharacterRanges(from: textView)
            isProgrammaticUpdate = false
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            return true
        }

        private func handleVerticalMove(in textView: NSTextView, direction: Int) -> Bool {
            guard !isProgrammaticUpdate else { return false }
            let nsText = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0, nsText.length > 0 else { return false }

            let safeLocation = max(0, min(selection.location, nsText.length))
            guard let currentRow = lineIndexForLocation(safeLocation),
                  let currentLineRange = effectiveRowRange(at: currentRow) else { return false }
            let targetRow = currentRow + (direction < 0 ? -1 : 1)
            guard targetRow >= 0,
                  let targetLineRange = effectiveRowRange(at: targetRow) else { return true }
            let targetLineText = targetLineRange.length > 0 ? nsText.substring(with: targetLineRange) : ""
            let currentPrefix = ""
            let targetPrefix = ""
            let currentContentStart = currentLineRange.location + currentPrefix.count
            let currentOffsetInContent = max(0, safeLocation - currentContentStart)
            let targetRawContentLength = max(0, targetLineRange.length - targetPrefix.count)
            let targetContentLength = targetLineText.hasSuffix("\n")
                ? max(0, targetRawContentLength - 1)
                : targetRawContentLength
            let targetLocation = targetLineRange.location
                + targetPrefix.count
                + min(currentOffsetInContent, targetContentLength)

            setSelectionIfNeeded(textView, range: NSRange(location: targetLocation, length: 0))
            return true
        }

        private func handleTabCommand(in textView: NSTextView, increaseLevel: Bool) -> Bool {
            guard !isProgrammaticUpdate else { return false }
            if activeNodeTransaction != nil {
                _ = finishActiveNodeTransaction(in: textView, commit: true)
            }
            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return false }
            let selection = textView.selectedRange()
            if selection.length > 0 {
                return handleTabCommandForSelection(
                    in: textView,
                    increaseLevel: increaseLevel,
                    selection: selection,
                    sourceText: nsText
                )
            }

            let safeLocation = max(0, min(selection.location, nsText.length))
            guard let lineIndex = lineIndexForLocation(safeLocation),
                  let lineRange = effectiveRowRange(at: lineIndex) else { return false }

            if lineIndex >= 0, isProtectedH3Row(lineIndex) {
                if increaseLevel {
                    insertSiblingLine(level: 4, below: true, textView: textView, lineRange: lineRange)
                } else {
                    insertSiblingLine(level: 2, below: false, textView: textView, lineRange: lineRange)
                }
                return true
            }

            adjustCurrentLineLevel(increase: increaseLevel, textView: textView, lineRange: lineRange)
            return true
        }

        func handleTabCommandFromView(_ textView: NSTextView, increaseLevel: Bool) -> Bool {
            handleTabCommand(in: textView, increaseLevel: increaseLevel)
        }

        private func handleTabCommandForSelection(
            in textView: NSTextView,
            increaseLevel: Bool,
            selection: NSRange,
            sourceText: NSString
        ) -> Bool {
            let fullLineRange = sourceText.lineRange(for: selection)
            if fullLineRange.length <= 0 { return false }
            var changedRows: Set<Int> = []
            registerUndoSnapshot(for: textView)
            for index in rowCharacterRanges.indices {
                guard NSIntersectionRange(fullLineRange, rowCharacterRanges[index]).length > 0,
                      rowMetadata.indices.contains(index),
                      !isProtectedH3Row(index) else { continue }
                let currentLevel = rowMetadata[index].level
                let nextLevel = increaseLevel ? min(12, currentLevel + 1) : max(1, currentLevel - 1)
                rowMetadata[index] = rowMetadata[index].changingLevel(to: nextLevel)
                changedRows.insert(index)
            }
            let styleRows = rowsIncludingFollowingParagraph(for: changedRows)
            if !changedRows.isEmpty {
                noteDocumentMutation()
            }
            applyStyle(to: textView, targetRows: styleRows, source: .textChanged)
            discardEditingNodeDraft()
            publishTextChange(sourceText as String)
            return true
        }

        private func lineIndexForRange(_ range: NSRange) -> Int {
            if let index = lineIndexForLocation(range.location) {
                return index
            }
            let tailLocation = max(range.location, range.location + max(0, range.length - 1))
            if let index = lineIndexForLocation(tailLocation) {
                return index
            }
            return -1
        }

        private func lineIndexForLocation(_ location: Int) -> Int? {
            if let transaction = activeNodeTransaction {
                return transaction.rowIndex(
                    containing: location,
                    stableRanges: rowCharacterRanges
                )
            }
            return NodeMarkdownLegacyRowRangeIndex.rowIndex(
                containing: location,
                in: rowCharacterRanges,
                editedRow: nil,
                characterDelta: 0
            )
        }

        private func lineIndexByScanningCurrentText(location: Int, in textView: NSTextView) -> Int? {
            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return nil }
            let safeLocation = max(0, min(location, nsText.length))
            let prefixRange = NSRange(location: 0, length: safeLocation)
            let prefixText = nsText.substring(with: prefixRange)
            return prefixText.reduce(into: 0) { count, character in
                if character == "\n" { count += 1 }
            }
        }

        func currentRowIndex(in textView: NSTextView) -> Int? {
            let nsText = textView.string as NSString
            if nsText.length == 0 { return nil }
            let selection = textView.selectedRange()
            let safeLocation = max(0, min(selection.location, nsText.length))
            if let index = lineIndexForLocation(safeLocation) {
                return index
            }
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let fallback = lineIndexForRange(lineRange)
            if fallback >= 0 {
                return fallback
            }
            return lineIndexByScanningCurrentText(location: safeLocation, in: textView)
        }

        func requestInsertImage(at rowIndex: Int) -> String? {
            onRequestInsertImageAtRow?(rowIndex)
        }

        /// 图片粘贴属于当前Node的一次普通本行编辑。它不能走外部全文替换，
        /// 否则焦点、离行渲染登记和滚动视野会分别落在不同事务中。
        func applyPreparedImageText(
            _ updatedRowText: String,
            at rowIndex: Int,
            in textView: NSTextView
        ) {
            guard let rowRange = effectiveRowRange(at: rowIndex),
                  let storage = textView.textStorage else { return }
            let contentRange: NSRange = {
                guard rowRange.length > 0,
                      NSMaxRange(rowRange) <= storage.length else { return rowRange }
                let source = storage.mutableString
                let last = source.substring(with: NSRange(location: NSMaxRange(rowRange) - 1, length: 1))
                guard last == "\n" || last == "\r" else { return rowRange }
                return NSRange(location: rowRange.location, length: rowRange.length - 1)
            }()
            guard contentRange.location <= storage.length,
                  NSMaxRange(contentRange) <= storage.length else { return }

            let styledTextView = textView as? NodeMarkdownStyledTextView
            let scrollView = textView.enclosingScrollView
            let originalOrigin = scrollView?.contentView.bounds.origin
            styledTextView?.suppressesAutomaticSelectionScrolling = true

            registerUndoSnapshot(for: textView)
            beginEditingNodeDraftIfNeeded(row: rowIndex, in: textView)
            noteDocumentMutation()
            performPreservingVisibleOrigin(in: textView) {
                isProgrammaticUpdate = true
                storage.beginEditing()
                storage.replaceCharacters(in: contentRange, with: updatedRowText)
                storage.endEditing()
                rebuildRowCharacterRanges(from: textView)
                activeSourceModeRowIndex = rowIndex
                lastSelectionRowIndex = rowIndex
                markEditedRows([rowIndex])
                markRegexDirty(rows: [rowIndex])
                let endLocation = contentRange.location + (updatedRowText as NSString).length
                setSelectionIfNeeded(textView, range: NSRange(location: endLocation, length: 0))
                ensureEditingRowVisibleSourceAttributes(in: textView, editingRow: rowIndex)
                isProgrammaticUpdate = false
            }

            updateEditingNodeDraftContent(row: rowIndex, in: textView)
            publishTextChange(sourceTextPreservingAttachmentTokens(from: textView))
            updateTypingAttributes(for: textView)
            notifyActiveRowChange(rowIndex)
            preservePersistenceViewport(
                origin: originalOrigin,
                scrollView: scrollView,
                textView: styledTextView
            )
        }

        func requestDeleteNodePackage(at rowIndex: Int) {
            onRequestDeleteNodePackageAtRow?(rowIndex)
        }

        func requestCutNodePackage(at rowIndex: Int) {
            onRequestCutNodePackageAtRow?(rowIndex)
        }

        func requestPasteNodePackage(after rowIndex: Int) {
            onRequestPasteNodePackageAfterRow?(rowIndex)
        }

        func canPasteNodePackage() -> Bool {
            canPasteNodePackageHandler?() ?? false
        }

        func canMutateNodePackage(at rowIndex: Int) -> Bool {
            rowCharacterRanges.indices.contains(rowIndex)
        }

        func isProtectedH3PackageRoot(at rowIndex: Int) -> Bool {
            isProtectedH3Row(rowIndex)
        }

        func requestDeleteProtectedH3(at rowIndex: Int) {
            onRequestDeleteProtectedH3AtRow?(rowIndex)
        }

        func requestOpenDrawingBoard(at rowIndex: Int) {
            onRequestOpenDrawingBoardAtRow?(rowIndex)
        }

        private func isProtectedH3Row(_ rowIndex: Int) -> Bool {
            guard rowMetadata.indices.contains(rowIndex) else { return false }
            return rowMetadata[rowIndex].isProtectedH3
        }

        private func shouldBlockProtectedH3StructuralEdit(in affectedRange: NSRange, sourceText: NSString) -> Bool {
            guard affectedRange.length > 0, !rowCharacterRanges.isEmpty else { return false }
            for rowIndex in rowCharacterRanges.indices {
                guard isProtectedH3Row(rowIndex) else { continue }
                let lineRange = rowCharacterRanges[rowIndex]
                guard lineRange.location < sourceText.length else { continue }
                let rawLine = sourceText.substring(with: lineRange)
                let prefixLength = 0
                let prefixRange = NSRange(location: lineRange.location, length: min(prefixLength, lineRange.length))
                if NSIntersectionRange(affectedRange, prefixRange).length > 0 {
                    return true
                }

                if lineRange.location > 0 {
                    let leadingSeparator = NSRange(location: lineRange.location - 1, length: 1)
                    if sourceText.substring(with: leadingSeparator) == "\n",
                       NSIntersectionRange(affectedRange, leadingSeparator).length > 0 {
                        return true
                    }
                }

                if rawLine.hasSuffix("\n"), lineRange.length > 0 {
                    let trailingSeparator = NSRange(location: NSMaxRange(lineRange) - 1, length: 1)
                    if NSIntersectionRange(affectedRange, trailingSeparator).length > 0 {
                        return true
                    }
                }
            }
            return false
        }

        private func protectedH3PackageCharacterRange(at rowIndex: Int, sourceText: NSString) -> NSRange? {
            guard rowCharacterRanges.indices.contains(rowIndex) else { return nil }
            let startRange = rowCharacterRanges[rowIndex]
            let levels = lineLevels(in: sourceText)
            guard levels.indices.contains(rowIndex), levels[rowIndex] == 3 else { return nil }
            var endRowIndex = rowIndex
            var cursor = rowIndex + 1
            while cursor < rowCharacterRanges.count {
                guard levels.indices.contains(cursor) else { break }
                if levels[cursor] <= 3 {
                    break
                }
                endRowIndex = cursor
                cursor += 1
            }
            let endRange = rowCharacterRanges[endRowIndex]
            return NSRange(location: startRange.location, length: NSMaxRange(endRange) - startRange.location)
        }

        private func lineLevels(in sourceText: NSString) -> [Int] {
            _ = sourceText
            return rowCharacterRanges.indices.map { index in
                rowMetadata.indices.contains(index) ? rowMetadata[index].level : 7
            }
        }

        private func insertSiblingLine(level: Int, below: Bool, textView: NSTextView, lineRange: NSRange) {
            let nsText = textView.string as NSString
            let lineString = nsText.substring(with: lineRange)
            let hasTrailingNewline = lineString.hasSuffix("\n")
            let sourceRow = max(0, lineIndexForRange(lineRange))

            let insertionLocation: Int
            let insertionText: String
            if below {
                insertionLocation = lineRange.location + lineRange.length
                if hasTrailingNewline {
                    insertionText = "\n"
                } else {
                    insertionText = "\n"
                }
            } else {
                insertionLocation = lineRange.location
                insertionText = "\n"
            }

            registerUndoSnapshot(for: textView)
            let metadataIndex = min(rowMetadata.count, below ? sourceRow + 1 : sourceRow)
            discardEditingNodeDraft()
            rowMetadata.insert(.fresh(level: level), at: metadataIndex)
            noteDocumentMutation()
            installStructuralFocusAnchor(
                row: metadataIndex,
                contentOffset: 0,
                projectedMetadata: rowMetadata
            )
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: insertionText)
            rebuildRowCharacterRanges(from: textView)
            isProgrammaticUpdate = false
            let restoredLocation = consumeStructuralFocusAnchor(in: textView)
            renderRowsAffectedByLayout(rowsIncludingFollowingParagraph(for: [metadataIndex]), in: textView)
            revealStructuralFocusOnce(restoredLocation, in: textView)
            publishTextChange(sourceTextPreservingAttachmentTokens(from: textView))
            notifyActiveRowChange(metadataIndex)
        }

        private func adjustCurrentLineLevel(increase: Bool, textView: NSTextView, lineRange: NSRange) {
            let selection = textView.selectedRange()
            let rowIndex = lineIndexForRange(lineRange)
            guard rowIndex >= 0, rowMetadata.indices.contains(rowIndex) else { return }
            beginEditingNodeDraftIfNeeded(row: rowIndex, in: textView)
            updateEditingNodeDraftContent(row: rowIndex, in: textView)
            let currentLevel = rowMetadata[rowIndex].level
            let newLevel = increase ? min(12, currentLevel + 1) : max(1, currentLevel - 1)
            registerUndoSnapshot(for: textView)
            rowMetadata[rowIndex] = rowMetadata[rowIndex].changingLevel(to: newLevel)
            noteDocumentMutation()
            updateEditingNodeDraftLevel(row: rowIndex, level: newLevel)
            installStructuralFocusAnchor(
                row: rowIndex,
                contentOffset: max(0, selection.location - lineRange.location),
                projectedMetadata: rowMetadata
            )
            let styleRows = rowsIncludingFollowingParagraph(for: [rowIndex])
            activeSourceModeRowIndex = rowIndex
            applyStyle(to: textView, targetRows: styleRows, source: .textChanged)
            let restoredLocation = consumeStructuralFocusAnchor(in: textView)
            revealStructuralFocusOnce(restoredLocation, in: textView)
        }

        private func handleDeleteBackward(in textView: NSTextView) -> Bool {
            guard !isProgrammaticUpdate else { return false }
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return false }

            let safeLocation = max(0, min(selection.location, nsText.length))
            if safeLocation == 0 { return false }

            guard let resolvedCurrentLineIndex = lineIndexForLocation(safeLocation),
                  let currentLineRange = effectiveRowRange(at: resolvedCurrentLineIndex) else { return false }
            let currentLineStart = currentLineRange.location

            let currentLineTextRaw = currentLineRange.length > 0 ? nsText.substring(with: currentLineRange) : ""
            let currentLineText = currentLineTextRaw.hasSuffix("\n") ? String(currentLineTextRaw.dropLast()) : currentLineTextRaw
            let currentPrefix = ""
            let prefixBoundary = currentLineStart + currentPrefix.count

            guard safeLocation <= prefixBoundary else {
                return false
            }

            let currentLineIndex = resolvedCurrentLineIndex
            if currentLineIndex == 0 { return true }
            if currentLineIndex >= 0, isProtectedH3Row(currentLineIndex) {
                showProtectedH3Alert()
                return true
            }

            let previousAnchor = max(0, currentLineStart - 1)
            let previousLineRange = nsText.lineRange(for: NSRange(location: previousAnchor, length: 0))
            let previousLineTextRaw = nsText.substring(with: previousLineRange)
            let previousHasNewline = previousLineTextRaw.hasSuffix("\n")
            let previousLineText = previousHasNewline ? String(previousLineTextRaw.dropLast()) : previousLineTextRaw
            let previousPrefix = ""
            let previousContent = previousPrefix.isEmpty ? previousLineText : String(previousLineText.dropFirst(previousPrefix.count))

            let currentContent = currentPrefix.isEmpty ? currentLineText : String(currentLineText.dropFirst(currentPrefix.count))
            let mergedPreviousLineCore = previousPrefix + previousContent + currentContent
            let currentHasNewline = currentLineTextRaw.hasSuffix("\n")
            let mergedPreviousLineRaw = currentHasNewline ? mergedPreviousLineCore + "\n" : mergedPreviousLineCore

            let replaceStart = previousLineRange.location
            let replaceEnd = currentLineRange.location + currentLineRange.length
            let replaceRange = NSRange(location: replaceStart, length: max(0, replaceEnd - replaceStart))
            let previousContentLength = (previousContent as NSString).length
            registerPendingEdit(affectedRange: replaceRange, replacement: mergedPreviousLineRaw, in: nsText)
            if let projectedMetadata = pendingEdit?.projectedRowMetadata {
                installStructuralFocusAnchor(
                    row: currentLineIndex - 1,
                    contentOffset: previousContentLength,
                    projectedMetadata: projectedMetadata
                )
            }
            registerUndoSnapshot(for: textView)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: replaceRange, with: mergedPreviousLineRaw)
            rebuildRowCharacterRanges(from: textView)
            isProgrammaticUpdate = false
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
            return true
        }

        private func showProtectedH3Alert() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "母本H3包保护"
            alert.informativeText = "该H3节点关联母本（SourceID非空），不允许在行首通过Backspace合并删除。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }

        private func showProtectedH3SelectionDeleteAlert() {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "母本H3包保护"
            alert.informativeText = "当前选中删除包含完整母本H3包（SourceID和SourceFile非空），禁止删除。请使用右键“母本删除”。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }
}

private enum NodeMarkdownRenderSmokeScenario: String, CaseIterable {
    case typingSingleCharacter = "typing_single_character"
    case typingContinuous = "typing_continuous"
    case selectionRowSwitch = "selection_row_switch"
    case blurSingleTransactionCommit = "blur_single_transaction_commit"
    case imeMarkedComposition = "ime_marked_composition"
    case imeCommitAfterMarkedText = "ime_commit_after_marked_text"
    case staleRevisionDrop = "stale_revision_drop"
}

private final class NodeMarkdownRenderSmokeRecorder {
    static let shared = NodeMarkdownRenderSmokeRecorder()

    private var covered: Set<NodeMarkdownRenderSmokeScenario> = []

    private var isEnabled: Bool {
        #if DEBUG
        NodeMarkdownFeatureFlags.renderSmokeEnabled
        #else
        false
        #endif
    }

    func recordScenario(_ scenario: NodeMarkdownRenderSmokeScenario) {
        guard isEnabled else { return }
        covered.insert(scenario)
        reportIfNeeded()
    }

    func recordTrace(source: String, requestKind: String, droppedAsStale: Bool, droppedAsEditing: Bool) {
        guard isEnabled else { return }
        if droppedAsStale {
            covered.insert(.staleRevisionDrop)
        }
        if droppedAsEditing {
            covered.insert(.blurSingleTransactionCommit)
        }
        reportIfNeeded()
    }

    private func reportIfNeeded() {
        guard covered.count == NodeMarkdownRenderSmokeScenario.allCases.count else { return }
        let ordered = NodeMarkdownRenderSmokeScenario.allCases.filter { covered.contains($0) }.map(\.rawValue)
        print("[NodeMarkdown][Smoke] all scenarios covered: \(ordered.joined(separator: ","))")
    }
}

private final class NodeMarkdownStyledTextView: NSTextView, NSLayoutManagerDelegate {
    private struct BackgroundGradientCacheKey: Hashable {
        let level: Int
        let red: Int
        let green: Int
        let blue: Int
    }
    private static let renderContract = NodeMarkdownRenderContract.default
    private static let leadingPadding = renderContract.layout.leadingPadding
    private static let levelIndentStep = renderContract.layout.levelIndentStep
    private static let markerWidth = renderContract.layout.markerWidth
    private static let markerGap = renderContract.layout.markerGap
    private static let formulaRenderScale: CGFloat = 2
    static var formulaRenderScaleForAttachment: CGFloat { formulaRenderScale }
    private var backgroundGradientCache: [BackgroundGradientCacheKey: NSGradient] = [:]
    var suppressesAutomaticSelectionScrolling = false
    var onRequestInsertImage: (() -> Void)?
    var onRequestDeleteNodePackage: (() -> Void)?
    var onRequestCutNodePackage: (() -> Void)?
    var onRequestPasteNodePackage: (() -> Void)?
    var canPasteNodePackage: (() -> Bool)?
    var canCutNodePackage: (() -> Bool)?
    var canDeleteNodePackage: (() -> Bool)?
    var canDeleteProtectedH3: (() -> Bool)?
    var onRequestDeleteProtectedH3: (() -> Void)?
    var onHandleTabCommand: ((Bool) -> Bool)?
    var onRequestOpenDrawingBoard: (() -> Void)?
    var imageBaseDirectoryURL: URL?

    override func scrollRangeToVisible(_ range: NSRange) {
        guard !suppressesAutomaticSelectionScrolling else { return }
        super.scrollRangeToVisible(range)
    }

    /// 公式和图片的Markdown源码仍保留在NSTextStorage中，但渲染时是一个视觉单元。
    /// TextKit若从源码范围内部自动换行，绘制图和后续文字就会分别落到不同视觉行。
    /// 只允许在整个渲染单元之前或之后换行，禁止从内部拆开。
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByWordBeforeCharacterAt charIndex: Int
    ) -> Bool {
        !isInsideInlineRenderPayload(at: charIndex, layoutManager: layoutManager)
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int
    ) -> Bool {
        !isInsideInlineRenderPayload(at: charIndex, layoutManager: layoutManager)
    }

    private func isInsideInlineRenderPayload(
        at characterIndex: Int,
        layoutManager: NSLayoutManager
    ) -> Bool {
        guard characterIndex > 0,
              let storage = layoutManager.textStorage,
              characterIndex < storage.length else { return false }
        var payloadRange = NSRange(location: NSNotFound, length: 0)
        guard storage.attribute(
            nodeMarkdownInlineRenderPayloadKey,
            at: characterIndex,
            longestEffectiveRange: &payloadRange,
            in: NSRange(location: 0, length: storage.length)
        ) is NodeMarkdownInlineRenderPayload else {
            return false
        }
        return characterIndex > payloadRange.location
            && characterIndex < NSMaxRange(payloadRange)
    }

    private var nodeDocumentStyleIdentity = NodeMarkdownDocumentStyle().renderIdentity
    var nodeDocumentStyle = NodeMarkdownDocumentStyle() {
        didSet {
            let identity = nodeDocumentStyle.renderIdentity
            if nodeDocumentStyleIdentity != identity {
                nodeDocumentStyleIdentity = identity
                backgroundGradientCache.removeAll(keepingCapacity: true)
                needsDisplay = true
            }
        }
    }
    var rowCharacterRanges: [NSRange] = [] {
        didSet {
            if oldValue.count != rowCharacterRanges.count {
                needsDisplay = true
            }
        }
    }
    /// Marked text is temporary. A single logical suffix delta keeps row lookup local while
    /// pinyin candidates change, instead of rebuilding every row range for every IME frame.
    var transientEditedRowIndex: Int?
    var transientCharacterDelta = 0
    var nodeRowLevels: [Int] = [] {
        didSet {
            if oldValue != nodeRowLevels { needsDisplay = true }
        }
    }
    private var isPerformanceProfilingEnabled: Bool {
        #if DEBUG
        NodeMarkdownFeatureFlags.performanceProfilingEnabled
        #else
        false
        #endif
    }

    /// marked text会先改变当前行的排版高度，然后才由AppKit补做下游布局。
    /// 编号和背景条是自绘内容，必须在读取几何坐标前确保可见区已完成布局。
    /// 这里只重画可见装饰，不改文字属性，也不扫描文档其他部分。
    func refreshDecorationsAfterMarkedTextMutation() {
        let redrawRect = visibleRect.insetBy(dx: -24, dy: -32)
        guard let layoutManager, let textContainer else {
            setNeedsDisplay(redrawRect)
            return
        }
        let containerOrigin = textContainerOrigin
        let layoutRect = redrawRect.offsetBy(
            dx: -containerOrigin.x,
            dy: -containerOrigin.y
        )
        layoutManager.ensureLayout(forBoundingRect: layoutRect, in: textContainer)
        setNeedsDisplay(redrawRect)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return NodeMarkdownContextMenuController.makeMenu(
            target: self,
            context: .init(
                canCutPackage: canCutNodePackage?() ?? false,
                canDeletePackage: canDeleteNodePackage?() ?? false,
                canPastePackage: canPasteNodePackage?() ?? false,
                canMotherDelete: canDeleteProtectedH3?() ?? false
            )
        )
    }

    @objc func handleCutPackageMenuAction() {
        onRequestCutNodePackage?()
    }

    @objc func handlePastePackageMenuAction() {
        onRequestPasteNodePackage?()
    }

    @objc func handleDeleteNodePackageMenuAction() {
        onRequestDeleteNodePackage?()
    }

    @objc private func handleInsertImageMenuAction() {
        onRequestInsertImage?()
    }

    @objc private func handleDeleteProtectedH3MenuAction() {
        onRequestDeleteProtectedH3?()
    }

    @objc private func handleOpenDrawingBoardMenuAction() {
        onRequestOpenDrawingBoard?()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawNodeDecorations(in: visibleRect.insetBy(dx: 0, dy: -6))
        drawMarkdownHighlights(in: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawInlineRenderPayloads(in: dirtyRect)
        drawLockedPrefixSelectionMask(in: dirtyRect)
        drawNodeUnderlines(in: dirtyRect)
    }

    /// 公式和图片在透明源码占据的真实字符范围上绘制。这里只读布局结果，
    /// 不修改正文、不触发重排，因此滚动多少次都不会改变任何Markdown字符。
    private func drawInlineRenderPayloads(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else { return }

        let containerOrigin = textContainerOrigin
        let layoutRect = dirtyRect.offsetBy(dx: -containerOrigin.x, dy: -containerOrigin.y)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: layoutRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharacterRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange,
            actualGlyphRange: nil
        )

        var drawnRanges: Set<NSRange> = []
        storage.enumerateAttribute(
            nodeMarkdownInlineRenderPayloadKey,
            in: visibleCharacterRange,
            options: []
        ) { value, characterRange, _ in
            guard let payload = value as? NodeMarkdownInlineRenderPayload,
                  characterRange.length > 0 else { return }
            var payloadRange = NSRange(location: 0, length: 0)
            guard storage.attribute(
                nodeMarkdownInlineRenderPayloadKey,
                at: characterRange.location,
                longestEffectiveRange: &payloadRange,
                in: NSRange(location: 0, length: storage.length)
            ) is NodeMarkdownInlineRenderPayload,
            payloadRange.length > 0,
            drawnRanges.insert(payloadRange).inserted else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: payloadRange,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0 else { return }
            let visualRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            guard !visualRect.isEmpty else { return }

            let firstGlyph = glyphRange.location
            var lineFragmentRange = NSRange(location: NSNotFound, length: 0)
            var lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: firstGlyph,
                effectiveRange: &lineFragmentRange
            )
            var lineUsedRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: firstGlyph,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            if lineFragmentRect.isEmpty {
                lineFragmentRect = visualRect
            }
            if lineUsedRect.isEmpty {
                lineUsedRect = lineFragmentRect
            }
            // location(forGlyphAt:)是所属视觉行内部的坐标。公式靠近自动换行
            // 边界时，整段透明源码的boundingRect可能横跨多行，不能作为起点。
            let firstGlyphLocation = layoutManager.location(forGlyphAt: firstGlyph)
            let verticalCenter = payload.centersOnLineAxis
                ? lineFragmentRect.midY
                : lineUsedRect.midY
            let drawRect = NSRect(
                x: containerOrigin.x
                    + lineFragmentRect.minX
                    + firstGlyphLocation.x
                    + payload.horizontalInset,
                y: containerOrigin.y + verticalCenter - payload.size.height * 0.5,
                width: payload.size.width,
                height: payload.size.height
            )
            guard drawRect.intersects(dirtyRect) else { return }
            payload.image.draw(
                in: drawRect,
                from: NSRect(origin: .zero, size: payload.image.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }

    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    ) -> NSRange {
        let range = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard granularity == .selectByParagraph else { return range }
        return rangeExcludingTrailingLineBreak(range)
    }

    private func rangeExcludingTrailingLineBreak(_ range: NSRange) -> NSRange {
        let nsText = string as NSString
        guard range.length > 0, NSMaxRange(range) <= nsText.length else { return range }
        let lastCharacterRange = NSRange(location: NSMaxRange(range) - 1, length: 1)
        let lastCharacter = nsText.substring(with: lastCharacterRange)
        guard lastCharacter == "\n" || lastCharacter == "\r" else { return range }
        return NSRange(location: range.location, length: range.length - 1)
    }

    override func mouseDown(with event: NSEvent) {
        guard shouldRedirectEventFromLockedPrefix(event) else {
            super.mouseDown(with: event)
            return
        }
        redirectInsertionToEditableContent(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard shouldRedirectEventFromLockedPrefix(event) else {
            super.mouseDragged(with: event)
            return
        }
        redirectInsertionToEditableContent(for: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard shouldRedirectEventFromLockedPrefix(event) else {
            super.rightMouseDown(with: event)
            return
        }
        redirectInsertionToEditableContent(for: event)
        super.rightMouseDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if NodeMarkdownImageAssetService.hasPastedImage() {
            onRequestInsertImage?()
            return
        }
        super.paste(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleImagePasteShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleImagePasteShortcut(event) {
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommandLikeModifier = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        if event.keyCode == 6,
           flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option) {
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return
        }
        if event.keyCode == 48 && !hasCommandLikeModifier {
            if flags.contains(.shift) {
                doCommand(by: #selector(NSResponder.insertBacktab(_:)))
            } else {
                doCommand(by: #selector(NSResponder.insertTab(_:)))
            }
            return
        }
        super.keyDown(with: event)
    }

    /// macOS可能在`paste(_:)`之前由菜单系统消费Command+V。只拦截纯Command+V
    /// 且剪贴板确实含图片的情况，普通文本继续交给NSTextView。
    private func handleImagePasteShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command),
              !flags.contains(.shift),
              !flags.contains(.option),
              !flags.contains(.control),
              event.charactersIgnoringModifiers?.lowercased() == "v",
              NodeMarkdownImageAssetService.hasPastedImage() else {
            return false
        }
        onRequestInsertImage?()
        return true
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        let redrawRect = visibleRect.insetBy(dx: -24, dy: -32)
        let compositionRow = transientEditedRowIndex ?? currentRowIndexForSelection()
        let stableTextLength = rowCharacterRanges.last.map(NSMaxRange) ?? 0
        let currentTextLength = textStorage?.length ?? (self.string as NSString).length
        let existingMarkedRange = markedRange()
        let actualReplacementRange: NSRange = {
            if replacementRange.location != NSNotFound {
                return replacementRange
            }
            if existingMarkedRange.location != NSNotFound {
                return existingMarkedRange
            }
            return self.selectedRange()
        }()
        let safeReplacementLength: Int = {
            guard actualReplacementRange.location != NSNotFound,
                  actualReplacementRange.location <= currentTextLength else {
                return 0
            }
            return min(actualReplacementRange.length, currentTextLength - actualReplacementRange.location)
        }()
        let incomingLength: Int
        if let attributed = string as? NSAttributedString {
            incomingLength = attributed.length
        } else if let plain = string as? String {
            incomingLength = (plain as NSString).length
        } else {
            incomingLength = (String(describing: string) as NSString).length
        }

        // AppKit can draw synchronously inside super.setMarkedText. Publish the row shift
        // before that call, otherwise one frame resolves the following row against stale
        // UTF-16 coordinates and paints its marker/style on the composing row.
        transientEditedRowIndex = compositionRow
        transientCharacterDelta = currentTextLength - safeReplacementLength
            + incomingLength - stableTextLength
        setNeedsDisplay(redrawRect)
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        // Correct the prediction with AppKit's final storage length. Stable row ranges remain
        // untouched until the candidate is committed.
        transientCharacterDelta = (textStorage?.length ?? stableTextLength) - stableTextLength
        refreshDecorationsAfterMarkedTextMutation()
    }

    override func unmarkText() {
        super.unmarkText()
        refreshDecorationsAfterMarkedTextMutation()
    }

    override func insertTab(_ sender: Any?) {
        if dispatchTabCommand(increaseLevel: true) {
            return
        }
        super.insertTab(sender)
        TeachingDebugLogStore.append(
            "tab fallback to system insertTab: delegate did not handle",
            category: "NodeMarkdown.TabKey"
        )
    }

    override func insertBacktab(_ sender: Any?) {
        if dispatchTabCommand(increaseLevel: false) {
            return
        }
        super.insertBacktab(sender)
        TeachingDebugLogStore.append(
            "backtab fallback to system insertBacktab: delegate did not handle",
            category: "NodeMarkdown.TabKey"
        )
    }

    override func insertTabIgnoringFieldEditor(_ sender: Any?) {
        if dispatchTabCommand(increaseLevel: true) {
            return
        }
        super.insertTabIgnoringFieldEditor(sender)
        TeachingDebugLogStore.append(
            "tabIgnoringFieldEditor fallback to system handler: delegate did not handle",
            category: "NodeMarkdown.TabKey"
        )
    }

    private func dispatchTabCommand(increaseLevel: Bool) -> Bool {
        if onHandleTabCommand?(increaseLevel) == true {
            return true
        }
        guard let delegate else { return false }
        let selector = increaseLevel ? #selector(NSResponder.insertTab(_:)) : #selector(NSResponder.insertBacktab(_:))
        return delegate.textView?(self, doCommandBy: selector) == true
    }

    private func currentRowIndexForSelection() -> Int? {
        let selected = selectedRange()
        let location = max(0, min(selected.location, (string as NSString).length))
        return rowIndex(containing: location, in: rowCharacterRanges)
    }

    private func isCurrentRowH3Node() -> Bool {
        let nsText = string as NSString
        if nsText.length == 0 { return false }
        let selected = selectedRange()
        let safeLocation = max(0, min(selected.location, nsText.length))
        guard let row = rowIndex(containing: safeLocation, in: rowCharacterRanges),
              nodeRowLevels.indices.contains(row) else { return false }
        return nodeRowLevels[row] == 3
    }

    override func copy(_ sender: Any?) {
        let selected = selectedRange()
        guard selected.length > 0 else {
            super.copy(sender)
            return
        }
        guard let clipped = clippedPlainTextForSelection(selected), !clipped.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(clipped, forType: .string)
    }

    private func shouldRedirectEventFromLockedPrefix(_ event: NSEvent) -> Bool {
        let localPoint = convert(event.locationInWindow, from: nil)
        return localPoint.x < lockedPrefixBoundaryX
    }

    private var lockedPrefixBoundaryX: CGFloat {
        textContainerOrigin.x + Self.leadingPadding + Self.markerWidth + Self.markerGap
    }

    private func redirectInsertionToEditableContent(for event: NSEvent) {
        guard let layoutManager, let textContainer else { return }
        let localPoint = convert(event.locationInWindow, from: nil)
        let clampedPoint = NSPoint(x: lockedPrefixBoundaryX + 1, y: localPoint.y)
        let glyphIndex = layoutManager.glyphIndex(for: clampedPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let safeLocation = max(0, min(characterIndex, (string as NSString).length))
        setSelectedRange(NSRange(location: safeLocation, length: 0))
    }

    private func drawLockedPrefixSelectionMask(in dirtyRect: NSRect) {
        let lockRect = NSRect(
            x: 0,
            y: dirtyRect.minY,
            width: max(0, lockedPrefixBoundaryX),
            height: dirtyRect.height
        )
        guard !lockRect.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.setFillColor(NSColor.black.cgColor)
        context.fill(lockRect)
        context.restoreGState()
    }

    private func clippedPlainTextForSelection(_ range: NSRange) -> String? {
        let content = string as NSString
        let cappedRange = NSRange(
            location: max(0, min(range.location, content.length)),
            length: max(0, min(range.length, content.length - max(0, min(range.location, content.length))))
        )
        guard cappedRange.length > 0 else { return nil }

        var chunks: [String] = []
        var lineLocation = content.lineRange(for: NSRange(location: cappedRange.location, length: 0)).location
        let selectionEnd = NSMaxRange(cappedRange)

        while lineLocation < content.length, lineLocation < selectionEnd {
            let lineRange = content.lineRange(for: NSRange(location: lineLocation, length: 0))
            lineLocation = NSMaxRange(lineRange)

            let segmentLocation = max(cappedRange.location, lineRange.location)
            let segmentEnd = min(selectionEnd, NSMaxRange(lineRange))
            guard segmentEnd > segmentLocation else { continue }

            let boundary = editableBoundary(inLineRange: lineRange, content: content)
            let clippedStart = max(segmentLocation, boundary)
            guard segmentEnd > clippedStart else { continue }

            let chunkRange = NSRange(location: clippedStart, length: segmentEnd - clippedStart)
            chunks.append(plainTextPreservingAttachmentTokens(in: chunkRange))
        }
        return chunks.joined()
    }

    private func plainTextPreservingAttachmentTokens(in range: NSRange) -> String {
        guard let storage = textStorage else {
            return (string as NSString).substring(with: range)
        }
        let nsText = storage.mutableString
        let textLength = nsText.length
        let safeLocation = max(0, min(range.location, textLength))
        let safeEnd = max(safeLocation, min(NSMaxRange(range), textLength))
        guard safeEnd > safeLocation else { return "" }

        return nsText.substring(with: NSRange(location: safeLocation, length: safeEnd - safeLocation))
    }

    private func editableBoundary(inLineRange lineRange: NSRange, content: NSString) -> Int {
        _ = content
        return lineRange.location
    }

    private func level(for lineRange: NSRange, rowRanges: [NSRange]? = nil) -> Int {
        let ranges = rowRanges ?? rowCharacterRanges
        guard let rowIndex = rowIndex(containing: lineRange.location, in: ranges),
              nodeRowLevels.indices.contains(rowIndex) else { return 7 }
        return max(1, min(12, nodeRowLevels[rowIndex]))
    }

    private func rowIndex(containing location: Int, in ranges: [NSRange]) -> Int? {
        NodeMarkdownLegacyRowRangeIndex.rowIndex(
            containing: location,
            in: ranges,
            editedRow: transientEditedRowIndex,
            characterDelta: transientCharacterDelta
        )
    }

    /// marked text changes the backing string before the delegate can publish new row ranges.
    /// Custom decorations must never resolve levels against coordinates from the previous IME frame.
    private func decorationRowRanges(for content: NSString) -> [NSRange] {
        guard content.length > 0 else { return [] }
        return rowCharacterRanges
    }

    private func drawMarkdownHighlights(in paintRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else { return }

        let expandedPaintRect = paintRect.insetBy(dx: -8, dy: -8)
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: expandedPaintRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        let containerOrigin = textContainerOrigin
        storage.enumerateAttribute(
            nodeMarkdownHighlightBackgroundColorKey,
            in: visibleCharacterRange,
            options: []
        ) { value, characterRange, _ in
            guard let color = value as? NSColor, characterRange.length > 0 else { return }
            let highlightGlyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard highlightGlyphRange.length > 0 else { return }

            layoutManager.enumerateLineFragments(forGlyphRange: highlightGlyphRange) { lineFragmentRect, _, lineTextContainer, lineGlyphRange, _ in
                let clippedGlyphRange = NSIntersectionRange(highlightGlyphRange, lineGlyphRange)
                guard clippedGlyphRange.length > 0 else { return }

                guard let highlightRect = self.inlineHighlightRect(
                    characterRange: characterRange,
                    glyphRange: clippedGlyphRange,
                    lineFragmentRect: lineFragmentRect,
                    textContainer: lineTextContainer,
                    containerOrigin: containerOrigin
                ) else { return }

                color.setFill()
                let radius = min(8, highlightRect.height * 0.28)
                NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius).fill()
            }
        }
    }

    private func inlineHighlightRect(
        characterRange: NSRange,
        glyphRange: NSRange,
        lineFragmentRect: NSRect,
        textContainer: NSTextContainer,
        containerOrigin: NSPoint
    ) -> NSRect? {
        guard let layoutManager,
              let storage = textStorage,
              characterRange.location < storage.length else { return nil }

        let visualRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard !visualRect.isEmpty else { return nil }

        let glyphCharacterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let visibleCharacterRange = NSIntersectionRange(characterRange, glyphCharacterRange)
        let renderedContentHeight = inlineHighlightHeight(in: visibleCharacterRange, storage: storage)
        let horizontalPadding = Self.renderContract.layout.backgroundHorizontalPadding * 0.5
        let verticalPadding = Self.renderContract.layout.backgroundVerticalPadding * 0.5
        let fallbackHeight = max(1, lineFragmentRect.height * 0.72)
        let contentHeight = renderedContentHeight > 0 ? renderedContentHeight : fallbackHeight
        let highlightHeight = min(
            max(contentHeight + verticalPadding * 2, fallbackHeight),
            max(lineFragmentRect.height, contentHeight) + verticalPadding * 2
        )
        let contentRect = visualRect

        return NSRect(
            x: containerOrigin.x + contentRect.minX - horizontalPadding,
            y: containerOrigin.y + contentRect.midY - highlightHeight * 0.5,
            width: max(1, contentRect.width) + horizontalPadding * 2,
            height: highlightHeight
        )
    }

    private func inlineHighlightHeight(in range: NSRange, storage: NSTextStorage) -> CGFloat {
        guard range.length > 0 else { return 0 }
        var height: CGFloat = 0
        storage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            if let payload = attributes[nodeMarkdownInlineRenderPayloadKey] as? NodeMarkdownInlineRenderPayload {
                height = max(height, payload.size.height)
            }
            if let font = attributes[.font] as? NSFont, font.pointSize > 0.5 {
                height = max(height, ceil(font.ascender - font.descender))
            }
        }
        return height
    }

    private func drawNodeDecorations(in paintRect: NSRect) {
        guard let layoutManager,
              let textContainer else { return }

        let content = string as NSString
        guard content.length > 0 else { return }
        let decorationRanges = decorationRowRanges(for: content)

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: paintRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        var lineLocation = content.lineRange(for: NSRange(location: visibleCharacterRange.location, length: 0)).location
        let visibleEnd = NSMaxRange(visibleCharacterRange)
        let containerOrigin = textContainerOrigin
        let trailingEdge = bounds.width - textContainerInset.width
        while lineLocation < content.length, lineLocation < visibleEnd {
            let lineRange = content.lineRange(for: NSRange(location: lineLocation, length: 0))
            lineLocation = NSMaxRange(lineRange)

            let level = level(for: lineRange, rowRanges: decorationRanges)
            let roleStyle = nodeDocumentStyle.style(forLevel: level)
            let prefixLength = 0
            let safeCharacter = min(lineRange.location, max(0, content.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeCharacter)

            var lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            if lineFragmentRect.isEmpty {
                lineFragmentRect = layoutManager.lineFragmentUsedRect(
                    forGlyphAt: glyphIndex,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
            }
            if lineFragmentRect.isEmpty { continue }
            let firstTextRect = firstVisibleTextRect(
                lineRange: lineRange,
                prefixLength: prefixLength,
                fallback: lineFragmentRect
            )
            var usesMeasuredInlineAxis = false
            if let storage = textStorage {
                storage.enumerateAttribute(
                    nodeMarkdownInlineRenderPayloadKey,
                    in: NSIntersectionRange(
                        lineRange,
                        NSRange(location: 0, length: storage.length)
                    ),
                    options: []
                ) { value, _, stop in
                    if let payload = value as? NodeMarkdownInlineRenderPayload,
                       payload.centersOnLineAxis {
                        usesMeasuredInlineAxis = true
                        stop.pointee = true
                    }
                }
            }

            let markerX = containerOrigin.x
                + Self.leadingPadding
                + CGFloat(max(0, level - 1)) * Self.levelIndentStep
            if markerX >= trailingEdge { continue }

            if roleStyle.hasBackgroundBar {
                let textFont = NSFont(name: roleStyle.fontName, size: roleStyle.fontSize)
                    ?? NSFont.monospacedSystemFont(ofSize: roleStyle.fontSize, weight: .regular)
                let textHeight = max(1, ceil(textFont.ascender - textFont.descender))
                let visualRange = lineContentRangeExcludingTerminator(lineRange, in: content)
                let glyphRange = layoutManager.glyphRange(forCharacterRange: visualRange, actualCharacterRange: nil)
                var lineUsedRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                if lineUsedRect.isEmpty {
                    lineUsedRect = lineFragmentRect
                }
                let barHeight = max(textHeight, lineUsedRect.height)
                let barY = containerOrigin.y + lineUsedRect.midY - barHeight * 0.5
                let drawRect = NSRect(
                    x: markerX,
                    y: barY,
                    width: trailingEdge - markerX,
                    height: barHeight
                )
                if drawRect.intersects(paintRect) {
                    let base = NSColor(roleStyle.renderedColor).usingColorSpace(.deviceRGB) ?? NSColor(roleStyle.renderedColor)
                    let radii = NodeMarkdownRenderContract.backgroundBarCornerRadii(
                        fontSize: textFont.pointSize,
                        barHeight: drawRect.height
                    )
                    let path = NSBezierPath(
                        roundedRect: drawRect,
                        xRadius: radii.width,
                        yRadius: radii.height
                    )
                    NSGraphicsContext.saveGraphicsState()
                    cachedGradient(level: level, baseColor: base).draw(in: path, angle: 0)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }

            drawLevelMarker(
                level: level,
                textColor: NSColor(roleStyle.renderedColor),
                markerX: markerX,
                textRect: usesMeasuredInlineAxis ? lineFragmentRect : firstTextRect,
                containerOrigin: containerOrigin
            )
        }
        drawTerminalEmptyNodeDecorationIfNeeded(
            in: paintRect,
            content: content,
            trailingEdge: trailingEdge,
            containerOrigin: containerOrigin
        )
    }

    private func lineContentRangeExcludingTerminator(_ lineRange: NSRange, in content: NSString) -> NSRange {
        var end = min(NSMaxRange(lineRange), content.length)
        let start = min(lineRange.location, end)
        while end > start {
            let character = content.substring(with: NSRange(location: end - 1, length: 1))
            guard character == "\n" || character == "\r" else { break }
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private func drawTerminalEmptyNodeDecorationIfNeeded(
        in paintRect: NSRect,
        content: NSString,
        trailingEdge: CGFloat,
        containerOrigin: NSPoint
    ) {
        guard let layoutManager,
              let lastRow = rowCharacterRanges.indices.last,
              let range = NodeMarkdownLegacyRowRangeIndex.effectiveRange(
                at: lastRow,
                in: rowCharacterRanges,
                editedRow: transientEditedRowIndex,
                characterDelta: transientCharacterDelta
              ),
              range.location == content.length,
              range.length == 0,
              nodeRowLevels.indices.contains(lastRow) else { return }

        var fragmentRect = layoutManager.extraLineFragmentUsedRect
        if fragmentRect.isEmpty {
            fragmentRect = layoutManager.extraLineFragmentRect
        }
        guard !fragmentRect.isEmpty else { return }
        let visibleRect = fragmentRect.offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
        guard visibleRect.intersects(paintRect) else { return }

        let level = max(1, min(12, nodeRowLevels[lastRow]))
        let roleStyle = nodeDocumentStyle.style(forLevel: level)
        let markerX = containerOrigin.x
            + Self.leadingPadding
            + CGFloat(max(0, level - 1)) * Self.levelIndentStep
        guard markerX < trailingEdge else { return }

        if roleStyle.hasBackgroundBar {
            let font = NSFont(name: roleStyle.fontName, size: roleStyle.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: roleStyle.fontSize, weight: .regular)
            let barHeight = max(1, ceil(font.ascender - font.descender), fragmentRect.height)
            let drawRect = NSRect(
                x: markerX,
                y: containerOrigin.y + fragmentRect.midY - barHeight * 0.5,
                width: trailingEdge - markerX,
                height: barHeight
            )
            let base = NSColor(roleStyle.renderedColor).usingColorSpace(.deviceRGB)
                ?? NSColor(roleStyle.renderedColor)
            let radii = NodeMarkdownRenderContract.backgroundBarCornerRadii(
                fontSize: font.pointSize,
                barHeight: drawRect.height
            )
            let path = NSBezierPath(
                roundedRect: drawRect,
                xRadius: radii.width,
                yRadius: radii.height
            )
            NSGraphicsContext.saveGraphicsState()
            cachedGradient(level: level, baseColor: base).draw(in: path, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }

        drawLevelMarker(
            level: level,
            textColor: NSColor(roleStyle.renderedColor),
            markerX: markerX,
            textRect: fragmentRect,
            containerOrigin: containerOrigin
        )
    }

    private func drawNodeUnderlines(in paintRect: NSRect) {
        guard let layoutManager,
              let textContainer else { return }

        let content = string as NSString
        guard content.length > 0 else { return }
        let decorationRanges = decorationRowRanges(for: content)

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: paintRect.insetBy(dx: -8, dy: -8), in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        var lineLocation = content.lineRange(for: NSRange(location: visibleCharacterRange.location, length: 0)).location
        let visibleEnd = NSMaxRange(visibleCharacterRange)
        let containerOrigin = textContainerOrigin
        NSColor.systemBlue.setStroke()

        while lineLocation < content.length, lineLocation < visibleEnd {
            let lineRange = content.lineRange(for: NSRange(location: lineLocation, length: 0))
            lineLocation = NSMaxRange(lineRange)

            let level = level(for: lineRange, rowRanges: decorationRanges)
            guard nodeDocumentStyle.style(forLevel: level).isUnderline else { continue }

            let prefixLength = 0
            let contentRange = NSRange(
                location: lineRange.location + prefixLength,
                length: max(0, lineRange.length - prefixLength)
            )
            guard contentRange.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: contentRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, lineTextContainer, lineGlyphRange, _ in
                let clippedGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard clippedGlyphRange.length > 0 else { return }
                let textRect = layoutManager.boundingRect(forGlyphRange: clippedGlyphRange, in: lineTextContainer)
                guard textRect.width > 0, textRect.height > 0 else { return }
                let underlineY = containerOrigin.y + textRect.maxY + 1
                let path = NSBezierPath()
                path.lineWidth = max(1.2, min(2.4, textRect.height * 0.055))
                path.move(to: NSPoint(x: containerOrigin.x + textRect.minX, y: underlineY))
                path.line(to: NSPoint(x: containerOrigin.x + textRect.maxX, y: underlineY))
                path.stroke()
            }
        }
    }

    private func firstVisibleTextRect(lineRange: NSRange, prefixLength: Int, fallback: NSRect) -> NSRect {
        guard let layoutManager, textContainer != nil else { return fallback }
        let content = string as NSString
        var contentEnd = min(NSMaxRange(lineRange), content.length)
        var contentStart = min(lineRange.location + max(0, prefixLength), contentEnd)
        while contentStart < contentEnd {
            let character = content.substring(with: NSRange(location: contentStart, length: 1))
            if character != "\n" && character != "\r" { break }
            contentStart += 1
        }
        while contentEnd > contentStart {
            let character = content.substring(with: NSRange(location: contentEnd - 1, length: 1))
            if character != "\n" && character != "\r" { break }
            contentEnd -= 1
        }
        guard contentStart < contentEnd else { return fallback }

        // 末行换行符会形成额外排版片段。编号只能按真实文字片段居中，
        // 否则会落到下一行高度，看起来像一个不可进入的空Node。
        let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: contentRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return fallback }

        var firstRect: NSRect?
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, textContainer, lineGlyphRange, stop in
            let clippedRange = NSIntersectionRange(glyphRange, lineGlyphRange)
            guard clippedRange.length > 0 else { return }
            let rect = layoutManager.boundingRect(forGlyphRange: clippedRange, in: textContainer)
            firstRect = rect.isEmpty ? fallback : rect
            stop.pointee = true
        }
        return firstRect ?? fallback
    }

    private func drawLevelMarker(
        level: Int,
        textColor: NSColor,
        markerX: CGFloat,
        textRect: NSRect,
        containerOrigin: NSPoint
    ) {
        let rawMarker = nodeDocumentStyle.iconConfig.symbol(for: level)
        let marker = markerDisplayText(from: rawMarker)
        guard !marker.isEmpty else { return }

        let roleStyle = nodeDocumentStyle.style(forLevel: level)
        var markerFont = NSFont(name: roleStyle.fontName, size: roleStyle.fontSize)
            ?? NSFont.systemFont(ofSize: roleStyle.fontSize)
        if roleStyle.isBold {
            markerFont = NSFontManager.shared.convert(markerFont, toHaveTrait: .boldFontMask)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont,
            .foregroundColor: textColor.withAlphaComponent(0.85)
        ]
        let attributed = NSAttributedString(string: marker, attributes: attributes)
        let measured = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let markerSize = attributed.size()
        let markerOrigin = NSPoint(
            x: markerX - measured.minX,
            y: containerOrigin.y + textRect.midY - measured.midY
        )
        let markerRect = NSRect(origin: markerOrigin, size: markerSize)
        attributed.draw(in: markerRect)
    }

    private func markerDisplayText(from rawValue: String) -> String {
        NodeMarkdownRenderContract.markerDisplayText(from: rawValue)
    }

    private func cachedGradient(level: Int, baseColor: NSColor) -> NSGradient {
        let normalized = NodeMarkdownRenderContract.backgroundColor(from: baseColor)
        let key = BackgroundGradientCacheKey(
            level: level,
            red: Int((normalized.redComponent * 255).rounded()),
            green: Int((normalized.greenComponent * 255).rounded()),
            blue: Int((normalized.blueComponent * 255).rounded())
        )
        if let cached = backgroundGradientCache[key] {
            return cached
        }
        let gradient = NSGradient(
            colors: [
                normalized.withAlphaComponent(0.28),
                normalized.withAlphaComponent(0.14)
            ]
        ) ?? NSGradient(starting: normalized.withAlphaComponent(0.28), ending: normalized.withAlphaComponent(0.14))!
        backgroundGradientCache[key] = gradient
        return gradient
    }

}

#endif

#if os(macOS)
// MARK: - NodeMarkdown公式渲染载荷 - v1 - 保存原文本范围与SwiftMath渲染参数
private enum NodeMarkdownFormulaRenderMode: Hashable {
    case display
    case text
}

#endif

// MARK: - 正文编解码 - v2 - 编辑缓冲区只容纳Content，层级由行元数据承载
enum NodeMarkdownPlainTextCodec {
    static func serialize(document: NodeMarkdownDocument) -> String {
        document.nodes
            .map { NodeMarkdownLegacyAttachmentSourceRepair.repair($0.text) }
            .joined(separator: "\n")
    }

    /// 旧管线的结构快照已经逐行携带完整身份，不再通过正文相似度或前后位置
    /// 猜测UUID。只有快照中新建或重复的非法身份才生成新UUID。
    static func parse(
        snapshot: NodeMarkdownLegacyDocumentSnapshot,
        previousNodes: [NodeMarkdownNode]
    ) -> NodeMarkdownDocument {
        var previousByID: [UUID: NodeMarkdownNode] = [:]
        for node in previousNodes where previousByID[node.id] == nil {
            previousByID[node.id] = node
        }

        let now = Date()
        var assignedIDs: Set<UUID> = []
        var nodes: [NodeMarkdownNode] = []
        nodes.reserveCapacity(max(1, snapshot.rows.count))

        for row in snapshot.rows {
            let requestedID = UUID(uuidString: row.nodeID)
            let keepsRequestedIdentity = requestedID.map { !assignedIDs.contains($0) } ?? false
            let nodeID: UUID = {
                if let requestedID, keepsRequestedIdentity {
                    return requestedID
                }
                var freshID = UUID()
                while assignedIDs.contains(freshID) || previousByID[freshID] != nil {
                    freshID = UUID()
                }
                return freshID
            }()
            assignedIDs.insert(nodeID)

            let previousNode = previousByID[nodeID]
            let previousIsProtectedH3 = previousNode?.level == 3
                && !(previousNode?.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && !(previousNode?.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let level = previousIsProtectedH3 ? 3 : max(1, min(12, row.level))
            let rowSourceID = keepsRequestedIdentity
                ? row.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let rowSourceFile = keepsRequestedIdentity
                ? row.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let sourceID: String
            let sourceFile: String
            if level == 3 {
                // 已有关联的H3绝不能因一次元数据短缺而失去母本身份。
                sourceID = rowSourceID.isEmpty ? (previousNode?.sourceID ?? "") : row.sourceID
                sourceFile = rowSourceFile.isEmpty ? (previousNode?.sourceFile ?? "") : row.sourceFile
            } else {
                sourceID = ""
                sourceFile = ""
            }

            let repairedContent = NodeMarkdownLegacyAttachmentSourceRepair.repair(row.content)
            let changed = previousNode?.level != level
                || previousNode?.text != repairedContent
                || previousNode?.sourceID != sourceID
                || previousNode?.sourceFile != sourceFile
            let mtime = changed ? now : (previousNode?.mtimeCache ?? now)
            nodes.append(
                NodeMarkdownNode(
                    id: nodeID,
                    level: level,
                    text: repairedContent,
                    sourceID: sourceID,
                    sourceFile: sourceFile,
                    cache: level == 3 ? NodeMarkdownCacheCodec.encode(mtime: mtime) : "",
                    mtimeCache: mtime
                )
            )
        }

        if nodes.isEmpty {
            nodes = [NodeMarkdownNode(level: 1, text: "")]
        }
        return NodeMarkdownDocument(nodes: nodes)
    }

    static func parse(
        text: String,
        previousNodes: [NodeMarkdownNode],
        rowMetadata: [NodeMarkdownTextKitRowMetadata]? = nil
    ) -> NodeMarkdownDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map {
            NodeMarkdownLegacyAttachmentSourceRepair.repair(String($0))
        }
        let lines = rawLines.isEmpty ? [""] : rawLines
        let now = Date()
        let canTrustRowMetadata = rowMetadata?.count == lines.count
        var previousByID: [UUID: NodeMarkdownNode] = [:]
        for node in previousNodes {
            previousByID[node.id] = node
        }
        let decodedLines = lines.enumerated().map { index, line in
            let metadataLevel: Int? = {
                if canTrustRowMetadata {
                    return rowMetadata?[index].level
                }
                // 元数据条目数与文本行数不匹配时，仅保留UUID精确匹配的层级，
                // 其余交还给decodeLine从文本前缀自行解析，杜绝错位赋值。
                if let metadataRows = rowMetadata, metadataRows.indices.contains(index) {
                    let metadata = metadataRows[index]
                    if let nodeID = UUID(uuidString: metadata.nodeID), previousByID[nodeID] != nil {
                        return metadata.level
                    }
                }
                return nil
            }()
            return decodeLine(line, metadataLevel: metadataLevel)
        }
        let previousDecoded = previousNodes.map { (level: $0.level, content: $0.text) }

        // 行元信息代表编辑器明确传回的身份。先预留这些UUID，位置后备不得抢用。
        var metadataNodeByRow: [Int: NodeMarkdownNode] = [:]
        var metadataIDByRow: [Int: UUID] = [:]
        var reservedMetadataIDs: Set<UUID> = []
        if canTrustRowMetadata, let rowMetadata {
            for index in decodedLines.indices where rowMetadata.indices.contains(index) {
                guard let id = UUID(uuidString: rowMetadata[index].nodeID),
                      !reservedMetadataIDs.contains(id) else {
                    continue
                }
                reservedMetadataIDs.insert(id)
                metadataIDByRow[index] = id
                if let node = previousByID[id] {
                    metadataNodeByRow[index] = node
                }
            }
        }

        let prefixCount = commonPrefixCount(newLines: decodedLines, previousLines: previousDecoded)
        let suffixCount = commonSuffixCount(
            newLines: decodedLines,
            previousLines: previousDecoded,
            excludingPrefixCount: prefixCount
        )

        var nodes: [NodeMarkdownNode] = []
        nodes.reserveCapacity(lines.count)
        let middleNewStart = prefixCount
        let middleNewEnd = max(prefixCount, decodedLines.count - suffixCount)
        let middleOldStart = prefixCount
        let middleOldEnd = max(prefixCount, previousNodes.count - suffixCount)
        let middleOldCount = max(0, middleOldEnd - middleOldStart)
        var consumedPreviousIDs: Set<UUID> = []
        var assignedNodeIDs: Set<UUID> = []

        for index in decodedLines.indices {
            let decoded = decodedLines[index]
            let positionMatchedNode: NodeMarkdownNode? = {
                if index < prefixCount {
                    return previousNodes[index]
                }
                if index >= middleNewEnd {
                    let previousIndex = index - decodedLines.count + previousNodes.count
                    return previousNodes.indices.contains(previousIndex) ? previousNodes[previousIndex] : nil
                }
                let middleOffset = index - middleNewStart
                let candidateIndex = middleOldStart + middleOffset
                guard middleOffset >= 0, middleOffset < middleOldCount else { return nil }
                return previousNodes.indices.contains(candidateIndex) ? previousNodes[candidateIndex] : nil
            }()
            let metadataMatchedNode = metadataNodeByRow[index]
            let previousNode: NodeMarkdownNode? = {
                if let metadataMatchedNode,
                   !consumedPreviousIDs.contains(metadataMatchedNode.id) {
                    return metadataMatchedNode
                }
                guard let positionMatchedNode,
                      !consumedPreviousIDs.contains(positionMatchedNode.id),
                      !reservedMetadataIDs.contains(positionMatchedNode.id),
                      (positionMatchedNode.level == 3) == (decoded.level == 3) else {
                    return nil
                }
                return positionMatchedNode
            }()
            if let previousNode {
                consumedPreviousIDs.insert(previousNode.id)
            }

            let previousIsProtectedH3 = previousNode?.level == 3
                && !(previousNode?.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                && !(previousNode?.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let resolvedLevel = previousIsProtectedH3 ? 3 : decoded.level
            let nodeID: UUID = {
                if let previousNode, !assignedNodeIDs.contains(previousNode.id) {
                    return previousNode.id
                }
                if let metadataID = metadataIDByRow[index],
                   previousByID[metadataID] == nil,
                   !assignedNodeIDs.contains(metadataID) {
                    return metadataID
                }
                var freshID = UUID()
                while previousByID[freshID] != nil || assignedNodeIDs.contains(freshID) {
                    freshID = UUID()
                }
                return freshID
            }()
            assignedNodeIDs.insert(nodeID)

            let isChanged = previousNode?.level != resolvedLevel || previousNode?.text != decoded.content
            let metadataSourceID = canTrustRowMetadata ? rowMetadata?[index].sourceID ?? "" : ""
            let metadataSourceFile = canTrustRowMetadata ? rowMetadata?[index].sourceFile ?? "" : ""
            let shouldCarryPreviousSource = resolvedLevel == 3 && previousNode?.level == 3
            let shouldCarryMetadataSource = resolvedLevel == 3
                && !metadataSourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !metadataSourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let mtime = isChanged ? now : (previousNode?.mtimeCache ?? now)
            let node = NodeMarkdownNode(
                id: nodeID,
                level: resolvedLevel,
                text: decoded.content,
                sourceID: shouldCarryPreviousSource
                    ? (previousNode?.sourceID ?? "")
                    : (shouldCarryMetadataSource ? metadataSourceID : ""),
                sourceFile: shouldCarryPreviousSource
                    ? (previousNode?.sourceFile ?? "")
                    : (shouldCarryMetadataSource ? metadataSourceFile : ""),
                cache: NodeMarkdownCacheCodec.encode(mtime: mtime),
                mtimeCache: mtime
            )
            nodes.append(node)
        }

        return NodeMarkdownDocument(nodes: nodes)
    }

    private static func commonPrefixCount(
        newLines: [(level: Int, content: String)],
        previousLines: [(level: Int, content: String)]
    ) -> Int {
        let limit = min(newLines.count, previousLines.count)
        var index = 0
        while index < limit, newLines[index] == previousLines[index] {
            index += 1
        }
        return index
    }

    private static func commonSuffixCount(
        newLines: [(level: Int, content: String)],
        previousLines: [(level: Int, content: String)],
        excludingPrefixCount: Int
    ) -> Int {
        let newRemaining = newLines.count - excludingPrefixCount
        let oldRemaining = previousLines.count - excludingPrefixCount
        let limit = max(0, min(newRemaining, oldRemaining))
        guard limit > 0 else { return 0 }
        var count = 0
        while count < limit {
            let newIndex = newLines.count - 1 - count
            let oldIndex = previousLines.count - 1 - count
            if newLines[newIndex] != previousLines[oldIndex] {
                break
            }
            count += 1
        }
        return count
    }

    private static func decodeLine(
        _ line: String,
        metadataLevel: Int? = nil
    ) -> (level: Int, content: String) {
        if let metadataLevel {
            return (max(1, min(12, metadataLevel)), line)
        }
        // 从正文前缀解析层级，不剥离前缀以保证与信任元数据路径产出相同格式的content，
        // 避免prefix/suffix匹配因内容格式不一致而全线失败。
        let prefix = detectPrefix(in: line)
        if !prefix.isEmpty {
            return (NodeMarkdownPrefixCodec.decode(prefix: prefix), line)
        }
        return (7, line)
    }

    static func detectPrefix(in line: String) -> String {
        for level in stride(from: 12, through: 1, by: -1) {
            let prefix = NodeMarkdownPrefixCodec.encode(level: level)
            if line.hasPrefix(prefix) {
                return prefix
            }
        }
        return ""
    }
}
