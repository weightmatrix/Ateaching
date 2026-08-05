// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    static func applySearchHighlights(
        to styled: NSMutableAttributedString,
        source nsText: NSString,
        layout: NodeMarkdownTextKit2RowLayout,
        textLength: Int,
        searchQuery: String,
        activeRowIndex: Int?,
        activeMatchLocationInRow: Int?
    ) {
        let normalizedSearchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchQuery.isEmpty else { return }
        let searchableRange = layout.contentRange.clamped(toLength: textLength) ?? NSRange(location: 0, length: 0)
        guard searchableRange.length > 0 else { return }

        var remaining = searchableRange
        while remaining.length > 0 {
            let match = nsText.range(
                of: normalizedSearchQuery,
                options: [.caseInsensitive],
                range: remaining
            )
            guard match.location != NSNotFound, match.length > 0 else { break }

            let matchLocationInRow = match.location - searchableRange.location
            let isCurrentMatch = layout.rowIndex == activeRowIndex
                && matchLocationInRow == activeMatchLocationInRow
            styled.addAttribute(
                .backgroundColor,
                value: searchHighlightColor(isCurrentMatch: isCurrentMatch),
                range: match
            )

            let nextLocation = match.location + match.length
            let lineEnd = searchableRange.location + searchableRange.length
            guard nextLocation < lineEnd else { break }
            remaining = NSRange(location: nextLocation, length: lineEnd - nextLocation)
        }
    }

    private static func searchHighlightColor(isCurrentMatch: Bool) -> NSColor {
        NSColor(
            red: 240.0 / 255.0,
            green: 200.0 / 255.0,
            blue: 71.0 / 255.0,
            alpha: isCurrentMatch ? 0.58 : 0.34
        )
    }
}
#endif
