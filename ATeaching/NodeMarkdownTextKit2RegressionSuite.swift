// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

#if DEBUG
@MainActor
enum NodeMarkdownTextKit2RegressionSuite {
    private static var hasRun = false

    static func runOnce() {
        guard !hasRun else { return }
        hasRun = true
        testDocumentStateKeepsIdentity()
        testDuplicateIdentityIsRejected()
        testIncompleteDocumentContractsAreRejected()
        testProtectedH3CannotLoseIdentity()
        testDocumentStateSplitsNodeLocally()
        testProseMirrorCharacterTransactionAndMapping()
        testProseMirrorStructuralIndexAndHistory()
        testProtectedH3SplitCanUndo()
        testProseMirrorRejectsStaleTransaction()
        testTransactionImpactAndNodeVersions()
        testDeterministicTransactionReplay()
        testOutlineNumberingIndex()
        testRenderCacheIsBounded()
        testHeightIndex()
        testLargeIndexLookup()
        testCommittedNodeCollectsDirtyAndNewPackages()
        #if os(macOS)
        testNavigationRequestCanRepeatSameRow()
        testQuickInputReconcilesRealFollowingRowBoundary()
        testInputMethodTemporarilyProjectsFollowingRows()
        testNativeDeletionDefersSelectionAndRefreshesSeam()
        testInputMethodUsesCurrentNodeTypography()
        testBody3AndBody4UseIndependentStyles()
        testNodeAndWrappedLineSpacingStayIndependent()
        testParagraphBoundaryUsesFollowingNodeTextStyle()
        testFormulaAndTextShareVisualCenter()
        testMarkerUsesMeasuredTextBaseline()
        testImageTokenProtectionKeepsWidthEditable()
        #endif
    }

    private static func metadata(
        _ id: UUID,
        level: Int,
        sourceID: String = "",
        sourceFile: String = ""
    ) -> NodeMarkdownTextKitRowMetadata {
        NodeMarkdownTextKitRowMetadata(
            nodeID: id.uuidString,
            level: level,
            sourceID: sourceID,
            sourceFile: sourceFile
        )
    }

    #if os(macOS)
    private static func testNavigationRequestCanRepeatSameRow() {
        assert(NodeMarkdownTextKit2NavigationPolicy.targetRow(
            requestToken: 1,
            lastHandledToken: 0,
            activeRowIndex: 8,
            rowCount: 20
        ) == 8)
        assert(NodeMarkdownTextKit2NavigationPolicy.targetRow(
            requestToken: 1,
            lastHandledToken: 1,
            activeRowIndex: 8,
            rowCount: 20
        ) == nil)
        assert(NodeMarkdownTextKit2NavigationPolicy.targetRow(
            requestToken: 2,
            lastHandledToken: 1,
            activeRowIndex: 8,
            rowCount: 20
        ) == 8)
        assert(NodeMarkdownTextKit2NavigationPolicy.targetRow(
            requestToken: 3,
            lastHandledToken: 2,
            activeRowIndex: 20,
            rowCount: 20
        ) == nil)
    }
    #endif

