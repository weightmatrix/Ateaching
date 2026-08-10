// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

/// 新管线唯一的活动Node草稿。普通输入只改变这里和当前TextStorage，不接触其他Node。
struct NodeMarkdownTextKit2ActiveNodeSession: Equatable {
    let nodeID: UUID
    let baseline: NodeMarkdownTextKit2Node
    var draft: NodeMarkdownTextKit2Node

    init(node: NodeMarkdownTextKit2Node) {
        nodeID = node.id
        baseline = node
        draft = node
    }

    var isDirty: Bool { draft != baseline }
}

enum NodeMarkdownTextKit2LifecycleState: Equatable {
    case empty
    case loading
    case ready(revision: UInt64)
    case editing(nodeID: UUID, revision: UInt64)
}
