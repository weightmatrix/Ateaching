// PIPELINE MARKER: NodeMarkdown PDF export bridge (uses TextKit drawing, not the TextKit2 editor split pipeline).
import Foundation

#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

// MARK: - NodeMarkdown TextKit PDF导出 - v1 - 原生导出骨架，作为商用PDF主链路的基础
struct NodeMarkdownTextKitPDFExporter {
    static func export(
        sourceFileURL: URL,
        destinationURL: URL,
        document: NodeMarkdownDocument? = nil,
        style: NodeMarkdownDocumentStyle? = nil,
        settings: TeachingPDFExportSettings? = nil
    ) throws {
        let payload = try document.map { ($0, NodeMarkdownFileMeta()) } ?? NodeMarkdownFileManager.read(fileURL: sourceFileURL)
        let resolvedStyle = style ?? NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        let resolvedSettings = settings ?? effectivePDFSettings()
        let data = try renderData(
            sourceFileURL: sourceFileURL,
            document: payload.0,
            style: resolvedStyle,
            settings: resolvedSettings
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    static func renderData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        settings: TeachingPDFExportSettings? = nil,
        paginationMode: NodeMarkdownPDFPaginationMode = .natural
    ) throws -> Data {
        let renderer = Renderer(
            sourceFileURL: sourceFileURL,
            document: document,
            documentStyle: style,
            settings: settings ?? effectivePDFSettings(),
            contract: .default,
            paginationMode: paginationMode
        )
        return try renderer.render()
    }

    private static func effectivePDFSettings() -> TeachingPDFExportSettings {
        let dedicated = TeachingPDFSettingsStore.load().normalized()
        let snapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        return dedicated == TeachingPDFExportSettings() ? snapshot : dedicated
    }
}

private struct NodeMarkdownTextKitPDFLineFragment {
    let glyphRange: NSRange
    let usedRect: CGRect
}

private struct NodeMarkdownTextKitPDFFormulaRun {
    let glyphRange: NSRange
    let bounds: NSRect
    let image: NSImage
    let highlightColor: NSColor?
}

private let nodeMarkdownTextKitPDFFormulaImageKey = NSAttributedString.Key("NodeMarkdownTextKitPDFFormulaImage")
private let nodeMarkdownTextKitPDFHighlightColorKey = NSAttributedString.Key("NodeMarkdownHighlightBackgroundColor")

private final class NodeMarkdownTextKitPDFFormulaPlaceholderCell: NSTextAttachmentCell {
    private let attachmentBounds: NSRect

    init(attachmentBounds: NSRect) {
        self.attachmentBounds = attachmentBounds
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) {
        attachmentBounds = .zero
        super.init(coder: coder)
    }

    nonisolated override func cellSize() -> NSSize {
        attachmentBounds.size
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: attachmentBounds.minY)
    }

    nonisolated override func cellFrame(
        for textContainer: NSTextContainer,
        proposedLineFragment lineFrag: NSRect,
        glyphPosition position: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        NSRect(
            x: position.x + attachmentBounds.minX,
            y: position.y + attachmentBounds.minY,
            width: attachmentBounds.width,
            height: attachmentBounds.height
        )
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {}

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {}

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {}
}

private final class NodeMarkdownTextKitPDFRowLayout {
    let nodeIndex: Int
    let lineStyle: NodeMarkdownRenderContract.LineStyle
    let font: NSFont
    let color: NSColor
    let storage: NSTextStorage
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    let textUsedRect: CGRect
    let firstLineFragmentRect: CGRect
    let lineFragments: [NodeMarkdownTextKitPDFLineFragment]
    let formulaRuns: [NodeMarkdownTextKitPDFFormulaRun]
    let textHeight: CGFloat
    let rowHeight: CGFloat
    let spacingBefore: CGFloat
    let spacingAfter: CGFloat

