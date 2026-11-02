import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Word导出 - v1 - 把 Markdown / NodeMarkdown 按当前样式导出为 Word 兼容文件
enum WordExportRenderer {

    static func data(from attributed: NSAttributedString) throws -> Data {
        let range = NSRange(location: 0, length: attributed.length)
        #if os(macOS)
        return try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.docFormat]
        )
        #else
        return try attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        #endif
    }

    // MARK: - Markdown
    static func renderMarkdown(
        source: String,
        style: MarkdownDocumentStyle
    ) throws -> Data {
        let result = NSMutableAttributedString()
        let nsSource = source as NSString
        var cursor = 0
        while cursor < nsSource.length {
            let lineRange = nsSource.lineRange(for: NSRange(location: cursor, length: 0))
            let rawLine = nsSource.substring(with: lineRange)
            let content = rawLine.trimmingCharacters(in: .newlines)
            let roleStyle = markdownRoleStyle(for: content, documentStyle: style)
            let listItem = markdownListItem(content)
            let blockText: String
            let paragraphStyle: NSParagraphStyle?
            if let listItem {
                blockText = "• " + listItem.text
                paragraphStyle = bulletParagraphStyle(level: listItem.level)
            } else {
                blockText = markdownBlockText(content)
                paragraphStyle = nil
            }
            appendStyledLine(
                content: blockText,
                fontName: roleStyle.fontName,
                fontSize: roleStyle.fontSize,
                color: roleStyle.renderedColor,
                isBold: false,
                isUnderline: false,
                hasBackground: false,
                paragraphStyle: paragraphStyle,
                to: result
            )
            let next = NSMaxRange(lineRange)
            if next <= cursor { break }
            if next < nsSource.length {
                result.append(NSAttributedString(string: "\n"))
            }
            cursor = next
        }
        return try data(from: result)
    }

    // MARK: - NodeMarkdown
    static func renderNodeMarkdown(
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle
    ) throws -> Data {
        let result = NSMutableAttributedString()
        for (index, node) in document.nodes.enumerated() {
            let roleStyle = style.style(forLevel: node.level)
            appendStyledLine(
                content: node.text,
                fontName: roleStyle.fontName,
                fontSize: roleStyle.fontSize,
                color: roleStyle.renderedColor,
                isBold: roleStyle.isBold,
                isUnderline: roleStyle.isUnderline,
                hasBackground: roleStyle.hasBackgroundBar,
                to: result
            )
            if index < document.nodes.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return try data(from: result)
    }

    // MARK: - 行级样式
    private static func appendStyledLine(
        content: String,
        fontName: String,
        fontSize: Double,
        color: Color,
        isBold: Bool,
        isUnderline: Bool,
        hasBackground: Bool,
        paragraphStyle: NSParagraphStyle? = nil,
        to result: NSMutableAttributedString
    ) {
        let rendered = renderInlineStyled(source: content)
        let plain = rendered.plain
        let mutable = NSMutableAttributedString(string: plain)
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)

        let baseFont = resolvedFont(name: fontName, size: fontSize, bold: isBold)
        let baseColor = platformColor(color)
        var baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor
        ]
        if isUnderline {
            baseAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if hasBackground {
            baseAttributes[.backgroundColor] = platformColor(color, alpha: 0.18)
        }
        if let paragraphStyle {
            baseAttributes[.paragraphStyle] = paragraphStyle
        }
        mutable.addAttributes(baseAttributes, range: fullRange)

        for run in rendered.runs {
            let range = run.range
            guard range.location != NSNotFound,
                  range.length > 0,
                  NSMaxRange(range) <= (plain as NSString).length else { continue }
            switch run.kind {
            case .bold:
                mutable.addAttribute(.font, value: boldFont(from: baseFont), range: range)
            case .italic:
                mutable.addAttribute(.font, value: italicFont(from: baseFont), range: range)
            case .underline:
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .strike:
                mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case .code:
                mutable.addAttributes(codeAttributes(baseFont: baseFont), range: range)
            case .highlight:
                mutable.addAttribute(.backgroundColor, value: platformHighlightBackground, range: range)
            }
        }

        result.append(mutable)
    }

    // MARK: - 行内标记剥离与样式定位
    private enum InlineStyleKind {
        case bold
        case italic
        case underline
        case strike
        case code
        case highlight
    }

    private struct InlineStyleRun {
        let range: NSRange
        let kind: InlineStyleKind
    }

    private static func renderInlineStyled(source: String) -> (plain: String, runs: [InlineStyleRun]) {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        var matches: [(full: NSRange, content: NSRange, kind: InlineStyleKind)] = []

        collectPattern(#"\*\*([^*\n]+)\*\*|__([^_\n]+)__"#, kind: .bold, into: &matches, source: nsSource, base: fullRange)
        collectPattern(#"(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#, kind: .italic, into: &matches, source: nsSource, base: fullRange)
        collectPattern(#"~~([^~\n]+)~~|<s>([^<\n]+)</s>|<del>([^<\n]+)</del>"#, kind: .strike, into: &matches, source: nsSource, base: fullRange, options: [.caseInsensitive])
        collectPattern(#"<mark>([^<\n]+)</mark>"#, kind: .highlight, into: &matches, source: nsSource, base: fullRange, options: [.caseInsensitive])
        collectPattern(#"<u>([^<\n]+)</u>"#, kind: .underline, into: &matches, source: nsSource, base: fullRange, options: [.caseInsensitive])
        collectPattern(#"<code>([^<\n]+)</code>|`([^`\n]+)`"#, kind: .code, into: &matches, source: nsSource, base: fullRange)

        matches.sort { $0.full.location < $1.full.location }

        let output = NSMutableString()
        var runs: [InlineStyleRun] = []
        var cursor = 0
        for match in matches {
            let full = match.full
            guard full.location >= cursor, full.length > 0 else { continue }
            let beforeRange = NSRange(location: cursor, length: full.location - cursor)
            if beforeRange.length > 0 {
                output.append(nsSource.substring(with: beforeRange))
            }
            let contentStart = output.length
            output.append(nsSource.substring(with: match.content))
            let contentLength = output.length - contentStart
            runs.append(InlineStyleRun(
                range: NSRange(location: contentStart, length: contentLength),
                kind: match.kind
            ))
            cursor = full.location + full.length
        }
        if cursor < nsSource.length {
            output.append(nsSource.substring(with: NSRange(location: cursor, length: nsSource.length - cursor)))
        }
        return (output as String, runs)
    }

    private static func collectPattern(
        _ pattern: String,
        kind: InlineStyleKind,
        into matches: inout [(full: NSRange, content: NSRange, kind: InlineStyleKind)],
        source: NSString,
        base: NSRange,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        for match in regex.matches(in: source as String, options: [], range: base) {
            let full = match.range
            guard full.location != NSNotFound, full.length > 0 else { continue }
            var content = full
            for index in 1..<match.numberOfRanges {
                let candidate = match.range(at: index)
                if candidate.location != NSNotFound {
                    content = candidate
                    break
                }
            }
            matches.append((full, content, kind))
        }
    }

    private static func codeAttributes(baseFont: Any) -> [NSAttributedString.Key: Any] {
        [
            .font: platformMonospacedFont(size: platformFontSize(baseFont)),
            .backgroundColor: platformCodeBackground
        ]
    }

    // MARK: - 平台字体/颜色
    private static func resolvedFont(name: String, size: Double, bold: Bool) -> Any {
        let pointSize = CGFloat(size)
        #if os(macOS)
        let base = NSFont(name: name, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
        return bold ? NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask) : base
        #else
        return bold
            ? UIFont.systemFont(ofSize: pointSize, weight: .bold)
            : (UIFont(name: name, size: pointSize) ?? UIFont.systemFont(ofSize: pointSize))
        #endif
    }

    private static func boldFont(from baseFont: Any) -> Any {
        #if os(macOS)
        guard let font = baseFont as? NSFont else { return baseFont }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        #else
        guard let font = baseFont as? UIFont else { return baseFont }
        return UIFont.systemFont(ofSize: font.pointSize, weight: .bold)
        #endif
    }

    private static func italicFont(from baseFont: Any) -> Any {
        #if os(macOS)
        guard let font = baseFont as? NSFont else { return baseFont }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        guard let font = baseFont as? UIFont else { return baseFont }
        return UIFont.italicSystemFont(ofSize: font.pointSize)
        #endif
    }

    private static func platformMonospacedFont(size: Double) -> Any {
        let pointSize = CGFloat(size)
        #if os(macOS)
        return NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        #else
        return UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        #endif
    }

    private static func platformFontSize(_ font: Any) -> Double {
        #if os(macOS)
        return Double((font as? NSFont)?.pointSize ?? 13)
        #else
        return Double((font as? UIFont)?.pointSize ?? 13)
        #endif
    }

    private static func platformColor(_ color: Color) -> Any {
        #if os(macOS)
        return NSColor(color)
        #else
        return UIColor(color)
        #endif
    }

    private static func platformColor(_ color: Color, alpha: CGFloat) -> Any {
        #if os(macOS)
        return NSColor(color).withAlphaComponent(alpha)
        #else
        return UIColor(color).withAlphaComponent(alpha)
        #endif
    }

    private static var platformHighlightBackground: Any {
        #if os(macOS)
        return NSColor.systemYellow.withAlphaComponent(0.35)
        #else
        return UIColor.systemYellow.withAlphaComponent(0.35)
        #endif
    }

    private static var platformCodeBackground: Any {
        #if os(macOS)
        return NSColor.quaternaryLabelColor.withAlphaComponent(0.28)
        #else
        return UIColor.systemGray5.withAlphaComponent(0.28)
        #endif
    }

    // MARK: - Markdown 行角色与块级标记剥离
    private static func markdownRoleStyle(
        for content: String,
        documentStyle: MarkdownDocumentStyle
    ) -> MarkdownRoleStyle {
        if let level = markdownHeadingLevel(content) {
            return documentStyle.headingStyle(level: level)
        }
        if content.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            return documentStyle.comment
        }
        return documentStyle.body
    }

    private static func markdownBlockText(_ content: String) -> String {
        if let level = markdownHeadingLevel(content) {
            return String(content.dropFirst(level + 1))
        }
        if content.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
            var result = content.trimmingCharacters(in: .whitespaces)
            if result.hasPrefix(">") {
                result.removeFirst()
                if result.first == " " { result.removeFirst() }
            }
            return result
        }
        return content
    }

    private static func markdownListItem(_ content: String) -> (level: Int, text: String)? {
        var leadingSpaces = 0
        for character in content {
            if character == " " { leadingSpaces += 1 } else { break }
        }
        let rest = content.dropFirst(leadingSpaces)
        guard rest.hasPrefix("- ") else { return nil }
        return (leadingSpaces / 2, String(rest.dropFirst(2)))
    }

    private static func bulletParagraphStyle(level: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let indent = CGFloat(max(0, level)) * 18
        style.firstLineHeadIndent = indent
        style.headIndent = indent + 16
        return style
    }

    private static func markdownHeadingLevel(_ line: String) -> Int? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level > 0, level <= 6 else { return nil }
        let index = line.index(line.startIndex, offsetBy: level)
        guard index < line.endIndex, line[index] == " " else { return nil }
        return level
    }
}
