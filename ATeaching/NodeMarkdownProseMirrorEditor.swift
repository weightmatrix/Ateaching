// PIPELINE MARKER: NodeMarkdown ProseMirror-style block pipeline.
import SwiftUI

#if os(macOS)
import AppKit

/// A viewport made of independent Node blocks. TextKit never owns ranges that cross
/// Node boundaries; the document model is changed only through transactions.
struct NodeMarkdownProseMirrorRepresentable: NSViewRepresentable {
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

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeNSView(context: Context) -> NodeMarkdownProseMirrorContainerView {
        context.coordinator.makeView()
    }

    func updateNSView(_ containerView: NodeMarkdownProseMirrorContainerView, context: Context) {
        context.coordinator.update(owner: self, scrollView: containerView.scrollView)
    }

    static func dismantleNSView(_ containerView: NodeMarkdownProseMirrorContainerView, coordinator: Coordinator) {
        coordinator.commitActiveNode(reason: "关闭编辑器")
        coordinator.cancelPendingPublish()
        coordinator.cancelRuntimeTasks()
        coordinator.flushDiagnostic114(reason: "关闭编辑器")
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
        private var owner: NodeMarkdownProseMirrorRepresentable
        private let state: NodeMarkdownTextKit2DocumentState
        // Node views are recycled and deleted. History belongs to the editor,
        // so moving focus or removing a Node must not change the undo stack.
        private let editorUndoManager = UndoManager()
        private var lastNativeEditWasDeletion = false
        private var lastNativeEditNodeID: UUID?
        private weak var tableView: NSTableView?
        private var textViewsByNodeID: [UUID: WeakTextView] = [:]
        private var nodeIDByTextView: [ObjectIdentifier: UUID] = [:]
        private var activeNodeID: UUID?
        private var baselineNode: NodeMarkdownTextKit2Node?
        private let exactLayoutEngine = NodeMarkdownExactLayoutEngine()
        private var exactGeometries: [UUID: NodeMarkdownExactGeometry] = [:]
        private var readyRowCount = 0
        // 每次插入最多追踪8个H3及首个后继；两分钟后停止滚动/配置采样。
        private var diagnostic123Operation = "-"
        private var diagnostic123Token = UUID()
        private var diagnostic123IDs: [UUID] = []
        private var diagnostic123Until: TimeInterval = 0
        private var diagnostic123Counts: [String: Int] = [:]
        private var exactLayoutTask: Task<Void, Never>?
        private var exactLayoutGeneration: UInt64 = 0
        private var exactLayoutWidth: CGFloat = 0
        private var exactLayoutScale: CGFloat = 0
        private var initialViewportIsReady = false
        private var viewportWidthTransitionPending = false
        private var exactLayoutRecoveryScheduled = false
        private let renderCache = NodeMarkdownTextKit2RenderCache<NodeMarkdownBlockRenderRecord>(capacity: 4_096)
        private var viewportObserver: NSObjectProtocol?
        private var lastExternalToken: Int
        private var lastNavigationToken: Int
        private var lastVisualState: VisualState
        private var appliedInPlaceEditRequestID: UUID?
        private var documentStyleRevision = 1
        private var publishWorkItem: DispatchWorkItem?
        private var isApplyingModel = false
        private var pendingFocusNodeID: UUID?
        private var pendingFocusOffset: Int?
        private var structuralEditInProgress = false
        private var structuralEditGeneration: UInt64 = 0
        private var structuralViewportOrigin: NSPoint?
        private var pendingNavigationRow: Int?
        private var transientMeasurementGeneration: UInt64 = 0
        private var caretVisibilityWorkItem: DispatchWorkItem?
        private var pendingViewportAnchor: ViewportAnchor?
        private let rowIdentifier = NSUserInterfaceItemIdentifier("NodeMarkdownProseMirrorRow")
        private let bottomPageMarginIdentifier = NSUserInterfaceItemIdentifier("NodeMarkdownBottomPageMargin")
        private let bottomPageMarginHeight: CGFloat = 15
        private let sessionID: UUID
        private let diagnostic114: NodeMarkdownDiagnostic114

        init(owner: NodeMarkdownProseMirrorRepresentable) {
            let initializationStart = NodeMarkdownDiagnostic114.now()
            let sessionID = UUID()
            self.owner = owner
            self.sessionID = sessionID
            state = NodeMarkdownTextKit2DocumentState(text: owner.text, rowMetadata: owner.rowMetadata)
            diagnostic114 = NodeMarkdownDiagnostic114(
                sessionID: sessionID,
                documentRows: owner.rowMetadata.count,
                documentUTF16: (owner.text as NSString).length
            )
            lastExternalToken = owner.externalTextSyncToken
            lastNavigationToken = owner.navigationRequestToken
            lastVisualState = VisualState(owner: owner)
            super.init()
            installDraftController(owner.draftCommitController)
            diagnostic114.recordDuration(
                "DocumentState初始化",
                since: initializationStart,
                slowThresholdMilliseconds: 8
            )
        }

        func makeView() -> NodeMarkdownProseMirrorContainerView {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            let table = NodeMarkdownProseMirrorTableView()
            table.headerView = nil
            table.backgroundColor = .clear
            table.gridStyleMask = []
            table.intercellSpacing = .zero
            table.selectionHighlightStyle = .none
            table.usesAutomaticRowHeights = false
            table.dataSource = self
            table.delegate = self
            table.onWidthWillChange = { [weak self] width in
                guard let self else { return }
                self.prepareForViewportWidthChange(to: width)
            }
            table.onWidthChange = { [weak self] in self?.handleViewportWidthChange() }
            let column = NSTableColumn(identifier: .init("Node"))
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scroll.documentView = table
            scroll.contentView.postsBoundsChangedNotifications = true
            viewportObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.viewportDidChange() }
            }
            tableView = table
            DispatchQueue.main.async { [weak self] in self?.scheduleExactLayout() }
            diagnostic114.recordDuration("makeView", since: diagnosticStart, slowThresholdMilliseconds: 8)
            diagnostic114.flushIfNeeded(reason: "编辑器建立", readyRows: readyRowCount, force: true)
            return NodeMarkdownProseMirrorContainerView(
                scrollView: scroll,
                bottomFrameHeight: 35
            )
        }

        func update(owner: NodeMarkdownProseMirrorRepresentable, scrollView: NSScrollView) {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.updateDocument(
                    rows: state.snapshot.nodes.count,
                    utf16: (owner.text as NSString).length
                )
                diagnostic114.recordDuration("SwiftUI update", since: diagnosticStart)
                diagnostic114.recordCount("SwiftUI update次数")
                diagnostic114.flushIfNeeded(reason: "SwiftUI更新", readyRows: readyRowCount)
            }
            let previousStyle = self.owner.documentStyle.renderIdentity
            let visualState = VisualState(owner: owner)
            self.owner = owner
            installDraftController(owner.draftCommitController)
            if let request = owner.inPlaceEditRequest,
               request.id != appliedInPlaceEditRequestID {
                appliedInPlaceEditRequestID = request.id
                TeachingCourseDiagnostic116.record(
                    "op=\(request.diagnosticID ?? "-") TextKit2收到inPlaceRequest request=\(String(request.id.uuidString.prefix(8))) currentNodes=\(state.snapshot.nodes.count) ready=\(readyRowCount)"
                )
                applyInPlaceEditCommand(request.command, diagnosticID: request.diagnosticID)
            }
            if owner.externalTextSyncToken != lastExternalToken {
                diagnostic114.recordCount("外部同步次数")
                lastExternalToken = owner.externalTextSyncToken
                if !matchesCurrentDocument(text: owner.text, rowMetadata: owner.rowMetadata) {
                    diagnostic114.recordCount("外部全文重装次数")
                    captureViewportAnchor()
                    commitActiveNode(reason: "外部文档更新")
                    guard state.replace(text: owner.text, rowMetadata: owner.rowMetadata) else {
                        lastVisualState = visualState
                        return
                    }
                    editorUndoManager.removeAllActions()
                    invalidateExactLayout()
                    renderCache.removeAll()
                    activeNodeID = nil
                    baselineNode = nil
                    tableView?.reloadData()
                    scheduleExactLayout()
                }
            } else if owner.documentStyle.renderIdentity != previousStyle {
                diagnostic114.recordCount("样式全文重排次数")
                captureViewportAnchor()
                documentStyleRevision &+= 1
                invalidateExactLayout()
                renderCache.removeAll()
                tableView?.reloadData()
                scheduleExactLayout()
            } else if visualState != lastVisualState {
                diagnostic114.recordCount("可见状态刷新次数")
                refreshVisibleNodesForStateOnly()
            }
            lastVisualState = visualState

            if owner.navigationRequestToken != lastNavigationToken {
                lastNavigationToken = owner.navigationRequestToken
                if let row = owner.activeRowIndex, state.snapshot.nodes.indices.contains(row) {
                    navigate(to: row, in: scrollView)
                }
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            readyRowCount + (showsBottomPageMargin ? 1 : 0)
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            if isBottomPageMarginRow(row) {
                return bottomPageMarginHeight
            }
            let width = viewportLayoutWidth()
            guard let node = state.node(at: row),
                  let geometry = exactGeometries[node.id],
                  geometry.key == exactLayoutKey(for: node.id, width: width) else {
                diagnostic123Event(nodeID: state.node(at: row)?.id, stage: "行高缓存未命中")
                requestExactLayoutRecovery()
                return 0
            }
            return geometry.height
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if isBottomPageMarginRow(row) {
                let view = tableView.makeView(withIdentifier: bottomPageMarginIdentifier, owner: self) ?? NSView()
                view.identifier = bottomPageMarginIdentifier
                return view
            }
            guard let node = state.node(at: row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? NodeMarkdownProseMirrorCellView)
                ?? NodeMarkdownProseMirrorCellView(identifier: rowIdentifier)
            configure(cell: cell, node: node, row: row, width: viewportLayoutWidth())
            return cell
        }

        func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
            diagnostic123Event(nodeID: state.node(at: row)?.id, stage: "行视图加入表格")
        }

        private var showsBottomPageMargin: Bool {
            readyRowCount > 0 && readyRowCount == state.snapshot.nodes.count
        }

        private func isBottomPageMarginRow(_ row: Int) -> Bool {
            showsBottomPageMargin && row == readyRowCount
        }

        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            pruneDeadTextViews()
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return }
            activateNode(node: node, row: row, in: textView, origin: "textDidBeginEditing")
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString,
                  let nodeTextView = textView as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(nodeTextView)] else { return true }
            if !editorUndoManager.isUndoing, !editorUndoManager.isRedoing,
               !nodeTextView.hasActiveInputMethodComposition {
                let isDeletion = replacementString.isEmpty && affectedCharRange.length > 0
                if lastNativeEditNodeID != nodeID
                    || isDeletion != lastNativeEditWasDeletion
                    || nodeTextView.selectedRange().length > 0 {
                    nodeTextView.breakUndoCoalescing()
                }
                lastNativeEditNodeID = nodeID
                lastNativeEditWasDeletion = isDeletion
            }
            if replacementString.isEmpty, affectedCharRange.length > 0 {
                let source = nodeTextView.documentString() as NSString
                let deletedText = affectedCharRange.exact(toLength: source.length).map { source.substring(with: $0) } ?? "<range越界>"
                NodeMarkdownDiagnostic117.record(
                    operationID: nodeTextView.diagnostic117OperationID,
                    "分块管线shouldChange node=\(short(nodeID)) row=\(state.row(for: nodeID).map(String.init) ?? "nil") affected=\(NSStringFromRange(affectedCharRange)) selection=\(NSStringFromRange(nodeTextView.selectedRange())) fullNode=\(affectedCharRange.location == 0 && affectedCharRange.length == source.length) deleted=\(NodeMarkdownDiagnostic117.textSummary(deletedText))"
                )
            }
            if let protectedEdit = NodeMarkdownImageEditProtection.protectedEdit(
                sourceText: nodeTextView.documentString(),
                affectedRange: affectedCharRange,
                replacement: replacementString
            ) {
                replaceNodeText(
                    nodeID: nodeID,
                    in: nodeTextView,
                    range: protectedEdit.replacementRange,
                    replacement: protectedEdit.replacement
                )
                return false
            }
            guard replacementString.contains("\n") else { return true }
            return !replaceWithNodeSequence(
                nodeID: nodeID,
                affectedRange: affectedCharRange,
                replacement: replacementString,
                undoManager: textView.undoManager
            )
        }

        func textDidChange(_ notification: Notification) {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.recordDuration("输入textDidChange", since: diagnosticStart, slowThresholdMilliseconds: 8)
                diagnostic114.recordCount("输入次数")
                diagnostic114.flushIfNeeded(reason: "输入", readyRows: readyRowCount)
            }
            guard !isApplyingModel,
                  let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID),
                  let oldNode = state.node(at: row) else { return }
            guard !textView.isApplyingQuickInputReplacement else { return }
            let isHistoryReplay = editorUndoManager.isUndoing || editorUndoManager.isRedoing
            defer {
                if isHistoryReplay {
                    let revision = state.revision
                    // AppKit restores its selection after textDidChange. Collapse
                    // that restored range only after the undo command finishes.
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self, let textView,
                              self.state.revision == revision,
                              self.nodeIDByTextView[ObjectIdentifier(textView)] == nodeID else { return }
                        let selection = textView.selectedRange()
                        let caret = min(NSMaxRange(selection), textView.nodeSourceTextSnapshot.utf16.count)
                        textView.setSelectedRange(NSRange(location: caret, length: 0))
                        textView.setNeedsDisplay(textView.bounds)
                    }
                    lastNativeEditNodeID = nil
                }
            }
            let typedContent = textView.string
            if let operationID = textView.diagnostic117OperationID {
                NodeMarkdownDiagnostic117.record(
                    operationID: operationID,
                    "分块管线textDidChange前 node=\(short(nodeID)) row=\(row) old=\(NodeMarkdownDiagnostic117.textSummary(oldNode.content)) typed=\(NodeMarkdownDiagnostic117.textSummary(typedContent)) selection=\(NSStringFromRange(textView.selectedRange()))"
                )
            }
            textView.commitProjectedSourceText(typedContent)

            // 快捷输入只作用于当前 Node 文本，检查与替换都在单块内完成；未命中时不再重复读正文。
            let quickInputEdit: NodeMarkdownTextKit2QuickInputEdit?
            let quickInputStart = NodeMarkdownDiagnostic114.now()
            if !textView.hasActiveInputMethodComposition,
               textView.undoManager?.isUndoing != true,
               textView.undoManager?.isRedoing != true {
                quickInputEdit = textView.applyQuickInputIfNeeded(documentStyle: owner.documentStyle)
            } else {
                quickInputEdit = nil
            }
            diagnostic114.recordDuration("快捷输入检查", since: quickInputStart)

            let content: String
            if quickInputEdit != nil {
                content = textView.string
            } else {
                content = typedContent
            }
            guard content != oldNode.content else { return }
            var replacement = oldNode
            replacement.content = content
            let selection = NodeMarkdownNodeSelection(
                anchor: .init(nodeID: nodeID, utf16Offset: textView.selectedRange().location),
                head: .init(nodeID: nodeID, utf16Offset: NSMaxRange(textView.selectedRange()))
            )
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceNode(nodeID: nodeID, node: replacement)],
                selectionBefore: selection,
                selectionAfter: selection,
                recordsHistory: false,
                label: "Type in Node"
            )
            let dispatchStart = NodeMarkdownDiagnostic114.now()
            guard let result = state.dispatch(transaction) else {
                diagnostic114.recordDuration("输入事务dispatch", since: dispatchStart)
                reinstall(node: oldNode, in: textView, row: row)
                return
            }
            if let operationID = textView.diagnostic117OperationID {
                NodeMarkdownDiagnostic117.record(
                    operationID: operationID,
                    "分块管线文字事务成功 node=\(short(nodeID)) row=\(row) new=\(NodeMarkdownDiagnostic117.textSummary(state.node(at: row)?.content ?? "<missing>")) rows=\(state.snapshot.nodes.count)"
                )
            }
            diagnostic114.recordDuration("输入事务dispatch", since: dispatchStart)
            consume(result: result, refresh: false)
            textView.nodeMarkdownRowLayouts = [localLayout(for: replacement, row: row).replacingSpacingBefore(0)]
            owner.onEditingDraftDirtyChange?(true)
            reportFocus(textView: textView, row: row)
            measure(textView: textView, nodeID: nodeID, row: row)
            scheduleCaretVisibility(textView: textView, nodeID: nodeID)
            textView.setNeedsDisplay(textView.bounds)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID) else { return }
            reportFocus(textView: textView, row: row)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)] else { return }
            guard activeNodeID == nodeID else { return }
            commitActiveNode(reason: "Node失焦")
            if !structuralEditInProgress {
                owner.onInputSessionStateChange?(false)
            }
        }

        func commitActiveNode(reason: String) {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.recordDuration("提交活动Node", since: diagnosticStart, slowThresholdMilliseconds: 8, details: "reason=\(reason)")
            }
            guard let nodeID = activeNodeID,
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return }
            let isStructuralTransition = structuralEditInProgress
            if let textView = textViewsByNodeID[nodeID]?.value {
                let selection = textView.selectedRange()
                if selection.length > 0 {
                    let caret = min(NSMaxRange(selection), (textView.nodeSourceTextSnapshot as NSString).length)
                    textView.setSelectedRange(NSRange(location: caret, length: 0))
                }
            }
            if let baselineNode, baselineNode != node {
                if let onCommitEditingNode = owner.onCommitEditingNode {
                    onCommitEditingNode(draft(for: node))
                } else {
                    publishProjectionFallback()
                }
            }
            activeNodeID = nil
            baselineNode = nil
            owner.onEditingDraftDirtyChange?(false)
            guard !isStructuralTransition else { return }
            installExactStaticGeometry(at: row)
            owner.onActiveRowChange?(nil)
            owner.onFocusLocationChange?(nil)
            if let textView = textViewsByNodeID[nodeID]?.value {
                reinstall(node: node, in: textView, row: row)
                measure(textView: textView, nodeID: nodeID, row: row)
                textView.setNeedsDisplay(textView.bounds)
            } else {
                refreshRows([row])
            }
            _ = reason
        }

        private func flushActiveNodeForSave() {
            guard let nodeID = activeNodeID,
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return }
            if baselineNode != node {
                if let onCommitEditingNode = owner.onCommitEditingNode {
                    onCommitEditingNode(draft(for: node))
                } else {
                    publishProjectionFallback()
                }
                baselineNode = node
            }
            owner.onEditingDraftDirtyChange?(false)
        }

        func cancelPendingPublish() {
            publishWorkItem?.cancel()
            publishWorkItem = nil
        }

        func cancelRuntimeTasks() {
            cancelExactLayout()
            caretVisibilityWorkItem?.cancel()
            caretVisibilityWorkItem = nil
            if let viewportObserver {
                NotificationCenter.default.removeObserver(viewportObserver)
                self.viewportObserver = nil
            }
        }

        func flushDiagnostic114(reason: String) {
            diagnostic114.flushIfNeeded(reason: reason, readyRows: readyRowCount, force: true)
        }

        private func configure(cell: NodeMarkdownProseMirrorCellView, node: NodeMarkdownTextKit2Node, row: Int, width: CGFloat) {
            defer { diagnostic123Event(nodeID: node.id, stage: "Cell配置结束") }
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.recordDuration(
                    "可见Cell配置",
                    since: diagnosticStart,
                    details: "row=\(row) nodeUTF16=\(node.content.utf16.count)"
                )
                diagnostic114.recordCount("Cell配置次数")
            }
            let textView = cell.textView
            var record = renderRecord(for: node, row: row, width: width)
            if record == nil, structuralEditInProgress {
                diagnostic114.recordCount("结构编辑同步补测次数")
                // A structural edit may invalidate one visible Node. Repair that
                // exact Node synchronously; never escalate a local miss into a
                // document-wide geometry reset.
                installExactStaticGeometry(at: row, notifyTable: false)
                record = renderRecord(for: node, row: row, width: width)
            }
            guard let record else {
                diagnostic114.recordCount("Cell缺失几何次数")
                if let previousNodeID = cell.nodeID {
                    textViewsByNodeID.removeValue(forKey: previousNodeID)
                }
                nodeIDByTextView.removeValue(forKey: ObjectIdentifier(textView))
                cell.nodeID = nil
                cell.renderedKey = nil
                cell.isHidden = true
                diagnostic123Event(nodeID: node.id, stage: "Cell缺失渲染记录被隐藏")
                requestExactLayoutRecovery()
                return
            }
            cell.isHidden = false
            cell.setContentTopInset(record.layout.spacingBefore)
            if let previousNodeID = cell.nodeID, previousNodeID != node.id {
                textViewsByNodeID.removeValue(forKey: previousNodeID)
            }
            cell.nodeID = node.id
            textView.delegate = self
            textView.drawsBackground = false
            textView.isRichText = true
            textView.importsGraphics = false
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = false
            textView.textContainerInset = NSSize(
                width: 16,
                height: NodeMarkdownTextKit2TextView.blockVerticalInset(for: record.layout)
            )
            textView.nodeTextContainer.widthTracksTextView = true
            textView.nodeTextContainer.containerSize = NSSize(width: max(1, width - 32), height: .greatestFiniteMagnitude)
            textView.quickInputSettings = owner.quickInputSettings
            textView.suppressesAutomaticSelectionScrolling = !(
                activeNodeID == node.id && textView.window?.firstResponder === textView
            )
            textView.onRequestSave = { [weak self] in
                self?.flushActiveNodeForSave()
                self?.owner.onRequestSave?()
            }
            textView.onTransientLayoutChange = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scheduleTransientMeasurement(textView: textView, nodeID: node.id)
            }
            textView.onHandleInsertNewline = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.splitNode(nodeID: node.id, textView: textView)
            }
            textView.onHandleTabCommand = { [weak self, weak textView] increaseLevel in
                guard let self, let textView,
                      let currentID = self.nodeIDByTextView[ObjectIdentifier(textView)] else { return false }
                return self.changeLevel(nodeID: currentID, increaseLevel: increaseLevel)
            }
            textView.onHandleDeleteBackward = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                let selection = textView.selectedRange()
                let sourceLength = (textView.documentString() as NSString).length
                if selection.length > 0 {
                    if selection.location == 0, selection.length == sourceLength {
                        return self.deleteFullySelectedNode(nodeID: node.id, textView: textView)
                    }
                    return false
                }
                let atStart = selection.location == 0
                NodeMarkdownDiagnostic117.record(
                    operationID: textView.diagnostic117OperationID,
                    "分块管线Backspace判定 node=\(self.short(node.id)) row=\(self.state.row(for: node.id).map(String.init) ?? "nil") selection=\(NSStringFromRange(selection)) nodeUTF16=\((textView.documentString() as NSString).length) atStart=\(atStart) decision=\(atStart ? "尝试向上合并" : "交给系统删除")"
                )
                guard atStart else { return false }
                return self.joinWithPrevious(nodeID: node.id)
            }
            textView.onHandleDeleteForward = { [weak self, weak textView] in
                guard let self, let textView,
                      textView.selectedRange().length == 0,
                      textView.selectedRange().location == (textView.string as NSString).length else { return false }
                return self.joinWithNext(nodeID: node.id)
            }
            textView.onHandleVerticalMove = { [weak self, weak textView] direction in
                guard let self, let textView else { return false }
                return self.moveVertically(from: node.id, direction: direction, selection: textView.selectedRange())
            }
            textView.onRequestInsertImage = { [weak self, weak textView] in
                guard let self, let textView else { return }
                let firstResponder = textView.window?.firstResponder as? NodeMarkdownTextKit2TextView
                let targetTextView = firstResponder ?? textView
                let targetID = self.activeNodeID ?? self.nodeIDByTextView[ObjectIdentifier(targetTextView)]
                guard let targetID else { return }
                self.insertImage(at: targetID, in: targetTextView)
            }
            textView.onRequestDeleteNodePackage = { [weak self] in
                guard let self, let row = self.state.row(for: node.id) else { return }
                self.commitActiveNode(reason: "删除包前")
                self.owner.onRequestDeleteNodePackageAtRow?(row)
            }
            textView.onRequestCutNodePackage = { [weak self] in
                guard let self, let row = self.state.row(for: node.id) else { return }
                self.commitActiveNode(reason: "剪切包前")
                self.owner.onRequestCutNodePackageAtRow?(row)
            }
            textView.onRequestPasteNodePackage = { [weak self] in
                guard let self, let row = self.state.row(for: node.id) else { return }
                self.commitActiveNode(reason: "粘贴包前")
                self.owner.onRequestPasteNodePackageAfterRow?(row)
            }
            textView.canPasteNodePackage = { [weak self] in self?.owner.canPasteNodePackage?() ?? false }
            textView.canCutNodePackage = { true }
            textView.canDeleteNodePackage = { true }
            textView.canDeleteProtectedH3 = { node.isProtectedH3 }
            textView.onRequestDeleteProtectedH3 = { [weak self] in
                guard let self, let row = self.state.row(for: node.id) else { return }
                self.owner.onRequestDeleteProtectedH3AtRow?(row)
            }
            textView.onRequestOpenDrawingBoard = { [weak self] in
                guard let self, let row = self.state.row(for: node.id) else { return }
                self.owner.onRequestOpenDrawingBoardAtRow?(row)
            }
            textView.onHandleCancelOperation = { [weak self] in
                self?.commitActiveNode(reason: "ESC")
                self?.tableView?.window?.makeFirstResponder(nil)
                return true
            }
            textView.onHandlePrimaryClick = { [weak self, weak textView] in
                guard let self, let textView,
                      let row = self.state.row(for: node.id),
                      let currentNode = self.state.node(at: row) else { return }
                self.activateNode(node: currentNode, row: row, in: textView, origin: "mouseDown主点击")
            }

            nodeIDByTextView[ObjectIdentifier(textView)] = node.id
            textViewsByNodeID[node.id] = WeakTextView(textView)
            if activeNodeID != node.id || textView.window?.firstResponder !== textView {
                if cell.renderedKey != record.key {
                    reinstall(record: record, in: textView)
                    cell.renderedKey = record.key
                }
            }
            if pendingFocusNodeID == node.id {
                // `configure` runs inside NSTableView's row update. Changing the
                // first responder here re-enters table layout and can bind the
                // editor to the wrong row. `focus` claims it after the update.
            }
        }

        private func reinstall(node: NodeMarkdownTextKit2Node, in textView: NodeMarkdownTextKit2TextView, row: Int) {
            let width = viewportLayoutWidth(fallback: textView.bounds.width)
            if let record = renderRecord(for: node, row: row, width: width) {
                reinstall(record: record, in: textView)
                return
            }
            // renderRecord 暂缺时也要保证可见文本、行布局和编号同步，不丢标记。
            let layout = localLayout(for: node, row: row).replacingSpacingBefore(0)
            textView.replaceDocumentText(node.content, documentStyle: owner.documentStyle)
            textView.nodeMarkdownRowLayouts = [layout]
            textView.applyNodeMarkdownStyles(
                rowLayouts: [layout],
                documentStyle: owner.documentStyle,
                baseDirectoryURL: owner.workingDirectoryURL,
                searchQuery: owner.searchQuery,
                activeRowIndex: owner.activeRowIndex == row ? 0 : nil,
                activeMatchLocationInRow: owner.activeRowIndex == row ? owner.activeMatchLocationInRow : nil,
                editingRowIndex: activeNodeID == node.id ? 0 : nil
            )
        }

        private func reinstall(record: NodeMarkdownBlockRenderRecord, in textView: NodeMarkdownTextKit2TextView) {
            let node = record.node
            let row = record.row
            let selection = textView.selectedRange()
            isApplyingModel = true
            textView.replaceDocumentText(node.content, documentStyle: owner.documentStyle)
            let layout = record.layout.replacingSpacingBefore(0)
            textView.nodeMarkdownRowLayouts = [layout]
            textView.applyNodeMarkdownStyles(
                rowLayouts: [layout],
                documentStyle: owner.documentStyle,
                baseDirectoryURL: owner.workingDirectoryURL,
                searchQuery: owner.searchQuery,
                activeRowIndex: owner.activeRowIndex == row ? 0 : nil,
                activeMatchLocationInRow: owner.activeRowIndex == row ? owner.activeMatchLocationInRow : nil,
                editingRowIndex: activeNodeID == node.id ? 0 : nil
            )
            let attributes = textView.typingAttributes(for: layout, documentStyle: owner.documentStyle)
            textView.nodeMarkdownTypingAttributes = attributes
            textView.typingAttributes = attributes
            if activeNodeID == node.id,
               selection.exact(toLength: node.content.utf16.count) != nil {
                textView.setSelectedRange(selection)
            }
            _ = textView.exactNodeMarkdownVisualBounds()
            isApplyingModel = false
        }

        private func activateNode(
            node: NodeMarkdownTextKit2Node,
            row: Int,
            in textView: NodeMarkdownTextKit2TextView,
            origin: String
        ) {
            let isNewActivation = activeNodeID != node.id
            if isNewActivation {
                commitActiveNode(reason: "切换到另一Node")
                activeNodeID = node.id
                baselineNode = node
                reinstall(node: node, in: textView, row: row)
                measure(textView: textView, nodeID: node.id, row: row)
                owner.onBeginEditing?()
                owner.onInputSessionStateChange?(true)
                owner.onActiveRowChange?(row)
            }
            textView.suppressesAutomaticSelectionScrolling = false
            reportFocus(textView: textView, row: row)
            _ = origin
        }

        private func localLayout(for node: NodeMarkdownTextKit2Node, row: Int) -> NodeMarkdownTextKit2RowLayout {
            let style = NodeMarkdownRenderContract.default.lineStyle(
                level: node.level,
                prefix: "",
                documentStyle: owner.documentStyle
            )
            let previousLayout = state.node(at: row - 1).map { previous -> NodeMarkdownTextKit2RowLayout in
                let previousStyle = NodeMarkdownRenderContract.default.lineStyle(
                    level: previous.level,
                    prefix: "",
                    documentStyle: owner.documentStyle
                )
                return NodeMarkdownTextKit2RowLayout(
                    rowIndex: 0,
                    range: NSRange(location: 0, length: 0),
                    contentRange: NSRange(location: 0, length: 0),
                    prefix: "",
                    level: previous.level,
                    lineStyle: previousStyle,
                    spacingBefore: 0,
                    isProtectedH3: previous.isProtectedH3
                )
            }
            let length = (node.content as NSString).length
            return NodeMarkdownTextKit2RowLayout(
                rowIndex: 0,
                range: NSRange(location: 0, length: length),
                contentRange: NSRange(location: 0, length: length),
                prefix: "",
                level: node.level,
                lineStyle: style,
                spacingBefore: NodeMarkdownTextKit2Coordinator.spacingBeforeRow(
                    previousLayout: previousLayout,
                    currentLevel: node.level,
                    currentLineStyle: style
                ),
                isProtectedH3: node.isProtectedH3
            )
        }

        private func splitNode(nodeID: UUID, textView: NodeMarkdownTextKit2TextView) -> Bool {
            guard let row = state.row(for: nodeID), let node = state.node(at: row) else { return false }
            guard ownsStructuralInput(nodeID: nodeID, textView: textView) else { return true }
            let selection = textView.selectedRange()
            guard beginStructuralEdit(nodeID: nodeID, textView: textView) else { return true }
            let newID = UUID()
            let newLevel = node.isProtectedH3 ? 4 : node.level
            var steps: [NodeMarkdownTransactionStep] = []
            if selection.length > 0 {
                steps.append(.replaceText(nodeID: nodeID, range: selection, replacement: ""))
            }
            steps.append(.splitNode(nodeID: nodeID, offset: selection.location, newNodeID: newID, newLevel: newLevel))
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: steps,
                selectionBefore: NodeMarkdownNodeSelection(anchor: .init(nodeID: nodeID, utf16Offset: selection.location)),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: newID, utf16Offset: 0)),
                label: "Split Node"
            )
            guard let result = state.dispatch(transaction) else {
                cancelStructuralEdit()
                return true
            }
            registerStructuralUndo(from: textView)
            finishStructuralEdit(
                result: result,
                targetNodeID: newID,
                targetRow: row + 1,
                targetOffset: 0,
                insertedRows: IndexSet(integer: row + 1),
                removedRows: [],
                rowsToReload: IndexSet(integersIn: row..<min(row + 3, state.snapshot.nodes.count))
            )
            return true
        }

        private func deleteFullySelectedNode(nodeID: UUID, textView: NodeMarkdownTextKit2TextView) -> Bool {
            guard let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return true }
            // Preserve the existing protected-heading rules. The final Node stays
            // editable as an empty paragraph through the native text deletion.
            guard !node.isProtectedH3 else { return true }
            guard state.snapshot.nodes.count > 1 else { return false }
            let selection = textView.selectedRange()
            guard ownsStructuralInput(nodeID: nodeID, textView: textView),
                  beginStructuralEdit(nodeID: nodeID, textView: textView) else { return true }
            let targetRow = row > 0 ? row - 1 : 0
            guard let target = state.node(at: row > 0 ? row - 1 : row + 1) else {
                cancelStructuralEdit()
                return true
            }
            let offset = row > 0 ? target.content.utf16.count : 0
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.deleteNodes(nodeIDs: [nodeID])],
                selectionBefore: NodeMarkdownNodeSelection(
                    anchor: .init(nodeID: nodeID, utf16Offset: selection.location),
                    head: .init(nodeID: nodeID, utf16Offset: NSMaxRange(selection))
                ),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: target.id, utf16Offset: offset)),
                label: "Delete Selected Node"
            )
            guard let result = state.dispatch(transaction) else {
                cancelStructuralEdit()
                return true
            }
            registerStructuralUndo(from: textView)
            finishStructuralEdit(
                result: result,
                targetNodeID: target.id,
                targetRow: targetRow,
                targetOffset: offset,
                insertedRows: [],
                removedRows: IndexSet(integer: row),
                rowsToReload: IndexSet(integersIn: targetRow..<min(row + 1, state.snapshot.nodes.count))
            )
            return true
        }

        private func joinWithPrevious(nodeID: UUID) -> Bool {
            guard let row = state.row(for: nodeID), row > 0,
                  let previous = state.node(at: row - 1),
                  let node = state.node(at: row),
                  !node.isProtectedH3 else { return false }
            guard let textView = textViewsByNodeID[nodeID]?.value,
                  ownsStructuralInput(nodeID: nodeID, textView: textView) else { return true }
            NodeMarkdownDiagnostic117.record(
                operationID: textView.diagnostic117OperationID,
                "向上合并开始 left=\(short(previous.id)) right=\(short(node.id)) row=\(row) selection=\(NSStringFromRange(textView.selectedRange())) leftText=\(NodeMarkdownDiagnostic117.textSummary(previous.content)) rightText=\(NodeMarkdownDiagnostic117.textSummary(node.content))"
            )
            guard beginStructuralEdit(nodeID: nodeID, textView: textView) else { return true }
            let offset = (previous.content as NSString).length
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.joinNodes(leftID: previous.id, rightID: node.id)],
                selectionBefore: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: 0)),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: previous.id, utf16Offset: offset)),
                label: "Join Nodes"
            )
            guard let result = state.dispatch(transaction) else {
                NodeMarkdownDiagnostic117.record(
                    operationID: textView.diagnostic117OperationID,
                    "向上合并事务失败 row=\(row) revision=\(state.revision)"
                )
                cancelStructuralEdit()
                return true
            }
            NodeMarkdownDiagnostic117.record(
                operationID: textView.diagnostic117OperationID,
                "向上合并事务成功 targetRow=\(row - 1) target=\(short(previous.id)) merged=\(NodeMarkdownDiagnostic117.textSummary(state.node(at: row - 1)?.content ?? "<missing>")) rows=\(state.snapshot.nodes.count)"
            )
            registerStructuralUndo(from: textView)
            finishStructuralEdit(
                result: result,
                targetNodeID: previous.id,
                targetRow: row - 1,
                targetOffset: offset,
                insertedRows: [],
                removedRows: IndexSet(integer: row),
                rowsToReload: IndexSet(integersIn: (row - 1)..<min(row + 1, state.snapshot.nodes.count))
            )
            return true
        }

        private func joinWithNext(nodeID: UUID) -> Bool {
            guard let row = state.row(for: nodeID),
                  let node = state.node(at: row),
                  let next = state.node(at: row + 1),
                  !next.isProtectedH3 else { return false }
            guard let textView = textViewsByNodeID[nodeID]?.value,
                  ownsStructuralInput(nodeID: nodeID, textView: textView) else { return true }
            guard beginStructuralEdit(nodeID: nodeID, textView: textView) else { return true }
            let offset = (node.content as NSString).length
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.joinNodes(leftID: node.id, rightID: next.id)],
                selectionBefore: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: offset)),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: offset)),
                label: "Join Next Node"
            )
            guard let result = state.dispatch(transaction) else {
                cancelStructuralEdit()
                return true
            }
            registerStructuralUndo(from: textView)
            finishStructuralEdit(
                result: result,
                targetNodeID: nodeID,
                targetRow: row,
                targetOffset: offset,
                insertedRows: [],
                removedRows: IndexSet(integer: row + 1),
                rowsToReload: IndexSet(integersIn: row..<min(row + 2, state.snapshot.nodes.count))
            )
            return true
        }

        private func moveVertically(from nodeID: UUID, direction: Int, selection: NSRange) -> Bool {
            guard selection.length == 0,
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return false }
            if direction < 0, selection.location == 0, let previous = state.node(at: row - 1) {
                focus(nodeID: previous.id, offset: (previous.content as NSString).length)
                return true
            }
            if direction > 0,
               selection.location == (node.content as NSString).length,
               let next = state.node(at: row + 1) {
                focus(nodeID: next.id, offset: 0)
                return true
            }
            return false
        }

        private func replaceWithNodeSequence(
            nodeID: UUID,
            affectedRange: NSRange,
            replacement: String,
            undoManager: UndoManager?
        ) -> Bool {
            guard let row = state.row(for: nodeID), let node = state.node(at: row) else { return false }
            guard let textView = textViewsByNodeID[nodeID]?.value,
                  ownsStructuralInput(nodeID: nodeID, textView: textView) else { return true }
            guard beginStructuralEdit(nodeID: nodeID, textView: textView) else { return true }
            let source = node.content as NSString
            guard let safeRange = affectedRange.exact(toLength: source.length) else { return false }
            let resulting = source.replacingCharacters(in: safeRange, with: replacement)
            let lines = resulting.components(separatedBy: "\n")
            guard lines.count > 1 else { return false }

            var first = node
            first.content = lines[0]
            let childLevel = node.isProtectedH3 ? 4 : node.level
            let inserted = lines.dropFirst().map {
                NodeMarkdownTextKit2Node(id: UUID(), level: childLevel, content: $0, sourceID: "", sourceFile: "")
            }
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [
                    .replaceNode(nodeID: nodeID, node: first),
                    .insertNodes(row: row + 1, nodes: inserted)
                ],
                label: "Paste Node Sequence"
            )
            guard let result = state.dispatch(transaction), let last = inserted.last else {
                cancelStructuralEdit()
                return true
            }
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: undoManager)
            }
            finishStructuralEdit(
                result: result,
                targetNodeID: last.id,
                targetRow: row + inserted.count,
                targetOffset: (last.content as NSString).length,
                insertedRows: IndexSet(integersIn: (row + 1)..<(row + inserted.count + 1)),
                removedRows: [],
                rowsToReload: IndexSet(integersIn: row..<min(row + inserted.count + 2, state.snapshot.nodes.count))
            )
            return true
        }

        private func ownsStructuralInput(
            nodeID: UUID,
            textView: NodeMarkdownTextKit2TextView
        ) -> Bool {
            let ownsInput = !structuralEditInProgress
                && activeNodeID == nodeID
                && nodeIDByTextView[ObjectIdentifier(textView)] == nodeID
                && textView.window?.firstResponder === textView
            return ownsInput
        }

        private func beginStructuralEdit(
            nodeID: UUID,
            textView: NodeMarkdownTextKit2TextView
        ) -> Bool {
            guard !structuralEditInProgress,
                  activeNodeID == nodeID,
                  textView.window?.firstResponder === textView,
                  let tableView,
                  let window = textView.window else { return false }

            structuralEditInProgress = true
            structuralEditGeneration &+= 1
            structuralViewportOrigin = tableView.enclosingScrollView?.contentView.bounds.origin
            pendingFocusNodeID = nil
            pendingFocusOffset = nil

            // A structural command must stop the old field editor before the
            // document changes. Otherwise subsequent keys can reach a view whose
            // captured Node identity no longer matches the model.
            guard window.makeFirstResponder(tableView) else {
                structuralEditInProgress = false
                structuralViewportOrigin = nil
                return false
            }
            activeNodeID = nil
            baselineNode = nil
            return true
        }

        private func finishStructuralEdit(
            result: NodeMarkdownTransactionResult,
            targetNodeID: UUID,
            targetRow: Int,
            targetOffset: Int,
            insertedRows: IndexSet,
            removedRows: IndexSet,
            rowsToReload: IndexSet
        ) {
            let generation = structuralEditGeneration
            applyStructuralTableDelta(
                result: result,
                insertedRows: insertedRows,
                removedRows: removedRows,
                rowsToReload: rowsToReload
            )
            pendingFocusNodeID = targetNodeID
            pendingFocusOffset = targetOffset
            publishNow()

            restoreStructuralViewport()
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.structuralEditInProgress,
                      self.structuralEditGeneration == generation,
                      self.state.row(for: targetNodeID) == targetRow else { return }
                self.restoreStructuralViewport()
                self.fulfillPendingFocusIfPossible()
            }
        }

        private func applyStructuralTableDelta(
            result: NodeMarkdownTransactionResult,
            insertedRows: IndexSet,
            removedRows: IndexSet,
            rowsToReload: IndexSet
        ) {
            guard let tableView else { return }
            cancelExactLayout()

            for id in result.impact.deletedNodeIDs {
                renderCache.invalidate(nodeID: id)
                exactGeometries[id] = nil
                textViewsByNodeID.removeValue(forKey: id)
            }
            let livingIDs = Set(state.snapshot.nodes.map(\.id))
            renderCache.retain(nodeIDs: livingIDs)
            exactGeometries = exactGeometries.filter { livingIDs.contains($0.key) }

            // The current row is visible, therefore it is inside the measured
            // prefix. Preserve every existing geometry and measure only Nodes
            // whose content or predecessor changed.
            for id in result.impact.layoutNodeIDs {
                guard let row = state.row(for: id) else { continue }
                installExactStaticGeometry(at: row, notifyTable: false)
            }
            let oldReadyCount = readyRowCount
            let visibleRemovedRows = IndexSet(removedRows.filter { $0 >= 0 && $0 < oldReadyCount })
            let newReadyCount = max(
                0,
                min(
                    state.snapshot.nodes.count,
                    oldReadyCount + insertedRows.count - visibleRemovedRows.count
                )
            )
            readyRowCount = newReadyCount
            initialViewportIsReady = readyRowCount > 0

            tableView.beginUpdates()
            if !visibleRemovedRows.isEmpty {
                tableView.removeRows(at: visibleRemovedRows, withAnimation: [])
            }
            if !insertedRows.isEmpty {
                tableView.insertRows(at: insertedRows, withAnimation: [])
            }
            tableView.endUpdates()
            let validReloads = IndexSet(rowsToReload.filter { $0 >= 0 && $0 < readyRowCount })
            if !validReloads.isEmpty {
                tableView.reloadData(
                    forRowIndexes: validReloads,
                    columnIndexes: IndexSet(integer: 0)
                )
                tableView.noteHeightOfRows(withIndexesChanged: validReloads)
            }
            if readyRowCount < state.snapshot.nodes.count {
                scheduleExactLayout()
            }
        }

        private func cancelStructuralEdit() {
            structuralEditInProgress = false
            pendingFocusNodeID = nil
            pendingFocusOffset = nil
            restoreStructuralViewport()
            structuralViewportOrigin = nil
        }

        private func restoreStructuralViewport() {
            guard let origin = structuralViewportOrigin,
                  let scrollView = tableView?.enclosingScrollView else { return }
            var bounds = scrollView.contentView.bounds
            bounds.origin = origin
            scrollView.contentView.setBoundsOrigin(scrollView.contentView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func changeLevel(nodeID: UUID, increaseLevel: Bool) -> Bool {
            guard let row = state.row(for: nodeID), let node = state.node(at: row), !node.isProtectedH3 else { return false }
            let level = max(1, min(12, node.level + (increaseLevel ? 1 : -1)))
            guard level != node.level else { return true }
            let diagnosticID = String(UUID().uuidString.prefix(8))
            recordDiagnostic123(operationID: diagnosticID, stage: "改级前", anchorID: nodeID)
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.setLevel(nodeID: nodeID, level: level)],
                label: increaseLevel ? "Sink Node" : "Lift Node"
            )
            guard let result = state.dispatch(transaction) else { return false }
            registerStructuralUndo(from: textViewsByNodeID[nodeID]?.value)
            consume(result: result, refresh: false)
            if let updated = state.node(at: row), let textView = textViewsByNodeID[nodeID]?.value {
                reinstall(node: updated, in: textView, row: row)
                measure(textView: textView, nodeID: nodeID, row: row)
            }
            publishNow()
            recordDiagnostic123(operationID: diagnosticID, stage: "改级后", anchorID: nodeID)
            DispatchQueue.main.async { [weak self] in
                self?.recordDiagnostic123(operationID: diagnosticID, stage: "下一轮", anchorID: nodeID)
            }
            return true
        }

        private func recordDiagnostic123(operationID: String, stage: String, anchorID: UUID) {
            guard let tableView, let anchorRow = state.row(for: anchorID) else { return }
            for row in anchorRow...min(anchorRow + 1, state.snapshot.nodes.count - 1) {
                guard let node = state.node(at: row) else { continue }
                let expectedInset = localLayout(for: node, row: row).spacingBefore
                let geometry = exactGeometries[node.id]
                let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NodeMarkdownProseMirrorCellView
                let message = "[诊断·123·背景裁剪] op=\(operationID) stage=\(stage) row=\(row) node=\(node.id) level=\(node.level) expectedInset=\(expectedInset) actualInset=\(String(describing: cell?.diagnosticTopInset)) geometryHeight=\(String(describing: geometry?.height)) visualBounds=\(String(describing: geometry?.visualBounds)) cellFrame=\(String(describing: cell?.frame)) textFrame=\(String(describing: cell?.textView.frame)) textBounds=\(String(describing: cell?.textView.bounds))"
                TeachingDebugLogStore.append(message, category: "诊断·123·背景裁剪", force: true)
            }
        }

        private func insertImage(at nodeID: UUID, in targetTextView: NodeMarkdownTextKit2TextView) {
            flushActiveNodeForSave()
            guard let row = state.row(for: nodeID),
                  let preparedContent = owner.onRequestInsertImageAtRow?(row),
                  let node = state.node(at: row) else { return }
            var replacement = node
            replacement.content = preparedContent
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceNode(nodeID: nodeID, node: replacement)],
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: nodeID, utf16Offset: replacement.content.utf16.count)),
                label: "Insert Image"
            )
            guard let result = state.dispatch(transaction) else { return }
            registerStructuralUndo(from: targetTextView)
            consume(result: result, refresh: false)
            if let updated = state.node(at: row) {
                let textView = targetTextView
                textViewsByNodeID[nodeID] = WeakTextView(textView)
                nodeIDByTextView[ObjectIdentifier(textView)] = nodeID
                // The open panel temporarily resigns first responder. Reclaim this exact
                // Node before installing text so the inserted link is immediately shown
                // as editable source instead of waiting for another click/blur cycle.
                activeNodeID = nodeID
                baselineNode = node
                owner.onInputSessionStateChange?(true)
                owner.onActiveRowChange?(row)
                reinstall(node: updated, in: textView, row: row)
                _ = textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(
                    NSRange(location: (updated.content as NSString).length, length: 0)
                )
                measure(textView: textView, nodeID: nodeID, row: row)
                reportFocus(textView: textView, row: row)
                pendingFocusNodeID = nil
                pendingFocusOffset = nil
            } else {
                focus(nodeID: nodeID, offset: (replacement.content as NSString).length)
            }
            owner.onEditingDraftDirtyChange?(true)
            publishNow()
        }

        private func replaceNodeText(
            nodeID: UUID,
            in textView: NodeMarkdownTextKit2TextView,
            range: NSRange,
            replacement: String
        ) {
            guard let row = state.row(for: nodeID),
                  let node = state.node(at: row),
                  let safeRange = range.exact(toLength: (node.content as NSString).length) else { return }
            let content = (node.content as NSString).replacingCharacters(in: safeRange, with: replacement)
            var updated = node
            updated.content = content
            let caret = safeRange.location + (replacement as NSString).length
            let selection = NodeMarkdownNodeSelection(anchor: .init(nodeID: nodeID, utf16Offset: caret))
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceNode(nodeID: nodeID, node: updated)],
                selectionAfter: selection,
                label: "Protect Image Link"
            )
            guard let result = state.dispatch(transaction) else { return }
            registerStructuralUndo(from: textView)
            consume(result: result, refresh: false)
            reinstall(node: updated, in: textView, row: row)
            textView.setSelectedRange(NSRange(location: caret, length: 0))
            measure(textView: textView, nodeID: nodeID, row: row)
            owner.onEditingDraftDirtyChange?(true)
            reportFocus(textView: textView, row: row)
            publishNow()
        }

        private func applyInPlaceEditCommand(_ command: NodeMarkdownInPlaceEditCommand, diagnosticID: String?) {
            switch command {
            case let .replaceNodeText(nodeID, content):
                applyReplaceNodeTextInPlace(nodeID: nodeID, content: content)
            case let .synchronize(nodes):
                applySynchronizeInPlace(targetNodes: nodes, diagnosticID: diagnosticID)
            }
        }

        /// 画图插入：只替换单个 Node 的正文，随后发布快照，让父页面重建 document。
        private func applyReplaceNodeTextInPlace(nodeID: UUID, content: String) {
            flushActiveNodeForSave()
            guard let row = state.row(for: nodeID),
                  let node = state.node(at: row),
                  node.content != content else { return }
            var replacement = node
            replacement.content = content
            let selection = NodeMarkdownNodeSelection(
                anchor: .init(nodeID: nodeID, utf16Offset: content.utf16.count)
            )
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceNode(nodeID: nodeID, node: replacement)],
                selectionAfter: selection,
                label: "In-Place Drawing"
            )
            guard let result = state.dispatch(transaction) else { return }
            registerStructuralUndo(from: textViewsByNodeID[nodeID]?.value)
            consume(result: result, refresh: false)
            if let textView = textViewsByNodeID[nodeID]?.value {
                nodeIDByTextView[ObjectIdentifier(textView)] = nodeID
                reinstall(node: replacement, in: textView, row: row)
                measure(textView: textView, nodeID: nodeID, row: row)
            } else {
                refreshRows([row])
            }
            // 该命令在 updateNSView 内触发，把快照发布推迟到下一轮 runloop，
            // 避免在 SwiftUI 视图更新过程中同步修改 @State。
            DispatchQueue.main.async { [weak self] in
                self?.publishNow()
            }
        }

        /// 随堂插入H3包：将 ProseMirror 状态就地同步到父页面已更新好的目标序列。
        /// 父页面已经处理了 document、textKitDraft 与磁盘，因此这里只做结构事务，不发布快照。
        private func applySynchronizeInPlace(targetNodes: [NodeMarkdownTextKit2Node], diagnosticID: String?) {
            let diagnosticID = diagnosticID ?? "-"
            let diagnosticStart = TeachingCourseDiagnostic116.now()
            let current = state.snapshot.nodes
            guard current != targetNodes else {
                TeachingCourseDiagnostic116.record(
                    "op=\(diagnosticID) TextKit2同步跳过 reason=当前与目标相同 nodes=\(current.count)"
                )
                return
            }

            let prefix = commonPrefixCount(current, targetNodes)
            let suffix = commonSuffixCount(current, targetNodes, prefix: prefix)
            let removed = Array(current[prefix..<(current.count - suffix)])
            let inserted = Array(targetNodes[prefix..<(targetNodes.count - suffix)])
            TeachingCourseDiagnostic116.record(
                "op=\(diagnosticID) TextKit2结构差分 current=\(current.count) target=\(targetNodes.count) prefix=\(prefix) suffix=\(suffix) removed=\(removed.count) inserted=\(inserted.count) ready=\(readyRowCount)"
            )

            beginDiagnostic123(inserted: inserted, operation: diagnosticID)
            diagnostic123Snapshot(stage: "结构事务前")
            defer {
                diagnostic123Snapshot(stage: "结构事务返回")
                let token = diagnostic123Token
                for delay in [0.0, 0.3, 1.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self, self.diagnostic123Token == token else { return }
                        self.diagnostic123Snapshot(stage: "延迟\(delay)秒")
                    }
                }
            }
            let removedIDs = Set(removed.map(\.id))
            let insertedIDs = Set(inserted.map(\.id))
            let survivingIDs = Set(current.map(\.id)).subtracting(removedIDs)
            let isClean = removedIDs.isDisjoint(with: insertedIDs)
                && insertedIDs.isDisjoint(with: survivingIDs)
                && !(removed.isEmpty && inserted.isEmpty)
            guard isClean else {
                TeachingCourseDiagnostic116.record(
                    "op=\(diagnosticID) TextKit2结构差分回退 reason=身份集合不干净 removedIDs=\(removedIDs.count) insertedIDs=\(insertedIDs.count) surviving=\(survivingIDs.count)"
                )
                fallBackToFullExternalReload()
                return
            }

            var steps: [NodeMarkdownTransactionStep] = []
            if !removed.isEmpty {
                steps.append(.deleteNodes(nodeIDs: removed.map(\.id)))
            }
            if !inserted.isEmpty {
                steps.append(.insertNodes(row: prefix, nodes: inserted))
            }
            guard !steps.isEmpty else { return }

            applyExternalInPlaceStructuralEdit(
                steps: steps,
                removedCount: removed.count,
                insertedCount: inserted.count,
                anchorRow: prefix,
                diagnosticID: diagnosticID
            )
            TeachingCourseDiagnostic116.record(
                "op=\(diagnosticID) TextKit2同步命令返回 duration=\(String(format: "%.2f", TeachingCourseDiagnostic116.elapsedMilliseconds(since: diagnosticStart)))ms stateNodes=\(state.snapshot.nodes.count) ready=\(readyRowCount)"
            )
        }

        private func applyExternalInPlaceStructuralEdit(
            steps: [NodeMarkdownTransactionStep],
            removedCount: Int,
            insertedCount: Int,
            anchorRow: Int,
            diagnosticID: String
        ) {
            guard let tableView else {
                TeachingCourseDiagnostic116.record("op=\(diagnosticID) TextKit2结构应用回退 reason=tableView不存在")
                fallBackToFullExternalReload()
                return
            }
            commitActiveNode(reason: "就地结构更新")
            structuralEditGeneration &+= 1
            let generation = structuralEditGeneration
            structuralEditInProgress = true
            structuralViewportOrigin = tableView.enclosingScrollView?.contentView.bounds.origin
            pendingFocusNodeID = nil
            pendingFocusOffset = nil
            tableView.window?.makeFirstResponder(tableView)

            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: steps,
                label: "In-Place External Structural Edit"
            )
            guard let result = state.dispatch(transaction) else {
                TeachingCourseDiagnostic116.record("op=\(diagnosticID) TextKit2结构事务失败 reason=dispatch返回nil")
                structuralEditInProgress = false
                structuralViewportOrigin = nil
                fallBackToFullExternalReload()
                return
            }
            registerStructuralUndo(from: nil)

            if anchorRow >= readyRowCount {
                TeachingCourseDiagnostic116.record(
                    "op=\(diagnosticID) TextKit2结构应用尾部路径 anchor=\(anchorRow) ready=\(readyRowCount) removed=\(removedCount) inserted=\(insertedCount) stateNodes=\(state.snapshot.nodes.count)"
                )
                // 插入/删除落在尚未测量的尾部，可见行完全不变。只推进精确布局即可，
                // 不触碰当前表格行，避免把 readyRowCount 清空造成视野跳动。
                cancelExactLayout()
                for id in result.impact.deletedNodeIDs {
                    renderCache.invalidate(nodeID: id)
                    exactGeometries[id] = nil
                    textViewsByNodeID.removeValue(forKey: id)
                }
                for id in result.impact.layoutNodeIDs {
                    guard let row = state.row(for: id) else { continue }
                    installExactStaticGeometry(at: row, notifyTable: false)
                }
                scheduleExactLayout()
                structuralEditInProgress = false
                structuralViewportOrigin = nil
                return
            }

            let removedRows = removedCount > 0
                ? IndexSet(integersIn: anchorRow..<(anchorRow + removedCount))
                : IndexSet()
            let insertedRows = insertedCount > 0
                ? IndexSet(integersIn: anchorRow..<(anchorRow + insertedCount))
                : IndexSet()
            let reloadLower = max(0, anchorRow - 1)
            let reloadUpper = min(state.snapshot.nodes.count, anchorRow + insertedCount + 1)
            let rowsToReload = reloadLower < reloadUpper
                ? IndexSet(integersIn: reloadLower..<reloadUpper)
                : IndexSet()

            applyStructuralTableDelta(
                result: result,
                insertedRows: insertedRows,
                removedRows: removedRows,
                rowsToReload: rowsToReload
            )
            TeachingCourseDiagnostic116.record(
                "op=\(diagnosticID) TextKit2表格增删完成 anchor=\(anchorRow) removed=\(removedRows.count) inserted=\(insertedRows.count) ready=\(readyRowCount) stateNodes=\(state.snapshot.nodes.count)"
            )
            restoreStructuralViewport()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.structuralEditGeneration == generation else { return }
                self.restoreStructuralViewport()
                self.structuralEditInProgress = false
                self.structuralViewportOrigin = nil
            }
        }

        private func beginDiagnostic123(inserted: [NodeMarkdownTextKit2Node], operation: String) {
            diagnostic123Operation = operation
            diagnostic123Token = UUID()
            diagnostic123Counts.removeAll(keepingCapacity: true)
            diagnostic123IDs = []
            let headings = inserted.enumerated().filter { $0.element.level == 3 }
            for (offset, node) in headings.prefix(8) {
                diagnostic123IDs.append(node.id)
                if offset + 1 < inserted.count { diagnostic123IDs.append(inserted[offset + 1].id) }
            }
            diagnostic123Until = ProcessInfo.processInfo.systemUptime + 120
            TeachingH3InsertDiagnostic123.record("op=\(operation) stage=同步目标 inserted=\(inserted.count) H3=\(headings.count) tracked=\(diagnostic123IDs.count) limitH3=8")
            for node in inserted.lazy.filter({ $0.level == 3 }).prefix(8) {
                TeachingH3InsertDiagnostic123.record("op=\(operation) stage=目标H3 node=\(node.id) sourceID=\(node.sourceID) level=\(node.level) chars=\(node.content.utf16.count)")
            }
        }

        private func diagnostic123Event(nodeID: UUID?, stage: String) {
            guard let nodeID, diagnostic123IDs.contains(nodeID),
                  ProcessInfo.processInfo.systemUptime < diagnostic123Until else { return }
            let key = "\(stage)/\(nodeID)"
            let count = diagnostic123Counts[key, default: 0]
            guard count < 2 else { return }
            diagnostic123Counts[key] = count + 1
            diagnostic123Snapshot(stage: stage, only: nodeID)
        }

        /// 只观察已有缓存与已有Cell；不创建Cell、不触发测量或布局、不移动视口。
        private func diagnostic123Snapshot(stage: String, only: UUID? = nil) {
            guard !diagnostic123IDs.isEmpty else { return }
            let width = viewportLayoutWidth()
            for id in diagnostic123IDs where only == nil || only == id {
                guard let row = state.row(for: id), let node = state.node(at: row) else {
                    TeachingH3InsertDiagnostic123.record("op=\(diagnostic123Operation) stage=\(stage) node=\(id) stateMissing=true")
                    continue
                }
                let geometry = exactGeometries[id]
                let valid = geometry?.key == exactLayoutKey(for: id, width: width)
                let tableRows = tableView?.numberOfRows ?? 0
                let cell = row < tableRows
                    ? tableView?.view(atColumn: 0, row: row, makeIfNecessary: false) as? NodeMarkdownProseMirrorCellView : nil
                let rowRect = row < tableRows ? tableView?.rect(ofRow: row) : nil
                let visible = rowRect.map { tableView?.visibleRect.intersects($0) == true } ?? false
                TeachingH3InsertDiagnostic123.record(
                    "op=\(diagnostic123Operation) stage=\(stage) node=\(id) row=\(row) level=\(node.level) chars=\(node.content.utf16.count) stateNodes=\(state.snapshot.nodes.count) ready=\(readyRowCount) tableRows=\(tableRows) cacheValid=\(valid) cachedHeight=\(String(describing: geometry?.height)) rowRect=\(String(describing: rowRect)) visible=\(visible) cell=\(cell != nil) cellNode=\(String(describing: cell?.nodeID)) hidden=\(String(describing: cell?.isHidden)) cellFrame=\(String(describing: cell?.frame)) textFrame=\(String(describing: cell?.textView.frame)) inset=\(String(describing: cell?.diagnosticTopInset)) renderedChars=\(String(describing: cell?.textView.string.utf16.count))"
                )
            }
        }

        private func fallBackToFullExternalReload() {
            captureViewportAnchor()
            commitActiveNode(reason: "就地同步回退")
            guard state.replace(text: owner.text, rowMetadata: owner.rowMetadata) else { return }
            editorUndoManager.removeAllActions()
            invalidateExactLayout()
            renderCache.removeAll()
            activeNodeID = nil
            baselineNode = nil
            tableView?.reloadData()
            scheduleExactLayout()
        }

        private func commonPrefixCount(
            _ a: [NodeMarkdownTextKit2Node],
            _ b: [NodeMarkdownTextKit2Node]
        ) -> Int {
            var index = 0
            while index < a.count && index < b.count && a[index] == b[index] {
                index += 1
            }
            return index
        }

        private func commonSuffixCount(
            _ a: [NodeMarkdownTextKit2Node],
            _ b: [NodeMarkdownTextKit2Node],
            prefix: Int
        ) -> Int {
            var index = 0
            while index < a.count - prefix && index < b.count - prefix {
                if a[a.count - 1 - index] != b[b.count - 1 - index] {
                    break
                }
                index += 1
            }
            return index
        }

        private func focus(nodeID: UUID, offset: Int) {
            guard let row = state.row(for: nodeID), let tableView else { return }
            pendingFocusNodeID = nodeID
            pendingFocusOffset = offset
            guard row < readyRowCount else {
                scheduleExactLayout()
                return
            }
            let rowRect = tableView.rect(ofRow: row)
            if !tableView.visibleRect.intersects(rowRect) {
                tableView.scrollRowToVisible(row)
            }
            tableView.layoutSubtreeIfNeeded()
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? NodeMarkdownProseMirrorCellView {
                let textView = cell.textView
                guard textView.window?.makeFirstResponder(textView) == true,
                      textView.window?.firstResponder === textView,
                      nodeIDByTextView[ObjectIdentifier(textView)] == nodeID,
                      let node = state.node(at: row) else {
                    scheduleExactLayout()
                    return
                }

                // AppKit does not guarantee another textDidBeginEditing callback when
                // focus moves directly between row editors. Establish editing ownership
                // explicitly before setting the caret, so the complete trailing source
                // receives this Node's editing typography before the next keystroke.
                activateNode(
                    node: node,
                    row: row,
                    in: textView,
                    origin: "程序化焦点接管"
                )
                let sourceLength = (textView.nodeSourceTextSnapshot as NSString).length
                let selection = NSRange(location: min(max(0, offset), sourceLength), length: 0)
                textView.setSelectedRange(selection)
                pendingFocusNodeID = nil
                pendingFocusOffset = nil
                if structuralEditInProgress {
                    structuralEditInProgress = false
                    restoreStructuralViewport()
                    structuralViewportOrigin = nil
                }
                scheduleCaretVisibility(textView: textView, nodeID: nodeID)
            }
        }

        /// 像文字处理器一样，让输入光标始终停留在上下边界内侧。
        /// 普通输入、软换行、拼音组合态和回车后的新Node共用这一条路径。
        private func scheduleCaretVisibility(
            textView: NodeMarkdownTextKit2TextView,
            nodeID: UUID,
            allowsActiveComposition: Bool = false
        ) {
            caretVisibilityWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.scrollCaretIntoComfortZone(
                    textView: textView,
                    nodeID: nodeID,
                    allowsActiveComposition: allowsActiveComposition
                )
            }
            caretVisibilityWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
        }

        private func scrollCaretIntoComfortZone(
            textView: NodeMarkdownTextKit2TextView,
            nodeID: UUID,
            allowsActiveComposition: Bool
        ) {
            guard textView.window?.firstResponder === textView,
                  nodeIDByTextView[ObjectIdentifier(textView)] == nodeID,
                  let row = state.row(for: nodeID),
                  row < readyRowCount,
                  let tableView,
                  let scrollView = tableView.enclosingScrollView else { return }

            let selection = textView.selectedRange()
            guard selection.length == 0 else { return }
            _ = allowsActiveComposition

            textView.suppressesAutomaticSelectionScrolling = false
            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            let viewport = scrollView.contentView.bounds
            let comfortMargin = bottomPageMarginHeight
            var caretRect = rowRect
            let screenRect = textView.firstRect(forCharacterRange: selection, actualRange: nil)
            if !screenRect.isNull,
               screenRect.height > 0,
               let window = textView.window {
                caretRect = tableView.convert(window.convertFromScreen(screenRect), from: nil)
            }

            let scrollDelta: CGFloat
            if caretRect.minY < viewport.minY + comfortMargin {
                scrollDelta = caretRect.minY - (viewport.minY + comfortMargin)
            } else if caretRect.maxY > viewport.maxY - comfortMargin {
                scrollDelta = caretRect.maxY - (viewport.maxY - comfortMargin)
            } else {
                return
            }
            guard abs(scrollDelta) > 0.5 else { return }

            var bounds = viewport
            bounds.origin.y += scrollDelta
            let target = scrollView.contentView.constrainBoundsRect(bounds).origin
            scrollView.contentView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func navigate(to row: Int, in scrollView: NSScrollView) {
            guard let tableView else { return }
            guard row < readyRowCount else {
                pendingNavigationRow = row
                scheduleExactLayout()
                return
            }
            pendingNavigationRow = nil
            tableView.scrollRowToVisible(row)
            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            var bounds = scrollView.contentView.bounds
            bounds.origin.y = max(0, rowRect.minY - NodeMarkdownTextKit2NavigationPolicy.targetTopPadding)
            scrollView.contentView.setBoundsOrigin(scrollView.contentView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func measure(
            textView: NodeMarkdownTextKit2TextView,
            nodeID: UUID,
            row: Int,
            transient: Bool = false
        ) {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.recordDuration(
                    transient ? "编辑态瞬时测量" : "可见Node测量",
                    since: diagnosticStart,
                    details: "row=\(row)"
                )
            }
            guard state.row(for: nodeID) == row,
                  let node = state.node(at: row) else { return }
            let width = viewportLayoutWidth(fallback: textView.bounds.width)
            textView.nodeTextContainer.containerSize = NSSize(
                width: max(1, width - textView.textContainerInset.width * 2),
                height: .greatestFiniteMagnitude
            )
            guard let bounds = textView.exactNodeMarkdownVisualBounds() else { return }
            let contentHeight = ceil(max(0, bounds.maxY) + textView.textContainerInset.height)
            guard contentHeight.isFinite, contentHeight > 0 else { return }
            let previous = exactGeometries[nodeID]?.height
            let key = exactLayoutKey(for: nodeID, width: width)
            let layout = localLayout(for: node, row: row)
            let geometry = NodeMarkdownExactGeometry.block(
                key: key,
                contentHeight: contentHeight,
                spacingBefore: layout.spacingBefore,
                fragmentCount: textView.exactNodeMarkdownLayoutFragmentCount(),
                contentVisualBounds: bounds
            )
            exactGeometries[nodeID] = geometry
            synchronizeVisibleCellInset(nodeID: nodeID, row: row, inset: layout.spacingBefore)
            if !transient {
                renderCache.invalidate(nodeID: nodeID)
            }
            guard row < readyRowCount, previous == nil || abs(previous! - geometry.height) > 0.5 else { return }
            tableView?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        }

        private func scheduleTransientMeasurement(
            textView: NodeMarkdownTextKit2TextView,
            nodeID: UUID
        ) {
            transientMeasurementGeneration &+= 1
            let generation = transientMeasurementGeneration
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView,
                      self.transientMeasurementGeneration == generation,
                      self.nodeIDByTextView[ObjectIdentifier(textView)] == nodeID,
                      let row = self.state.row(for: nodeID) else { return }
                self.measure(
                    textView: textView,
                    nodeID: nodeID,
                    row: row,
                    transient: true
                )
                self.scheduleCaretVisibility(
                    textView: textView,
                    nodeID: nodeID,
                    allowsActiveComposition: true
                )
            }
        }

        private func exactLayoutKey(for nodeID: UUID, width: CGFloat) -> NodeMarkdownExactLayoutKey {
            let scale = actualBackingScale()
            return NodeMarkdownExactLayoutKey(
                documentID: state.documentID,
                nodeID: nodeID,
                nodeRevision: state.nodeRevision(for: nodeID),
                styleRevision: documentStyleRevision,
                widthPixels: Int((width * scale).rounded()),
                scaleMilli: Int((scale * 1_000).rounded())
            )
        }

        private func cacheKey(for nodeID: UUID, row: Int, width: CGFloat) -> NodeMarkdownTextKit2RenderCacheKey {
            let scale = actualBackingScale()
            return NodeMarkdownTextKit2RenderCacheKey(
                documentID: state.documentID,
                nodeID: nodeID,
                nodeRevision: state.nodeRevision(for: nodeID),
                styleRevision: documentStyleRevision,
                visualRevision: presentationRevision(for: nodeID, row: row),
                width: Int((width * scale).rounded()),
                scaleMilli: Int((scale * 1_000).rounded())
            )
        }

        private func actualBackingScale() -> CGFloat {
            guard let tableView else { return 1 }
            let converted = tableView.convertToBacking(NSSize(width: 1, height: 1)).width
            return converted.isFinite && converted > 0 ? converted : 1
        }

        /// One width authority for measurement, cache keys and live TextKit containers.
        /// Overlay scrollers do not subtract from this viewport, and NSTableView's own
        /// document-frame adjustments are deliberately excluded.
        private func viewportLayoutWidth(fallback: CGFloat = 1) -> CGFloat {
            let width = tableView?.enclosingScrollView?.contentView.bounds.width ?? fallback
            return width.isFinite && width > 0 ? width : max(1, fallback)
        }

        private func presentationRevision(for nodeID: UUID, row: Int) -> UInt64 {
            var hasher = Hasher()
            hasher.combine(owner.searchQuery)
            let isSearchTarget = owner.activeRowIndex == row
            hasher.combine(isSearchTarget)
            if isSearchTarget { hasher.combine(owner.activeMatchLocationInRow) }
            hasher.combine(owner.editingRowIndex == row)
            hasher.combine(activeNodeID == nodeID)
            return UInt64(bitPattern: Int64(hasher.finalize()))
        }

        private func renderRecord(
            for node: NodeMarkdownTextKit2Node,
            row: Int,
            width: CGFloat
        ) -> NodeMarkdownBlockRenderRecord? {
            let key = cacheKey(for: node.id, row: row, width: width)
            if let cached = renderCache[key], cached.node == node, cached.row == row {
                diagnostic114.recordCount("渲染缓存命中")
                return cached
            }
            guard let geometry = exactGeometries[node.id],
                  geometry.key == exactLayoutKey(for: node.id, width: width) else {
                diagnostic114.recordCount("渲染缓存缺失几何")
                return nil
            }
            diagnostic114.recordCount("渲染缓存重建")
            let record = NodeMarkdownBlockRenderRecord(
                key: key,
                node: node,
                row: row,
                layout: localLayout(for: node, row: row),
                height: geometry.height,
                isMeasured: true
            )
            renderCache[key] = record
            return record
        }

        private func refreshRows(_ rows: Set<Int>) {
            guard let tableView else { return }
            guard activeNodeID == nil else { return }
            let valid = IndexSet(rows.filter { state.snapshot.nodes.indices.contains($0) })
            guard !valid.isEmpty else { return }
            tableView.reloadData(forRowIndexes: valid, columnIndexes: IndexSet(integer: 0))
        }

        private func refreshVisibleNodesForStateOnly() {
            guard let tableView else { return }
            // NSTableView may terminate its field editor even when a different visible row
            // is reloaded. While a Node owns focus, all other Node views stay immutable.
            guard activeNodeID == nil else { return }
            let visible = tableView.rows(in: tableView.visibleRect)
            if visible.location != NSNotFound {
                let rows = IndexSet(integersIn: visible.location..<NSMaxRange(visible))
                guard !rows.isEmpty else { return }
                tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
            }
        }

        private func prepareForViewportWidthChange(to width: CGFloat) {
            guard width.isFinite, width > 0 else { return }
            let scale = actualBackingScale()
            let oldPixels = Int((exactLayoutWidth * exactLayoutScale).rounded())
            let newPixels = Int((width * scale).rounded())
            let oldScaleMilli = Int((exactLayoutScale * 1_000).rounded())
            let newScaleMilli = Int((scale * 1_000).rounded())
            guard oldPixels != newPixels || oldScaleMilli != newScaleMilli else { return }
            diagnostic114.recordCount("宽度全文重排次数")

            captureViewportAnchor()
            cancelExactLayout()
            exactLayoutWidth = width
            exactLayoutScale = scale
            exactGeometries.removeAll(keepingCapacity: true)
            renderCache.removeAll()
            readyRowCount = 0
            initialViewportIsReady = false
            viewportWidthTransitionPending = true
        }

        private func handleViewportWidthChange() {
            guard let tableView else { return }
            let width = viewportLayoutWidth()
            guard width > 0 else { return }
            if !viewportWidthTransitionPending {
                let scale = actualBackingScale()
                let oldPixels = Int((exactLayoutWidth * exactLayoutScale).rounded())
                let newPixels = Int((width * scale).rounded())
                let oldScaleMilli = Int((exactLayoutScale * 1_000).rounded())
                let newScaleMilli = Int((scale * 1_000).rounded())
                if oldPixels == newPixels, oldScaleMilli == newScaleMilli {
                    scheduleExactLayout()
                    return
                }
                prepareForViewportWidthChange(to: width)
            }
            viewportWidthTransitionPending = false
            tableView.reloadData()
            scheduleExactLayout()
        }

        private func requestExactLayoutRecovery() {
            guard !exactLayoutRecoveryScheduled else { return }
            diagnostic114.recordCount("布局恢复次数")
            exactLayoutRecoveryScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.exactLayoutRecoveryScheduled = false
                guard let tableView = self.tableView else { return }
                let width = self.viewportLayoutWidth()
                guard width > 0 else { return }
                self.cancelExactLayout()
                self.exactLayoutWidth = width
                self.exactLayoutScale = self.actualBackingScale()
                self.exactGeometries.removeAll(keepingCapacity: true)
                self.renderCache.removeAll()
                self.readyRowCount = 0
                self.initialViewportIsReady = false
                self.viewportWidthTransitionPending = false
                tableView.reloadData()
                self.scheduleExactLayout()
            }
        }

        private func consume(result: NodeMarkdownTransactionResult, refresh: Bool) {
            for id in result.impact.deletedNodeIDs {
                renderCache.invalidate(nodeID: id)
                exactGeometries[id] = nil
            }
            if result.impact.isStructural {
                cancelExactLayout()
                let livingIDs = Set(state.snapshot.nodes.map(\.id))
                renderCache.retain(nodeIDs: livingIDs)
                exactGeometries = exactGeometries.filter { livingIDs.contains($0.key) }
                for id in result.impact.layoutNodeIDs {
                    guard let row = state.row(for: id) else { continue }
                    installExactStaticGeometry(at: row)
                }
                recomputeReadyPrefix()
                tableView?.noteNumberOfRowsChanged()
                scheduleExactLayout()
            } else {
                for id in result.impact.layoutNodeIDs where id != activeNodeID {
                    guard let row = state.row(for: id) else { continue }
                    installExactStaticGeometry(at: row)
                }
            }
            if refresh, activeNodeID == nil {
                let rows = Set(result.impact.layoutNodeIDs.compactMap { state.row(for: $0) })
                refreshRows(rows)
            }
        }

        private func viewportDidChange() {
            diagnostic114.recordCount("视口变化次数")
            scheduleExactLayout()
            diagnostic114.flushIfNeeded(reason: "滚动", readyRows: readyRowCount)
        }

        private func matchesCurrentDocument(
            text: String,
            rowMetadata: [NodeMarkdownTextKitRowMetadata]
        ) -> Bool {
            let snapshot = state.snapshot
            return snapshot.plainText == text && snapshot.rowMetadata == rowMetadata
        }

        private func captureViewportAnchor() {
            guard pendingViewportAnchor == nil,
                  let tableView,
                  let scrollView = tableView.enclosingScrollView else { return }
            let visibleRect = scrollView.contentView.bounds
            let visibleRows = tableView.rows(in: visibleRect)
            guard visibleRows.location != NSNotFound,
                  visibleRows.location < readyRowCount,
                  let node = state.node(at: visibleRows.location) else { return }
            let rowRect = tableView.rect(ofRow: visibleRows.location)
            pendingViewportAnchor = ViewportAnchor(
                nodeID: node.id,
                offsetFromRowTop: visibleRect.minY - rowRect.minY,
                fallbackOrigin: visibleRect.origin
            )
        }

        private func restorePendingViewportAnchorIfPossible() {
            guard let anchor = pendingViewportAnchor,
                  let tableView,
                  let scrollView = tableView.enclosingScrollView else { return }
            var requestedOrigin = anchor.fallbackOrigin
            if let row = state.row(for: anchor.nodeID) {
                guard row < readyRowCount else { return }
                requestedOrigin.y = tableView.rect(ofRow: row).minY + anchor.offsetFromRowTop
            } else {
                guard readyRowCount == state.snapshot.nodes.count else { return }
            }
            var bounds = scrollView.contentView.bounds
            bounds.origin = requestedOrigin
            scrollView.contentView.setBoundsOrigin(
                scrollView.contentView.constrainBoundsRect(bounds).origin
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            pendingViewportAnchor = nil
        }

        private func invalidateExactLayout(startingAt row: Int = 0) {
            diagnostic114.recordCount("布局失效次数")
            cancelExactLayout()
            let start = max(0, min(row, state.snapshot.nodes.count))
            if start == 0 {
                exactGeometries.removeAll(keepingCapacity: true)
                initialViewportIsReady = false
            } else {
                for node in state.snapshot.nodes[start...] { exactGeometries[node.id] = nil }
            }
            readyRowCount = min(readyRowCount, start)
            tableView?.noteNumberOfRowsChanged()
        }

        private func cancelExactLayout() {
            if exactLayoutTask != nil {
                diagnostic114.recordCount("布局任务取消次数")
            }
            exactLayoutTask?.cancel()
            exactLayoutTask = nil
            exactLayoutGeneration &+= 1
        }

        private func scheduleExactLayout() {
            guard exactLayoutTask == nil else { return }
            guard let tableView,
                  viewportLayoutWidth() > 0,
                  (tableView.enclosingScrollView?.contentView.bounds.height ?? 0) > 0 else {
                return
            }
            guard readyRowCount < state.snapshot.nodes.count else { return }
            exactLayoutWidth = viewportLayoutWidth()
            exactLayoutScale = actualBackingScale()
            exactLayoutGeneration &+= 1
            let generation = exactLayoutGeneration
            exactLayoutTask = Task { [weak self] in
                guard let self else { return }
                await self.buildExactLayout(generation: generation)
            }
        }

        private func installExactStaticGeometry(at row: Int, notifyTable: Bool = true) {
            guard let tableView, let node = state.node(at: row) else { return }
            let width = viewportLayoutWidth()
            let key = exactLayoutKey(for: node.id, width: width)
            guard let geometry = exactLayoutEngine.measure(
                key: key,
                documentRow: row,
                node: node,
                layout: localLayout(for: node, row: row),
                width: width,
                documentStyle: owner.documentStyle,
                baseDirectoryURL: owner.workingDirectoryURL,
                diagnostic114: diagnostic114
            ) else { return }
            let oldHeight = exactGeometries[node.id]?.height
            exactGeometries[node.id] = geometry
            synchronizeVisibleCellInset(
                nodeID: node.id,
                row: row,
                inset: localLayout(for: node, row: row).spacingBefore
            )
            renderCache.invalidate(nodeID: node.id)
            if notifyTable,
               row < readyRowCount,
               oldHeight == nil || abs(oldHeight! - geometry.height) > 0.5 {
                tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            }
        }

        /// Geometry includes spacingBefore; the existing cell must reserve that
        /// same amount before its height changes, without replacing its editor.
        private func synchronizeVisibleCellInset(nodeID: UUID, row: Int, inset: CGFloat) {
            guard let tableView,
                  row >= 0, row < tableView.numberOfRows,
                  let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NodeMarkdownProseMirrorCellView,
                  cell.nodeID == nodeID else { return }
            cell.setContentTopInset(inset)
        }

        private func recomputeReadyPrefix() {
            guard tableView != nil else {
                readyRowCount = 0
                return
            }
            let width = viewportLayoutWidth()
            var count = 0
            for node in state.snapshot.nodes {
                guard let geometry = exactGeometries[node.id],
                      geometry.key == exactLayoutKey(for: node.id, width: width) else { break }
                count += 1
            }
            readyRowCount = count
            initialViewportIsReady = count > 0
        }

        private func fulfillPendingNavigationIfPossible() {
            guard let row = pendingNavigationRow,
                  row < readyRowCount,
                  let scroll = tableView?.enclosingScrollView else { return }
            navigate(to: row, in: scroll)
        }

        private func fulfillPendingFocusIfPossible() {
            guard let nodeID = pendingFocusNodeID,
                  let row = state.row(for: nodeID),
                  row < readyRowCount else { return }
            focus(nodeID: nodeID, offset: pendingFocusOffset ?? 0)
        }

        private func buildExactLayout(generation: UInt64) async {
            guard let tableView else { return }
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            let startingRow = readyRowCount
            defer {
                diagnostic114.recordDuration(
                    "精确布局任务",
                    since: diagnosticStart,
                    slowThresholdMilliseconds: 16,
                    details: "start=\(startingRow) end=\(readyRowCount)"
                )
            }
            let width = exactLayoutWidth
            let viewportHeight = tableView.enclosingScrollView?.contentView.bounds.height ?? 0
            var accumulatedHeight: CGFloat = 0
            var unpublishedStart = readyRowCount
            var row = readyRowCount
            while row < state.snapshot.nodes.count, !Task.isCancelled, generation == exactLayoutGeneration {
                guard let node = state.node(at: row) else { break }
                let key = exactLayoutKey(for: node.id, width: width)
                let layout = localLayout(for: node, row: row)
                let nodeMeasureStart = NodeMarkdownDiagnostic114.now()
                guard let geometry = exactLayoutEngine.measure(
                    key: key,
                    documentRow: row,
                    node: node,
                    layout: layout,
                    width: width,
                    documentStyle: owner.documentStyle,
                    baseDirectoryURL: owner.workingDirectoryURL,
                    diagnostic114: diagnostic114
                ) else { break }
                diagnostic114.recordDuration(
                    "精确布局单Node",
                    since: nodeMeasureStart,
                    details: "row=\(row) nodeUTF16=\(node.content.utf16.count) fragments=\(geometry.fragmentCount)"
                )
                diagnostic114.recordCount("精确布局Node数")
                exactGeometries[node.id] = geometry
                accumulatedHeight += geometry.height
                row += 1

                let completedInitialViewport = !initialViewportIsReady && accumulatedHeight >= viewportHeight
                let completedBatch = initialViewportIsReady && row - unpublishedStart >= 12
                let completedDocument = row == state.snapshot.nodes.count
                if completedInitialViewport || completedBatch || completedDocument {
                    let publishStart = NodeMarkdownDiagnostic114.now()
                    readyRowCount = row
                    initialViewportIsReady = true
                    tableView.noteNumberOfRowsChanged()
                    restorePendingViewportAnchorIfPossible()
                    fulfillPendingNavigationIfPossible()
                    fulfillPendingFocusIfPossible()
                    unpublishedStart = row
                    diagnostic114.recordDuration("布局批次发布", since: publishStart)
                    diagnostic114.recordCount("布局批次数")
                    diagnostic114.flushIfNeeded(
                        reason: completedInitialViewport ? "首屏就绪" : (completedDocument ? "全文布局完成" : "布局批次"),
                        readyRows: readyRowCount,
                        force: completedInitialViewport || completedDocument
                    )
                }
                await Task.yield()
            }
            if generation == exactLayoutGeneration {
                if readyRowCount < row {
                    readyRowCount = row
                    initialViewportIsReady = true
                    tableView.noteNumberOfRowsChanged()
                    restorePendingViewportAnchorIfPossible()
                    fulfillPendingNavigationIfPossible()
                    fulfillPendingFocusIfPossible()
                }
                exactLayoutTask = nil
                diagnostic114.flushIfNeeded(reason: "布局任务结束", readyRows: readyRowCount, force: true)
            }
        }

        private func schedulePublish() {
            publishWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.publishNow() }
            publishWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }

        private func publishNow() {
            let diagnosticStart = NodeMarkdownDiagnostic114.now()
            defer {
                diagnostic114.recordDuration("发布文档快照", since: diagnosticStart, slowThresholdMilliseconds: 8)
                diagnostic114.flushIfNeeded(reason: "发布快照", readyRows: readyRowCount)
            }
            cancelPendingPublish()
            let snapshot = state.snapshot
            if let onDocumentSnapshot = owner.onDocumentSnapshot {
                onDocumentSnapshot(
                    NodeMarkdownLegacyDocumentSnapshot(
                        sessionID: sessionID,
                        revision: snapshot.revision,
                        rows: snapshot.nodes.map {
                            .init(nodeID: $0.id.uuidString, level: $0.level, content: $0.content, sourceID: $0.sourceID, sourceFile: $0.sourceFile)
                        }
                    )
                )
            } else {
                publishProjectionFallback()
            }
        }

        private func publishProjectionFallback() {
            let snapshot = state.snapshot
            if let onTextChangeWithRowMetadata = owner.onTextChangeWithRowMetadata {
                onTextChangeWithRowMetadata(snapshot.plainText, snapshot.rowMetadata)
            } else {
                owner.text = snapshot.plainText
                owner.onTextChange?(snapshot.plainText)
            }
        }

        private func installDraftController(_ controller: NodeMarkdownLegacyDraftCommitController?) {
            controller?.install(
                commit: { [weak self] in
                    self?.flushActiveNodeForSave()
                },
                focusRowEnd: { [weak self] row in
                    guard let self, let node = self.state.node(at: row) else { return }
                    self.focus(nodeID: node.id, offset: node.content.utf16.count)
                }
            )
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
        }

        private func registerStructuralUndo(from textView: NSTextView?) {
            let undoManager = editorUndoManager
            textView?.breakUndoCoalescing()
            lastNativeEditNodeID = nil
            undoManager.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: undoManager)
            }
        }

        private func performStructuralUndo(using undoManager: UndoManager?) {
            guard applyHistoryChange(redo: false) else { return }
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralRedo(using: undoManager)
            }
        }

        private func performStructuralRedo(using undoManager: UndoManager?) {
            guard applyHistoryChange(redo: true) else { return }
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: undoManager)
            }
        }

        @discardableResult
        private func applyHistoryChange(redo: Bool) -> Bool {
            guard !structuralEditInProgress,
                  redo ? state.canRedo : state.canUndo else { return false }
            let oldIDs = state.snapshot.nodes.map(\.id)
            // End the current field editor before replacing table rows. Otherwise
            // its stale source projection can conceal (or overwrite) restored text.
            if let nodeID = activeNodeID,
               let textView = textViewsByNodeID[nodeID]?.value {
                guard beginStructuralEdit(nodeID: nodeID, textView: textView) else { return false }
            } else {
                structuralEditInProgress = true
                structuralEditGeneration &+= 1
                structuralViewportOrigin = tableView?.enclosingScrollView?.contentView.bounds.origin
            }
            guard let result = redo ? state.redo() : state.undo() else {
                cancelStructuralEdit()
                return false
            }
            let newIDs = state.snapshot.nodes.map(\.id)
            let oldSet = Set(oldIDs)
            let newSet = Set(newIDs)
            let removed = IndexSet(oldIDs.indices.filter { !newSet.contains(oldIDs[$0]) })
            let inserted = IndexSet(newIDs.indices.filter { !oldSet.contains(newIDs[$0]) })
            let affectedRows = IndexSet(result.impact.layoutNodeIDs.compactMap { state.row(for: $0) })
            let selection = result.mappedSelection
            let targetID = selection?.anchor.nodeID
                ?? affectedRows.first.flatMap { state.node(at: $0)?.id }
                ?? newIDs.first
            guard let targetID, let targetRow = state.row(for: targetID) else {
                cancelStructuralEdit()
                return false
            }
            finishStructuralEdit(
                result: result,
                targetNodeID: targetID,
                targetRow: targetRow,
                targetOffset: selection.map { max($0.anchor.utf16Offset, $0.head.utf16Offset) } ?? 0,
                insertedRows: inserted,
                removedRows: removed,
                rowsToReload: affectedRows
            )
            // Restore focus immediately when the affected row is already visible.
            // finishStructuralEdit also retries after AppKit completes row updates.
            fulfillPendingFocusIfPossible()
            if let selection,
               selection.anchor.nodeID == selection.head.nodeID,
               let textView = textViewsByNodeID[targetID]?.value {
                let end = max(selection.anchor.utf16Offset, selection.head.utf16Offset)
                let range = NSRange(location: end, length: 0)
                if range.exact(toLength: textView.nodeSourceTextSnapshot.utf16.count) != nil {
                    textView.setSelectedRange(range)
                }
                textView.needsLayout = true
                textView.setNeedsDisplay(textView.bounds)
            }
            return true
        }

        private func reportFocus(textView: NSTextView, row: Int) {
            let selection = textView.selectedRange()
            owner.onFocusLocationChange?(
                NodeMarkdownTextFocusLocation(rowIndex: row, location: selection.location, length: selection.length, column: selection.location)
            )
        }

        private func draft(for node: NodeMarkdownTextKit2Node) -> NodeMarkdownLegacyEditingNodeDraft {
            NodeMarkdownLegacyEditingNodeDraft(
                nodeID: node.id.uuidString,
                level: node.level,
                content: node.content,
                sourceID: node.sourceID,
                sourceFile: node.sourceFile
            )
        }

        private func pruneDeadTextViews() {
            textViewsByNodeID = textViewsByNodeID.filter { $0.value.value != nil }
            let living = Set(textViewsByNodeID.values.compactMap { $0.value }.map(ObjectIdentifier.init))
            nodeIDByTextView = nodeIDByTextView.filter { living.contains($0.key) }
        }

        private func short(_ id: UUID?) -> String {
            id.map { String($0.uuidString.prefix(8)) } ?? "nil"
        }

        private func containsImageSource(_ text: String) -> Bool {
            text.contains("![") || text.contains("🌼[图片]") || text.contains("{图片}")
        }
    }
}

