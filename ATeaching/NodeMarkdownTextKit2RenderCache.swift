// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

struct NodeMarkdownTextKit2RenderCacheKey: Hashable {
    let nodeID: UUID
    let contentRevision: UInt64
    let styleRevision: Int
    let width: Int
}

/// 渲染产物按Node而不是行号缓存。结构插入不会让后面全部缓存错位。
final class NodeMarkdownTextKit2RenderCache<Value> {
    private var values: [NodeMarkdownTextKit2RenderCacheKey: Value] = [:]

    subscript(key: NodeMarkdownTextKit2RenderCacheKey) -> Value? {
        get { values[key] }
        set { values[key] = newValue }
    }

    func invalidate(nodeID: UUID) {
        values = values.filter { $0.key.nodeID != nodeID }
    }

    func retain(nodeIDs: Set<UUID>) {
        values = values.filter { nodeIDs.contains($0.key.nodeID) }
    }

    func removeAll(keepingCapacity: Bool = true) {
        values.removeAll(keepingCapacity: keepingCapacity)
    }
}
