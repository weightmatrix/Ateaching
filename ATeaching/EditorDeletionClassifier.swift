import Foundation

/// Shared deletion classifier for Markdown and NodeMarkdown editors.
///
/// The editor must decide the cost of a deletion before running expensive
/// structure logic. A normal content deletion should stay local; only newline,
/// protected-prefix, cross-line, or very large deletions should wake line,
/// structure, or document-level work.
enum EditorDeletionImpact: Int, Comparable {
    case character
    case line
    case structure
    case document

    static func < (lhs: EditorDeletionImpact, rhs: EditorDeletionImpact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum EditorDeletionDirection {
    case backward
    case forward
}

/// 删除诊断分类 - v1 - 只记录删除形态，不改变编辑行为，供后续快路径优化使用。
enum EditorDeletionKind: String {
    case none
    case inlineCharacter
    case protectedPrefix
    case lineBoundary
    case multilineSelection
    case tokenBoundary
    case documentRange
}

/// 删除诊断结果 - v1 - 同时保存粗粒度成本和细粒度原因。
struct EditorDeletionDiagnosis {
    let impact: EditorDeletionImpact
    let kind: EditorDeletionKind
    let affectedRange: NSRange
    let deletedUTF16Length: Int
    let deletedLineBreakCount: Int
    let details: String

    var logSummary: String {
        "kind=\(kind.rawValue),impact=\(impact),range={\(affectedRange.location),\(affectedRange.length)},deletedUtf16=\(deletedUTF16Length),lineBreaks=\(deletedLineBreakCount),\(details)"
    }
}

enum EditorDeletionClassifier {
    private static let documentLevelLineBreakThreshold = 120
    private static let documentLevelCharacterThreshold = 20_000

    static func deletionRangeForCommand(
        source: NSString,
        selectedRange: NSRange,
        direction: EditorDeletionDirection
    ) -> NSRange? {
        guard source.length > 0 else { return nil }
        if selectedRange.length > 0 {
            let location = max(0, min(selectedRange.location, source.length))
            let end = max(location, min(NSMaxRange(selectedRange), source.length))
            return NSRange(location: location, length: end - location)
        }

        switch direction {
        case .backward:
            guard selectedRange.location > 0 else { return nil }
            let location = max(0, min(selectedRange.location - 1, source.length - 1))
            return NSRange(location: location, length: 1)
        case .forward:
            guard selectedRange.location < source.length else { return nil }
            let location = max(0, min(selectedRange.location, source.length - 1))
            return NSRange(location: location, length: 1)
        }
    }

    static func classifyDeletion(
        source: NSString,
        affectedRange: NSRange,
        protectedPrefixLengthForLine: (String) -> Int
    ) -> EditorDeletionImpact {
        diagnoseDeletion(
            source: source,
            affectedRange: affectedRange,
            protectedPrefixLengthForLine: protectedPrefixLengthForLine
        ).impact
    }

    static func diagnoseDeletion(
        source: NSString,
        affectedRange: NSRange,
        protectedPrefixLengthForLine: (String) -> Int
    ) -> EditorDeletionDiagnosis {
        guard source.length > 0 else {
            return EditorDeletionDiagnosis(
                impact: .character,
                kind: .none,
                affectedRange: NSRange(location: 0, length: 0),
                deletedUTF16Length: 0,
                deletedLineBreakCount: 0,
                details: "emptySource"
            )
        }
        let safeRange = clampedRange(affectedRange, in: source)
        guard safeRange.length > 0 else {
            return EditorDeletionDiagnosis(
                impact: .character,
                kind: .none,
                affectedRange: safeRange,
                deletedUTF16Length: 0,
                deletedLineBreakCount: 0,
                details: "empty"
            )
        }

        let deletedText = source.substring(with: safeRange)
        let lineBreakCount = deletedText.reduce(into: 0) { count, character in
            if character == "\n" || character == "\r" {
                count += 1
            }
        }
        if safeRange.length >= documentLevelCharacterThreshold || lineBreakCount >= documentLevelLineBreakThreshold {
            return EditorDeletionDiagnosis(
                impact: .document,
                kind: .documentRange,
                affectedRange: safeRange,
                deletedUTF16Length: safeRange.length,
                deletedLineBreakCount: lineBreakCount,
                details: "largeDeletion"
            )
        }
        if lineBreakCount > 0 {
            return EditorDeletionDiagnosis(
                impact: .line,
                kind: safeRange.length > 1 ? .multilineSelection : .lineBoundary,
                affectedRange: safeRange,
                deletedUTF16Length: safeRange.length,
                deletedLineBreakCount: lineBreakCount,
                details: "containsLineBreak"
            )
        }

        let anchor = min(safeRange.location, source.length - 1)
        let lineRange = source.lineRange(for: NSRange(location: anchor, length: 0))
        guard NSMaxRange(safeRange) <= NSMaxRange(lineRange) else {
            return EditorDeletionDiagnosis(
                impact: .line,
                kind: .multilineSelection,
                affectedRange: safeRange,
                deletedUTF16Length: safeRange.length,
                deletedLineBreakCount: lineBreakCount,
                details: "crossesLineRange"
            )
        }

        let lineText = source.substring(with: lineRange)
        let normalizedLine = lineText.hasSuffix("\n") || lineText.hasSuffix("\r")
            ? String(lineText.dropLast())
            : lineText
        let prefixLength = max(0, protectedPrefixLengthForLine(normalizedLine))
        let protectedBoundary = lineRange.location + min(prefixLength, (normalizedLine as NSString).length)
        if safeRange.location < protectedBoundary {
            return EditorDeletionDiagnosis(
                impact: .structure,
                kind: .protectedPrefix,
                affectedRange: safeRange,
                deletedUTF16Length: safeRange.length,
                deletedLineBreakCount: lineBreakCount,
                details: "protectedBoundary=\(protectedBoundary)"
            )
        }

        let tokenWindow = tokenProbeText(in: source, around: safeRange, lineRange: lineRange)
        if mayTouchInlineToken(deletedText: deletedText, tokenWindow: tokenWindow) {
            return EditorDeletionDiagnosis(
                impact: .character,
                kind: .tokenBoundary,
                affectedRange: safeRange,
                deletedUTF16Length: safeRange.length,
                deletedLineBreakCount: lineBreakCount,
                details: "inlineTokenProbe"
            )
        }

        return EditorDeletionDiagnosis(
            impact: .character,
            kind: .inlineCharacter,
            affectedRange: safeRange,
            deletedUTF16Length: safeRange.length,
            deletedLineBreakCount: lineBreakCount,
            details: "sameLine"
        )
    }

    static func isCharacterDeletion(
        source: NSString,
        affectedRange: NSRange,
        protectedPrefixLengthForLine: (String) -> Int
    ) -> Bool {
        classifyDeletion(
            source: source,
            affectedRange: affectedRange,
            protectedPrefixLengthForLine: protectedPrefixLengthForLine
        ) == .character
    }

    private static func clampedRange(_ range: NSRange, in source: NSString) -> NSRange {
        let location = max(0, min(range.location, source.length))
        let end = max(location, min(NSMaxRange(range), source.length))
        return NSRange(location: location, length: end - location)
    }

    private static func tokenProbeText(in source: NSString, around range: NSRange, lineRange: NSRange) -> String {
        let probeStart = max(lineRange.location, range.location - 8)
        let probeEnd = min(NSMaxRange(lineRange), NSMaxRange(range) + 24)
        guard probeEnd > probeStart else { return "" }
        return source.substring(with: NSRange(location: probeStart, length: probeEnd - probeStart))
    }

    private static func mayTouchInlineToken(deletedText: String, tokenWindow: String) -> Bool {
        if deletedText.contains("$")
            || deletedText.contains("*")
            || deletedText.contains("_")
            || deletedText.contains("<")
            || deletedText.contains(">")
            || deletedText.contains("!")
            || deletedText.contains("[")
            || deletedText.contains("]")
            || deletedText.contains("(")
            || deletedText.contains(")") {
            return true
        }
        return tokenWindow.contains("$")
            || tokenWindow.contains("![")
            || tokenWindow.contains("](")
            || tokenWindow.localizedCaseInsensitiveContains("<img")
            || tokenWindow.localizedCaseInsensitiveContains("<u")
            || tokenWindow.localizedCaseInsensitiveContains("</u")
            || tokenWindow.localizedCaseInsensitiveContains("<mark")
            || tokenWindow.localizedCaseInsensitiveContains("</mark")
            || tokenWindow.contains("**")
    }
}
