// PIPELINE MARKER: NodeMarkdown exact block layout.
import Foundation

#if os(macOS)
import AppKit

struct NodeMarkdownExactLayoutKey: Hashable {
    let documentID: UUID
    let nodeID: UUID
    let nodeRevision: UInt64
    let styleRevision: Int
    let widthPixels: Int
    let scaleMilli: Int
}

struct NodeMarkdownExactGeometry: Equatable {
    let key: NodeMarkdownExactLayoutKey
    let height: CGFloat
    let contentHeight: CGFloat
    let spacingBefore: CGFloat
    let fragmentCount: Int
    let visualBounds: CGRect

    static func block(
        key: NodeMarkdownExactLayoutKey,
        contentHeight: CGFloat,
        spacingBefore: CGFloat,
        fragmentCount: Int,
        contentVisualBounds: CGRect
    ) -> NodeMarkdownExactGeometry {
        let spacing = max(0, spacingBefore)
        return NodeMarkdownExactGeometry(
            key: key,
            height: ceil(spacing + contentHeight),
            contentHeight: contentHeight,
            spacingBefore: spacing,
            fragmentCount: fragmentCount,
            visualBounds: contentVisualBounds.offsetBy(dx: 0, dy: spacing)
        )
    }
}

/// The only static Node geometry authority. It installs the same final styles and
/// attachments used for drawing, then measures every TextKit2 layout fragment.
/// No source-string or character-count estimate is accepted by this type.
@MainActor
final class NodeMarkdownExactLayoutEngine {
    private let probe = NodeMarkdownTextKit2TextView()

    init() {
        probe.isEditable = false
        probe.isSelectable = false
        probe.drawsBackground = false
        probe.isHorizontallyResizable = false
        probe.isVerticallyResizable = false
        probe.textContainerInset = NSSize(width: 16, height: 0)
        probe.nodeTextContainer.widthTracksTextView = true
        probe.suppressesAutomaticSelectionScrolling = true
    }

    func measure(
        key: NodeMarkdownExactLayoutKey,
        documentRow: Int,
        node: NodeMarkdownTextKit2Node,
        layout: NodeMarkdownTextKit2RowLayout,
        width: CGFloat,
        documentStyle: NodeMarkdownDocumentStyle,
        baseDirectoryURL: URL?
    ) -> NodeMarkdownExactGeometry? {
        guard width.isFinite, width > 0 else { return nil }
        let verticalInset = NodeMarkdownTextKit2TextView.blockVerticalInset(for: layout)
        probe.textContainerInset = NSSize(width: 16, height: verticalInset)
        let containerWidth = max(1, width - probe.textContainerInset.width * 2)
        probe.setFrameSize(NSSize(width: width, height: 1))
        probe.nodeTextContainer.containerSize = NSSize(
            width: containerWidth,
            height: .greatestFiniteMagnitude
        )
        let contentLayout = layout.replacingSpacingBefore(0)
        probe.replaceDocumentText(node.content, documentStyle: documentStyle)
        probe.nodeMarkdownRowLayouts = [contentLayout]
        probe.applyNodeMarkdownStyles(
            rowLayouts: [contentLayout],
            documentStyle: documentStyle,
            baseDirectoryURL: baseDirectoryURL,
            searchQuery: "",
            activeRowIndex: nil,
            activeMatchLocationInRow: nil,
            editingRowIndex: nil
        )
        let typingAttributes = probe.typingAttributes(for: contentLayout, documentStyle: documentStyle)
        probe.nodeMarkdownTypingAttributes = typingAttributes
        probe.typingAttributes = typingAttributes
        probe.font = typingAttributes[.font] as? NSFont

        guard let bounds = probe.exactNodeMarkdownVisualBounds() else { return nil }
        let contentHeight = ceil(max(0, bounds.maxY) + probe.textContainerInset.height)
        guard contentHeight.isFinite, contentHeight > 0 else { return nil }
        let geometry = NodeMarkdownExactGeometry.block(
            key: key,
            contentHeight: contentHeight,
            spacingBefore: layout.spacingBefore,
            fragmentCount: probe.exactNodeMarkdownLayoutFragmentCount(),
            contentVisualBounds: bounds
        )
        _ = documentRow
        return geometry
    }
}

