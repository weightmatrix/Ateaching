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
            for line in fragment.textLineFragments {
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
