// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

struct NodeMarkdownTextKit2RenderCacheKey: Hashable {
    let documentID: UUID
    let nodeID: UUID
    let nodeRevision: UInt64
    let styleRevision: Int
    let visualRevision: UInt64
    let width: Int
    let scaleMilli: Int
}

/// 渲染产物按Node而不是行号缓存。结构插入不会让后面全部缓存错位。
final class NodeMarkdownTextKit2RenderCache<Value> {
    private var values: [NodeMarkdownTextKit2RenderCacheKey: Value] = [:]
    private var accessOrder: [NodeMarkdownTextKit2RenderCacheKey: UInt64] = [:]
    private var accessQueue: [(key: NodeMarkdownTextKit2RenderCacheKey, stamp: UInt64)] = []
    private var queueHead = 0
    private var clock: UInt64 = 0
    var capacity: Int

    init(capacity: Int = 1_024) {
        self.capacity = max(16, capacity)
    }

    subscript(key: NodeMarkdownTextKit2RenderCacheKey) -> Value? {
        get {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }
        set {
            values[key] = newValue
            if newValue == nil {
                accessOrder[key] = nil
            } else {
                touch(key)
                evictIfNeeded()
            }
        }
    }

    func invalidate(nodeID: UUID) {
        let keys = values.keys.filter { $0.nodeID == nodeID }
        keys.forEach { values[$0] = nil; accessOrder[$0] = nil }
    }

    func retain(nodeIDs: Set<UUID>) {
        let keys = values.keys.filter { !nodeIDs.contains($0.nodeID) }
        keys.forEach { values[$0] = nil; accessOrder[$0] = nil }
    }

    func removeAll(keepingCapacity: Bool = true) {
        values.removeAll(keepingCapacity: keepingCapacity)
        accessOrder.removeAll(keepingCapacity: keepingCapacity)
        accessQueue.removeAll(keepingCapacity: keepingCapacity)
        queueHead = 0
    }

    var count: Int { values.count }

    private func touch(_ key: NodeMarkdownTextKit2RenderCacheKey) {
        clock &+= 1
        accessOrder[key] = clock
        accessQueue.append((key, clock))
    }

    private func evictIfNeeded() {
        while values.count > capacity, queueHead < accessQueue.count {
            let candidate = accessQueue[queueHead]
            queueHead += 1
            guard accessOrder[candidate.key] == candidate.stamp else { continue }
            values[candidate.key] = nil
            accessOrder[candidate.key] = nil
        }
        if queueHead > 4_096, queueHead * 2 > accessQueue.count {
            accessQueue.removeFirst(queueHead)
            queueHead = 0
        }
    }
}