extension NodeMarkdownTextKit2TextView {
    /// 可靠地求出每个行片段对应的源字符串范围。`NSTextLineFragment.characterRange`
    /// 在多行段落（含被隐藏源码行）中会返回错误范围，不能作为依据；这里用
    /// `textLineFragment(for:isUpstreamAffinity:)` 逐字符扫描得到真实行边界。
    func nodeMarkdownLineCharacterRanges(
        in fragment: NSTextLayoutFragment
    ) -> [(line: NSTextLineFragment, range: NSRange)] {
        let documentStart = nodeTextContentStorage.documentRange.location
        let startOffset = nodeTextContentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
        let endOffset = nodeTextContentStorage.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
        guard startOffset != NSNotFound,
              endOffset != NSNotFound,
              startOffset < endOffset else { return [] }

        var result: [(NSTextLineFragment, NSRange)] = []
        var currentLine: NSTextLineFragment?
        var currentStart = startOffset
        for offset in startOffset..<endOffset {
            guard let location = nodeTextContentStorage.location(documentStart, offsetBy: offset) else { break }
            guard let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else { continue }
            if let existing = currentLine {
                if line !== existing {
                    result.append((existing, NSRange(location: currentStart, length: offset - currentStart)))
                    currentLine = line
                    currentStart = offset
                }
            } else {
                currentLine = line
                currentStart = offset
            }
        }
        if let existing = currentLine {
            result.append((existing, NSRange(location: currentStart, length: endOffset - currentStart)))
        }
        return result
    }

    /// 该源字符串范围是否完全没有可见内容：没有附件、所有非换行字符都是透明色或亚像素字号。
    /// 换行只是行终止符，不计入可见内容。
    func nodeMarkdownCharacterRangeIsFullyInvisible(_ range: NSRange) -> Bool {
        guard range.length > 0,
              range.exact(toLength: nodeTextStorage.length) != nil else { return false }
        let nsText = nodeTextStorage.string as NSString
        var hasAttachment = false
        var hasVisibleGlyph = false
        nodeTextStorage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            if attributes[.attachment] != nil {
                hasAttachment = true
            } else {
                let font = attributes[.font] as? NSFont
                let color = attributes[.foregroundColor] as? NSColor
                let isTiny = (font?.pointSize ?? 0) <= 0.5
                let isClear = color == NSColor.clear
                guard !isTiny && !isClear else { return }
                let subText = nsText.substring(with: subrange)
                if subText.contains(where: { $0 != "\n" }) {
                    hasVisibleGlyph = true
                }
            }
        }
        return !hasAttachment && !hasVisibleGlyph
    }

    func exactNodeMarkdownVisualBounds() -> CGRect? {
        if nodeTextStorage.length == 0,
           nodeMarkdownRowLayouts.count == 1,
           let layout = nodeMarkdownRowLayouts.first {
            return Self.emptyParagraphRect(for: layout, textContainerOrigin: textContainerOrigin)
        }
        let documentRange = nodeTextLayoutManager.documentRange
        nodeTextLayoutManager.ensureLayout(for: documentRange)
        var result: CGRect?
        nodeTextLayoutManager.enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { [weak self] fragment in
            guard let self else { return false }
            // The fragment frame also covers layout space occupied by collapsed
            // formula/image source characters. Static Node height is determined by
            // the actual typographic lines, whose bounds already include attachment
            // ascent and descent. Counting the fragment frame adds source-only rows.
            for (line, range) in self.nodeMarkdownLineCharacterRanges(in: fragment) {
                guard !self.nodeMarkdownCharacterRangeIsFullyInvisible(range) else { continue }
                let lineRect = line.typographicBounds.offsetBy(
                    dx: self.textContainerOrigin.x + fragment.layoutFragmentFrame.minX,
                    dy: self.textContainerOrigin.y + fragment.layoutFragmentFrame.minY
                )
                result = result.map { $0.union(lineRect) } ?? lineRect
            }
            return true
        }
        if result == nil {
            let font = nodeMarkdownTypingAttributes[.font] as? NSFont ?? self.font ?? .systemFont(ofSize: 12)
            result = CGRect(
                x: textContainerOrigin.x,
                y: textContainerOrigin.y,
                width: 0,
                height: ceil(font.ascender - font.descender + font.leading)
            )
        }
        guard let result else { return nil }
        return result
    }

    func exactNodeMarkdownLayoutFragmentCount() -> Int {
        let documentRange = nodeTextLayoutManager.documentRange
        nodeTextLayoutManager.ensureLayout(for: documentRange)
        var count = 0
        nodeTextLayoutManager.enumerateTextLayoutFragments(
            from: documentRange.location,
            options: [.ensuresLayout]
        ) { _ in
            count += 1
            return true
        }
        return count
    }
}
#endif
