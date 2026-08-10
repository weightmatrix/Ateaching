// PIPELINE MARKER: NodeMarkdown TextKit2 new pipeline.
import SwiftUI

#if os(macOS)
import AppKit
#if canImport(SwiftMath)
import SwiftMath
#endif

extension NodeMarkdownTextKit2TextView {
    func invalidateNodeMarkdownDecorationsAfterViewportLayout() {
        let displayRect = visibleRect.isEmpty ? bounds : visibleRect
        guard !displayRect.isEmpty else { return }
        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: displayRect))
        setNeedsDisplay(displayRect)
    }

    /// 行属性事务会使TextKit2旧片段失效。先让当前可见区完成布局，再一次性重画
    /// 背景条、高亮和编号；不能依靠下一次滚动碰巧触发第二次draw。
    func invalidateNodeMarkdownDecorationsAfterRowStyleChange(rows: [Int]) {
        let displayRect = visibleRect.isEmpty ? bounds : visibleRect
        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: displayRect))
        setNeedsDisplay(displayRect)
        NodeMarkdownTextKit2Diagnostics.log("行样式事务完成：刷新行=\(rows)，装饰重画区域=\(NSStringFromRect(displayRect))，viewportRange=\(nodeTextLayoutManager.textViewportLayoutController.viewportRange.map(String.init(describing:)) ?? "nil")。")
    }

    @discardableResult
    func drawNodeMarkdownMarkers(in dirtyRect: NSRect) -> Int {
        guard !nodeMarkdownRowLayouts.isEmpty else { return 0 }
        let documentStart = nodeTextContentStorage.documentRange.location
        var drawnCount = 0

        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: dirtyRect))
        for layout in visibleRowLayouts(in: dirtyRect) {
            guard let lineRect = firstLineRect(for: layout, documentStart: documentStart) else { continue }
            let markerRect = markerDrawingRect(for: layout, lineRect: lineRect)
            guard markerRect.intersects(dirtyRect) else { continue }
            drawMarker(for: layout, in: markerRect)
            drawnCount += 1
        }
        return drawnCount
    }

    @discardableResult
    func drawNodeMarkdownBackgroundBars(in dirtyRect: NSRect) -> Int {
        guard !nodeMarkdownRowLayouts.isEmpty else { return 0 }
        let documentStart = nodeTextContentStorage.documentRange.location
        var drawnCount = 0

        nodeTextLayoutManager.ensureLayout(for: visibleTextContainerRect(in: dirtyRect))
        for layout in visibleRowLayouts(in: dirtyRect) where layout.lineStyle.hasBackgroundBar {
            guard let textRect = rowTextRect(for: layout, documentStart: documentStart) else { continue }
            let barRect = backgroundBarRect(for: layout, textRect: textRect)
            guard barRect.intersects(dirtyRect) else { continue }
            drawBackgroundBar(for: layout, in: barRect)
            drawnCount += 1
        }
        return drawnCount
    }

    @discardableResult
    func drawNodeMarkdownInlineHighlights(in dirtyRect: NSRect) -> Int {
        guard !nodeMarkdownRowLayouts.isEmpty else { return 0 }
        // 绘制发生在主线程，直接只读唯一TextStorage；禁止每次滚动复制整篇富文本。
        let attributed: NSAttributedString = nodeTextStorage
        guard attributed.length > 0 else { return 0 }
        let visibleLayouts = visibleRowLayouts(in: dirtyRect)
        guard !visibleLayouts.isEmpty else { return 0 }
        guard visibleLayouts.allSatisfy({ $0.range.exact(toLength: attributed.length) != nil }) else {
            NodeMarkdownTextKit2Diagnostics.log("跳过高亮绘制：可见行范围与真实TextStorage不一致。")
            return 0
        }

        let visibleRange = visibleLayouts.reduce(nil as NSRange?) { result, layout in
            let current = layout.range
            guard let result else { return current }
            return NSUnionRange(result, current)
        }
        guard let visibleRange, visibleRange.length > 0 else { return 0 }

        let documentStart = nodeTextContentStorage.documentRange.location
        var drawnCount = 0
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
            drawnCount += 1
        }
        return drawnCount
    }

    func installNodeMarkdownDiagnostics19(in scrollView: NSScrollView) {
        #if DEBUG
        for observer in diagnostic19Observers {
            NotificationCenter.default.removeObserver(observer)
        }
        diagnostic19Observers.removeAll()

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        diagnostic19Observers.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recordNodeMarkdownViewportEvent19(reason: "滚动")
                }
            }
        )
        diagnostic19Observers.append(
            center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recordNodeMarkdownViewportEvent19(reason: "视口尺寸变化")
                }
            }
        )
        #endif
    }

    func diagnoseNodeMarkdownDecorations19(
        stage: String,
        dirtyRect: NSRect,
        drawnBackgrounds: Int,
        drawnHighlights: Int,
        drawnMarkers: Int
    ) {
        #if DEBUG
        guard nodeTextStorage.length > 0, !nodeMarkdownRowLayouts.isEmpty else { return }
        let candidates = visibleRowLayouts(in: dirtyRect)
        let candidateRows = candidates.map(\.rowIndex)
        let viewportRows = diagnostic19ViewportRows()
        let documentStart = nodeTextContentStorage.documentRange.location
        var rowsWithLineGeometry: [Int] = []
        var expectedBackgrounds = 0
        var expectedMarkers = 0
        var expectedHighlights = 0

        for layout in candidates {
            guard let lineRect = firstLineRect(for: layout, documentStart: documentStart) else { continue }
            rowsWithLineGeometry.append(layout.rowIndex)
            if layout.lineStyle.hasBackgroundBar,
               let textRect = rowTextRect(for: layout, documentStart: documentStart),
               backgroundBarRect(for: layout, textRect: textRect).intersects(dirtyRect) {
                expectedBackgrounds += 1
            }
            if !layout.lineStyle.iconGlyph.isEmpty,
               markerDrawingRect(for: layout, lineRect: lineRect).intersects(dirtyRect) {
                expectedMarkers += 1
            }
            if let safeRange = layout.range.exact(toLength: nodeTextStorage.length), safeRange.length > 0 {
                nodeTextStorage.enumerateAttribute(
                    Self.inlineHighlightBackgroundColorKey,
                    in: safeRange,
                    options: []
                ) { value, range, _ in
                    guard value is NSColor,
                          let rect = inlineHighlightRect(
                            for: range,
                            in: nodeTextStorage,
                            layout: layout,
                            lineRect: lineRect
                          ),
                          rect.intersects(dirtyRect) else { return }
                    expectedHighlights += 1
                }
            }
        }

        let candidateRowSet = Set(candidateRows)
        let mismatch = expectedBackgrounds != drawnBackgrounds
            || expectedHighlights != drawnHighlights
            || expectedMarkers != drawnMarkers
            || !Set(viewportRows).isSubset(of: candidateRowSet)
        NodeMarkdownTextKit2Diagnostics.log19(
            "\(stage)，dirty=\(NSStringFromRect(dirtyRect))，visible=\(NSStringFromRect(visibleRect))，viewport字符=\(diagnostic19ViewportCharacterRangeDescription())，viewport行=\(viewportRows)，候选行=\(candidateRows)，有行几何=\(rowsWithLineGeometry)，期望/实画=背景\(expectedBackgrounds)/\(drawnBackgrounds)、高亮\(expectedHighlights)/\(drawnHighlights)、编号\(expectedMarkers)/\(drawnMarkers)，不一致=\(mismatch)。"
        )
        #endif
    }

    private func recordNodeMarkdownViewportEvent19(reason: String) {
        guard nodeTextStorage.length > 0, diagnostic19EventSequence < 80 else { return }
        diagnostic19EventSequence += 1
        let event = diagnostic19EventSequence
        let drawSequenceAtEvent = diagnostic19DrawSequence
        NodeMarkdownTextKit2Diagnostics.log19(
            "事件-\(event)=\(reason)，clip=\(NSStringFromRect(enclosingScrollView?.contentView.bounds ?? .zero))，visible=\(NSStringFromRect(visibleRect))，viewport字符=\(diagnostic19ViewportCharacterRangeDescription())，viewport行=\(diagnostic19ViewportRows())，当时draw序号=\(drawSequenceAtEvent)，needsDisplay=\(needsDisplay)。"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            NodeMarkdownTextKit2Diagnostics.log19(
                "事件-\(event)后80ms，draw序号=\(self.diagnostic19DrawSequence)，发生新draw=\(self.diagnostic19DrawSequence != drawSequenceAtEvent)，needsDisplay=\(self.needsDisplay)，viewport字符=\(self.diagnostic19ViewportCharacterRangeDescription())，viewport行=\(self.diagnostic19ViewportRows())。"
            )
        }
    }

    private func diagnostic19ViewportCharacterRange() -> NSRange? {
        guard let viewportRange = nodeTextLayoutManager.textViewportLayoutController.viewportRange else {
            return nil
        }
        let documentStart = nodeTextContentStorage.documentRange.location
        let start = nodeTextContentStorage.offset(from: documentStart, to: viewportRange.location)
        let end = nodeTextContentStorage.offset(from: documentStart, to: viewportRange.endLocation)
        guard start >= 0, end >= start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func diagnostic19ViewportCharacterRangeDescription() -> String {
        diagnostic19ViewportCharacterRange().map(NSStringFromRange) ?? "nil"
    }

    private func diagnostic19ViewportRows() -> [Int] {
        guard let range = diagnostic19ViewportCharacterRange() else { return [] }
        return nodeMarkdownRowLayouts.compactMap { layout in
            let intersects = NSIntersectionRange(layout.range, range).length > 0
                || (layout.range.length == 0 && NSLocationInRange(layout.range.location, range))
            return intersects ? layout.rowIndex : nil
        }
    }

    private func visibleTextContainerRect(in dirtyRect: NSRect) -> NSRect {
        dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
    }

    private func visibleRowLayouts(in dirtyRect: NSRect) -> [NodeMarkdownTextKit2RowLayout] {
        guard !nodeMarkdownRowLayouts.isEmpty else { return [] }
        let documentLength = nodeTextStorage.length
        guard documentLength > 0 else { return Array(nodeMarkdownRowLayouts.prefix(1)) }

        // TextKit2 already owns the authoritative viewport. Do not infer visible rows by hit
        // testing the marker gutter: before the first scroll that empty area can resolve to
        // the document tail and make every decoration at the top disappear.
        guard let viewportRange = nodeTextLayoutManager.textViewportLayoutController.viewportRange else {
            // prepareViewport会在真实尺寸布局完成后明确请求重画；这里没有事实范围时不猜。
            return []
        }
        let documentStart = nodeTextContentStorage.documentRange.location
        let viewportStart = nodeTextContentStorage.offset(from: documentStart, to: viewportRange.location)
        let viewportEnd = nodeTextContentStorage.offset(from: documentStart, to: viewportRange.endLocation)
        guard viewportStart >= 0,
              viewportStart <= viewportEnd,
              viewportEnd <= documentLength else { return [] }
        return rowLayouts(from: viewportStart, through: viewportEnd)
    }

    private func rowLayouts(from startLocation: Int, through endLocation: Int) -> [NodeMarkdownTextKit2RowLayout] {
        guard let exactStartRow = rowIndex(containing: startLocation),
              let exactEndRow = rowIndex(containing: max(startLocation, endLocation)) else { return [] }
        let startRow = max(0, exactStartRow - 2)
        let endRow = min(
            nodeMarkdownRowLayouts.count - 1,
            exactEndRow + 2
        )
        guard startRow <= endRow else { return [] }
        return Array(nodeMarkdownRowLayouts[startRow...endRow])
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
        var rect = NSRect(
            x: textContainerOrigin.x + fragmentFrame.minX + lineBounds.minX,
            y: textContainerOrigin.y + fragmentFrame.minY + lineBounds.minY,
            width: lineBounds.width,
            height: lineBounds.height
        )
        if layout.range.length == 0 {
            let font = Self.resolvedFont(for: layout.lineStyle.roleStyle)
            let paragraphStyle = Self.paragraphStyle(for: layout, font: font)
            let minHeight = paragraphStyle.minimumLineHeight
            if rect.height < minHeight {
                rect.origin.y -= (minHeight - rect.height) * 0.5
                rect.size.height = minHeight
            }
        }
        return rect
    }

    private func rowTextRect(
        for layout: NodeMarkdownTextKit2RowLayout,
        documentStart: any NSTextLocation
    ) -> NSRect? {
        guard let location = nodeTextContentStorage.location(
            documentStart,
            offsetBy: layout.range.location
        ),
        let fragment = nodeTextLayoutManager.textLayoutFragment(for: location) else {
            return nil
        }

        let fragmentFrame = fragment.layoutFragmentFrame
        let lineRects = fragment.textLineFragments.map { lineFragment in
            let bounds = lineFragment.typographicBounds
            return NSRect(
                x: textContainerOrigin.x + fragmentFrame.minX + bounds.minX,
                y: textContainerOrigin.y + fragmentFrame.minY + bounds.minY,
                width: bounds.width,
                height: bounds.height
            )
        }
        guard var rect = lineRects.reduce(nil as NSRect?, { partial, lineRect in
            partial.map { $0.union(lineRect) } ?? lineRect
        }) else {
            return firstLineRect(for: layout, documentStart: documentStart)
        }

        let font = Self.resolvedFont(for: layout.lineStyle.roleStyle)
        let minimumHeight = max(
            layout.lineStyle.backgroundBar.minimumHeight,
            ceil(font.ascender - font.descender)
        )
        if rect.height < minimumHeight {
            rect.origin.y -= (minimumHeight - rect.height) * 0.5
            rect.size.height = minimumHeight
        }
        return rect
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
        guard let row = rowIndex(containing: range.location) else { return nil }
        guard nodeMarkdownRowLayouts.indices.contains(row) else { return nil }
        let layout = nodeMarkdownRowLayouts[row]
        return NSIntersectionRange(layout.range, range).length == range.length ? layout : nil
    }

    private func rowIndex(containing requestedLocation: Int) -> Int? {
        guard !nodeMarkdownRowLayouts.isEmpty else { return nil }
        guard requestedLocation >= 0, requestedLocation <= nodeTextStorage.length else { return nil }
        let location = requestedLocation
        if location == nodeTextStorage.length { return nodeMarkdownRowLayouts.count - 1 }
        var low = 0
        var high = nodeMarkdownRowLayouts.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = nodeMarkdownRowLayouts[middle].range
            if location < range.location {
                high = middle - 1
            } else if location >= NSMaxRange(range) {
                low = middle + 1
            } else {
                return middle
            }
        }
        return nil
    }

    private func inlineHighlightRect(
        for range: NSRange,
        in attributed: NSAttributedString,
        layout: NodeMarkdownTextKit2RowLayout,
        lineRect: NSRect
    ) -> NSRect? {
        guard layout.range.exact(toLength: attributed.length) != nil,
              let contentRange = layout.contentRange.exact(toLength: attributed.length),
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
              let safeRange = range.exact(toLength: attributed.length),
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

    private func backgroundBarRect(for layout: NodeMarkdownTextKit2RowLayout, textRect: NSRect) -> NSRect {
        let roleStyle = layout.lineStyle.roleStyle
        let font = Self.resolvedFont(for: roleStyle)
        let textHeight = max(layout.lineStyle.backgroundBar.minimumHeight, ceil(font.ascender - font.descender))
        let barHeight = max(textHeight, textRect.height)
        let trailingEdge = bounds.width - textContainerInset.width
        let startX = textContainerOrigin.x + layout.lineStyle.markerX
        return NSRect(
            x: startX,
            y: textRect.midY - barHeight * 0.5,
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
