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
}

enum NodeMarkdownTextKit2FormulaRenderMode: Hashable {
    case display
    case text
}

struct NodeMarkdownTextKit2FormulaAttachmentCacheKey: Hashable {
    let latex: String
    let mode: Int
    let fontSize: Int
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
