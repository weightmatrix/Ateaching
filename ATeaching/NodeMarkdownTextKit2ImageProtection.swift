// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2Coordinator {
    struct ProtectedImageTokenEdit {
        let replacementRange: NSRange
        let replacement: String
    }

    func protectedImageTokenEdit(
        in textView: NodeMarkdownTextKit2TextView,
        affectedRange: NSRange,
        replacement: String
    ) -> ProtectedImageTokenEdit? {
        let sourceText = textView.documentString() as NSString
        guard sourceText.length > 0 else { return nil }
        let safeRange = affectedRange.clamped(toLength: sourceText.length) ?? NSRange(location: sourceText.length, length: 0)
        let probeRange = imageTokenProbeRange(for: safeRange, in: sourceText)
        guard probeRange.length > 0 else { return nil }

        let probeText = sourceText.substring(with: probeRange)
        for token in NodeMarkdownImageResourceManager.parseImageTokens(in: probeText) {
            let tokenRange = NSRange(
                location: probeRange.location + token.sourceRange.location,
                length: token.sourceRange.length
            )
            guard editRange(safeRange, touchesImageTokenRange: tokenRange) else { continue }
            if imageWidthEditIsAllowed(
                token: token,
                tokenRange: tokenRange,
                affectedRange: safeRange,
                replacement: replacement
            ) {
                return nil
            }
            let replacementRange = safeRange.length > 0 ? NSUnionRange(safeRange, tokenRange) : tokenRange
            return ProtectedImageTokenEdit(
                replacementRange: replacementRange,
                replacement: safeRange.length > 0 ? replacement : ""
            )
        }
        return nil
    }

    private func imageTokenProbeRange(for affectedRange: NSRange, in sourceText: NSString) -> NSRange {
        let textLength = sourceText.length
        guard textLength > 0 else { return NSRange(location: 0, length: 0) }
        if affectedRange.length > 0 {
            return sourceText.lineRange(for: affectedRange.clamped(toLength: textLength) ?? affectedRange)
        }
        let anchor = max(0, min(affectedRange.location, textLength - 1))
        return sourceText.lineRange(for: NSRange(location: anchor, length: 0))
    }

    private func editRange(_ editRange: NSRange, touchesImageTokenRange tokenRange: NSRange) -> Bool {
        if editRange.length == 0 {
            return editRange.location > tokenRange.location && editRange.location < NSMaxRange(tokenRange)
        }
        return NSIntersectionRange(editRange, tokenRange).length > 0
    }

    private func imageWidthEditIsAllowed(
        token: NodeMarkdownImageToken,
        tokenRange: NSRange,
        affectedRange: NSRange,
        replacement: String
    ) -> Bool {
        guard replacement.allSatisfy({ $0.isNumber }) || replacement.isEmpty else { return false }
        let tokenSource = token.sourceText as NSString
        let patterns = [
            #"width\s*=\s*["']?(\d+)"#,
            #"\{width\s*=\s*(\d+)\}"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let fullRange = NSRange(location: 0, length: tokenSource.length)
            guard let match = regex.firstMatch(in: token.sourceText, range: fullRange),
                  match.numberOfRanges > 1 else { continue }
            let widthRange = match.range(at: 1)
            guard widthRange.location != NSNotFound, widthRange.length > 0 else { continue }
            let absoluteWidthRange = NSRange(location: tokenRange.location + widthRange.location, length: widthRange.length)
            if affectedRange.length == 0 {
                return affectedRange.location >= absoluteWidthRange.location
                    && affectedRange.location <= NSMaxRange(absoluteWidthRange)
            }
            return NSIntersectionRange(affectedRange, absoluteWidthRange).length == affectedRange.length
        }
        return false
    }
}
#endif
