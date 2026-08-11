// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    func editableLocation(for location: Int) -> Int? {
        let textLength = (documentString() as NSString).length
        guard NSRange(location: location, length: 0).exact(toLength: textLength) != nil,
              let layout = exactRowLayout(containingCaretAt: location, textLength: textLength) else {
            return nil
        }

        if location <= layout.contentRange.location {
            return layout.contentRange.location
        }
        return min(location, NSMaxRange(layout.contentRange))
    }

    func clampedEditableSelection(_ range: NSRange) -> NSRange? {
        let textLength = (documentString() as NSString).length
        guard let safeRange = range.exact(toLength: textLength),
              let lower = editableLocation(for: safeRange.location),
              let upper = editableLocation(for: NSMaxRange(safeRange)),
              upper >= lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    func clampedEditableSelections(_ range: NSRange) -> [NSRange]? {
        let textLength = (documentString() as NSString).length
        guard let safeRange = range.exact(toLength: textLength) else { return nil }
        guard safeRange.length > 0 else {
            guard let selection = clampedEditableSelection(safeRange) else { return nil }
            return [selection]
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
            guard let selection = clampedEditableSelection(safeRange) else { return nil }
            return [selection]
        }
        return ranges
    }

    func normalizeSelectedRangesToEditableContent() {
        let normalizedGroups = selectedRanges.compactMap { value -> [NSValue]? in
            clampedEditableSelections(value.rangeValue)?.map { NSValue(range: $0) }
        }
        guard normalizedGroups.count == selectedRanges.count else {
            NodeMarkdownTextKit2Diagnostics.log("拒绝规范化选区：存在无法与真实行边界对应的选区。")
            return
        }
        let normalized = normalizedGroups.flatMap { $0 }
        guard !normalized.isEmpty else { return }
        guard normalized.map(\.rangeValue) != selectedRanges.map(\.rangeValue) else { return }
        let before = selectedRange()
        selectedRanges = normalized
        if let requested = normalized.first?.rangeValue {
            NodeMarkdownDiagnostic31.recordSelectionWrite(
                "normalizeSelectedRangesToEditableContent",
                before: before,
                requested: requested,
                in: self,
                rowLayouts: nodeMarkdownRowLayouts
            )
        }
    }

    func editableChangeRange(for affectedRange: NSRange) -> NSRange? {
        let textLength = (documentString() as NSString).length
        guard let safeRange = affectedRange.exact(toLength: textLength),
              let clamped = clampedEditableSelection(safeRange) else { return nil }
        if safeRange.length == 0 {
            return NSRange(location: clamped.location, length: 0)
        }
        guard clamped.length > 0 else { return nil }
        return clamped
    }

    private func exactRowLayout(
        containingCaretAt location: Int,
        textLength: Int
    ) -> NodeMarkdownTextKit2RowLayout? {
        guard !nodeMarkdownRowLayouts.isEmpty else { return nil }
        if textLength == 0 {
            guard nodeMarkdownRowLayouts.count == 1,
                  nodeMarkdownRowLayouts[0].range == NSRange(location: 0, length: 0) else { return nil }
            return nodeMarkdownRowLayouts[0]
        }
        if location == textLength {
            guard let last = nodeMarkdownRowLayouts.last,
                  NSMaxRange(last.range) == textLength else { return nil }
            return last
        }
        var lower = 0
        var upper = nodeMarkdownRowLayouts.count - 1
        while lower <= upper {
            let middle = (lower + upper) / 2
            let layout = nodeMarkdownRowLayouts[middle]
            if location < layout.range.location {
                upper = middle - 1
            } else if location >= NSMaxRange(layout.range) {
                lower = middle + 1
            } else {
                return layout
            }
        }
        return nil
    }
}
#endif
