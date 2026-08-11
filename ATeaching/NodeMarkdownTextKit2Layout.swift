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

enum NodeMarkdownTextKit2TransientLayoutProjection {
    static func project(
        _ layouts: [NodeMarkdownTextKit2RowLayout],
        replacing affectedRange: NSRange,
        characterDelta: Int
    ) -> [NodeMarkdownTextKit2RowLayout]? {
        guard affectedRange.location != NSNotFound,
              affectedRange.length >= 0,
              let rowIndex = layouts.firstIndex(where: { layout in
                  affectedRange.location >= layout.contentRange.location
                      && NSMaxRange(affectedRange) <= NSMaxRange(layout.contentRange)
              }),
              let changedRow = layouts[rowIndex].changingLength(by: characterDelta) else {
            return nil
        }

        var projected = layouts
        projected[rowIndex] = changedRow
        if characterDelta != 0, rowIndex + 1 < projected.count {
            for index in (rowIndex + 1)..<projected.count {
                projected[index] = projected[index].offsetBy(characterDelta)
            }
        }
        return projected
    }
}

enum NodeMarkdownTextKit2RowLayoutReconciler {
    static func replacingRow(
        in layouts: [NodeMarkdownTextKit2RowLayout],
        rowIndex: Int,
        with rebuiltRow: NodeMarkdownTextKit2RowLayout,
        documentLength: Int
    ) -> [NodeMarkdownTextKit2RowLayout]? {
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
        reconciled[rowIndex] = rebuiltRow
        if rowIndex + 1 < reconciled.count {
            let followingStart = reconciled[rowIndex + 1].range.location
            let realFollowingStart = NSMaxRange(rebuiltRow.range)
            let requiredOffset = realFollowingStart - followingStart
            if requiredOffset != 0 {
                for index in (rowIndex + 1)..<reconciled.count {
                    guard reconciled[index].range.location + requiredOffset >= 0,
                          reconciled[index].contentRange.location + requiredOffset >= 0 else {
                        return nil
                    }
                    reconciled[index] = reconciled[index].offsetBy(requiredOffset)
                }
            }
        }

        var expectedLocation = 0
        for layout in reconciled {
            guard layout.range.location == expectedLocation,
                  layout.range.exact(toLength: documentLength) != nil,
                  layout.contentRange.exact(toLength: documentLength) != nil else {
                return nil
            }
            expectedLocation = NSMaxRange(layout.range)
        }
        guard expectedLocation == documentLength else { return nil }
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
