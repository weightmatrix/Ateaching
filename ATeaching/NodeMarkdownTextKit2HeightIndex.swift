// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import Foundation

/// Fenwick高度索引。Node高度变化和y坐标查找均为O(log N)，全文越长不会拖慢当前Node输入。
struct NodeMarkdownTextKit2HeightIndex {
    private var heights: [Double] = []
    private var tree: [Double] = [0]

    var count: Int { heights.count }
    var totalHeight: Double { prefixSum(count) }

    mutating func replace(with values: [Double]) {
        heights = values.map { max(0, $0) }
        tree = Array(repeating: 0, count: heights.count + 1)
        for index in heights.indices { add(heights[index], at: index) }
    }

    mutating func updateHeight(_ value: Double, at index: Int) {
        guard heights.indices.contains(index) else { return }
        let normalized = max(0, value)
        let delta = normalized - heights[index]
        guard delta != 0 else { return }
        heights[index] = normalized
        add(delta, at: index)
    }

    func height(at index: Int) -> Double? {
        heights.indices.contains(index) ? heights[index] : nil
    }

    func offset(of index: Int) -> Double { prefixSum(max(0, min(index, count))) }

    func row(containingY y: Double) -> Int? {
        guard !heights.isEmpty else { return nil }
        let target = max(0, min(y, max(0, totalHeight.nextDown)))
        var index = 0
        var accumulated = 0.0
        var bit = 1
        while bit << 1 <= count { bit <<= 1 }
        while bit > 0 {
            let next = index + bit
            if next <= count, accumulated + tree[next] <= target {
                index = next
                accumulated += tree[next]
            }
            bit >>= 1
        }
        return min(index, count - 1)
    }

    private func prefixSum(_ end: Int) -> Double {
        var cursor = max(0, min(end, count))
        var result = 0.0
        while cursor > 0 {
            result += tree[cursor]
            cursor -= cursor & -cursor
        }
        return result
    }

    private mutating func add(_ delta: Double, at index: Int) {
        var cursor = index + 1
        while cursor < tree.count {
            tree[cursor] += delta
            cursor += cursor & -cursor
        }
    }
}
