// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit

extension NodeMarkdownTextKit2TextView {
    private static var imageCache: [String: (modifiedAt: Date?, image: NSImage)] = [:]
    func maxImageWidth(for layout: NodeMarkdownTextKit2RowLayout) -> CGFloat {
        let containerWidth = textContainer?.containerSize.width ?? bounds.width
        let usableWidth: CGFloat
        if containerWidth.isFinite, containerWidth > 0, containerWidth < CGFloat.greatestFiniteMagnitude / 2 {
            usableWidth = containerWidth - layout.lineStyle.contentX - 24
        } else if bounds.width > 0 {
            usableWidth = bounds.width - layout.lineStyle.contentX - 24
        } else {
            usableWidth = 720 - layout.lineStyle.contentX
        }
        return max(120, usableWidth)
    }

    static func applyImageAttachments(
        to storage: NSMutableAttributedString,
        source: NSString,
        contentRange: NSRange,
        baseDirectoryURL: URL?,
        baseFont: NSFont,
        maxWidth: CGFloat
    ) -> [NSRange] {
        let lineText = source.substring(with: contentRange)
        let tokens = NodeMarkdownImageResourceManager.parseImageTokens(in: lineText)
        guard !tokens.isEmpty else { return [] }

        var protectedRanges: [NSRange] = []
        for token in tokens {
            let absoluteRange = NSRange(
                location: contentRange.location + token.sourceRange.location,
                length: token.sourceRange.length
            )
            guard absoluteRange.location >= contentRange.location,
                  NSMaxRange(absoluteRange) <= NSMaxRange(contentRange),
                  absoluteRange.length > 0 else { continue }
            protectedRanges.append(absoluteRange)

            guard let attachment = imageAttachment(
                for: token,
                baseDirectoryURL: baseDirectoryURL,
                maxWidth: maxWidth
            ) else {
                hideImageToken(in: storage, range: absoluteRange)
                continue
            }

            let sourceToken = source.substring(with: absoluteRange)
            prepareImageTokenForAttachment(
                in: storage,
                range: absoluteRange,
                baseFont: baseFont,
                sourceToken: sourceToken
            )
            storage.addAttributes(
                [
                    .attachment: attachment,
                    .baselineOffset: 0
                ],
                range: NSRange(location: absoluteRange.location, length: 1)
            )
        }
        return protectedRanges
    }

    private static func imageAttachment(
        for token: NodeMarkdownImageToken,
        baseDirectoryURL: URL?,
        maxWidth: CGFloat
    ) -> NSTextAttachment? {
        let relativePath = token.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !relativePath.isEmpty,
              let imageURL = NodeMarkdownRenderContract.default.resolvedImageURL(
                relativePath: relativePath,
                baseDirectoryURL: baseDirectoryURL
              ),
              FileManager.default.fileExists(atPath: imageURL.path),
              let image = cachedImage(at: imageURL),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        let requestedWidth = max(1, CGFloat(token.width))
        let width = min(maxWidth, requestedWidth)
        let height = max(1, width * (image.size.height / image.size.width))
        return NodeMarkdownTextKit2ImageAttachment(image: image, width: width, height: height)
    }

    private static func cachedImage(at url: URL) -> NSImage? {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let cached = imageCache[url.path], cached.modifiedAt == modifiedAt {
            return cached.image
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[url.path] = (modifiedAt, image)
        return image
    }

    private static func prepareImageTokenForAttachment(
        in storage: NSMutableAttributedString,
        range: NSRange,
        baseFont: NSFont,
        sourceToken: String
    ) {
        guard range.length > 0 else { return }
        let attachmentAnchorRange = NSRange(location: range.location, length: 1)
        let currentAnchor = (storage.string as NSString).substring(with: attachmentAnchorRange)
        if currentAnchor != "\u{FFFC}" {
            storage.replaceCharacters(in: attachmentAnchorRange, with: "\u{FFFC}")
        }
        storage.addAttributes(
            [
                .font: baseFont,
                .foregroundColor: NSColor.clear,
                .kern: 0,
                .ligature: 0,
                .expansion: 0,
                nodeMarkdownTextKit2AttachmentSourceTokenKey: sourceToken
            ],
            range: range
        )
        if range.length > 1 {
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular),
                    .kern: -2.0,
                    .ligature: 0
                ],
                range: NSRange(location: range.location + 1, length: range.length - 1)
            )
        }
    }

    private static func hideImageToken(in storage: NSMutableAttributedString, range: NSRange) {
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

}

final class NodeMarkdownTextKit2ImageAttachment: NSTextAttachment {
    init(image: NSImage, width: CGFloat, height: CGFloat) {
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = NSRect(x: 0, y: 0, width: max(0, width), height: max(0, height))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        position: CGPoint
    ) -> CGRect {
        bounds
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        bounds
    }
}

final class NodeMarkdownTextKit2FormulaAttachment: NSTextAttachment {
    let baselineOriginY: CGFloat
    let formulaAscent: CGFloat
    let formulaDescent: CGFloat

    init(image: NSImage, width: CGFloat, imageHeight: CGFloat,
         baselineOriginY: CGFloat, formulaAscent: CGFloat, formulaDescent: CGFloat) {
        self.formulaAscent = formulaAscent
        self.formulaDescent = formulaDescent
        self.baselineOriginY = baselineOriginY
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = NSRect(x: 0, y: baselineOriginY,
                        width: max(0, width),
                        height: max(0, imageHeight))
    }

    required init?(coder: NSCoder) {
        baselineOriginY = 0
        formulaAscent = 0
        formulaDescent = 0
        super.init(coder: coder)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        position: CGPoint
    ) -> CGRect {
        centeredBounds(in: lineFrag, at: position)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        centeredBounds(in: lineFrag, at: position)
    }

    private func centeredBounds(in lineFrag: CGRect, at position: CGPoint) -> CGRect {
        _ = lineFrag
        _ = position
        return bounds
    }
}
#endif
