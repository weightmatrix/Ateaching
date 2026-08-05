// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    func editableLocation(for location: Int) -> Int {
        let textLength = (documentString() as NSString).length
        let safeLocation = max(0, min(location, textLength))
        guard !nodeMarkdownRowLayouts.isEmpty else { return safeLocation }

        let anchor: Int
        if safeLocation == textLength {
            anchor = max(0, textLength - 1)
        } else {
            anchor = safeLocation
        }

        guard let layout = nodeMarkdownRowLayouts.first(where: { layout in
            anchor >= layout.range.location && anchor < NSMaxRange(layout.range)
        }) else {
            return safeLocation
        }

        if safeLocation <= layout.contentRange.location {
            return layout.contentRange.location
        }
        return safeLocation
    }

    func clampedEditableSelection(_ range: NSRange) -> NSRange {
        let textLength = (documentString() as NSString).length
        guard let safeRange = range.clamped(toLength: textLength) else {
            return NSRange(location: editableLocation(for: textLength), length: 0)
        }

        let lower = editableLocation(for: safeRange.location)
        let upper = editableLocation(for: NSMaxRange(safeRange))
        if upper < lower {
            return NSRange(location: lower, length: 0)
        }
        return NSRange(location: lower, length: upper - lower)
    }

    func clampedEditableSelections(_ range: NSRange) -> [NSRange] {
        let textLength = (documentString() as NSString).length
        guard let safeRange = range.clamped(toLength: textLength) else {
            return [NSRange(location: editableLocation(for: textLength), length: 0)]
        }
        guard safeRange.length > 0 else {
            return [clampedEditableSelection(safeRange)]
        }

        var ranges: [NSRange] = []
        for layout in nodeMarkdownRowLayouts {
            let intersection = NSIntersectionRange(safeRange, layout.range)
            guard intersection.length > 0 else { continue }
            let lower = max(intersection.location, layout.contentRange.location)
            let upper = min(NSMaxRange(intersection), NSMaxRange(layout.contentRange))
            if upper > lower {
                ranges.append(NSRange(location: lower, length: upper - lower))
            }
        }

        if ranges.isEmpty {
            return [clampedEditableSelection(safeRange)]
        }
        return ranges
    }

    func normalizeSelectedRangesToEditableContent() {
        let normalized = selectedRanges.flatMap { value -> [NSValue] in
            clampedEditableSelections(value.rangeValue).map { NSValue(range: $0) }
        }
        guard !normalized.isEmpty else { return }
        guard normalized.map(\.rangeValue) != selectedRanges.map(\.rangeValue) else { return }
        selectedRanges = normalized
    }

    func editableChangeRange(for affectedRange: NSRange) -> NSRange? {
        let textLength = (documentString() as NSString).length
        guard let safeRange = affectedRange.clamped(toLength: textLength) else { return nil }
        let clamped = clampedEditableSelection(safeRange)
        if safeRange.length == 0 {
            return NSRange(location: clamped.location, length: 0)
        }
        guard clamped.length > 0 else { return nil }
        return clamped
    }
}
#endif