    private static func testDocumentStateKeepsIdentity() {
        let first = UUID()
        let second = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "A\nB",
            rowMetadata: [metadata(first, level: 1), metadata(second, level: 9)]
        )
        assert(state.row(for: second) == 1)
        assert(state.updateRow(1, content: "BBB", metadata: metadata(second, level: 9)))
        assert(state.node(at: 0)?.content == "A")
        assert(state.node(at: 1)?.content == "BBB")
        assert(state.node(at: 1)?.level == 9)
    }

    private static func testDuplicateIdentityIsRejected() {
        let first = UUID()
        let second = UUID()
        let duplicate = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "A\nB",
            rowMetadata: [metadata(first, level: 1), metadata(second, level: 2)]
        )
        let snapshot = state.snapshot
        assert(!state.replace(
            text: "C\nD",
            rowMetadata: [metadata(duplicate, level: 1), metadata(duplicate, level: 2)]
        ))
        assert(state.snapshot.nodes == snapshot.nodes)
        assert(state.lastValidationError == .duplicateNodeID(row: 1, id: duplicate))
    }

    private static func testIncompleteDocumentContractsAreRejected() {
        let first = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "A",
            rowMetadata: [metadata(first, level: 1)]
        )
        let snapshot = state.snapshot
        assert(!state.replace(text: "A\nB", rowMetadata: [metadata(first, level: 1)]))
        assert(state.snapshot.nodes == snapshot.nodes)

        let invalidID = NodeMarkdownTextKitRowMetadata(
            nodeID: "",
            level: 1,
            sourceID: "",
            sourceFile: ""
        )
        assert(!state.replace(text: "A", rowMetadata: [invalidID]))
        assert(state.snapshot.nodes == snapshot.nodes)

        assert(!state.replace(text: "A", rowMetadata: [metadata(first, level: 13)]))
        assert(state.snapshot.nodes == snapshot.nodes)

        let incompleteSource = metadata(first, level: 3, sourceID: "source", sourceFile: "")
        assert(!state.replace(text: "A", rowMetadata: [incompleteSource]))
        assert(state.snapshot.nodes == snapshot.nodes)

        let sourceOnH4 = metadata(first, level: 4, sourceID: "source", sourceFile: "chapter.csv")
        assert(!state.replace(text: "A", rowMetadata: [sourceOnH4]))
        assert(state.snapshot.nodes == snapshot.nodes)
    }

    private static func testProtectedH3CannotLoseIdentity() {
        let id = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "H3",
            rowMetadata: [metadata(id, level: 3, sourceID: "source", sourceFile: "chapter.csv")]
        )
        _ = state.updateNode(id: id) { node in
            node.level = 4
            node.sourceID = ""
            node.sourceFile = ""
        }
        assert(state.node(at: 0)?.level == 3)
        assert(state.node(at: 0)?.sourceID == "source")
        assert(state.node(at: 0)?.sourceFile == "chapter.csv")
    }

    private static func testDocumentStateSplitsNodeLocally() {
        let first = UUID()
        let following = UUID()
        let inserted = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "AABBCC\nDD",
            rowMetadata: [metadata(first, level: 5), metadata(following, level: 8)]
        )
        assert(state.splitNode(at: 0, utf16Offset: 4, newNodeID: inserted, newLevel: 5))
        assert(state.snapshot.plainText == "AABB\nCC\nDD")
        assert(state.node(at: 0)?.id == first)
        assert(state.node(at: 1)?.id == inserted)
        assert(state.node(at: 1)?.level == 5)
        assert(state.node(at: 2)?.id == following)
        assert(state.row(for: following) == 2)
    }

    private static func testProseMirrorCharacterTransactionAndMapping() {
        let first = UUID()
        let second = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "ABCDE\nFollowing",
            rowMetadata: [metadata(first, level: 5), metadata(second, level: 9)]
        )
        let beforeRevision = state.revision
        let selection = NodeMarkdownNodeSelection(
            anchor: NodeMarkdownNodePosition(nodeID: first, utf16Offset: 5)
        )
        let result = state.dispatch(
            NodeMarkdownTransaction(
                baseRevision: beforeRevision,
                steps: [
                    .replaceText(
                        nodeID: first,
                        range: NSRange(location: 1, length: 2),
                        replacement: "XYZ"
                    )
                ],
                selectionBefore: selection,
                label: "Regression typing"
            )
        )
        assert(result?.structural == false)
        assert(result?.affectedNodeIDs == [first])
        assert(result?.mappedSelection?.head == NodeMarkdownNodePosition(nodeID: first, utf16Offset: 6))
        assert(state.node(at: 0)?.content == "AXYZDE")
        assert(state.node(at: 1)?.content == "Following")
        assert(state.row(for: second) == 1)
    }

    private static func testProseMirrorStructuralIndexAndHistory() {
        let h1 = UUID()
        let h3 = UUID()
        let child = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "H1\nPackage\nChild",
            rowMetadata: [
                metadata(h1, level: 1),
                metadata(h3, level: 3),
                metadata(child, level: 4)
            ]
        )
        assert(state.parentRow(of: 2) == 1)
        assert(state.owningH3Row(for: 2) == 1)
        assert(state.packageRange(rootID: h3) == 1..<3)

        let inserted = UUID()
        let transaction = NodeMarkdownTransaction(
            baseRevision: state.revision,
            steps: [
                .splitNode(nodeID: child, offset: 2, newNodeID: inserted, newLevel: 4)
            ],
            label: "Regression split"
        )
        assert(state.dispatch(transaction)?.structural == true)
        assert(state.snapshot.plainText == "H1\nPackage\nCh\nild")
        assert(state.packageRange(rootID: h3) == 1..<4)
        assert(state.undo() != nil)
        assert(state.snapshot.plainText == "H1\nPackage\nChild")
        assert(state.row(for: inserted) == nil)
        assert(state.redo() != nil)
        assert(state.snapshot.plainText == "H1\nPackage\nCh\nild")
    }

    private static func testProseMirrorRejectsStaleTransaction() {
        let id = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "A",
            rowMetadata: [metadata(id, level: 7)]
        )
        let staleRevision = state.revision
        assert(state.updateRow(0, content: "AB", metadata: metadata(id, level: 7)))
        let stale = NodeMarkdownTransaction(
            baseRevision: staleRevision,
            steps: [.replaceText(nodeID: id, range: NSRange(location: 0, length: 1), replacement: "X")],
            label: "Stale"
        )
        assert(state.dispatch(stale) == nil)
        assert(state.node(at: 0)?.content == "AB")
    }

    private static func testProtectedH3SplitCanUndo() {
        let root = UUID()
        let child = UUID()
        let state = NodeMarkdownTextKit2DocumentState(
            text: "Package\nFollowing",
            rowMetadata: [
                metadata(root, level: 3, sourceID: "source", sourceFile: "chapter.csv"),
                metadata(child, level: 4)
            ]
        )
        let inserted = UUID()
        let transaction = NodeMarkdownTransaction(
            baseRevision: state.revision,
            steps: [.splitNode(nodeID: root, offset: 7, newNodeID: inserted, newLevel: 4)],
            label: "Protected H3 Enter"
        )
        assert(state.dispatch(transaction) != nil)
        assert(state.node(at: 0)?.isProtectedH3 == true)
        assert(state.node(at: 1)?.level == 4)
        assert(state.node(at: 1)?.sourceID.isEmpty == true)
        assert(state.undo() != nil)
        assert(state.snapshot.plainText == "Package\nFollowing")
        assert(state.node(at: 0)?.isProtectedH3 == true)
    }

    private static func testTransactionImpactAndNodeVersions() {
        let ids = (0..<1_000).map { _ in UUID() }
        let state = NodeMarkdownTextKit2DocumentState(
            text: Array(repeating: "Node", count: ids.count).joined(separator: "\n"),
            rowMetadata: ids.map { metadata($0, level: 7) }
        )
        let target = ids[500]
        let untouched = ids[999]
        let untouchedRevision = state.nodeRevision(for: untouched)
        let result = state.dispatch(
            NodeMarkdownTransaction(
                baseRevision: state.revision,
                steps: [.replaceText(
                    nodeID: target,
                    range: NSRange(location: 4, length: 0),
                    replacement: "!"
                )],
                label: "Version isolation"
            )
        )
        assert(result?.impact.contentNodeIDs == [target])
        assert(result?.impact.structuralRange == nil)
        assert(state.nodeRevision(for: target) > 1)
        assert(state.nodeRevision(for: untouched) == untouchedRevision)
        assert(state.node(at: 999)?.content == "Node")
    }

    private static func testOutlineNumberingIndex() {
        let ids = (0..<6).map { _ in UUID() }
        let state = NodeMarkdownTextKit2DocumentState(
            text: "A\nB\nC\nD\nE\nF",
            rowMetadata: [
                metadata(ids[0], level: 1),
                metadata(ids[1], level: 2),
                metadata(ids[2], level: 3),
                metadata(ids[3], level: 3),
                metadata(ids[4], level: 2),
                metadata(ids[5], level: 3)
            ]
        )
        assert(state.numberingText(for: 0) == "1")
        assert(state.numberingText(for: 2) == "1.1.1")
        assert(state.numberingText(for: 3) == "1.1.2")
        assert(state.numberingText(for: 5) == "1.2.1")
    }

    private static func testDeterministicTransactionReplay() {
        let ids = (0..<4).map { _ in UUID() }
        let metadataRows = [
            metadata(ids[0], level: 1),
            metadata(ids[1], level: 3),
            metadata(ids[2], level: 4),
            metadata(ids[3], level: 7)
        ]
        let inserted = NodeMarkdownTextKit2Node(
            id: UUID(), level: 4, content: "Inserted", sourceID: "", sourceFile: ""
        )
        let batches: [[NodeMarkdownTransactionStep]] = [
            [.replaceText(nodeID: ids[2], range: NSRange(location: 5, length: 0), replacement: "!")],
            [.insertNodes(row: 3, nodes: [inserted])],
            [.setLevel(nodeID: ids[3], level: 8)]
        ]
        let first = NodeMarkdownTransactionReplayer.replay(
            text: "H1\nH3\nChild\nBody",
            rowMetadata: metadataRows,
            stepBatches: batches
        )
        let second = NodeMarkdownTransactionReplayer.replay(
            text: "H1\nH3\nChild\nBody",
            rowMetadata: metadataRows,
            stepBatches: batches
        )
        assert(first == second)
        assert(first?.last?.nodes.map(\.id) == [ids[0], ids[1], ids[2], inserted.id, ids[3]])
        assert(first?.last?.nodes[2].content == "Child!")
        assert(first?.last?.nodes[4].level == 8)
    }

    private static func testRenderCacheIsBounded() {
        let cache = NodeMarkdownTextKit2RenderCache<Int>(capacity: 16)
        let documentID = UUID()
        for value in 0..<40 {
            cache[NodeMarkdownTextKit2RenderCacheKey(
                documentID: documentID,
                nodeID: UUID(),
                nodeRevision: 1,
                styleRevision: 1,
                visualRevision: 1,
                width: 1_000,
                scaleMilli: 2_000
            )] = value
        }
        assert(cache.count == 16)
    }

    private static func testHeightIndex() {
        var index = NodeMarkdownTextKit2HeightIndex()
        index.replace(with: [10, 20, 30])
        assert(index.offset(of: 2) == 30)
        assert(index.row(containingY: 0) == 0)
        assert(index.row(containingY: 10) == 1)
        index.updateHeight(25, at: 1)
        assert(index.totalHeight == 65)
        assert(index.row(containingY: 34) == 1)
        assert(index.row(containingY: 35) == 2)
    }

    private static func testLargeIndexLookup() {
        let count = 50_000
        var index = NodeMarkdownTextKit2HeightIndex()
        index.replace(with: Array(repeating: 24, count: count))
        for row in stride(from: 0, to: count, by: 997) {
            assert(index.row(containingY: Double(row * 24)) == row)
        }
    }

    private static func testCommittedNodeCollectsDirtyAndNewPackages() {
        let linkedRoot = NodeMarkdownNode(
            level: 3,
            text: "已入库包",
            sourceID: "source",
            sourceFile: "chapter.csv"
        )
        let child = NodeMarkdownNode(level: 4, text: "原文")
        let linkedDocument = NodeMarkdownDocument(nodes: [linkedRoot, child])
        var changedLinkedDocument = linkedDocument
        changedLinkedDocument.nodes[1].text = "已修改"
        let tracker = TeachingCoursePackageChangeTracker()
        tracker.establishBaseline(document: linkedDocument)
        _ = tracker.recordDocumentMutation(
            previousDocument: linkedDocument,
            currentDocument: changedLinkedDocument
        )
        assert(tracker.dirtyPackageIDList().contains(linkedRoot.id.uuidString))

        let h1 = NodeMarkdownNode(level: 1, text: "日期")
        let documentBeforeNewH3 = NodeMarkdownDocument(nodes: [h1])
        let newRoot = NodeMarkdownNode(level: 3, text: "新包标题")
        let documentWithNewH3 = NodeMarkdownDocument(nodes: [h1, newRoot])
        tracker.establishBaseline(document: documentBeforeNewH3)
        _ = tracker.recordDocumentMutation(
            previousDocument: documentBeforeNewH3,
            currentDocument: documentWithNewH3,
            collectNewPackages: false
        )
        assert(!tracker.newPackageIDList().contains(newRoot.id.uuidString))
        _ = tracker.recordDocumentMutation(
            previousDocument: documentWithNewH3,
            currentDocument: documentWithNewH3
        )
        assert(tracker.newPackageIDList().contains(newRoot.id.uuidString))
        let newItems = tracker.newPackageDisplayItems(document: documentWithNewH3)
        assert(newItems.first(where: { $0.id == newRoot.id.uuidString })?.title == "新包标题")

        var demotedDocument = documentWithNewH3
        demotedDocument.nodes[1].level = 4
        _ = tracker.recordDocumentMutation(
            previousDocument: documentWithNewH3,
            currentDocument: demotedDocument
        )
        assert(!tracker.newPackageIDList().contains(newRoot.id.uuidString))

        let h1Tracker = TeachingCoursePackageChangeTracker()
        let changedH1Document = NodeMarkdownDocument(
            nodes: [NodeMarkdownNode(id: h1.id, level: 1, text: "改过的日期")]
        )
        h1Tracker.establishBaseline(document: documentBeforeNewH3)
        _ = h1Tracker.recordDocumentMutation(
            previousDocument: documentBeforeNewH3,
            currentDocument: changedH1Document
        )
        assert(h1Tracker.dirtyPackageIDList().isEmpty)
        assert(h1Tracker.newPackageIDList().isEmpty)
    }

    #if os(macOS)
    private static func testQuickInputReconcilesRealFollowingRowBoundary() {
        let lineStyle = NodeMarkdownRenderContract.default.lineStyle(
            level: 6,
            prefix: "",
            documentStyle: NodeMarkdownDocumentStyle()
        )
        func layout(_ row: Int, _ location: Int, _ length: Int) -> NodeMarkdownTextKit2RowLayout {
            NodeMarkdownTextKit2RowLayout(
                rowIndex: row,
                range: NSRange(location: location, length: length),
                contentRange: NSRange(location: location, length: max(0, length - (row < 2 ? 1 : 0))),
                prefix: "",
                level: 6,
                lineStyle: lineStyle,
                spacingBefore: 0,
                isProtectedH3: false
            )
        }

        let staleLayouts = [layout(0, 0, 3), layout(1, 3, 2), layout(2, 5, 1)]
        let rebuiltFirstRow = layout(0, 0, 9)
        let reconciledFromStale = NodeMarkdownTextKit2RowLayoutReconciler.replacingRow(
            in: staleLayouts,
            rowIndex: 0,
            with: rebuiltFirstRow,
            documentLength: 12
        )
        assert(reconciledFromStale?[1].range.location == 9)
        assert(reconciledFromStale?[2].range.location == 11)

        let alreadyProjected = [layout(0, 0, 9), layout(1, 9, 2), layout(2, 11, 1)]
        let reconciledFromProjection = NodeMarkdownTextKit2RowLayoutReconciler.replacingRow(
            in: alreadyProjected,
            rowIndex: 0,
            with: rebuiltFirstRow,
            documentLength: 12
        )
        assert(reconciledFromProjection?[1].range.location == 9)
        assert(reconciledFromProjection?[2].range.location == 11)
    }

    private static func testInputMethodTemporarilyProjectsFollowingRows() {
        let lineStyle = NodeMarkdownRenderContract.default.lineStyle(
            level: 5,
            prefix: "",
            documentStyle: NodeMarkdownDocumentStyle()
        )
        let layouts = [
            NodeMarkdownTextKit2RowLayout(
                rowIndex: 0,
                range: NSRange(location: 0, length: 2),
                contentRange: NSRange(location: 0, length: 1),
                prefix: "",
                level: 5,
                lineStyle: lineStyle,
                spacingBefore: 0,
                isProtectedH3: false
            ),
            NodeMarkdownTextKit2RowLayout(
                rowIndex: 1,
                range: NSRange(location: 2, length: 1),
                contentRange: NSRange(location: 2, length: 1),
                prefix: "",
                level: 9,
                lineStyle: lineStyle,
                spacingBefore: 0,
                isProtectedH3: false
            )
        ]
        let projected = NodeMarkdownTextKit2TransientLayoutProjection.project(
            layouts,
            replacing: NSRange(location: 1, length: 0),
            characterDelta: 3
        )
        assert(projected?[0].range == NSRange(location: 0, length: 5))
        assert(projected?[0].contentRange == NSRange(location: 0, length: 4))
        assert(projected?[1].range == NSRange(location: 5, length: 1))
        assert(projected?[1].level == 9)
    }

    private static func testNativeDeletionDefersSelectionAndRefreshesSeam() {
        assert(NodeMarkdownTextKit2NativeEditPolicy.shouldDeferSelectionSynchronization(
            hasPendingSourceProjection: true
        ))
        assert(!NodeMarkdownTextKit2NativeEditPolicy.shouldDeferSelectionSynchronization(
            hasPendingSourceProjection: false
        ))
        assert(NodeMarkdownTextKit2NativeEditPolicy.seamRows(
            afterSettling: NSRange(location: 24, length: 3),
            rowIndex: 7
        ) == Set([7, 8]))
        assert(NodeMarkdownTextKit2NativeEditPolicy.seamRows(
            afterSettling: NSRange(location: 24, length: 0),
            rowIndex: 7
        ).isEmpty)
    }

    private static func testInputMethodUsesCurrentNodeTypography() {
        let font = NSFont.systemFont(ofSize: 19)
        let color = NSColor.systemTeal
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 31
        let original = NSAttributedString(
            string: "pinyin",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let result = NodeMarkdownTextKit2TextView.markedText(
            original,
            applying: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        assert((result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font)
        assert((result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == color)
        assert((result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) == paragraph)
        assert((result.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)

        let overwritten = NSMutableAttributedString(attributedString: result)
        overwritten.addAttributes(
            [.font: NSFont.boldSystemFont(ofSize: 48), .foregroundColor: NSColor.systemBlue],
            range: NSRange(location: 0, length: overwritten.length)
        )
        NodeMarkdownTextKit2TextView.applyControlledTypingAttributes(
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph],
            to: overwritten,
            range: NSRange(location: 0, length: overwritten.length)
        )
        assert((overwritten.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == font)
        assert((overwritten.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == color)
        assert((overwritten.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle) == paragraph)
        assert((overwritten.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
    }

    private static func testBody3AndBody4UseIndependentStyles() {
        var style = NodeMarkdownDocumentStyle()
        style.body3.color = .red
        style.body3.semanticColor = nil
        style.body4.color = .green
        style.body4.semanticColor = nil

        let contract = NodeMarkdownRenderContract.default
        let body3 = contract.lineStyle(level: 9, prefix: "", documentStyle: style)
        let body4 = contract.lineStyle(level: 10, prefix: "", documentStyle: style)
        assert(body3.level == NodeMarkdownStyleRole.body3.level)
        assert(body4.level == NodeMarkdownStyleRole.body4.level)
        assert(body3.roleStyle == style.body3)
        assert(body4.roleStyle == style.body4)
        assert(colorsMatch(NSColor(body3.roleStyle.renderedColor), NSColor(style.body3.renderedColor)))
        assert(colorsMatch(NSColor(body4.roleStyle.renderedColor), NSColor(style.body4.renderedColor)))
    }

    private static func testParagraphBoundaryUsesFollowingNodeTextStyle() {
        var style = NodeMarkdownDocumentStyle()
        style.body3.color = .red
        style.body3.semanticColor = nil
        style.body4.color = .green
        style.body4.semanticColor = nil
        let followingStyle = NodeMarkdownRenderContract.default.lineStyle(
            level: 10,
            prefix: "",
            documentStyle: style
        )
        let followingLayout = NodeMarkdownTextKit2RowLayout(
            rowIndex: 1,
            range: NSRange(location: 2, length: 1),
            contentRange: NSRange(location: 2, length: 1),
            prefix: "",
            level: 10,
            lineStyle: followingStyle,
            spacingBefore: 0,
            isProtectedH3: false
        )
        let text = NSMutableAttributedString(
            string: "A\nB",
            attributes: [.foregroundColor: NSColor.red]
        )
        NodeMarkdownTextKit2TextView.applyTextAttributesOfFollowingRowToPrecedingSeparator(
            in: text,
            followingLayout: followingLayout
        )
        guard let separatorColor = text.attribute(
            .foregroundColor,
            at: 1,
            effectiveRange: nil
        ) as? NSColor else {
            assertionFailure("Paragraph separator is missing the following Node color")
            return
        }
        assert(colorsMatch(separatorColor, NSColor(style.body4.renderedColor)))
    }

    private static func testNodeAndWrappedLineSpacingStayIndependent() {
        var style = NodeMarkdownDocumentStyle()
        style.body1.paragraphSpacingBefore = 3
        style.body1.paragraphSpacingAfter = 7
        style.body1.peerLineSpacing = 19
        style.body2.paragraphSpacingBefore = 11
        style.body2.paragraphSpacingAfter = 2
        style.body2.peerLineSpacing = 23

        let body1 = style.body1
        let body2 = style.body2
        assert(NodeMarkdownRenderContract.interRowSpacing(
            previousLevel: 7,
            previousRoleStyle: body1,
            currentLevel: 7,
            currentRoleStyle: body1
        ) == 7)
        assert(NodeMarkdownRenderContract.interRowSpacing(
            previousLevel: 7,
            previousRoleStyle: body1,
            currentLevel: 8,
            currentRoleStyle: body2
        ) == 11)

        let lineStyle = NodeMarkdownRenderContract.default.lineStyle(
            level: 7,
            prefix: "",
            documentStyle: style
        )
        let layout = NodeMarkdownTextKit2RowLayout(
            rowIndex: 0,
            range: NSRange(location: 0, length: 0),
            contentRange: NSRange(location: 0, length: 0),
            prefix: "",
            level: 7,
            lineStyle: lineStyle,
            spacingBefore: 7,
            isProtectedH3: false
        )
        let font = NodeMarkdownTextKit2TextView.resolvedFont(for: body1)
        let paragraph = NodeMarkdownTextKit2TextView.paragraphStyle(for: layout, font: font)
        assert(paragraph.lineSpacing == 19)
        assert(paragraph.paragraphSpacingBefore == 7)
        let blockContentLayout = layout.replacingSpacingBefore(0)
        let blockParagraph = NodeMarkdownTextKit2TextView.paragraphStyle(
            for: blockContentLayout,
            font: font
        )
        assert(blockParagraph.paragraphSpacingBefore == 0)
        let emptyRect = NodeMarkdownTextKit2TextView.emptyParagraphRect(
            for: blockContentLayout,
            textContainerOrigin: .zero
        )
        assert(emptyRect.minY == 0)
        assert(emptyRect.height >= paragraph.minimumLineHeight)

        let geometry = NodeMarkdownExactGeometry.block(
            key: NodeMarkdownExactLayoutKey(
                documentID: UUID(),
                nodeID: UUID(),
                nodeRevision: 1,
                styleRevision: 1,
                widthPixels: 1_000,
                scaleMilli: 2_000
            ),
            contentHeight: 41,
            spacingBefore: 7,
            fragmentCount: 1,
            contentVisualBounds: CGRect(x: 10, y: 2, width: 100, height: 37)
        )
        assert(geometry.contentHeight == 41)
        assert(geometry.spacingBefore == 7)
        assert(geometry.height == 48)
        assert(geometry.visualBounds.minY == 9)
    }

    private static func testFormulaAndTextShareVisualCenter() {
        let bounds = NodeMarkdownRenderContract.centeredInlineAttachmentBounds(
            fontAscender: 45.12,
            fontDescender: -9.88,
            width: 488.015,
            height: 134.882
        )
        let textCenter = (45.12 - 9.88) * 0.5
        assert(abs(bounds.midY - textCenter) < 0.000_001)
        assert(abs(bounds.minY - (-49.821)) < 0.001)
        assert(abs(bounds.maxY - 85.061) < 0.001)

        let shortBounds = NodeMarkdownRenderContract.centeredInlineAttachmentBounds(
            fontAscender: 30,
            fontDescender: -10,
            width: 20,
            height: 16
        )
        assert(abs(shortBounds.midY - 10) < 0.000_001)
    }

    private static func testMarkerUsesMeasuredTextBaseline() {
        let font = NSFont.systemFont(ofSize: 50)
        let baseline: CGFloat = 622.472
        let expected = baseline - (font.ascender + font.descender) * 0.5
        let measured = NodeMarkdownTextKit2TextView.markerVisualCenterY(
            textBaselineY: baseline,
            font: font,
            fallback: -1
        )
        assert(abs(measured - expected) < 0.000_001)

        let fallback = NodeMarkdownTextKit2TextView.markerVisualCenterY(
            textBaselineY: nil,
            font: font,
            fallback: 123
        )
        assert(fallback == 123)
    }

    private static func testImageTokenProtectionKeepsWidthEditable() {
        let source = "before ![image](Pic/a.png){width=600} after"
        guard let token = NodeMarkdownImageResourceManager.parseImageTokens(in: source).first else {
            assertionFailure("Expected image token")
            return
        }
        let tokenText = token.sourceText as NSString
        let pathRange = tokenText.range(of: "Pic/a.png")
        let protectedEdit = NodeMarkdownImageEditProtection.protectedEdit(
            sourceText: source,
            affectedRange: NSRange(
                location: token.sourceRange.location + pathRange.location,
                length: 1
            ),
            replacement: ""
        )
        assert(protectedEdit?.replacementRange == token.sourceRange)
        assert(protectedEdit?.replacement == "")

        let widthRange = tokenText.range(of: "600")
        let widthEdit = NodeMarkdownImageEditProtection.protectedEdit(
            sourceText: source,
            affectedRange: NSRange(
                location: token.sourceRange.location + widthRange.location,
                length: widthRange.length
            ),
            replacement: "420"
        )
        assert(widthEdit == nil)
    }

    private static func colorsMatch(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        guard let lhsRGB = lhs.usingColorSpace(.deviceRGB),
              let rhsRGB = rhs.usingColorSpace(.deviceRGB) else { return false }
        let tolerance = 0.000_001
        return abs(lhsRGB.redComponent - rhsRGB.redComponent) <= tolerance
            && abs(lhsRGB.greenComponent - rhsRGB.greenComponent) <= tolerance
            && abs(lhsRGB.blueComponent - rhsRGB.blueComponent) <= tolerance
            && abs(lhsRGB.alphaComponent - rhsRGB.alphaComponent) <= tolerance
    }
    #endif
}
#endif
