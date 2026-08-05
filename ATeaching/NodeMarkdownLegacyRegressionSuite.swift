import Foundation
import SwiftUI

#if DEBUG
/// 旧管线的边界回归检查。这里不创建界面，也不依赖磁盘；启动旧管线时只运行一次，
/// 用纯数据验证行坐标、Node身份、焦点事务、版本作废和可见区刷新约束。
enum NodeMarkdownLegacyRegressionSuite {
    private static var hasRun = false

    static func runOnce() {
        guard !hasRun else { return }
        hasRun = true

        testFinalEmptyRow()
        testCharacterEditKeepsFollowingRowsAddressable()
        testFormulaAndImageDoNotCreateRows()
        testFocusAnchorFollowsNodeIdentity()
        testFocusAnchorIsConsumedOnce()
        testSnapshotKeepsNodeIdentity()
        testProtectedH3KeepsSourceIdentity()
        testUnlinkedH3IsNotProtected()
        testUndoSnapshotShape()
        testStaleRenderRevision()
        testInitialDocumentBuildsStaticSnapshot()
        testIncrementalRenderUsesOneResolvedRowSet()
        testBodyStyleLevelsDoNotShift()
        testMeasuredFormulaVerticalAlignment()
        testPersistenceSignatureResolvesImagePaths()
        testCourseInsertAnchorRequiresEditingSession()
        testSourceMetadataDoesNotChangeLayoutIdentity()
        testActiveNodeTransactionOwnsOnlyItsRow()
        testProtectedH3ReturnCreatesH4()
        testLeakedAttachmentSourceRepair()
        testFileBoundaryRepairsLeakedAttachmentSource()
    }

    private static func metadata(
        id: String,
        level: Int,
        sourceID: String = "",
        sourceFile: String = ""
    ) -> NodeMarkdownTextKitRowMetadata {
        NodeMarkdownTextKitRowMetadata(
            nodeID: id,
            level: level,
            sourceID: sourceID,
            sourceFile: sourceFile
        )
    }

