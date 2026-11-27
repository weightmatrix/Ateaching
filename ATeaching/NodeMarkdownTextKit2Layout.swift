// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#endif
#if canImport(SwiftMath)
import SwiftMath
#endif

struct NodeMarkdownTextKit2RowLayout: Equatable {
    let rowIndex: Int
    let range: NSRange
    let contentRange: NSRange
    let prefix: String
    let level: Int
    let lineStyle: NodeMarkdownRenderContract.LineStyle
    let spacingBefore: CGFloat
    let isProtectedH3: Bool

    func replacingSpacingBefore(_ spacingBefore: CGFloat) -> NodeMarkdownTextKit2RowLayout {
        NodeMarkdownTextKit2RowLayout(
            rowIndex: rowIndex,
            range: range,
            contentRange: contentRange,
            prefix: prefix,
            level: level,
            lineStyle: lineStyle,
            spacingBefore: spacingBefore,
            isProtectedH3: isProtectedH3
        )
    }

    func offsetBy(_ delta: Int) -> NodeMarkdownTextKit2RowLayout {
        NodeMarkdownTextKit2RowLayout(
            rowIndex: rowIndex,
            range: NSRange(location: max(0, range.location + delta), length: range.length),
            contentRange: NSRange(location: max(0, contentRange.location + delta), length: contentRange.length),
            prefix: prefix,
            level: level,
            lineStyle: lineStyle,
            spacingBefore: spacingBefore,
            isProtectedH3: isProtectedH3
        )
    }

    func reindexed(_ newRowIndex: Int, offsetBy delta: Int = 0) -> NodeMarkdownTextKit2RowLayout {
        NodeMarkdownTextKit2RowLayout(
            rowIndex: newRowIndex,
            range: NSRange(location: max(0, range.location + delta), length: range.length),
            contentRange: NSRange(location: max(0, contentRange.location + delta), length: contentRange.length),
            prefix: prefix,
            level: level,
            lineStyle: lineStyle,
            spacingBefore: spacingBefore,
            isProtectedH3: isProtectedH3
        )
    }

    func changingLength(by delta: Int) -> NodeMarkdownTextKit2RowLayout? {
        let updatedRangeLength = range.length + delta
        let updatedContentLength = contentRange.length + delta
        guard updatedRangeLength >= 0, updatedContentLength >= 0 else { return nil }
        return NodeMarkdownTextKit2RowLayout(
            rowIndex: rowIndex,
            range: NSRange(location: range.location, length: updatedRangeLength),
            contentRange: NSRange(location: contentRange.location, length: updatedContentLength),
            prefix: prefix,
            level: level,
            lineStyle: lineStyle,
            spacingBefore: spacingBefore,
            isProtectedH3: isProtectedH3
        )
    }
}

/// Stores uniform suffix shifts once per block, while exposing absolute row coordinates.
struct NodeMarkdownRowLayouts: RandomAccessCollection, Equatable, ExpressibleByArrayLiteral {
    private struct Block: Equatable {
        var rows: [NodeMarkdownTextKit2RowLayout]
        var offset = 0

        subscript(index: Int) -> NodeMarkdownTextKit2RowLayout {
            offset == 0 ? rows[index] : rows[index].offsetBy(offset)
        }

        mutating func materialize() {
            guard offset != 0 else { return }
            rows = rows.map { $0.offsetBy(offset) }
            offset = 0
        }
    }

    private static let blockSize = 128
    private var blocks: [Block]
    let endIndex: Int
    var startIndex: Int { 0 }
    var indices: Range<Int> { startIndex..<endIndex }

    init(_ rows: [NodeMarkdownTextKit2RowLayout]) {
        endIndex = rows.count
        blocks = stride(from: 0, to: rows.count, by: Self.blockSize).map { start in
            Block(rows: Array(rows[start..<Swift.min(start + Self.blockSize, rows.count)]))
        }
    }

    init(arrayLiteral elements: NodeMarkdownTextKit2RowLayout...) {
        self.init(elements)
    }

    subscript(index: Int) -> NodeMarkdownTextKit2RowLayout {
        precondition(indices.contains(index))
        return blocks[index / Self.blockSize][index % Self.blockSize]
    }

    mutating func replaceRow(at index: Int, with row: NodeMarkdownTextKit2RowLayout) {
        guard self[index] != row else { return }
        let block = index / Self.blockSize
        blocks[block].materialize()
        blocks[block].rows[index % Self.blockSize] = row
    }

