import Foundation
import Markdown

/// Shared CommonMark/GFM semantic results. Source text remains authoritative and is never formatted on save.
nonisolated enum NormalMarkdownSyntax {
    struct HeadingInfo: Sendable { let level: Int; let title: String; let offset: Int }
    struct Span: Sendable { enum Kind: Sendable, Equatable { case code, strong, emphasis, link }; let range: NSRange; let kind: Kind }
    struct Block: Sendable { let source: String; let preview: String; let startLine: Int }
    struct Unit: Sendable {
        enum Kind: Sendable, Equatable { case paragraph, heading, code, other }
        var range: NSRange
        var startLine: Int
        let kind: Kind
    }
    struct Snapshot: Sendable {
        var units: [Unit] = []
        var requiresFullParse = false
        var parsedUTF16 = 0
        var reusedUnits = 0
        var lineStarts: [Int] = []
        var headings: [HeadingInfo] = []
        func headingLevel(at offset: Int) -> Int? {
            var low = 0, high = headings.count
            while low < high {
                let mid = (low + high) / 2
                if headings[mid].offset < offset { low = mid + 1 } else { high = mid }
            }
            return low < headings.count && headings[low].offset == offset ? headings[low].level : nil
        }
        func lineIndex(at offset: Int) -> Int {
            var low = 0, high = lineStarts.count
            while low < high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= offset { low = mid + 1 } else { high = mid }
            }
            return max(0, low - 1)
        }
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
        var previousLarge: (source: String, snapshot: Snapshot)?
        init() { values.countLimit = 8; values.totalCostLimit = 24 * 1024 * 1024 }
    }
    private static let cache = SyntaxCache()

    static func parse(_ source: String, useIncremental: Bool = true) -> Snapshot {
        let key = source as NSString
        cache.lock.lock()
        if useIncremental, let cached = cache.values.object(forKey: key) {
            cache.lock.unlock()
            let snapshot = cached.wait()
            remember(source, snapshot: snapshot)
            return snapshot
        }
        let entry = Cached()
        if useIncremental { cache.values.setObject(entry, forKey: key, cost: max(1, key.length * 6)) }
        let previous = useIncremental ? cache.previousLarge : nil
        cache.lock.unlock()
        if key.length >= 16_384, let previous,
           let incremental = incrementallyParse(source, previousSource: previous.source, previous: previous.snapshot) {
            entry.complete(incremental)
            remember(source, snapshot: incremental)
            return incremental
        }
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
        result.lineStarts = utf16Starts.filter { $0 <= sourceLength }
        result.parsedUTF16 = sourceLength
        result.requiresFullParse = source.range(of: #"(?m)^ {0,3}\[[^\]\n]+\]:"#, options: .regularExpression) != nil
        for child in document.children {
            guard let r = range(child) else { continue }
            let kind: Unit.Kind = child is Paragraph ? .paragraph : child is Heading ? .heading : child is CodeBlock ? .code : .other
            result.units.append(.init(range: r, startLine: max(0, (child.range?.lowerBound.line ?? 1) - 1), kind: kind))
        }
        var resolvedLinks: [(range: NSRange, markdown: String)] = []
        func visit(_ node: any Markup) {
            if let heading = node as? Heading, let r = range(node) {
                let markerLine = lines[max(0, min((heading.range?.lowerBound.line ?? 1) - 1, lines.count - 1))]
                if markerLine.range(of: #"^ {0,3}#{1,6}\r?$"#, options: .regularExpression) == nil {
                    result.headings.append(.init(level: heading.level, title: heading.plainText, offset: r.location))
                }
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
        if !mathRanges.isEmpty { result.requiresFullParse = true }
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
        if useIncremental { remember(source, snapshot: result) }
        return result
    }
    private static func remember(_ source: String, snapshot: Snapshot) {
        guard source.utf8.count >= 16_384 else { return }
        cache.lock.lock()
        // Keep one bounded lineage; switching documents only loses reuse, never correctness.
        if source.utf8.count <= 24 * 1024 * 1024 { cache.previousLarge = (source, snapshot) }
        cache.lock.unlock()
    }

    private static func incrementallyParse(_ source: String, previousSource: String, previous: Snapshot) -> Snapshot? {
        guard !previous.requiresFullParse, previous.units.count == previous.blocks.count else { return nil }
        var old = previousSource, next = source
        old.makeContiguousUTF8(); next.makeContiguousUTF8()
        let difference: (Int, Int)? = old.utf8.withContiguousStorageIfAvailable { a in
            next.utf8.withContiguousStorageIfAvailable { b -> (Int, Int) in
                var prefix = 0, suffix = 0
                let count = min(a.count, b.count)
                while prefix + 4096 <= count,
                      memcmp(a.baseAddress! + prefix, b.baseAddress! + prefix, 4096) == 0 { prefix += 4096 }
                while prefix < count, a[prefix] == b[prefix] { prefix += 1 }
                // Never split a UTF8 scalar when converting the edit to UTF16 coordinates.
                while prefix > 0, prefix < b.count, b[prefix] & 0xC0 == 0x80 { prefix -= 1 }
                let remaining = count - prefix
                while suffix + 4096 <= remaining,
                      memcmp(a.baseAddress! + a.count - suffix - 4096, b.baseAddress! + b.count - suffix - 4096, 4096) == 0 { suffix += 4096 }
                while suffix < remaining, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
                while suffix > 0, b[b.count - suffix] & 0xC0 == 0x80 { suffix -= 1 }
                return (prefix, suffix)
            }!
        }
        guard let (prefix, suffix) = difference else { return nil }
        let start8 = old.utf8.index(old.utf8.startIndex, offsetBy: prefix)
        let end8 = old.utf8.index(old.utf8.endIndex, offsetBy: -suffix)
        guard let start = String.Index(start8, within: old), let end = String.Index(end8, within: old) else { return nil }
        let edit = NSRange(start..<end, in: old)
        let nsSource = source as NSString, oldLength = (previousSource as NSString).length
        let delta = nsSource.length - oldLength
        // Strictly inside one top-level block: changes at boundaries can merge/split blocks.
        guard let index = previous.units.firstIndex(where: {
            edit.location > $0.range.location && NSMaxRange(edit) < NSMaxRange($0.range)
        }) else { return nil }
        let unit = previous.units[index]
        guard unit.kind != .other, unit.range.length + delta > 0 else { return nil }
        let raw = nsSource.substring(with: NSRange(location: unit.range.location, length: unit.range.length + delta))
        let originalRaw = previous.blocks[index].source
        var local: Snapshot
        var parserWork = (raw as NSString).length
        // A fenced code body's ordinary text has no inline semantics. Reuse its literal
        // range only when the delimiters remain identical and no interior fence is added.
        let originalLines = originalRaw.components(separatedBy: "\n")
        let changedLines = raw.components(separatedBy: "\n")
        let stableFence = unit.kind == .code && originalLines.count >= 2
            && originalLines.first == changedLines.first && originalLines.last == changedLines.last
            && raw.range(of: #"^ {0,3}(`{3,}|~{3,})"#, options: .regularExpression) != nil
            && changedLines.dropFirst().dropLast().allSatisfy {
                $0.range(of: #"^ {0,3}(`{3,}|~{3,})"#, options: .regularExpression) == nil
            }
        let plainPattern = #"[`*_<>\[\]\\$~|&\r\n#!+.):=\-]"#
        let stablePlain = unit.kind == .paragraph
            && raw.range(of: plainPattern, options: .regularExpression) == nil
            && originalRaw.range(of: plainPattern, options: .regularExpression) == nil
        if stableFence || stablePlain {
            local = Snapshot()
            local.units = [.init(range: NSRange(location: 0, length: (raw as NSString).length), startLine: 0, kind: unit.kind)]
            local.blocks = [.init(source: raw, preview: raw, startLine: 0)]
            if stableFence { local.literalRanges = [local.units[0].range] }
            parserWork = 0
        } else {
            // Never recursively parse the same single-block document.
            guard raw.utf8.count < source.utf8.count else { return nil }
            local = parse(raw)
        }
        guard !local.requiresFullParse, local.units.count == 1, local.blocks.count == 1,
              local.units[0].kind == unit.kind else { return nil }
        if unit.kind == .code {
            guard originalLines.first == changedLines.first, originalLines.last == changedLines.last else { return nil }
        }
        let oldEnd = NSMaxRange(unit.range)
        let lineDelta = raw.utf8.reduce(into: 0) { if $1 == 10 { $0 += 1 } }
            - previous.blocks[index].source.utf8.reduce(into: 0) { if $1 == 10 { $0 += 1 } }
        var result = previous
        let unitEnd = unit.range.location + (raw as NSString).length
        var localLineStarts = [Int]()
        var position = unit.range.location
        for line in raw.components(separatedBy: "\n").dropLast() {
            position += line.utf16.count + 1
            if position <= unitEnd { localLineStarts.append(position) }
        }
        result.lineStarts = previous.lineStarts.filter { $0 <= unit.range.location }
            + localLineStarts
            + previous.lineStarts.filter { $0 > oldEnd }.map { $0 + delta }
        result.parsedUTF16 = parserWork
        result.reusedUnits = previous.units.count - 1
        result.headings = previous.headings.filter { !NSLocationInRange($0.offset, unit.range) }.map {
            HeadingInfo(level: $0.level, title: $0.title, offset: $0.offset >= oldEnd ? $0.offset + delta : $0.offset)
        } + local.headings.map { HeadingInfo(level: $0.level, title: $0.title, offset: $0.offset + unit.range.location) }
        func shifted(_ range: NSRange) -> NSRange {
            NSRange(location: range.location >= oldEnd ? range.location + delta : range.location, length: range.length)
        }
        result.spans = previous.spans.filter { NSIntersectionRange($0.range, unit.range).length == 0 }.map {
            Span(range: shifted($0.range), kind: $0.kind)
        } + local.spans.map { Span(range: NSRange(location: $0.range.location + unit.range.location, length: $0.range.length), kind: $0.kind) }
        result.literalRanges = previous.literalRanges.filter { NSIntersectionRange($0, unit.range).length == 0 }.map(shifted)
            + local.literalRanges.map { NSRange(location: $0.location + unit.range.location, length: $0.length) }
        for i in (index + 1)..<result.units.count {
            result.units[i].range.location += delta
            result.units[i].startLine += lineDelta
            let block = result.blocks[i]
            result.blocks[i] = .init(source: block.source, preview: block.preview, startLine: block.startLine + lineDelta)
        }
        result.units[index] = .init(range: NSRange(location: unit.range.location, length: unit.range.length + delta), startLine: unit.startLine, kind: unit.kind)
        let block = local.blocks[0]
        result.blocks[index] = .init(source: block.source, preview: block.preview, startLine: unit.startLine)
        result.headings.sort { $0.offset < $1.offset }
        result.spans.sort { $0.range.location < $1.range.location }
        result.literalRanges.sort { $0.location < $1.location }
        var maxEnd = 0
        result.spanMaxEnds = result.spans.map { maxEnd = max(maxEnd, NSMaxRange($0.range)); return maxEnd }
        return result
    }

}