    init(
        nodeIndex: Int,
        attributedText: NSAttributedString,
        lineStyle: NodeMarkdownRenderContract.LineStyle,
        font: NSFont,
        color: NSColor,
        textWidth: CGFloat,
        spacingBefore: CGFloat,
        spacingAfter: CGFloat
    ) {
        self.nodeIndex = nodeIndex
        self.lineStyle = lineStyle
        self.font = font
        self.color = color
        self.spacingBefore = spacingBefore
        self.spacingAfter = spacingAfter

        storage = NSTextStorage(attributedString: attributedText.length == 0 ? NSAttributedString(string: " ") : attributedText)
        layoutManager = NSLayoutManager()
        textContainer = NSTextContainer(size: CGSize(width: max(1, textWidth), height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let layoutUsedRect = layoutManager.usedRect(for: textContainer)
        var fragments: [NodeMarkdownTextKitPDFLineFragment] = []
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphRange, _ in
                fragments.append(NodeMarkdownTextKitPDFLineFragment(glyphRange: fragmentGlyphRange, usedRect: usedRect))
            }
        }
        lineFragments = fragments
        var formulas: [NodeMarkdownTextKitPDFFormulaRun] = []
        var formulaUsedRect = CGRect.null
        let storageRef = storage
        let layoutManagerRef = layoutManager
        storageRef.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storageRef.length)) { value, characterRange, _ in
            guard let attachment = value as? NodeMarkdownTextKit2FormulaAttachment,
                  let image = storageRef.attribute(nodeMarkdownTextKitPDFFormulaImageKey, at: characterRange.location, effectiveRange: nil) as? NSImage else { return }
            var actualCharacterRange = NSRange(location: NSNotFound, length: 0)
            let attachmentGlyphRange = layoutManagerRef.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: &actualCharacterRange
            )
            guard attachmentGlyphRange.location != NSNotFound, attachmentGlyphRange.length > 0 else { return }
            let formulaRect = Self.formulaRect(
                bounds: attachment.bounds,
                glyphIndex: attachmentGlyphRange.location,
                layoutManager: layoutManagerRef,
                font: font
            )
            formulaUsedRect = formulaUsedRect.union(formulaRect)
                formulas.append(
                    NodeMarkdownTextKitPDFFormulaRun(
                        glyphRange: attachmentGlyphRange,
                        bounds: attachment.bounds,
                        image: image,
                        highlightColor: storageRef.attribute(
                            NSAttributedString.Key("NodeMarkdownHighlightBackgroundColor"),
                            at: characterRange.location,
                            effectiveRange: nil
                        ) as? NSColor
                    )
                )
        }
        formulaRuns = formulas
        textUsedRect = formulaUsedRect.isNull ? layoutUsedRect : layoutUsedRect.union(formulaUsedRect)
        if let firstFragment = fragments.first {
            firstLineFragmentRect = firstFragment.usedRect.isEmpty ? textUsedRect : firstFragment.usedRect
        } else {
            firstLineFragmentRect = textUsedRect
        }
        textHeight = max(font.ascender - font.descender + font.leading, ceil(textUsedRect.height))
        rowHeight = ceil(spacingBefore + textHeight + spacingAfter)
    }

    static func formulaRect(
        bounds: NSRect,
        glyphIndex: Int,
        layoutManager: NSLayoutManager,
        font: NSFont
    ) -> CGRect {
        // location(forGlyphAt:) 是行片段内坐标，不是文本容器坐标。
        // 自动换行、分H1或跨页时必须先加回所属行片段原点，
        // 否则公式会被画到段落第一行。横坐标与基线都只在这里转换一次。
        var effectiveLineRange = NSRange(location: NSNotFound, length: 0)
        let lineFragmentRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &effectiveLineRange
        )
        let locationInLine = layoutManager.location(forGlyphAt: glyphIndex)
        let baseline = lineFragmentRect.minY + locationInLine.y
        let textCenterFromBaseline = -(font.ascender + font.descender) * 0.5
        return CGRect(
            x: lineFragmentRect.minX + locationInLine.x + bounds.minX,
            y: baseline + textCenterFromBaseline - bounds.height * 0.5,
            width: bounds.width,
            height: bounds.height
        )
    }
}

private final class Renderer {
    private let sourceFileURL: URL
    private let baseDirectoryURL: URL
    private let document: NodeMarkdownDocument
    private let documentStyle: NodeMarkdownDocumentStyle
    private let settings: TeachingPDFExportSettings
    private let contract: NodeMarkdownRenderContract
    private let scale: CGFloat
    private let pageRect: CGRect
    private let contentRect: CGRect
    private let pageBackgroundColor: NSColor
    private let paginationMode: NodeMarkdownPDFPaginationMode
    private let usesMonochromeDecorationBorders: Bool