    mutating func shiftSuffix(from start: Int, by delta: Int) {
        guard delta != 0, start < endIndex else { return }
        let firstBlock = start / Self.blockSize
        for block in firstBlock..<blocks.count {
            let localStart = block == firstBlock ? start % Self.blockSize : 0
            let first = blocks[block][localStart]
            if localStart == 0, first.range.location + delta >= 0,
               first.contentRange.location + delta >= 0 {
                blocks[block].offset += delta
            } else {
                blocks[block].materialize()
                for index in localStart..<blocks[block].rows.count {
                    blocks[block].rows[index] = blocks[block].rows[index].offsetBy(delta)
                }
            }
        }
    }

    func intersectingRowIndices(_ range: NSRange) -> Range<Int> {
        guard range.length > 0 else { return 0..<0 }
        var lower = startIndex
        var upper = endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(self[middle].range) <= range.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let first = lower
        let end = NSMaxRange(range)
        while lower < endIndex, self[lower].range.location < end {
            lower += 1
        }
        return first..<lower
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.endIndex == rhs.endIndex else { return false }
        for index in lhs.blocks.indices {
            let left = lhs.blocks[index]
            let right = rhs.blocks[index]
            if left == right { continue }
            for row in left.rows.indices where left[row] != right[row] {
                return false
            }
        }
        return true
    }
}

enum NodeMarkdownTextKit2TransientLayoutProjection {
    static func project(
        _ layouts: NodeMarkdownRowLayouts,
        replacing affectedRange: NSRange,
        characterDelta: Int
    ) -> NodeMarkdownRowLayouts? {
        guard affectedRange.location != NSNotFound, affectedRange.length >= 0 else { return nil }
        let affectedEnd = NSMaxRange(affectedRange)

        // Content ranges follow document order. Find the first row whose end can
        // contain the edit, including an insertion exactly at the end of a row.
        var lower = layouts.startIndex
        var upper = layouts.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(layouts[middle].contentRange) < affectedEnd {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard layouts.indices.contains(lower),
              affectedRange.location >= layouts[lower].contentRange.location else { return nil }
        guard characterDelta != 0 else { return layouts }
        guard let changedRow = layouts[lower].changingLength(by: characterDelta) else { return nil }

        var projected = layouts
        projected.replaceRow(at: lower, with: changedRow)
        projected.shiftSuffix(from: lower + 1, by: characterDelta)
        return projected
    }
}

enum NodeMarkdownTextKit2RowLayoutReconciler {
    static func replacingRow(
        in layouts: NodeMarkdownRowLayouts,
        rowIndex: Int,
        with rebuiltRow: NodeMarkdownTextKit2RowLayout,
        documentLength: Int
    ) -> NodeMarkdownRowLayouts? {
        guard layouts.indices.contains(rowIndex),
              rebuiltRow.rowIndex == rowIndex,
              rebuiltRow.range.exact(toLength: documentLength) != nil,
              rebuiltRow.contentRange.exact(toLength: documentLength) != nil else {
            return nil
        }
        if rowIndex > 0 {
            guard NSMaxRange(layouts[rowIndex - 1].range) == rebuiltRow.range.location else {
                return nil
            }
        } else if rebuiltRow.range.location != 0 {
            return nil
        }

        var reconciled = layouts
        reconciled.replaceRow(at: rowIndex, with: rebuiltRow)
        if rowIndex + 1 < reconciled.count {
            let following = reconciled[rowIndex + 1]
            let requiredOffset = NSMaxRange(rebuiltRow.range) - following.range.location
            guard following.range.location + requiredOffset >= 0,
                  following.contentRange.location + requiredOffset >= 0 else { return nil }
            reconciled.shiftSuffix(from: rowIndex + 1, by: requiredOffset)
        }

        // 输入布局在上一次结构事务中已经完整验证。普通字符只改变一个Node的长度，
        // 后续范围统一增加同一个偏移，彼此之间的连续性在数学上不会改变；逐键再次
        // 遍历全表没有新增证明。这里只验证改动接缝和文档末端，完整校验留给结构事务。
        if rowIndex + 1 < reconciled.count {
            guard NSMaxRange(reconciled[rowIndex].range) == reconciled[rowIndex + 1].range.location else {
                return nil
            }
        }
        guard reconciled.last.map({ NSMaxRange($0.range) }) == documentLength else { return nil }
        return reconciled
    }
}

enum NodeMarkdownTextKit2FormulaRenderMode: Hashable {
    case display
    case text
}

struct NodeMarkdownTextKit2FormulaAttachmentCacheKey: Hashable {
    let latex: String
    let mode: Int
    let fontSize: Int
    let baseFontName: String
    let baseFontAscender: Int
    let baseFontDescender: Int
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int
}

struct NodeMarkdownTextKit2BackgroundGradientCacheKey: Hashable {
    let red: Int
    let green: Int
    let blue: Int
    let startAlpha: Int
    let endAlpha: Int
}