private struct VisualState: Equatable {
    let styleIdentity: NodeMarkdownDocumentStyleRecord
    let activeRow: Int?
    let match: Int?
    let editingRow: Int?
    let query: String

    init(owner: NodeMarkdownProseMirrorRepresentable) {
        styleIdentity = owner.documentStyle.renderIdentity
        activeRow = owner.activeRowIndex
        match = owner.activeMatchLocationInRow
        editingRow = owner.editingRowIndex
        query = owner.searchQuery
    }
}

private struct ViewportAnchor {
    let nodeID: UUID
    let offsetFromRowTop: CGFloat
    let fallbackOrigin: NSPoint
}

private struct NodeMarkdownBlockRenderRecord {
    let key: NodeMarkdownTextKit2RenderCacheKey
    let node: NodeMarkdownTextKit2Node
    let row: Int
    let layout: NodeMarkdownTextKit2RowLayout
    let height: CGFloat
    let isMeasured: Bool
}

private final class NodeMarkdownProseMirrorTableView: NSTableView {
    var onWidthWillChange: ((CGFloat) -> Void)?
    var onWidthChange: (() -> Void)?
    private var lastReportedWidth: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
        DispatchQueue.main.async { [weak self] in self?.reportViewportWidthIfNeeded() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        var constrainedSize = newSize
        if let viewportWidth = stableViewportWidth(), viewportWidth > 0 {
            constrainedSize.width = viewportWidth
        }
        super.setFrameSize(constrainedSize)
        synchronizeColumnWidth(to: constrainedSize.width)
        reportViewportWidthIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        reportViewportWidthIfNeeded(force: true)
    }

