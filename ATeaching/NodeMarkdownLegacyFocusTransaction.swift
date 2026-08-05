import Foundation

/// 结构编辑的焦点身份。全文字符位置会被公式、图片和段落重排改变，
/// 因而只保存Node UUID、行号回退和Node内部UTF-16偏移。
struct NodeMarkdownLegacyFocusAnchor: Equatable {
    let nodeID: String
    let fallbackRow: Int
    let contentOffset: Int
}

/// 一次性焦点事务。安装后只能消费一次；消费会先销毁状态，再解析最终Node行号。
/// 渲染器、SwiftUI回写和输入法都不能持有或重复使用已消费的锚点。
struct NodeMarkdownLegacyFocusTransaction {
    private(set) var pendingAnchor: NodeMarkdownLegacyFocusAnchor?

    mutating func install(nodeID: String, fallbackRow: Int, contentOffset: Int) {
        pendingAnchor = NodeMarkdownLegacyFocusAnchor(
            nodeID: nodeID,
            fallbackRow: max(0, fallbackRow),
            contentOffset: max(0, contentOffset)
        )
    }

    mutating func cancel() {
        pendingAnchor = nil
    }

    mutating func consume(metadata: [NodeMarkdownTextKitRowMetadata]) -> (row: Int, contentOffset: Int)? {
        guard let anchor = pendingAnchor else { return nil }
        pendingAnchor = nil
        guard !metadata.isEmpty else { return nil }
        let row: Int
        if !anchor.nodeID.isEmpty,
           let matched = metadata.firstIndex(where: { $0.nodeID == anchor.nodeID }) {
            row = matched
        } else {
            row = min(anchor.fallbackRow, metadata.count - 1)
        }
        return (row, anchor.contentOffset)
    }
}