    init(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        documentStyle: NodeMarkdownDocumentStyle,
        settings: TeachingPDFExportSettings,
        contract: NodeMarkdownRenderContract,
        paginationMode: NodeMarkdownPDFPaginationMode
    ) {
        let resolvedDocumentStyle = Self.resolvedExportStyle(documentStyle)
        self.sourceFileURL = sourceFileURL
        baseDirectoryURL = sourceFileURL.deletingLastPathComponent()
        self.document = document
        self.documentStyle = resolvedDocumentStyle
        self.settings = settings.normalized()
        self.contract = contract
        self.paginationMode = paginationMode
        usesMonochromeDecorationBorders = resolvedDocumentStyle.usesMonochromeDecorationBorders
        scale = CGFloat(max(0.1, min(1.0, settings.normalized().nodeMarkdownScalePercent / 100)))
        pageRect = Self.pageRect(for: settings.normalized())
        pageBackgroundColor = Self.exportBackgroundColor(for: resolvedDocumentStyle)
        contentRect = CGRect(
            x: CGFloat(settings.normalized().marginLeft),
            y: CGFloat(settings.normalized().marginTop),
            width: max(1, pageRect.width - CGFloat(settings.normalized().marginLeft + settings.normalized().marginRight)),
            height: max(1, pageRect.height - CGFloat(settings.normalized().marginTop + settings.normalized().marginBottom))
        )
    }

