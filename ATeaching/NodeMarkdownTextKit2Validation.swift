// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// 轻校验可在每次输入后运行；深校验只用于结构编辑和全文载入，避免高频路径扫描全文附件属性。
    @discardableResult
    func validateTextKit2State(
        in textView: NodeMarkdownTextKit2TextView,
        deep: Bool,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        #if DEBUG
        guard !textView.hasActiveInputMethodComposition else {
            NodeMarkdownTextKit2Diagnostics.log(
                "状态校验暂缓：输入法事务尚未提交，storage长度=\(textView.nodeTextStorage.length)，稳定源码长度=\((textView.documentString() as NSString).length)。"
            )
            return true
        }
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "状态校验开始，deep=\(deep)",
            textView: textView,
            metadataCount: rowMetadata.count,
            rowLayoutCount: rowLayouts.count
        )
        guard textView.hasSingleTextStorage else {
            NodeMarkdownTextKit2Diagnostics.log("状态校验失败：TextView不再使用唯一TextKit2对象链。")
            return false
        }
        let sourceLength = (textView.documentString() as NSString).length
        guard textView.nodeTextStorage.length == sourceLength else {
            NodeMarkdownTextKit2Diagnostics.log("状态校验失败：TextStorage长度\(textView.nodeTextStorage.length)与源码长度\(sourceLength)不一致。")
            return false
        }
        guard rowLayouts.count == rowCharacterRanges.count,
              rowLayouts.count == rowMetadata.count,
              rowLayouts.count == documentState.nodes.count else {
            NodeMarkdownTextKit2Diagnostics.log("状态校验失败：布局\(rowLayouts.count)、范围\(rowCharacterRanges.count)、元数据\(rowMetadata.count)、Node\(documentState.nodes.count)数量不一致。")
            return false
        }

        if deep {
            var expectedLocation = 0
            for (row, range) in rowCharacterRanges.enumerated() {
                guard range.location == expectedLocation,
                      range.exact(toLength: sourceLength) != nil else {
                    NodeMarkdownTextKit2Diagnostics.log("状态校验失败：第\(row + 1)行范围\(NSStringFromRange(range))不连续或越界，期望起点\(expectedLocation)。")
                    return false
                }
                expectedLocation = NSMaxRange(range)
            }
            guard expectedLocation == sourceLength else {
                NodeMarkdownTextKit2Diagnostics.log("状态校验失败：行范围末端\(expectedLocation)没有覆盖源码末端\(sourceLength)。")
                return false
            }
        } else if let row = currentRowIndex(in: textView) {
            let range = rowCharacterRanges[row]
            guard range.exact(toLength: sourceLength) != nil,
                  (row == 0 || NSMaxRange(rowCharacterRanges[row - 1]) == range.location),
                  (row + 1 == rowCharacterRanges.count
                      || NSMaxRange(range) == rowCharacterRanges[row + 1].location),
                  rowCharacterRanges.last.map(NSMaxRange) == sourceLength else {
                NodeMarkdownTextKit2Diagnostics.log("轻校验失败：当前Node或相邻边界不连续。")
                return false
            }
        }

        for selectionValue in textView.selectedRanges {
            let selection = selectionValue.rangeValue
            guard selection.exact(toLength: sourceLength) != nil else {
                NodeMarkdownTextKit2Diagnostics.log("状态校验失败：选区\(NSStringFromRange(selection))越出真实源码。")
                return false
            }
        }

        if deep, !textView.sourceSnapshotMatchesStorage() {
            NodeMarkdownTextKit2Diagnostics.log("状态校验失败：源码快照与唯一TextStorage不一致。")
            return false
        }
        NodeMarkdownTextKit2Diagnostics.log("状态校验通过，deep=\(deep)，源码长度=\(sourceLength)，行数=\(rowCharacterRanges.count)。")
        return true
        #endif
        #if !DEBUG
        return true
        #endif
    }
}
#endif
