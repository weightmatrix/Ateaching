// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    /// 新管线唯一的全文安装入口。首次载入和明确的外部文档替换必须共同经过这里。
    /// 普通字符输入、样式刷新和滚动严禁调用此方法。
    func installDocument(
        _ value: String,
        metadata: [NodeMarkdownTextKitRowMetadata],
        in textView: NodeMarkdownTextKit2TextView,
        preserving selectedRanges: [NSValue]? = nil,
        reason: String
    ) {
        NodeMarkdownTextKit2Diagnostics.log("准备安装文档，原因=\(reason)，binding长度=\((value as NSString).length)，metadata数量=\(metadata.count)。")
        NodeMarkdownTextKit2Diagnostics.log("安装文档Node层级样本=\(metadata.prefix(16).map(\.level))，Node UUID有效数量=\(metadata.prefix(16).filter { UUID(uuidString: $0.nodeID) != nil }.count)/\(min(16, metadata.count))。")
        guard documentState.replace(text: value, rowMetadata: metadata) else {
            NodeMarkdownTextKit2Diagnostics.log(
                "拒绝安装文档：\(documentState.lastValidationError?.description ?? "Node数据契约失败")。"
            )
            return
        }
        lifecycleState = .loading
        isApplyingExternalText = true
        textView.replaceDocumentText(
            value,
            documentStyle: documentStyle,
            selectedRanges: selectedRanges
        )
        rowMetadata = documentState.snapshot.rowMetadata
        isApplyingExternalText = false
        rebuildRowLayouts(from: textView)
        lifecycleState = .ready(revision: documentState.revision)
        validateTextKit2State(in: textView, deep: true)
        NodeMarkdownTextKit2Diagnostics.report(
            stage: "文档安装完成，原因=\(reason)",
            textView: textView,
            bindingText: value,
            metadataCount: rowMetadata.count,
            rowLayoutCount: rowLayouts.count
        )
    }
}
#endif