    func render() throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
            throw NSError(domain: "NodeMarkdownTextKitPDFExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建PDF输出缓冲区。"])
        }
        var mediaBox = pageRect
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "NodeMarkdownTextKitPDFExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "无法创建PDF上下文。"])
        }

        let rows = buildRows()
        beginTopDownPDFPage(in: context)
        var y = contentRect.minY
        for row in rows {
            autoreleasepool {
                if paginationMode == .h1StartsNewPage,
                   document.nodes.indices.contains(row.nodeIndex),
                   document.nodes[row.nodeIndex].level == 1,
                   y > contentRect.minY {
                    context.endPDFPage()
                    beginTopDownPDFPage(in: context)
                    y = contentRect.minY
                }
                if row.rowHeight <= contentRect.height || row.lineFragments.count <= 1 {
                    if y > contentRect.minY, y + row.rowHeight > contentRect.maxY {
                        context.endPDFPage()
                        beginTopDownPDFPage(in: context)
                        y = contentRect.minY
                    }
                    draw(row: row, atY: y, in: context)
                    y += row.rowHeight
                } else {
                    y = drawSplit(row: row, startingAtY: y, in: context)
                }
            }
        }
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    private func beginTopDownPDFPage(in context: CGContext) {
        context.beginPDFPage(nil)
        context.setFillColor(pageBackgroundColor.cgColor)
        context.fill(pageRect)
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
    }

    private func buildRows() -> [NodeMarkdownTextKitPDFRowLayout] {
        var rows: [NodeMarkdownTextKitPDFRowLayout] = []
        for (index, node) in document.nodes.enumerated() {
            let prefix = NodeMarkdownPrefixCodec.encode(level: node.level)
            var lineStyle = contract.lineStyle(level: node.level, prefix: prefix, documentStyle: documentStyle)
            // PDF的编号与正文必须有独立间距。原契约在大字号时会把
            // markerGap 吞进字号占位中，这里在上课 PDF 主链路明确保留它。
            lineStyle.contentX = max(
                lineStyle.contentX,
                lineStyle.markerX + CGFloat(lineStyle.roleStyle.fontSize) + lineStyle.markerGap
            )
            let font = resolvedFont(for: lineStyle.roleStyle)
            let color = Self.resolvedExportColor(
                lineStyle.roleStyle.renderedColor,
                scheme: documentStyle.preferredScheme.resolvedExportScheme
            )
            let textWidth = max(24, contentRect.width - lineStyle.contentX * scale)
            let formulaOnly = Self.isFormulaOnly(node.text)
            let attributedText = attributedContent(
                from: node.text,
                nodeIndex: index,
                level: node.level,
                prefix: prefix,
                lineStyle: lineStyle,
                font: font,
                color: color,
                textWidth: textWidth,
                formulaOnly: formulaOnly
            )
            guard attributedText.length > 0 else { continue }
            let spacingBefore = formulaOnly
                ? 0
                : spacingBeforeRow(previousLineStyle: rows.last?.lineStyle, currentLevel: node.level, currentLineStyle: lineStyle)
            rows.append(
                NodeMarkdownTextKitPDFRowLayout(
                    nodeIndex: index,
                    attributedText: attributedText,
                    lineStyle: lineStyle,
                    font: font,
                    color: color,
                    textWidth: textWidth,
                    spacingBefore: spacingBefore,
                    spacingAfter: 0
                )
            )
        }
        return rows
    }

    private func attributedContent(
        from text: String,
        nodeIndex: Int,
        level: Int,
        prefix: String,
        lineStyle: NodeMarkdownRenderContract.LineStyle,
        font: NSFont,
        color: NSColor,
        textWidth: CGFloat,
        formulaOnly: Bool
    ) -> NSAttributedString {
        let paragraph = pdfParagraphStyle(for: lineStyle)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if text.isEmpty {
            return NSAttributedString(string: " ", attributes: baseAttributes)
        }

        let sourceLine = prefix + text
        let sourceLength = (sourceLine as NSString).length
        let prefixLength = min((prefix as NSString).length, sourceLength)
        let contentRange = NSRange(location: prefixLength, length: max(0, sourceLength - prefixLength))
        guard contentRange.length > 0 else {
            return NSAttributedString(string: " ", attributes: baseAttributes)
        }

        let textKit2LineStyle = scaledLineStyle(lineStyle)
        let rowLayout = NodeMarkdownTextKit2RowLayout(
            rowIndex: nodeIndex,
            range: NSRange(location: 0, length: sourceLength),
            contentRange: contentRange,
            prefix: prefix,
            level: level,
            lineStyle: textKit2LineStyle,
            spacingBefore: 0,
            isProtectedH3: false
        )
        let styled = NSMutableAttributedString(string: sourceLine, attributes: baseAttributes)
        let textView = NodeMarkdownTextKit2TextView()
        textView.usesScreenMinimumFormulaFontSize = false
        textView.frame = CGRect(x: 0, y: 0, width: textWidth + textKit2LineStyle.contentX + 24, height: 1)
        textView.textContainer?.containerSize = CGSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.applyNodeMarkdownStyle(
            to: styled,
            source: sourceLine as NSString,
            layout: rowLayout,
            documentStyle: documentStyle,
            baseDirectoryURL: baseDirectoryURL,
            searchQuery: "",
            activeRowIndex: nil,
            activeMatchLocationInRow: nil,
            editingRowIndex: nil,
            textLength: sourceLength
        )

        let content = NSMutableAttributedString(attributedString: styled.attributedSubstring(from: contentRange))
        content.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: content.length))
        prepareAttachmentsForPDF(
            in: content,
            lineStyle: lineStyle,
            formulaOnly: formulaOnly
        )
        return content
    }

    private func prepareAttachmentsForPDF(
        in attributedText: NSMutableAttributedString,
        lineStyle: NodeMarkdownRenderContract.LineStyle,
        formulaOnly: Bool
    ) {
        guard attributedText.length > 0 else { return }
        var formulaAnchorLocation: Int?
        attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length)) { value, range, _ in
            if let imageAttachment = value as? NodeMarkdownTextKit2ImageAttachment {
                let sourceToken = attributedText.attribute(
                    nodeMarkdownTextKit2AttachmentSourceTokenKey,
                    at: range.location,
                    effectiveRange: nil
                ) as? String
                scaleImageAttachmentForPDF(
                    imageAttachment,
                    sourceToken: sourceToken,
                    lineStyle: lineStyle
                )
                return
            }

            guard let formulaAttachment = value as? NodeMarkdownTextKit2FormulaAttachment,
                  let image = formulaAttachment.image else { return }
            if formulaOnly { formulaAnchorLocation = range.location }
            attributedText.addAttribute(nodeMarkdownTextKitPDFFormulaImageKey, value: image, range: range)
            // 与编辑器保持同一排版输入：附件先用SwiftMath生成时记录的原始
            // 基线边界参与TextKit行布局。PDF绘图阶段再按所属行的文字中线
            // 定位一次；禁止在这里预先居中，否则高公式会造成基线二次偏移。
            let layoutBounds = formulaAttachment.bounds
            formulaAttachment.image = nil
            formulaAttachment.attachmentCell = NodeMarkdownTextKitPDFFormulaPlaceholderCell(
                attachmentBounds: layoutBounds
            )
        }
        if formulaOnly, let formulaAnchorLocation {
            // 纯公式行在 PDF 中只需一个附件锚点。透明 LaTeX 源码
            // 和前后空格若继续参与 TextKit 排版，就会凭空多出一行。
            if formulaAnchorLocation + 1 < attributedText.length {
                attributedText.deleteCharacters(
                    in: NSRange(
                        location: formulaAnchorLocation + 1,
                        length: attributedText.length - formulaAnchorLocation - 1
                    )
                )
            }
            if formulaAnchorLocation > 0 {
                attributedText.deleteCharacters(in: NSRange(location: 0, length: formulaAnchorLocation))
            }
        }
    }

    private static func isFormulaOnly(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        if value.hasPrefix("$$"), value.hasSuffix("$$"), value.count > 4 { return true }
        if value.hasPrefix("$"), value.hasSuffix("$"), !value.hasPrefix("$$"), value.count > 2 { return true }
        if value.hasPrefix("\\("), value.hasSuffix("\\)"), value.count > 4 { return true }
        if value.hasPrefix("\\["), value.hasSuffix("\\]"), value.count > 4 { return true }
        return false
    }

    private func scaleImageAttachmentForPDF(
        _ attachment: NodeMarkdownTextKit2ImageAttachment,
        sourceToken: String?,
        lineStyle: NodeMarkdownRenderContract.LineStyle
    ) {
        let originalBounds = attachment.bounds
        guard originalBounds.width > 0, originalBounds.height > 0 else { return }
        let sourceWidth = sourceToken
            .flatMap { NodeMarkdownImageResourceManager.parseImageTokens(in: $0).first?.width }
            .map(CGFloat.init)
        let requestedWidth = sourceWidth ?? originalBounds.width
        let availableWidth = max(24, contentRect.width - lineStyle.contentX * scale)
        let width = min(availableWidth, max(1, requestedWidth * scale))
        let height = max(1, width * (originalBounds.height / originalBounds.width))
        attachment.bounds = NSRect(
            x: originalBounds.minX,
            y: originalBounds.minY,
            width: width,
            height: height
        )
    }

    private func pdfParagraphStyle(for lineStyle: NodeMarkdownRenderContract.LineStyle) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = max(0, CGFloat(lineStyle.roleStyle.peerLineSpacing) * scale)
        paragraph.paragraphSpacingBefore = 0
        paragraph.paragraphSpacing = 0
        return paragraph
    }

    private func scaledLineStyle(_ lineStyle: NodeMarkdownRenderContract.LineStyle) -> NodeMarkdownRenderContract.LineStyle {
        var scaled = lineStyle
        scaled.roleStyle.fontSize *= Double(scale)
        scaled.roleStyle.paragraphSpacingBefore *= Double(scale)
        scaled.roleStyle.paragraphSpacingAfter *= Double(scale)
        scaled.roleStyle.peerLineSpacing *= Double(scale)
        scaled.contentX *= scale
        scaled.markerX *= scale
        scaled.markerWidth *= scale
        scaled.markerGap *= scale
        scaled.backgroundBar.minimumHeight *= scale
        return scaled
    }

    private func spacingBeforeRow(
        previousLineStyle: NodeMarkdownRenderContract.LineStyle?,
        currentLevel: Int,
        currentLineStyle: NodeMarkdownRenderContract.LineStyle
    ) -> CGFloat {
        NodeMarkdownRenderContract.interRowSpacing(
            previousLevel: previousLineStyle?.level,
            previousRoleStyle: previousLineStyle?.roleStyle,
            currentLevel: currentLevel,
            currentRoleStyle: currentLineStyle.roleStyle,
            scale: scale
        )
    }

    private func drawSplit(row: NodeMarkdownTextKitPDFRowLayout, startingAtY startY: CGFloat, in context: CGContext) -> CGFloat {
        var y = startY
        var fragmentIndex = 0
        let fragments = row.lineFragments
        while fragmentIndex < fragments.count {
            if y > contentRect.minY, contentRect.maxY - y < max(18 * scale, row.firstLineFragmentRect.height) {
                context.endPDFPage()
                beginTopDownPDFPage(in: context)
                y = contentRect.minY
            }

            let topPadding = fragmentIndex == 0 ? row.spacingBefore : 0
            let firstTop = fragments[fragmentIndex].usedRect.minY
            let availableTextHeight = max(1, contentRect.maxY - y - topPadding)
            var lastIndex = fragmentIndex
            var chunkBottom = fragments[fragmentIndex].usedRect.maxY
            while lastIndex + 1 < fragments.count,
                  fragments[lastIndex + 1].usedRect.maxY - firstTop <= availableTextHeight {
                lastIndex += 1
                chunkBottom = fragments[lastIndex].usedRect.maxY
            }

            if lastIndex == fragmentIndex,
               fragments[fragmentIndex].usedRect.height > availableTextHeight,
               y > contentRect.minY {
                context.endPDFPage()
                beginTopDownPDFPage(in: context)
                y = contentRect.minY
                continue
            }

            let bottomPadding = lastIndex == fragments.count - 1 ? row.spacingAfter : 0
            let chunkTextHeight = max(1, chunkBottom - firstTop)
            let chunkHeight = min(contentRect.height, topPadding + chunkTextHeight + bottomPadding)
            draw(
                row: row,
                atY: y,
                textYOffset: firstTop,
                topPadding: topPadding,
                clipHeight: chunkHeight,
                includeMarker: fragmentIndex == 0,
                in: context
            )
            y += chunkHeight
            fragmentIndex = lastIndex + 1
            if fragmentIndex < fragments.count {
                context.endPDFPage()
                beginTopDownPDFPage(in: context)
                y = contentRect.minY
            }
        }
        return y
    }

    private func draw(row: NodeMarkdownTextKitPDFRowLayout, atY y: CGFloat, in context: CGContext) {
        draw(
            row: row,
            atY: y,
            textYOffset: row.textUsedRect.minY,
            topPadding: row.spacingBefore,
            clipHeight: row.rowHeight,
            includeMarker: true,
            in: context
        )
    }

    private func draw(
        row: NodeMarkdownTextKitPDFRowLayout,
        atY y: CGFloat,
        textYOffset: CGFloat,
        topPadding: CGFloat,
        clipHeight: CGFloat,
        includeMarker: Bool,
        in context: CGContext
    ) {
        NSGraphicsContext.saveGraphicsState()
        context.saveGState()
        context.clip(to: CGRect(x: contentRect.minX, y: y, width: contentRect.width, height: min(clipHeight, contentRect.maxY - y)))
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = graphicsContext

        let markerX = contentRect.minX + row.lineStyle.markerX * scale
        let textX = contentRect.minX + row.lineStyle.contentX * scale
        let textOrigin = CGPoint(x: textX, y: y + topPadding - textYOffset)

        if row.lineStyle.hasBackgroundBar {
            drawBackgroundBar(for: row, textOrigin: textOrigin, markerX: markerX, in: context)
        }
        drawInlineHighlights(for: row, textOrigin: textOrigin)
        if includeMarker {
            drawMarker(for: row, x: markerX, textOrigin: textOrigin)
        }

        let glyphRange = row.layoutManager.glyphRange(for: row.textContainer)
        if !row.lineStyle.hasBackgroundBar {
            row.layoutManager.drawBackground(forGlyphRange: glyphRange, at: textOrigin)
        }
        row.layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: textOrigin)
        drawFormulaRuns(for: row, glyphRange: glyphRange, textOrigin: textOrigin, in: context)

        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFormulaRuns(
        for row: NodeMarkdownTextKitPDFRowLayout,
        glyphRange: NSRange,
        textOrigin: CGPoint,
        in context: CGContext
    ) {
        guard !row.formulaRuns.isEmpty else { return }
        for formula in row.formulaRuns where NSIntersectionRange(formula.glyphRange, glyphRange).length > 0 {
            let glyphIndex = formula.glyphRange.location
            guard glyphIndex < row.layoutManager.numberOfGlyphs else { continue }
            let formulaRect = NodeMarkdownTextKitPDFRowLayout.formulaRect(
                bounds: formula.bounds,
                glyphIndex: glyphIndex,
                layoutManager: row.layoutManager,
                font: row.font
            )
            let drawRect = formulaRect.offsetBy(dx: textOrigin.x, dy: textOrigin.y)
            guard drawRect.width > 0, drawRect.height > 0 else { continue }
            if let highlightColor = formula.highlightColor {
                drawFormulaHighlight(
                    color: highlightColor,
                    formulaRect: drawRect,
                    lineHeight: row.firstLineFragmentRect.height
                )
            }
            drawFormulaImage(formula.image, in: drawRect, context: context)
        }
    }

    private func drawFormulaHighlight(color: NSColor, formulaRect: NSRect, lineHeight: CGFloat) {
        let height = max(formulaRect.height + 4, min(max(1, lineHeight), formulaRect.height + 8))
        let rect = NSRect(
            x: formulaRect.minX - 2,
            y: formulaRect.midY - height * 0.5,
            width: formulaRect.width + 4,
            height: height
        )
        drawHighlightShape(
            rect: rect,
            color: color,
            radius: 3
        )
    }

    private func drawInlineHighlights(
        for row: NodeMarkdownTextKitPDFRowLayout,
        textOrigin: CGPoint
    ) {
        guard row.storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: row.storage.length)
        row.storage.enumerateAttribute(
            nodeMarkdownTextKitPDFHighlightColorKey,
            in: fullRange,
            options: []
        ) { value, characterRange, _ in
            guard let color = value as? NSColor, characterRange.length > 0 else { return }
            let highlightGlyphRange = row.layoutManager.glyphRange(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            guard highlightGlyphRange.length > 0 else { return }

            row.layoutManager.enumerateLineFragments(
                forGlyphRange: highlightGlyphRange
            ) { lineFragmentRect, _, textContainer, lineGlyphRange, _ in
                let clippedRange = NSIntersectionRange(highlightGlyphRange, lineGlyphRange)
                guard clippedRange.length > 0 else { return }
                let characterSubrange = row.layoutManager.characterRange(
                    forGlyphRange: clippedRange,
                    actualGlyphRange: nil
                )
                let containsFormula = row.storage.attribute(
                    .attachment,
                    at: min(characterSubrange.location, max(0, row.storage.length - 1)),
                    effectiveRange: nil
                ) is NodeMarkdownTextKit2FormulaAttachment
                if containsFormula && characterSubrange.length == 1 {
                    return
                }

                let visualRect = row.layoutManager.boundingRect(
                    forGlyphRange: clippedRange,
                    in: textContainer
                )
                guard !visualRect.isEmpty else { return }
                let height = min(
                    max(1, lineFragmentRect.height),
                    max(visualRect.height + 4, row.font.ascender - row.font.descender + 2)
                )
                let rect = NSRect(
                    x: textOrigin.x + visualRect.minX - 2,
                    y: textOrigin.y + visualRect.midY - height * 0.5,
                    width: visualRect.width + 4,
                    height: height
                )
                self.drawHighlightShape(
                    rect: rect,
                    color: color,
                    radius: min(8, rect.height * 0.28)
                )
            }
        }
    }

    private func drawHighlightShape(
        rect: NSRect,
        color: NSColor,
        radius: CGFloat
    ) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()
        guard usesMonochromeDecorationBorders else { return }
        NSColor.black.setStroke()
        path.lineWidth = max(0.75, scale)
        path.stroke()
    }

    private func drawFormulaImage(_ image: NSImage, in drawRect: NSRect, context: CGContext) {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.translateBy(x: drawRect.minX, y: drawRect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(origin: .zero, size: drawRect.size))
        context.restoreGState()
    }

    private func drawMarker(for row: NodeMarkdownTextKitPDFRowLayout, x: CGFloat, textOrigin: CGPoint) {
        let marker = row.lineStyle.iconGlyph
        guard !marker.isEmpty else { return }
        let markerFont = row.font
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont,
            .foregroundColor: row.color.withAlphaComponent(0.85)
        ]
        let attributed = NSAttributedString(string: marker, attributes: attributes)
        let measured = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let markerSize = attributed.size()
        let markerRect = CGRect(
            x: x + max(0, row.lineStyle.markerWidth * scale - measured.width) * 0.5 - measured.minX,
            y: textOrigin.y + row.firstLineFragmentRect.midY - measured.midY,
            width: markerSize.width,
            height: markerSize.height
        )
        attributed.draw(in: markerRect)
    }

    private func drawBackgroundBar(
        for row: NodeMarkdownTextKitPDFRowLayout,
        textOrigin: CGPoint,
        markerX: CGFloat,
        in context: CGContext
    ) {
        // 上课 PDF 直接使用层级原色，不参与编辑器的饱和度增强。
        // 先与页面底色合成再写入 PDF，避免不同查看器把透明渐变显示成浓色。
        let baseColor = row.color.usingColorSpace(.sRGB) ?? row.color
        let startColor = blendedBackgroundColor(baseColor, amount: 0.10)
        let endColor = blendedBackgroundColor(baseColor, amount: 0.02)
        let fontHeight = ceil(row.font.ascender - row.font.descender)
        let usedRect = row.textUsedRect.isEmpty ? row.firstLineFragmentRect : row.textUsedRect
        let height = max(row.lineStyle.backgroundBar.minimumHeight * scale, fontHeight, usedRect.height)
        let rect = CGRect(
            x: markerX,
            y: textOrigin.y + usedRect.midY - height * 0.5,
            width: max(24, contentRect.maxX - markerX),
            height: height
        )
        guard rect.width > 0, rect.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                colorSpace: colorSpace,
                colorComponents: [
                    startColor.redComponent, startColor.greenComponent, startColor.blueComponent, 1,
                    endColor.redComponent, endColor.greenComponent, endColor.blueComponent, 1
                ],
                locations: [0, 1],
                count: 2
              ) else { return }
        let radii = NodeMarkdownRenderContract.backgroundBarCornerRadii(
            fontSize: row.font.pointSize,
            barHeight: rect.height
        )
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: radii.width,
            cornerHeight: radii.height,
            transform: nil
        )

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        context.restoreGState()
        guard usesMonochromeDecorationBorders else { return }
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(max(0.75, scale))
        context.strokePath()
        context.restoreGState()
    }

    private func blendedBackgroundColor(_ foreground: NSColor, amount: CGFloat) -> NSColor {
        let foregroundRGB = foreground.usingColorSpace(.sRGB) ?? foreground
        let backgroundRGB = pageBackgroundColor.usingColorSpace(.sRGB) ?? pageBackgroundColor
        let ratio = max(0, min(1, amount))
        return NSColor(
            srgbRed: backgroundRGB.redComponent + (foregroundRGB.redComponent - backgroundRGB.redComponent) * ratio,
            green: backgroundRGB.greenComponent + (foregroundRGB.greenComponent - backgroundRGB.greenComponent) * ratio,
            blue: backgroundRGB.blueComponent + (foregroundRGB.blueComponent - backgroundRGB.blueComponent) * ratio,
            alpha: 1
        )
    }

    private func resolvedFont(for roleStyle: NodeMarkdownRoleStyle) -> NSFont {
        let size = max(8, CGFloat(roleStyle.fontSize) * scale)
        let base = NSFont(name: roleStyle.fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if roleStyle.isBold {
            return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
        }
        return base
    }

    private static func pageRect(for settings: TeachingPDFExportSettings) -> CGRect {
        let base: CGSize = switch settings.paperPreset {
        case .a4:
            CGSize(width: 595, height: 842)
        case .letter:
            CGSize(width: 612, height: 792)
        case .custom:
            CGSize(width: settings.customWidth, height: settings.customHeight)
        }
        let size: CGSize = switch settings.orientation {
        case .portrait:
            base
        case .landscape:
            CGSize(width: base.height, height: base.width)
        }
        return CGRect(origin: .zero, size: size)
    }

    private static func exportBackgroundColor(for style: NodeMarkdownDocumentStyle) -> NSColor {
        let scheme = style.preferredScheme.resolvedExportScheme
        guard !style.useSystemBackground else { return scheme == .dark ? .black : .white }
        return resolvedExportColor(style.editorBackgroundColor, scheme: scheme)
    }

    private static func resolvedExportStyle(
        _ style: NodeMarkdownDocumentStyle
    ) -> NodeMarkdownDocumentStyle {
        var resolvedStyle = style
        let scheme = style.preferredScheme.resolvedExportScheme
        for role in NodeMarkdownStyleRole.allCases {
            var roleStyle = style.style(for: role)
            let color = resolvedExportColor(roleStyle.renderedColor, scheme: scheme)
            roleStyle.color = Color(color)
            roleStyle.semanticColor = nil
            resolvedStyle.update(roleStyle, for: role)
        }
        if !style.useSystemBackground {
            resolvedStyle.editorBackgroundColor = Color(
                resolvedExportColor(style.editorBackgroundColor, scheme: scheme)
            )
        }
        return resolvedStyle
    }

    private static func resolvedExportColor(
        _ color: Color,
        scheme: NodeMarkdownPreferredScheme
    ) -> NSColor {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        var resolved: NSColor?
        appearance?.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        if resolved == nil {
            resolved = NSColor(color).usingColorSpace(.sRGB)
        }
        return resolved ?? .black
    }
}
#endif
