// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#if canImport(SwiftMath)
import SwiftMath
#endif

extension NodeMarkdownTextKit2TextView {
    func drawNodeMarkdownMarkers(in dirtyRect: NSRect) {
        guard !nodeMarkdownRowLayouts.isEmpty else { return }
        let documentStart = nodeTextContentStorage.documentRange.location

        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: dirtyRect))
        for layout in visibleRowLayouts(in: dirtyRect) {
            guard let lineRect = firstLineRect(for: layout, documentStart: documentStart) else { continue }
            let markerRect = markerDrawingRect(for: layout, lineRect: lineRect)
            guard markerRect.intersects(dirtyRect) else { continue }
            drawMarker(for: layout, in: markerRect)
        }
    }

    func drawNodeMarkdownBackgroundBars(in dirtyRect: NSRect) {
        guard !nodeMarkdownRowLayouts.isEmpty else { return }
        let documentStart = nodeTextContentStorage.documentRange.location

        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: dirtyRect))
        for layout in visibleRowLayouts(in: dirtyRect) where layout.lineStyle.hasBackgroundBar {
            guard let lineRect = firstLineRect(for: layout, documentStart: documentStart) else { continue }
            let barRect = backgroundBarRect(for: layout, lineRect: lineRect)
            guard barRect.intersects(dirtyRect) else { continue }
            drawBackgroundBar(for: layout, in: barRect)
        }
    }

    func drawNodeMarkdownInlineHighlights(in dirtyRect: NSRect) {
        guard !nodeMarkdownRowLayouts.isEmpty else { return }
        let attributed = displayedAttributedString()
        guard attributed.length > 0 else { return }
        let visibleLayouts = visibleRowLayouts(in: dirtyRect)
        guard !visibleLayouts.isEmpty else { return }

        let visibleRange = visibleLayouts.reduce(nil as NSRange?) { result, layout in
            guard let current = layout.range.clamped(toLength: attributed.length) else { return result }
            guard let result else { return current }
            return NSUnionRange(result, current)
        }
        guard let visibleRange, visibleRange.length > 0 else { return }

        let documentStart = nodeTextContentStorage.documentRange.location
        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: dirtyRect))
        attributed.enumerateAttribute(
            Self.inlineHighlightBackgroundColorKey,
            in: visibleRange,
            options: []
        ) { value, range, _ in
            guard let color = value as? NSColor,
                  range.length > 0,
                  let layout = rowLayout(containing: range),
                  let lineRect = firstLineRect(for: layout, documentStart: documentStart),
                  let highlightRect = inlineHighlightRect(
                    for: range,
                    in: attributed,
                    layout: layout,
                    lineRect: lineRect
                  ),
                  highlightRect.intersects(dirtyRect) else { return }

            color.setFill()
            let radius = min(8, highlightRect.height * 0.28)
            NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func visibleTextContainerRect(in dirtyRect: NSRect) -> NSRect {
        dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
    }

    private func visibleRowLayouts(in dirtyRect: NSRect) -> [NodeMarkdownTextKit2RowLayout] {
        nodeMarkdownRowLayouts
    }

    private func firstLineRect(
        for layout: NodeMarkdownTextKit2RowLayout,
        documentStart: any NSTextLocation
    ) -> NSRect? {
        guard let location = nodeTextContentStorage.location(documentStart, offsetBy: layout.range.location),
              let fragment = nodeTextLayoutManager.textLayoutFragment(for: location),
              let lineFragment = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else {
            return nil
        }
        let fragmentFrame = fragment.layoutFragmentFrame
        let lineBounds = lineFragment.typographicBounds
        return NSRect(
            x: textContainerOrigin.x + fragmentFrame.minX + lineBounds.minX,
            y: textContainerOrigin.y + fragmentFrame.minY + lineBounds.minY,
            width: lineBounds.width,
            height: lineBounds.height
        )
    }

    private func markerDrawingRect(for layout: NodeMarkdownTextKit2RowLayout, lineRect: NSRect) -> NSRect {
        let markerFont = Self.markerFont(for: layout.lineStyle.roleStyle)
        let marker = layout.lineStyle.iconGlyph
        let attributes: [NSAttributedString.Key: Any] = [.font: markerFont]
        let measured = NSAttributedString(string: marker, attributes: attributes).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let markerSize = (marker as NSString).size(withAttributes: attributes)
        return NSRect(
            x: textContainerOrigin.x + layout.lineStyle.markerX,
            y: lineRect.midY - measured.midY,
            width: Self.markerDisplayWidth(for: layout),
            height: markerSize.height
        )
    }

    private func drawMarker(for layout: NodeMarkdownTextKit2RowLayout, in rect: NSRect) {
        let marker = layout.lineStyle.iconGlyph
        guard !marker.isEmpty else { return }
        let roleStyle = layout.lineStyle.roleStyle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.markerFont(for: roleStyle),
            .foregroundColor: NSColor(roleStyle.renderedColor).withAlphaComponent(0.85)
        ]
        NSAttributedString(string: marker, attributes: attributes).draw(in: rect)
    }

    private func rowLayout(containing range: NSRange) -> NodeMarkdownTextKit2RowLayout? {
        nodeMarkdownRowLayouts.first { layout in
            NSIntersectionRange(layout.range, range).length == range.length
        }
    }

    private func inlineHighlightRect(
        for range: NSRange,
        in attributed: NSAttributedString,
        layout: NodeMarkdownTextKit2RowLayout,
        lineRect: NSRect
    ) -> NSRect? {
        guard layout.range.clamped(toLength: attributed.length) != nil,
              let contentRange = layout.contentRange.clamped(toLength: attributed.length),
              range.location >= contentRange.location,
              range.location + range.length <= contentRange.location + contentRange.length,
              range.location < attributed.length else { return nil }

        let prefixLength = max(0, range.location - contentRange.location)
        let prefixRange = NSRange(location: contentRange.location, length: prefixLength)
        let prefixWidth = inlineRenderedMetrics(in: attributed, range: prefixRange).width
        let highlightMetrics = inlineRenderedMetrics(in: attributed, range: range)
        let highlightWidth = max(1, highlightMetrics.width)
        let highlightPadding: CGFloat = highlightMetrics.containsAttachment ? 2 : 4
        let highlightHeight = max(1, highlightMetrics.height) + highlightPadding
        let rowContentX = textContainerOrigin.x + layout.lineStyle.contentX

        return NSRect(
            x: rowContentX + prefixWidth - 2,
            y: lineRect.midY - highlightHeight * 0.5,
            width: highlightWidth + 4,
            height: highlightHeight
        )
    }

    private func inlineRenderedMetrics(in attributed: NSAttributedString, range: NSRange) -> (width: CGFloat, height: CGFloat, containsAttachment: Bool) {
        guard range.length > 0,
              let safeRange = range.clamped(toLength: attributed.length),
              safeRange.length > 0 else { return (0, 0, false) }

        var width: CGFloat = 0
        var height: CGFloat = 0
        var containsAttachment = false
        attributed.enumerateAttributes(in: safeRange, options: []) { attributes, subrange, _ in
            guard subrange.length > 0 else { return }
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                containsAttachment = true
                width += max(0, ceil(attachment.bounds.width))
                height = max(height, ceil(attachment.bounds.height))
                return
            }
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let foregroundColor = attributes[.foregroundColor] as? NSColor
            if font.pointSize <= 0.5 || foregroundColor == NSColor.clear {
                return
            }
            let text = (attributed.string as NSString).substring(with: subrange)
            width += (text as NSString).size(withAttributes: [.font: font]).width
            height = max(height, ceil(font.ascender - font.descender))
        }
        return (width, height, containsAttachment)
    }

    private func backgroundBarRect(for layout: NodeMarkdownTextKit2RowLayout, lineRect: NSRect) -> NSRect {
        let roleStyle = layout.lineStyle.roleStyle
        let font = Self.resolvedFont(for: roleStyle)
        let textHeight = max(layout.lineStyle.backgroundBar.minimumHeight, ceil(font.ascender - font.descender))
        let barHeight = max(textHeight, lineRect.height)
        let trailingEdge = bounds.width - textContainerInset.width
        let startX = textContainerOrigin.x + layout.lineStyle.markerX
        return NSRect(
            x: startX,
            y: lineRect.midY - barHeight * 0.5,
            width: max(0, trailingEdge - startX),
            height: barHeight
        )
    }

    private func drawBackgroundBar(for layout: NodeMarkdownTextKit2RowLayout, in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let baseColor = NSColor(layout.lineStyle.roleStyle.renderedColor).usingColorSpace(.deviceRGB)
            ?? NSColor(layout.lineStyle.roleStyle.renderedColor)
        let backgroundBar = layout.lineStyle.backgroundBar
        let gradient = cachedBackgroundGradient(
            baseColor: baseColor,
            startAlpha: CGFloat(backgroundBar.startAlpha),
            endAlpha: CGFloat(backgroundBar.endAlpha)
        )
        guard let gradient else { return }
        let radii = NodeMarkdownRenderContract.backgroundBarCornerRadii(
            fontSize: CGFloat(layout.lineStyle.roleStyle.fontSize),
            barHeight: rect.height
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: radii.width, yRadius: radii.height)
        NSGraphicsContext.saveGraphicsState()
        gradient.draw(in: path, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func cachedBackgroundGradient(
        baseColor: NSColor,
        startAlpha: CGFloat,
        endAlpha: CGFloat
    ) -> NSGradient? {
        let normalized = NodeMarkdownRenderContract.backgroundColor(from: baseColor)
        let key = NodeMarkdownTextKit2BackgroundGradientCacheKey(
            red: Int((normalized.redComponent * 255).rounded()),
            green: Int((normalized.greenComponent * 255).rounded()),
            blue: Int((normalized.blueComponent * 255).rounded()),
            startAlpha: Int((startAlpha * 1000).rounded()),
            endAlpha: Int((endAlpha * 1000).rounded())
        )
        if let cached = Self.backgroundGradientCache[key] {
            return cached
        }
        let gradient = NSGradient(
            colors: [
                normalized.withAlphaComponent(startAlpha),
                normalized.withAlphaComponent(endAlpha)
            ]
        ) ?? NSGradient(
            starting: normalized.withAlphaComponent(startAlpha),
            ending: normalized.withAlphaComponent(endAlpha)
        )
        if let gradient {
            Self.backgroundGradientCache[key] = gradient
        }
        return gradient
    }
}
#endif