    private func stableViewportWidth() -> CGFloat? {
        guard let width = enclosingScrollView?.contentView.bounds.width,
              width.isFinite,
              width > 0 else { return nil }
        return width
    }

    /// NSTableView 的 column autoresizing 并不总是把单列可靠地撑满 table 宽度，
    /// 一旦 column 比 table 窄，cell/textView 的实际宽度就会比测量用的 viewport
    /// 宽度小，进而让换行边界分叉。这里显式同步，保证渲染与测量用同一个宽度。
    private func synchronizeColumnWidth(to width: CGFloat) {
        guard width.isFinite, width > 0, let column = tableColumns.first else { return }
        if abs(column.width - width) > 0.5 {
            column.width = width
        }
    }

    private func reportViewportWidthIfNeeded(force: Bool = false) {
        guard let width = stableViewportWidth() else { return }
        let changed = force || abs(width - lastReportedWidth) > 0.5
        guard changed else { return }
        lastReportedWidth = width
        onWidthWillChange?(width)
        DispatchQueue.main.async { [weak self] in self?.onWidthChange?() }
    }
}

final class NodeMarkdownProseMirrorContainerView: NSView {
    let scrollView: NSScrollView
    private let bottomFrameView = NSView()

    init(scrollView: NSScrollView, bottomFrameHeight: CGFloat) {
        self.scrollView = scrollView
        super.init(frame: .zero)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        bottomFrameView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(bottomFrameView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomFrameView.topAnchor),
            bottomFrameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomFrameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomFrameView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomFrameView.heightAnchor.constraint(equalToConstant: bottomFrameHeight)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class NodeMarkdownProseMirrorCellView: NSTableCellView {
    let textView = NodeMarkdownTextKit2TextView()
    var nodeID: UUID?
    var renderedKey: NodeMarkdownTextKit2RenderCacheKey?
    private var contentTopConstraint: NSLayoutConstraint!
    var diagnosticTopInset: CGFloat { contentTopConstraint.constant }

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        contentTopConstraint = textView.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentTopConstraint,
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func setContentTopInset(_ inset: CGFloat) {
        let value = max(0, inset)
        guard contentTopConstraint.constant != value else { return }
        contentTopConstraint.constant = value
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class WeakTextView {
    weak var value: NodeMarkdownTextKit2TextView?
    init(_ value: NodeMarkdownTextKit2TextView) { self.value = value }
}
#endif
