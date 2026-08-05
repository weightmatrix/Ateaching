// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// 轻校验可在每次输入后运行；深校验只用于结构编辑和全文载入，避免高频路径扫描全文附件属性。
    func validateTextKit2State(
        in textView: NodeMarkdownTextKit2TextView,
        deep: Bool,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        #if DEBUG
        textView.assertSingleTextStorage(file: file, line: line)
        let sourceLength = (textView.documentString() as NSString).length
        assert(textView.nodeTextStorage.length == sourceLength, "TextKit2 storage/source length mismatch", file: file, line: line)
        assert(rowLayouts.count == rowCharacterRanges.count, "TextKit2 row layout/range count mismatch", file: file, line: line)

        var expectedLocation = 0
        for range in rowCharacterRanges {
            assert(range.location == expectedLocation, "TextKit2 row ranges are not contiguous", file: file, line: line)
            assert(range.location >= 0 && NSMaxRange(range) <= sourceLength, "TextKit2 row range escaped document", file: file, line: line)
            expectedLocation = NSMaxRange(range)
        }
        assert(expectedLocation == sourceLength, "TextKit2 row ranges do not cover document", file: file, line: line)

        for selectionValue in textView.selectedRanges {
            let selection = selectionValue.rangeValue
            assert(selection.location >= 0 && NSMaxRange(selection) <= sourceLength, "TextKit2 selection escaped document", file: file, line: line)
        }

        if deep {
            textView.assertSourceSnapshotMatchesStorage(file: file, line: line)
        }
        #endif
    }
}
#endif
