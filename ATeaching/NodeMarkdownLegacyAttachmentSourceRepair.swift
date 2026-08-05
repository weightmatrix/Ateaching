import Foundation

/// TextKit用U+FFFC表示内存附件锚点。这个字符绝不能进入NodeMarkdown源码。
/// 历史版本若已泄漏锚点，只根据可验证的Markdown边界恢复，不猜测公式内容。
enum NodeMarkdownLegacyAttachmentSourceRepair {
    nonisolated private static let marker = "\u{FFFC}"

    nonisolated static func repair(_ source: String) -> String {
        guard source.contains(marker) else { return source }
        return source
            .components(separatedBy: "\n")
            .map { line in repairLine(line) }
            .joined(separator: "\n")
    }

    nonisolated private static func repairLine(_ line: String) -> String {
        var value = repairImageAnchors(in: line)
        guard value.contains(marker) else { return value }

        let withoutMarkers = value.replacingOccurrences(of: marker, with: "")
        if unescapedDollarCount(in: withoutMarkers).isMultiple(of: 2) {
            return withoutMarkers
        }

        // 去掉锚点后只差一个公式边界时，将第一个锚点恢复为$；其余锚点均为
        // 重复渲染留下的内部残片。恢复后必须重新满足成对条件。
        if let markerRange = value.range(of: marker) {
            value.replaceSubrange(markerRange, with: "$")
            value = value.replacingOccurrences(of: marker, with: "")
            if unescapedDollarCount(in: value).isMultiple(of: 2) {
                return value
            }
        }
        return withoutMarkers
    }

    nonisolated private static func repairImageAnchors(in source: String) -> String {
        let escapedMarker = NSRegularExpression.escapedPattern(for: marker)
        guard let regex = try? NSRegularExpression(
            pattern: "\(escapedMarker)+(?=\\[[^\\]\\n]*\\]\\([^\\)\\n]+\\)(?:\\{[^}\\n]*\\})?)"
        ) else { return source }
        let range = NSRange(location: 0, length: (source as NSString).length)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: "!")
    }

    nonisolated private static func unescapedDollarCount(in source: String) -> Int {
        let characters = Array(source)
        var count = 0
        for index in characters.indices where characters[index] == "$" {
            var slashCount = 0
            var cursor = index
            while cursor > characters.startIndex {
                let previous = characters.index(before: cursor)
                guard characters[previous] == "\\" else { break }
                slashCount += 1
                cursor = previous
            }
            if slashCount.isMultiple(of: 2) {
                count += 1
            }
        }
        return count
    }
}
