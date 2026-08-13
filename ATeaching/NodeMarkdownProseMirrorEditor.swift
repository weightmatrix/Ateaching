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

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(owner: self, scrollView: scrollView)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.commitActiveNode(reason: "关闭编辑器")
        coordinator.cancelPendingPublish()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
        private var owner: NodeMarkdownProseMirrorRepresentable
        private let state: NodeMarkdownTextKit2DocumentState
        private weak var tableView: NSTableView?
        private var textViewsByNodeID: [UUID: WeakTextView] = [:]
        private var nodeIDByTextView: [ObjectIdentifier: UUID] = [:]
        private var activeNodeID: UUID?
        private var baselineNode: NodeMarkdownTextKit2Node?
        private var heightIndex = NodeMarkdownTextKit2HeightIndex()
        private var measuredHeights: [UUID: CGFloat] = [:]
        private var contentRevisions: [UUID: UInt64] = [:]
        private let renderCache = NodeMarkdownTextKit2RenderCache<NodeMarkdownBlockRenderRecord>()
        private var lastExternalToken: Int
        private var lastNavigationToken: Int
        private var lastVisualState: VisualState
        private var publishWorkItem: DispatchWorkItem?
        private var isApplyingModel = false
        private var pendingFocusNodeID: UUID?
        private var pendingFocusOffset: Int?
        private let rowIdentifier = NSUserInterfaceItemIdentifier("NodeMarkdownProseMirrorRow")
        private let sessionID = UUID()

        init(owner: NodeMarkdownProseMirrorRepresentable) {
            self.owner = owner
            state = NodeMarkdownTextKit2DocumentState(text: owner.text, rowMetadata: owner.rowMetadata)
            lastExternalToken = owner.externalTextSyncToken
            lastNavigationToken = owner.navigationRequestToken
            lastVisualState = VisualState(owner: owner)
            super.init()
            rebuildHeightIndex()
            installDraftController(owner.draftCommitController)
        }

        func makeView() -> NSScrollView {
            #if DEBUG
            NodeMarkdownTextKit2RegressionSuite.runOnce()
            #endif
            let table = NodeMarkdownProseMirrorTableView()
            table.headerView = nil
            table.backgroundColor = .clear
            table.gridStyleMask = []
            table.intercellSpacing = .zero
            table.selectionHighlightStyle = .none
            table.usesAutomaticRowHeights = false
            table.dataSource = self
            table.delegate = self
            table.onWidthChange = { [weak self] in self?.handleViewportWidthChange() }
            table.addTableColumn(NSTableColumn(identifier: .init("Node")))

            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.documentView = table
            tableView = table
            return scroll
        }

        func update(owner: NodeMarkdownProseMirrorRepresentable, scrollView: NSScrollView) {
            let previousStyle = self.owner.documentStyle.renderIdentity
            let visualState = VisualState(owner: owner)
            self.owner = owner
            installDraftController(owner.draftCommitController)

            if owner.externalTextSyncToken != lastExternalToken {
                commitActiveNode(reason: "外部文档更新")
                lastExternalToken = owner.externalTextSyncToken
                if state.replace(text: owner.text, rowMetadata: owner.rowMetadata) {
                    measuredHeights.removeAll(keepingCapacity: true)
                    contentRevisions.removeAll(keepingCapacity: true)
                    renderCache.removeAll()
                    activeNodeID = nil
                    baselineNode = nil
                    rebuildHeightIndex()
                    tableView?.reloadData()
                }
            } else if owner.documentStyle.renderIdentity != previousStyle {
                measuredHeights.removeAll(keepingCapacity: true)
                renderCache.removeAll()
                rebuildHeightIndex()
                tableView?.reloadData()
            } else if visualState != lastVisualState {
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

        func numberOfRows(in tableView: NSTableView) -> Int { state.snapshot.nodes.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard let node = state.node(at: row) else { return 44 }
            if let cached = renderCache[cacheKey(for: node.id, width: tableView.bounds.width)] {
                return cached.height
            }
            return measuredHeights[node.id] ?? estimatedHeight(for: node)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let node = state.node(at: row) else { return nil }
            let cell = (tableView.makeView(withIdentifier: rowIdentifier, owner: self) as? NodeMarkdownProseMirrorCellView)
                ?? NodeMarkdownProseMirrorCellView(identifier: rowIdentifier)
            configure(cell: cell, node: node, row: row, width: max(1, tableView.bounds.width))
            return cell
        }

        func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
            pruneDeadTextViews()
        }

        func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return }
            if activeNodeID != nodeID { commitActiveNode(reason: "离开上一个Node") }
            activeNodeID = nodeID
            baselineNode = node
            reinstall(node: node, in: textView, row: row)
            owner.onBeginEditing?()
            owner.onInputSessionStateChange?(true)
            owner.onActiveRowChange?(row)
            reportFocus(textView: textView, row: row)
            refreshRows([row])
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString, replacementString.contains("\n"),
                  let nodeTextView = textView as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(nodeTextView)] else { return true }
            return !replaceWithNodeSequence(
                nodeID: nodeID,
                affectedRange: affectedCharRange,
                replacement: replacementString,
                undoManager: textView.undoManager
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingModel,
                  let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID),
                  let oldNode = state.node(at: row) else { return }
            let content = textView.string
            textView.commitProjectedSourceText(content)
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
            guard state.dispatch(transaction) != nil else {
                reinstall(node: oldNode, in: textView, row: row)
                return
            }
            contentRevisions[nodeID, default: 0] &+= 1
            renderCache.invalidate(nodeID: nodeID)
            owner.onEditingDraftDirtyChange?(true)
            reportFocus(textView: textView, row: row)
            measure(textView: textView, nodeID: nodeID, row: row)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  let row = state.row(for: nodeID) else { return }
            reportFocus(textView: textView, row: row)
        }

        func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NodeMarkdownTextKit2TextView,
                  let nodeID = nodeIDByTextView[ObjectIdentifier(textView)],
                  activeNodeID == nodeID else { return }
            commitActiveNode(reason: "Node失焦")
            owner.onInputSessionStateChange?(false)
        }

        func commitActiveNode(reason: String) {
            guard let nodeID = activeNodeID,
                  let row = state.row(for: nodeID),
                  let node = state.node(at: row) else { return }
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
            owner.onActiveRowChange?(nil)
            owner.onFocusLocationChange?(nil)
            refreshRows([row])
            _ = reason
        }

        func cancelPendingPublish() {
            publishWorkItem?.cancel()
            publishWorkItem = nil
        }

        private func configure(cell: NodeMarkdownProseMirrorCellView, node: NodeMarkdownTextKit2Node, row: Int, width: CGFloat) {
            let textView = cell.textView
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
            textView.textContainerInset = NSSize(width: 16, height: 6)
            textView.nodeTextContainer.widthTracksTextView = true
            textView.nodeTextContainer.containerSize = NSSize(width: max(1, width - 32), height: .greatestFiniteMagnitude)
            textView.quickInputSettings = owner.quickInputSettings
            textView.suppressesAutomaticSelectionScrolling = true
            textView.onRequestSave = { [weak self] in
                self?.commitActiveNode(reason: "Command+S")
                self?.owner.onRequestSave?()
            }
            textView.onHandleInsertNewline = { [weak self, weak textView] in
                guard let self, let textView else { return false }
                return self.splitNode(nodeID: node.id, textView: textView)
            }
            textView.onHandleTabCommand = { [weak self] shift in
                self?.changeLevel(nodeID: node.id, shift: shift) ?? false
            }
            textView.onHandleDeleteBackward = { [weak self, weak textView] in
                guard let self, let textView, textView.selectedRange().location == 0 else { return false }
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
            textView.onRequestInsertImage = { [weak self] in self?.insertImage(at: node.id) }
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
                guard let self, let textView, let row = self.state.row(for: node.id) else { return }
                if self.activeNodeID != node.id {
                    self.commitActiveNode(reason: "点击另一Node")
                    self.activeNodeID = node.id
                    self.baselineNode = self.state.node(at: row)
                    self.owner.onActiveRowChange?(row)
                }
                self.reportFocus(textView: textView, row: row)
            }

            nodeIDByTextView[ObjectIdentifier(textView)] = node.id
            textViewsByNodeID[node.id] = WeakTextView(textView)
            reinstall(node: node, in: textView, row: row)
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.measure(textView: textView, nodeID: node.id, row: row)
                if self.pendingFocusNodeID == node.id {
                    self.pendingFocusNodeID = nil
                    let offset = min(self.pendingFocusOffset ?? node.content.utf16.count, node.content.utf16.count)
                    self.pendingFocusOffset = nil
                    textView.window?.makeFirstResponder(textView)
                    textView.setSelectedRange(NSRange(location: offset, length: 0))
                }
            }
        }

        private func reinstall(node: NodeMarkdownTextKit2Node, in textView: NodeMarkdownTextKit2TextView, row: Int) {
            let selection = textView.selectedRange()
            isApplyingModel = true
            textView.replaceDocumentText(node.content, documentStyle: owner.documentStyle)
            let layout = localLayout(for: node, row: row)
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
            isApplyingModel = false
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
            let selection = textView.selectedRange()
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
            guard state.dispatch(transaction) != nil else { return false }
            registerStructuralUndo(from: textView)
            activeNodeID = nil
            baselineNode = nil
            rebuildHeightIndex()
            tableView?.noteNumberOfRowsChanged()
            tableView?.reloadData(forRowIndexes: IndexSet(integersIn: row...min(row + 1, state.snapshot.nodes.count - 1)), columnIndexes: IndexSet(integer: 0))
            publishNow()
            focus(nodeID: newID, offset: 0)
            return true
        }

        private func joinWithPrevious(nodeID: UUID) -> Bool {
            guard let row = state.row(for: nodeID), row > 0,
                  let previous = state.node(at: row - 1),
                  let node = state.node(at: row),
                  !node.isProtectedH3 else { return false }
            let offset = (previous.content as NSString).length
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.joinNodes(leftID: previous.id, rightID: node.id)],
                selectionBefore: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: 0)),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: previous.id, utf16Offset: offset)),
                label: "Join Nodes"
            )
            guard state.dispatch(transaction) != nil else { return false }
            if let textView = textViewsByNodeID[nodeID]?.value {
                registerStructuralUndo(from: textView)
            }
            activeNodeID = nil
            baselineNode = nil
            rebuildHeightIndex()
            tableView?.noteNumberOfRowsChanged()
            tableView?.reloadData()
            publishNow()
            focus(nodeID: previous.id, offset: offset)
            return true
        }

        private func joinWithNext(nodeID: UUID) -> Bool {
            guard let row = state.row(for: nodeID),
                  let node = state.node(at: row),
                  let next = state.node(at: row + 1),
                  !next.isProtectedH3 else { return false }
            let offset = (node.content as NSString).length
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.joinNodes(leftID: node.id, rightID: next.id)],
                selectionBefore: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: offset)),
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: node.id, utf16Offset: offset)),
                label: "Join Next Node"
            )
            guard state.dispatch(transaction) != nil else { return false }
            if let textView = textViewsByNodeID[nodeID]?.value { registerStructuralUndo(from: textView) }
            rebuildHeightIndex()
            tableView?.noteNumberOfRowsChanged()
            tableView?.reloadData()
            publishNow()
            focus(nodeID: nodeID, offset: offset)
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
            guard state.dispatch(transaction) != nil, let last = inserted.last else { return false }
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: undoManager)
            }
            activeNodeID = nil
            baselineNode = nil
            rebuildHeightIndex()
            tableView?.noteNumberOfRowsChanged()
            tableView?.reloadData()
            publishNow()
            focus(nodeID: last.id, offset: (last.content as NSString).length)
            return true
        }

        private func changeLevel(nodeID: UUID, shift: Bool) -> Bool {
            guard let row = state.row(for: nodeID), let node = state.node(at: row), !node.isProtectedH3 else { return false }
            let level = max(1, min(12, node.level + (shift ? -1 : 1)))
            guard level != node.level else { return true }
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.setLevel(nodeID: nodeID, level: level)],
                label: shift ? "Lift Node" : "Sink Node"
            )
            guard state.dispatch(transaction) != nil else { return false }
            measuredHeights[nodeID] = nil
            refreshRows([row])
            publishNow()
            return true
        }

        private func insertImage(at nodeID: UUID) {
            guard let row = state.row(for: nodeID),
                  let insertion = owner.onRequestInsertImageAtRow?(row),
                  let node = state.node(at: row) else { return }
            var replacement = node
            replacement.content += insertion
            let transaction = NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceNode(nodeID: nodeID, node: replacement)],
                selectionAfter: NodeMarkdownNodeSelection(anchor: .init(nodeID: nodeID, utf16Offset: replacement.content.utf16.count)),
                label: "Insert Image"
            )
            guard state.dispatch(transaction) != nil else { return }
            measuredHeights[nodeID] = nil
            refreshRows([row])
            publishNow()
            focus(nodeID: nodeID, offset: replacement.content.utf16.count)
        }

        private func focus(nodeID: UUID, offset: Int) {
            guard let row = state.row(for: nodeID) else { return }
            pendingFocusNodeID = nodeID
            pendingFocusOffset = offset
            tableView?.scrollRowToVisible(row)
            tableView?.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }

        private func navigate(to row: Int, in scrollView: NSScrollView) {
            guard let tableView else { return }
            tableView.scrollRowToVisible(row)
            tableView.layoutSubtreeIfNeeded()
            let rowRect = tableView.rect(ofRow: row)
            var bounds = scrollView.contentView.bounds
            bounds.origin.y = max(0, rowRect.minY - NodeMarkdownTextKit2NavigationPolicy.targetTopPadding)
            scrollView.contentView.setBoundsOrigin(scrollView.contentView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func measure(textView: NodeMarkdownTextKit2TextView, nodeID: UUID, row: Int) {
            guard state.row(for: nodeID) == row else { return }
            let width = max(1, tableView?.bounds.width ?? textView.bounds.width)
            textView.nodeTextContainer.containerSize = NSSize(
                width: max(1, width - textView.textContainerInset.width * 2),
                height: .greatestFiniteMagnitude
            )
            let documentRange = textView.nodeTextLayoutManager.documentRange
            textView.nodeTextLayoutManager.ensureLayout(for: documentRange)
            let laidOutHeight = textView.nodeTextLayoutManager
                .textLayoutFragment(for: documentRange.location)?
                .layoutFragmentFrame.maxY ?? 0
            let measured = max(
                estimatedHeight(for: state.node(at: row)),
                ceil(laidOutHeight + textView.textContainerInset.height * 2)
            )
            guard measured.isFinite, measured > 0,
                  abs((measuredHeights[nodeID] ?? 0) - measured) > 0.5 else { return }
            let anchorRow = visibleAnchorRow()
            let anchorOffset = anchorRow.map { heightIndex.offset(of: $0) } ?? 0
            measuredHeights[nodeID] = measured
            renderCache[cacheKey(for: nodeID, width: width)] = NodeMarkdownBlockRenderRecord(height: measured)
            heightIndex.updateHeight(Double(measured), at: row)
            tableView?.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            restoreVisibleAnchor(row: anchorRow, oldOffset: anchorOffset)
        }

        private func estimatedHeight(for node: NodeMarkdownTextKit2Node?) -> CGFloat {
            guard let node else { return 44 }
            let style = owner.documentStyle.platformDisplayStyle.style(forLevel: node.level)
            return max(34, ceil(CGFloat(style.fontSize) * 1.55 + 12))
        }

        private func rebuildHeightIndex() {
            heightIndex.replace(with: state.snapshot.nodes.map { Double(measuredHeights[$0.id] ?? estimatedHeight(for: $0)) })
        }

        private func cacheKey(for nodeID: UUID, width: CGFloat) -> NodeMarkdownTextKit2RenderCacheKey {
            NodeMarkdownTextKit2RenderCacheKey(
                nodeID: nodeID,
                contentRevision: contentRevisions[nodeID, default: 0],
                styleRevision: owner.documentStyle.renderIdentity.hashValue,
                width: Int(width.rounded())
            )
        }

        private func visibleAnchorRow() -> Int? {
            guard let tableView else { return nil }
            let rows = tableView.rows(in: tableView.visibleRect)
            return rows.location == NSNotFound ? nil : rows.location
        }

        private func restoreVisibleAnchor(row: Int?, oldOffset: Double) {
            guard let row, let scroll = tableView?.enclosingScrollView else { return }
            let delta = heightIndex.offset(of: row) - oldOffset
            guard abs(delta) > 0.5 else { return }
            var bounds = scroll.contentView.bounds
            bounds.origin.y += CGFloat(delta)
            scroll.contentView.setBoundsOrigin(scroll.contentView.constrainBoundsRect(bounds).origin)
        }

        private func refreshRows(_ rows: Set<Int>) {
            guard let tableView else { return }
            let valid = IndexSet(rows.filter { state.snapshot.nodes.indices.contains($0) })
            guard !valid.isEmpty else { return }
            tableView.reloadData(forRowIndexes: valid, columnIndexes: IndexSet(integer: 0))
        }

        private func refreshVisibleNodesForStateOnly() {
            guard let tableView else { return }
            let visible = tableView.rows(in: tableView.visibleRect)
            if visible.location != NSNotFound {
                tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)), columnIndexes: IndexSet(integer: 0))
            }
        }

        private func handleViewportWidthChange() {
            measuredHeights.removeAll(keepingCapacity: true)
            renderCache.removeAll()
            rebuildHeightIndex()
            tableView?.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<state.snapshot.nodes.count))
            refreshVisibleNodesForStateOnly()
        }

        private func schedulePublish() {
            publishWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.publishNow() }
            publishWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }

        private func publishNow() {
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
                    self?.commitActiveNode(reason: "保存/同步/导出前")
                },
                focusRowEnd: { [weak self] row in
                    guard let self, let node = self.state.node(at: row) else { return }
                    self.focus(nodeID: node.id, offset: node.content.utf16.count)
                }
            )
        }

        private func registerStructuralUndo(from textView: NSTextView) {
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: textView.undoManager)
            }
        }

        private func performStructuralUndo(using undoManager: UndoManager?) {
            guard state.undo() != nil else { return }
            rebuildHeightIndex()
            tableView?.reloadData()
            publishNow()
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralRedo(using: undoManager)
            }
        }

        private func performStructuralRedo(using undoManager: UndoManager?) {
            guard state.redo() != nil else { return }
            rebuildHeightIndex()
            tableView?.reloadData()
            publishNow()
            undoManager?.registerUndo(withTarget: self) { target in
                target.performStructuralUndo(using: undoManager)
            }
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

private struct NodeMarkdownBlockRenderRecord {
    let height: CGFloat
}

private final class NodeMarkdownProseMirrorTableView: NSTableView {
    var onWidthChange: (() -> Void)?
    private var lastReportedWidth: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }


    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(newSize.width - lastReportedWidth) > 0.5
        super.setFrameSize(newSize)
        guard changed, newSize.width > 0 else { return }
        lastReportedWidth = newSize.width
        DispatchQueue.main.async { [weak self] in self?.onWidthChange?() }
    }
}

private final class NodeMarkdownProseMirrorCellView: NSTableCellView {
    let textView = NodeMarkdownTextKit2TextView()
    var nodeID: UUID?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class WeakTextView {
    weak var value: NodeMarkdownTextKit2TextView?
    init(_ value: NodeMarkdownTextKit2TextView) { self.value = value }
}
#endif