    private static func testFinalEmptyRow() {
        let ranges = NodeMarkdownLegacyRowRangeIndex.rebuild(from: "A\n")
        assert(ranges == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 0)])
        assert(NodeMarkdownLegacyRowRangeIndex.rowIndex(
            containing: 2,
            in: ranges,
            editedRow: nil,
            characterDelta: 0
        ) == 1)
    }

    private static func testCharacterEditKeepsFollowingRowsAddressable() {
        let original = NodeMarkdownLegacyRowRangeIndex.rebuild(from: "A\nB\nC")
        let updated = NodeMarkdownLegacyRowRangeIndex.updatingCharacterEdit(
            ranges: original,
            editedRow: 1,
            text: "A\nBBBB\nC"
        )
        assert(updated?.count == 3)
        assert(updated?[2].location == 7)
    }

    private static func testFormulaAndImageDoNotCreateRows() {
        let text = "公式 $F=ma$\n![image](Pic/a.jpg){width=80}\n正文"
        let ranges = NodeMarkdownLegacyRowRangeIndex.rebuild(from: text)
        assert(ranges.count == 3)
        assert(NodeMarkdownLegacyRowRangeIndex.isValid(ranges, in: text as NSString))
    }

    private static func testFocusAnchorFollowsNodeIdentity() {
        var transaction = NodeMarkdownLegacyFocusTransaction()
        transaction.install(nodeID: "B", fallbackRow: 0, contentOffset: 3)
        let result = transaction.consume(metadata: [metadata(id: "A", level: 1), metadata(id: "B", level: 2)])
        assert(result?.row == 1 && result?.contentOffset == 3)
    }

    private static func testFocusAnchorIsConsumedOnce() {
        var transaction = NodeMarkdownLegacyFocusTransaction()
        transaction.install(nodeID: "A", fallbackRow: 0, contentOffset: 0)
        _ = transaction.consume(metadata: [metadata(id: "A", level: 1)])
        assert(transaction.consume(metadata: [metadata(id: "A", level: 1)]) == nil)
    }

    private static func testSnapshotKeepsNodeIdentity() {
        let snapshot = NodeMarkdownLegacyDocumentSnapshot(
            sessionID: UUID(),
            revision: 7,
            rows: [
                .init(nodeID: "A", level: 1, content: "标题", sourceID: "", sourceFile: ""),
                .init(nodeID: "B", level: 7, content: "正文", sourceID: "", sourceFile: "")
            ]
        )
        assert(snapshot.plainText == "标题\n正文")
        assert(snapshot.rowMetadata.map(\.nodeID) == ["A", "B"])
    }

    private static func testProtectedH3KeepsSourceIdentity() {
        let row = NodeMarkdownLegacyDocumentSnapshot.Row(
            nodeID: "H3",
            level: 3,
            content: "知识点",
            sourceID: "MASTER-H3",
            sourceFile: "教案.csv"
        )
        assert(row.metadata.isProtectedH3)
        assert(row.metadata.sourceID == "MASTER-H3")
        assert(row.metadata.sourceFile == "教案.csv")
    }

    private static func testUnlinkedH3IsNotProtected() {
        assert(!metadata(id: "NEW", level: 3).isProtectedH3)
        assert(!metadata(id: "HALF-ID", level: 3, sourceID: "MASTER-H3").isProtectedH3)
        assert(!metadata(id: "HALF-FILE", level: 3, sourceFile: "教案.csv").isProtectedH3)
        assert(metadata(id: "LINKED", level: 3, sourceID: "MASTER-H3", sourceFile: "教案.csv").isProtectedH3)
    }

    private static func testActiveNodeTransactionOwnsOnlyItsRow() {
        let stableText = "AAA\nBBB"
        let stableRanges = NodeMarkdownLegacyRowRangeIndex.rebuild(from: stableText)
        let draft = NodeMarkdownLegacyEditingNodeDraft(
            nodeID: UUID().uuidString,
            level: 7,
            content: "AAA",
            sourceID: "",
            sourceFile: ""
        )
        var transaction = NodeMarkdownLegacyActiveNodeTransaction(
            rowIndex: 0,
            range: stableRanges[0],
            draft: draft
        )
        let editedText = "AAAAA\nBBB" as NSString
        assert(transaction.synchronizeRange(in: editedText))
        assert(transaction.currentRange == NSRange(location: 0, length: 6))
        assert(transaction.effectiveRange(at: 1, stableRanges: stableRanges)?.location == 6)
        assert(
            editedText.substring(with: transaction.currentRange)
                .trimmingCharacters(in: .newlines) == "AAAAA"
        )
    }

    private static func testProtectedH3ReturnCreatesH4() {
        let protected = metadata(
            id: UUID().uuidString,
            level: 3,
            sourceID: UUID().uuidString,
            sourceFile: "教案.csv"
        )
        assert(NodeMarkdownLegacyStructurePolicy.insertedLevel(after: protected) == 4)
        assert(NodeMarkdownLegacyStructurePolicy.insertsEmptyChildInsteadOfSplitting(protected))
        assert(NodeMarkdownLegacyStructurePolicy.insertedLevel(after: metadata(id: "BODY", level: 8)) == 8)
        assert(!NodeMarkdownLegacyStructurePolicy.insertsEmptyChildInsteadOfSplitting(metadata(id: "BODY", level: 8)))
        assert(NodeMarkdownLegacyStructurePolicy.insertedLevel(after: metadata(id: "NEW-H3", level: 3)) == 3)
        assert(!NodeMarkdownLegacyStructurePolicy.insertsEmptyChildInsteadOfSplitting(metadata(id: "NEW-H3", level: 3)))
    }

    private static func testUndoSnapshotShape() {
        let rows = [
            NodeMarkdownLegacyDocumentSnapshot.Row(nodeID: "A", level: 1, content: "A", sourceID: "", sourceFile: ""),
            NodeMarkdownLegacyDocumentSnapshot.Row(nodeID: "B", level: 2, content: "B", sourceID: "", sourceFile: "")
        ]
        let snapshot = NodeMarkdownLegacyDocumentSnapshot(sessionID: UUID(), revision: 1, rows: rows)
        assert(snapshot.rows.count == snapshot.rowMetadata.count)
        assert(snapshot.plainText.split(separator: "\n", omittingEmptySubsequences: false).count == rows.count)
    }

    private static func testStaleRenderRevision() {
        let scheduled = NodeMarkdownLegacyRenderRevision(document: 1, style: 2, search: 3)
        let current = NodeMarkdownLegacyRenderRevision(document: 2, style: 2, search: 3)
        assert(scheduled != current)
    }

    private static func testInitialDocumentBuildsStaticSnapshot() {
        let visible = Set(500..<520)
        assert(NodeMarkdownLegacyRenderPolicy.rows(
            for: .initialDocument,
            rowCount: 10_000,
            visibleRows: visible
        ) == nil)
    }

    private static func testIncrementalRenderUsesOneResolvedRowSet() {
        let rows = NodeMarkdownLegacyRenderPolicy.incrementalRows(
            requestedRows: [5],
            rowCount: 12,
            visibleRows: Set(4...7),
            expandsNeighbors: true
        )
        assert(rows == Set([4, 5, 6]))

        let editingRows = NodeMarkdownLegacyRenderPolicy.incrementalRows(
            requestedRows: [5],
            rowCount: 12,
            visibleRows: Set(4...7),
            expandsNeighbors: false
        )
        assert(editingRows == Set([5]))
    }

    private static func testBodyStyleLevelsDoNotShift() {
        assert(NodeMarkdownStyleRole.role(forLevel: 7) == .body1)
        assert(NodeMarkdownStyleRole.role(forLevel: 8) == .body2)
        assert(NodeMarkdownStyleRole.role(forLevel: 9) == .body3)
        assert(NodeMarkdownStyleRole.role(forLevel: 10) == .body4)
        assert(NodeMarkdownStyleRole.role(forLevel: 11) == .body5)

        var style = NodeMarkdownDocumentStyle()
        style.body2 = NodeMarkdownRoleStyle(
            fontName: "BodyTwo", fontSize: 22, color: Color(red: 0.2, green: 0, blue: 0),
            semanticColor: nil, isBold: false, isUnderline: false, hasBackgroundBar: false,
            paragraphSpacingBefore: 2, paragraphSpacingAfter: 3, peerLineSpacing: 4
        )
        style.body3 = NodeMarkdownRoleStyle(
            fontName: "BodyThree", fontSize: 33, color: Color(red: 0.3, green: 0, blue: 0),
            semanticColor: nil, isBold: true, isUnderline: true, hasBackgroundBar: true,
            paragraphSpacingBefore: 5, paragraphSpacingAfter: 6, peerLineSpacing: 7
        )
        style.body4 = NodeMarkdownRoleStyle(
            fontName: "BodyFour", fontSize: 44, color: Color(red: 0.4, green: 0, blue: 0),
            semanticColor: nil, isBold: false, isUnderline: false, hasBackgroundBar: false,
            paragraphSpacingBefore: 8, paragraphSpacingAfter: 9, peerLineSpacing: 10
        )
        assert(style.style(forLevel: 9) == style.body3)
        assert(style.style(forLevel: 10) == style.body4)
        assert(style.style(forLevel: 10) != style.body3)
        assert(NodeMarkdownStyleRole.body3.level == 9)
        assert(NodeMarkdownStyleRole.body4.level == 10)
        let sourceRecord = NodeMarkdownDocumentStyleRecord(style: style)
        let restoredRecord = try? JSONDecoder().decode(
            NodeMarkdownDocumentStyleRecord.self,
            from: JSONEncoder().encode(sourceRecord)
        )
        // SwiftUI.Color经过sRGB分量落盘再重建后，视觉值相同但内部对象表示
        // 不保证Hashable完全相等。这里验证真正的JSON存储协议，既能发现
        // body3/body4错位，也不会因为Color内部表示变化在开课时误触发崩溃。
        assert(restoredRecord?.body3 == sourceRecord.body3)
        assert(restoredRecord?.body4 == sourceRecord.body4)
        assert(restoredRecord?.body3.fontName == "BodyThree")
        assert(restoredRecord?.body3.fontSize == 33)
        assert(restoredRecord?.body4.fontName == "BodyFour")
        assert(restoredRecord?.body4.fontSize == 44)

        let identityBeforeColorChange = style.renderIdentity
        style.body3.color = Color(red: 0.91, green: 0.17, blue: 0.29)
        assert(
            identityBeforeColorChange != style.renderIdentity,
            "A color-only style change must advance the render identity."
        )
    }

    private static func testMeasuredFormulaVerticalAlignment() {
        let metrics = NodeMarkdownRenderContract.inlineVerticalMetrics(
            fontAscender: 30,
            fontDescender: -10,
            fontLeading: 0,
            existingMinimumLineHeight: 44,
            renderedContentHeight: 100
        )
        assert(metrics.textHeight == 40)
        assert(metrics.lineHeight == 100)
        assert(metrics.textBaselineOffset == 28)

        let shortFormula = NodeMarkdownRenderContract.inlineVerticalMetrics(
            fontAscender: 30,
            fontDescender: -10,
            fontLeading: 0,
            existingMinimumLineHeight: 44,
            renderedContentHeight: 36
        )
        assert(shortFormula.lineHeight == 44)
        assert(shortFormula.textBaselineOffset == 0)
    }

    private static func testPersistenceSignatureResolvesImagePaths() {
        let notebookURL = URL(fileURLWithPath: "/tmp/student/note.csv")
        let sourceURL = URL(fileURLWithPath: "/tmp/system/chapter.csv")
        let imageURL = URL(fileURLWithPath: "/tmp/system/chapter/Pic/image.jpg")
        let notebookPath = NodeMarkdownImageResourceManager.relativePathString(
            from: notebookURL.deletingLastPathComponent(),
            to: imageURL
        )
        let sourcePath = NodeMarkdownImageResourceManager.relativePathString(
            from: sourceURL.deletingLastPathComponent(),
            to: imageURL
        )
        let packageID = UUID()
        let notebookPackage = [
            NodeMarkdownNode(id: packageID, level: 3, text: "包"),
            NodeMarkdownNode(
                level: 7,
                text: NodeMarkdownImageResourceManager.markdownImageToken(relativePath: notebookPath)
            )
        ]
        let sourcePackage = [
            NodeMarkdownNode(id: packageID, level: 3, text: "包"),
            NodeMarkdownNode(
                level: 7,
                text: NodeMarkdownImageResourceManager.markdownImageToken(relativePath: sourcePath)
            )
        ]
        assert(TeachingCoursePackageContentSignature.digest(notebookPackage)
            != TeachingCoursePackageContentSignature.digest(sourcePackage))
        assert(TeachingCoursePackageContentSignature.persistenceDigest(
            notebookPackage,
            documentFileURL: notebookURL
        ) == TeachingCoursePackageContentSignature.persistenceDigest(
            sourcePackage,
            documentFileURL: sourceURL
        ))
    }

    private static func testCourseInsertAnchorRequiresEditingSession() {
        let nodeID = UUID()
        assert(TeachingCourseInsertAnchor.resolve(isEditing: true, activeNodeID: nodeID) == .node(nodeID))
        assert(TeachingCourseInsertAnchor.resolve(isEditing: false, activeNodeID: nodeID) == .documentEnd)
        assert(TeachingCourseInsertAnchor.resolve(isEditing: true, activeNodeID: nil) == .documentEnd)
    }

    private static func testSourceMetadataDoesNotChangeLayoutIdentity() {
        let original = metadata(id: "A", level: 9, sourceID: "old", sourceFile: "old.csv")
        let relinked = metadata(id: "A", level: 9, sourceID: "new", sourceFile: "new.csv")
        let changedLevel = metadata(id: "A", level: 10, sourceID: "new", sourceFile: "new.csv")
        assert(original.hasSameLayoutIdentity(as: relinked))
        assert(!original.hasSameLayoutIdentity(as: changedLevel))
        assert(NodeMarkdownTextKitRowMetadata.collectionsHaveSameLayoutIdentity([original], [relinked]))
    }

    private static func testLeakedAttachmentSourceRepair() {
        let marker = "\u{FFFC}"
        assert(NodeMarkdownLegacyAttachmentSourceRepair.repair("$\(marker)\\frac{2}{3}$") == "$\\frac{2}{3}$")
        assert(NodeMarkdownLegacyAttachmentSourceRepair.repair("$mg = \(marker)F_向 = \(marker)F_万$") == "$mg = F_向 = F_万$")
        assert(NodeMarkdownLegacyAttachmentSourceRepair.repair("∑\(marker)F_引$＝0") == "∑$F_引$＝0")
        assert(NodeMarkdownLegacyAttachmentSourceRepair.repair("\(marker)ω_1t-ω_2t=2π") == "ω_1t-ω_2t=2π")
        assert(NodeMarkdownLegacyAttachmentSourceRepair.repair("\(marker)[image](Pic/a.jpg){width=80}") == "![image](Pic/a.jpg){width=80}")
    }

    private static func testFileBoundaryRepairsLeakedAttachmentSource() {
        let marker = "\u{FFFC}"
        let id = UUID().uuidString
        let source = "UUID,Prefix,Content,SourceID,SourceFile,Cach\n\(id),###### ,∑\(marker)F_引$＝0,,,"
        let loaded = NodeMarkdownFileManager.read(rawText: source)
        assert(loaded.0.nodes.first?.text == "∑$F_引$＝0")
        assert(!NodeMarkdownFileManager.serialize(document: loaded.0, meta: loaded.1).contains(marker))
    }
}
#endif
