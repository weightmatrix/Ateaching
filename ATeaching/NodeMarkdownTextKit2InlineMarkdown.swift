// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    static let inlineHighlightBackgroundColorKey = NSAttributedString.Key("NodeMarkdownHighlightBackgroundColor")

    static func inlineHighlightColor() -> NSColor {
        NSColor(
            red: 240.0 / 255.0,
            green: 200.0 / 255.0,
            blue: 71.0 / 255.0,
            alpha: 0.46
        )
    }

    static func applyInlineMarkdownStyles(
        to storage: NSMutableAttributedString,
        source: NSString,
        contentRange: NSRange,
        baseFont: NSFont,
        textColor: NSColor,
        protectedRanges initialProtectedRanges: [NSRange] = [],
        hideHTMLDelimiters: Bool = false
    ) {
        var protectedRanges = initialProtectedRanges

        func applyDelimiterStyle(fullRange: NSRange, innerRange: NSRange) {
            if hideHTMLDelimiters {
                hideDelimiterText(to: storage, fullRange: fullRange, innerRange: innerRange)
            } else {
                applyDelimiterFade(to: storage, fullRange: fullRange, innerRange: innerRange, textColor: textColor)
            }
        }

        func applyCodeStyle(fullRange: NSRange, innerRange: NSRange) {
            guard !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, baseFont.pointSize * 0.95), weight: .regular),
                    .backgroundColor: NSColor.textColor.withAlphaComponent(0.08)
                ],
                range: innerRange
            )
            protectedRanges.append(fullRange)
        }

        applyInlinePattern(#"`([^`\n]+)`"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            applyCodeStyle(fullRange: fullRange, innerRange: innerRange)
        }

        applyInlinePattern(#"<code>([\s\S]*?)</code>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange),
                  !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttributes(
                [
                    .font: NSFont.monospacedSystemFont(ofSize: max(11, baseFont.pointSize * 0.95), weight: .regular),
                    .backgroundColor: NSColor.textColor.withAlphaComponent(0.08)
                ],
                range: innerRange
            )
            protectedRanges.append(fullRange)
        }

        func applyFontTraitStyle(
            fullRange: NSRange,
            innerRange: NSRange,
            trait: NSFontTraitMask
        ) {
            guard !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(baseFont, toHaveTrait: trait),
                range: innerRange
            )
        }

        applyInlinePattern(#"\*\*([^*\n]+)\*\*|__([^_\n]+)__"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            applyFontTraitStyle(fullRange: fullRange, innerRange: innerRange, trait: .boldFontMask)
        }

        applyInlinePattern(#"<(?:strong|b)>([\s\S]*?)</(?:strong|b)>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange),
                  !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask),
                range: innerRange
            )
        }

        applyInlinePattern(#"(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            applyFontTraitStyle(fullRange: fullRange, innerRange: innerRange, trait: .italicFontMask)
        }

        applyInlinePattern(#"<(?:em|i)>([\s\S]*?)</(?:em|i)>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange),
                  !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(
                .font,
                value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
                range: innerRange
            )
        }

        func applyStrikethroughStyle(fullRange: NSRange, innerRange: NSRange) {
            guard !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: innerRange)
        }

        applyInlinePattern(#"~~([^~\n]+)~~"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            applyStrikethroughStyle(fullRange: fullRange, innerRange: innerRange)
        }

        applyInlinePattern(#"<(?:s|del)>([\s\S]*?)</(?:s|del)>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange),
                  !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: innerRange)
        }

        applyInlinePattern(#"==([^=\n]+)=="#, source: source, contentRange: contentRange) { fullRange, innerRange in
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(inlineHighlightBackgroundColorKey, value: inlineHighlightColor(), range: innerRange)
        }

        applyInlinePattern(#"<mark>([\s\S]*?)</mark>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttribute(inlineHighlightBackgroundColorKey, value: inlineHighlightColor(), range: innerRange)
        }

        applyInlinePattern(#"<u>([\s\S]*?)</u>"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  !containsLineBreak(source, range: fullRange) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttributes(
                [
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemBlue
                ],
                range: innerRange
            )
        }

        applyInlinePattern(#"\[([^\]\n]+)\]\(([^\)\n]+)\)"#, source: source, contentRange: contentRange) { fullRange, innerRange in
            guard !overlapsAny(fullRange, protectedRanges) else { return }
            applyDelimiterStyle(fullRange: fullRange, innerRange: innerRange)
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemBlue
                ],
                range: innerRange
            )
        }
    }

    static func applyInlinePattern(
        _ pattern: String,
        source: NSString,
        contentRange: NSRange,
        block: (NSRange, NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: source as String, options: [], range: contentRange)
        for match in matches {
            let fullRange = match.range
            guard fullRange.location != NSNotFound,
                  fullRange.length > 0,
                  NSIntersectionRange(fullRange, contentRange).length == fullRange.length,
                  let innerRange = firstCapturedRange(in: match) else { continue }
            block(fullRange, innerRange)
        }
    }

    static func applyDelimiterFade(
        to storage: NSMutableAttributedString,
        fullRange: NSRange,
        innerRange: NSRange,
        textColor: NSColor
    ) {
        let fadedColor = textColor.withAlphaComponent(0.36)
        let leadingLength = max(0, innerRange.location - fullRange.location)
        if leadingLength > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: fadedColor,
                range: NSRange(location: fullRange.location, length: leadingLength)
            )
        }

        let trailingStart = innerRange.location + innerRange.length
        let trailingEnd = fullRange.location + fullRange.length
        let trailingLength = max(0, trailingEnd - trailingStart)
        if trailingLength > 0 {
            storage.addAttribute(
                .foregroundColor,
                value: fadedColor,
                range: NSRange(location: trailingStart, length: trailingLength)
            )
        }
    }

    static func hideDelimiterText(
        to storage: NSMutableAttributedString,
        fullRange: NSRange,
        innerRange: NSRange
    ) {
        let leadingLength = max(0, innerRange.location - fullRange.location)
        if leadingLength > 0 {
            hideInlineTokenText(
                in: storage,
                range: NSRange(location: fullRange.location, length: leadingLength)
            )
        }

        let trailingStart = innerRange.location + innerRange.length
        let trailingEnd = fullRange.location + fullRange.length
        let trailingLength = max(0, trailingEnd - trailingStart)
        if trailingLength > 0 {
            hideInlineTokenText(
                in: storage,
                range: NSRange(location: trailingStart, length: trailingLength)
            )
        }
    }

    private static func hideInlineTokenText(in storage: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        storage.addAttributes(
            [
                .foregroundColor: NSColor.clear,
                .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                .kern: -2.0,
                .ligature: 0
            ],
            range: range
        )
    }

    static func overlapsAny(_ range: NSRange, _ protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    private static func containsLineBreak(_ source: NSString, range: NSRange) -> Bool {
        guard range.location != NSNotFound,
              range.length > 0,
              NSMaxRange(range) <= source.length else { return true }
        return source.range(of: "\n", range: range).location != NSNotFound
    }

    private static func firstCapturedRange(in match: NSTextCheckingResult) -> NSRange? {
        guard match.numberOfRanges > 1 else { return nil }
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound, range.length > 0 {
                return range
            }
        }
        return nil
    }
}
#endif
