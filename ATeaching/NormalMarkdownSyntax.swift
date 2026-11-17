import Foundation
import Markdown

/// Shared CommonMark/GFM semantic results. Source text remains authoritative and is never formatted on save.
nonisolated enum NormalMarkdownSyntax {
    struct HeadingInfo: Sendable { let level: Int; let title: String; let offset: Int }
    struct Span: Sendable { enum Kind: Sendable, Equatable { case code, strong, emphasis, link }; let range: NSRange; let kind: Kind }
    struct Block: Sendable { let source: String; let preview: String; let startLine: Int }
    struct Snapshot: Sendable {
        var headings: [HeadingInfo] = []
        var spans: [Span] = []
        var literalRanges: [NSRange] = []
        var blocks: [Block] = []
        var spanMaxEnds: [Int] = []
        func clipped(to range: NSRange) -> Snapshot {
            var local = Snapshot()
            func lowerBound(_ count: Int, _ isBefore: (Int) -> Bool) -> Int {
                var low = 0, high = count
                while low < high {
                    let mid = (low + high) / 2
                    if isBefore(mid) { low = mid + 1 } else { high = mid }
                }
                return low
            }
            var index = lowerBound(headings.count) { headings[$0].offset < range.location }
            while index < headings.count, headings[index].offset < NSMaxRange(range) {
                let h = headings[index]
                local.headings.append(.init(level: h.level, title: h.title, offset: h.offset - range.location))
                index += 1
            }
            index = lowerBound(spanMaxEnds.count) { spanMaxEnds[$0] <= range.location }
            while index < spans.count, spans[index].range.location < NSMaxRange(range) {
                let span = spans[index], overlap = NSIntersectionRange(spans[index].range, range)
                if overlap.length > 0 { local.spans.append(.init(range: NSRange(location: overlap.location - range.location, length: overlap.length), kind: span.kind)) }
                index += 1
            }
            index = lowerBound(literalRanges.count) { NSMaxRange(literalRanges[$0]) <= range.location }
            while index < literalRanges.count, literalRanges[index].location < NSMaxRange(range) {
                let overlap = NSIntersectionRange(literalRanges[index], range)
                if overlap.length > 0 { local.literalRanges.append(NSRange(location: overlap.location - range.location, length: overlap.length)) }
                index += 1
            }
            var maxEnd = 0
            local.spanMaxEnds = local.spans.map { maxEnd = max(maxEnd, NSMaxRange($0.range)); return maxEnd }
            return local
        }
        func isLiteral(at offset: Int) -> Bool {
            var low = 0, high = literalRanges.count
            while low < high {
                let mid = (low + high) / 2
                if literalRanges[mid].location <= offset { low = mid + 1 } else { high = mid }
            }
            return low > 0 && NSLocationInRange(offset, literalRanges[low - 1])
        }
    }

    private final class Cached: NSObject {
        let condition = NSCondition()
        var snapshot: Snapshot?
        func wait() -> Snapshot {
            condition.lock(); defer { condition.unlock() }
            while snapshot == nil { condition.wait() }
            return snapshot!
        }
        func complete(_ value: Snapshot) {
            condition.lock(); snapshot = value; condition.broadcast(); condition.unlock()
        }
    }
    // Coalesce same-source TOC/preview/style requests without blocking unrelated line parses.
    private final class SyntaxCache: @unchecked Sendable {
        let lock = NSLock()
        let values = NSCache<NSString, Cached>()
        init() { values.countLimit = 8; values.totalCostLimit = 24 * 1024 * 1024 }
    }
    private static let cache = SyntaxCache()

    static func parse(_ source: String) -> Snapshot {
        let key = source as NSString
        cache.lock.lock()
        if let cached = cache.values.object(forKey: key) {
            cache.lock.unlock()
            return cached.wait()
        }
        let entry = Cached()
        cache.values.setObject(entry, forKey: key, cost: max(1, key.length * 6))
        cache.lock.unlock()
        let nsSource = source as NSString
        let sourceLength = nsSource.length
        let document = Document(parsing: source)
        let lines = source.components(separatedBy: "\n")
        var utf16Starts = [0], total = 0
        var corrections: [[(byteEnd: Int, delta: Int)]] = []
        for line in lines {
            total += line.utf16.count + 1
            utf16Starts.append(total)
            var byteEnd = 0, delta = 0
            var changes: [(byteEnd: Int, delta: Int)] = []
            for scalar in line.unicodeScalars {
                let bytes = scalar.utf8.count
                byteEnd += bytes
                let difference = bytes - scalar.utf16.count
                if difference != 0 { delta += difference; changes.append((byteEnd, delta)) }
            }
            corrections.append(changes)
        }
        func offset(_ location: SourceLocation) -> Int {
            let row = max(0, min(location.line - 1, lines.count - 1))
            let bytes = max(0, location.column - 1)
            let changes = corrections[row]
            var low = 0, high = changes.count
            while low < high {
                let mid = (low + high) / 2
                if changes[mid].byteEnd <= bytes { low = mid + 1 } else { high = mid }
            }
            let delta = low == 0 ? 0 : changes[low - 1].delta
            return utf16Starts[row] + bytes - delta
        }
        func range(_ node: any Markup) -> NSRange? {
            guard let r = node.range else { return nil }
            let a = offset(r.lowerBound), b = offset(r.upperBound)
            return NSRange(location: a, length: max(0, b - a))
        }
        var result = Snapshot()
        var resolvedLinks: [(range: NSRange, markdown: String)] = []
        func visit(_ node: any Markup) {
            if let heading = node as? Heading, let r = range(node) {
                result.headings.append(.init(level: heading.level, title: heading.plainText, offset: r.location))
            }
            if let r = range(node) {
                if node is Link || node is Image {
                    resolvedLinks.append((r, node.format()))
                }
                if node is CodeBlock { result.literalRanges.append(r); return }
                // HTML keeps the app's existing image-width/inline-tag extensions.
                if node is HTMLBlock { return }
                let kind: Span.Kind? = node is InlineCode ? .code : node is Strong ? .strong : node is Emphasis ? .emphasis : node is Link ? .link : nil
                if let kind { result.spans.append(.init(range: r, kind: kind)) }
            }
            for child in node.children { visit(child) }
        }
        visit(document)
        result.literalRanges.sort { $0.location < $1.location }
        var mathRanges: [(range: NSRange, startLine: Int)] = []
        var mathStart: (line: Int, closing: String)?
        for (row, line) in lines.enumerated() {
            let marker = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isLiteral(at: utf16Starts[row]) else { continue }
            if let opening = mathStart {
                if marker == opening.closing {
                    mathRanges.append((NSRange(location: utf16Starts[opening.line], length: min(sourceLength, utf16Starts[row + 1]) - utf16Starts[opening.line]), opening.line))
                    mathStart = nil
                }
            } else if marker == "$$" || marker == "\\[" {
                mathStart = (row, marker == "$$" ? "$$" : "\\]")
            }
        }
        if let opening = mathStart {
            mathRanges.append((NSRange(location: utf16Starts[opening.line], length: sourceLength - utf16Starts[opening.line]), opening.line))
        }
        var headingMathIndex = 0
        result.headings.removeAll { heading in
            while headingMathIndex < mathRanges.count, NSMaxRange(mathRanges[headingMathIndex].range) <= heading.offset { headingMathIndex += 1 }
            return headingMathIndex < mathRanges.count && NSLocationInRange(heading.offset, mathRanges[headingMathIndex].range)
        }
        // AST boundaries retain fenced blocks/list continuations across blank lines.
        // Expand resolved links only for preview; retain raw formula/HTML/custom extension syntax.
        let orderedLinks = resolvedLinks.sorted {
            $0.range.location == $1.range.location ? $0.range.length > $1.range.length : $0.range.location < $1.range.location
        }
        var linkIndex = 0
        var mathIndex = 0
        var pendingMath: (range: NSRange, startLine: Int)?
        func appendMath() {
            guard let pending = pendingMath else { return }
            let raw = nsSource.substring(with: pending.range)
            result.blocks.append(.init(source: raw, preview: raw, startLine: pending.startLine))
            pendingMath = nil
        }
        for child in document.children {
            guard let r = range(child), NSMaxRange(r) <= sourceLength else { continue }
            while mathIndex < mathRanges.count, NSMaxRange(mathRanges[mathIndex].range) <= r.location { mathIndex += 1 }
            if mathIndex < mathRanges.count, NSIntersectionRange(r, mathRanges[mathIndex].range).length > 0 {
                let math = mathRanges[mathIndex]
                let combined = NSUnionRange(r, math.range)
                if let pending = pendingMath {
                    pendingMath = (NSUnionRange(pending.range, combined), pending.startLine)
                } else { pendingMath = (combined, min(math.startLine, max(0, (child.range?.lowerBound.line ?? 1) - 1))) }
                continue
            }
            appendMath()
            let raw = nsSource.substring(with: r)
            let preview = NSMutableString(string: raw)
            var blockLinks: [(range: NSRange, markdown: String)] = []
            while linkIndex < orderedLinks.count, orderedLinks[linkIndex].range.location < NSMaxRange(r) {
                let link = orderedLinks[linkIndex]
                if link.range.location >= (blockLinks.last.map { NSMaxRange($0.range) } ?? r.location) { blockLinks.append(link) }
                linkIndex += 1
            }
            var replacedStart = NSMaxRange(r)
            for link in blockLinks.reversed() {
                guard link.range.location >= r.location, NSMaxRange(link.range) <= replacedStart,
                      NSMaxRange(link.range) <= NSMaxRange(r) else { continue }
                preview.replaceCharacters(in: NSRange(location: link.range.location - r.location, length: link.range.length), with: link.markdown)
                replacedStart = link.range.location
            }
            result.blocks.append(.init(source: raw, preview: preview as String, startLine: max(0, (child.range?.lowerBound.line ?? 1) - 1)))
        }
        appendMath()
        result.headings.sort { $0.offset < $1.offset }
        result.literalRanges.append(contentsOf: mathRanges.map(\.range))
        var mergedLiterals: [NSRange] = []
        for range in result.literalRanges.sorted(by: { $0.location < $1.location }) {
            if let last = mergedLiterals.last, range.location <= NSMaxRange(last) {
                mergedLiterals[mergedLiterals.count - 1] = NSUnionRange(last, range)
            } else { mergedLiterals.append(range) }
        }
        result.literalRanges = mergedLiterals
        let literalContext = result
        result.spans.removeAll { literalContext.isLiteral(at: $0.range.location) }
        result.spans.sort { $0.range.location < $1.range.location }
        var maxEnd = 0
        result.spanMaxEnds = result.spans.map { maxEnd = max(maxEnd, NSMaxRange($0.range)); return maxEnd }
        result.literalRanges.sort { $0.location < $1.location }
        entry.complete(result)
        return result
    }
}
