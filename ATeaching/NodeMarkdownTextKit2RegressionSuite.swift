// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if DEBUG
enum NodeMarkdownTextKit2RegressionSuite {
    private static var hasRun = false

    static func runOnce() {
        guard !hasRun else { return }
        hasRun = true
        testDocumentStateKeepsIdentity()
        testDuplicateIdentityIsRejected()
        testIncompleteDocumentContractsAreRejected()
        testProtectedH3CannotLoseIdentity()
        testHeightIndex()
        testLargeIndexLookup()
        #if os(macOS)
        testQuickInputUsesCombinedCharacterDelta()
        testInputMethodTemporarilyProjectsFollowingRows()
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

    #if os(macOS)
    private static func testQuickInputUsesCombinedCharacterDelta() {
        let sourceAfterFourthKey = "A====\nB" as NSString
        let quickEdit = NodeMarkdownTextKit2QuickInputEdit(
            sourceBeforeReplacement: sourceAfterFourthKey,
            range: NSRange(location: 1, length: 4),
            replacement: "分隔线"
        )
        let combinedDelta = 1 + quickEdit.characterDelta
        let sourceBeforeFourthKeyLength = ("A===\nB" as NSString).length
        let finalLength = sourceAfterFourthKeyLengthAfterApplying(quickEdit)
        assert(sourceBeforeFourthKeyLength + combinedDelta == finalLength)
    }

    private static func sourceAfterFourthKeyLengthAfterApplying(
        _ edit: NodeMarkdownTextKit2QuickInputEdit
    ) -> Int {
        edit.sourceBeforeReplacement.length + edit.characterDelta
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
    #endif
}
#endif
