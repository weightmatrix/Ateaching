import Foundation
#if os(macOS)
import AppKit
#endif

enum NodeMarkdownScaledPDFExporter {
    static let defaultScale: Double = 0.4

    static func export(
        sourceFileURL: URL,
        destinationURL: URL,
        scale: Double = defaultScale
    ) throws {
        let payload = try NodeMarkdownFileManager.read(fileURL: sourceFileURL)
        let style = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        let data = try renderData(
            sourceFileURL: sourceFileURL,
            document: payload.0,
            style: style,
            scale: scale
        )
        try data.write(to: destinationURL, options: .atomic)
    }

    static func renderData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        scale: Double = defaultScale
    ) throws -> Data {
        #if os(macOS)
        let settingsFromDedicated = TeachingPDFSettingsStore.load()
        let settingsFromSnapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        let settings = settingsFromDedicated == TeachingPDFExportSettings() ? settingsFromSnapshot : settingsFromDedicated
        let clampedScale = min(1.0, max(0.1, scale))
        let paperSize = paperSize(for: settings)
        let printInfo = configuredPrintInfo(settings: settings, paperSize: paperSize)

        let textStorage = NSTextStorage(attributedString: buildAttributedDocument(document: document, style: style, scale: clampedScale))
        let layoutManager = NSLayoutManager()
        if #available(macOS 13.0, *) {
            layoutManager.usesFontLeading = true
        }
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(
            width: max(1, paperSize.width - printInfo.leftMargin - printInfo.rightMargin),
            height: .greatestFiniteMagnitude
        ))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: paperSize), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = true
        textView.backgroundColor = .white

        let output = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(
            with: textView,
            inside: textView.bounds,
            to: output,
            printInfo: printInfo
        )
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw NSError(domain: "NodeMarkdownScaledPDFExporter", code: -71, userInfo: [NSLocalizedDescriptionKey: "TextKit2 PDF导出失败。"])
        }
        return output as Data
        #else
        throw NSError(domain: "NodeMarkdownScaledPDFExporter", code: -70, userInfo: [NSLocalizedDescriptionKey: "当前平台不支持TextKit2 PDF导出。"])
        #endif
    }

    #if os(macOS)
    private static func configuredPrintInfo(settings: TeachingPDFExportSettings, paperSize: CGSize) -> NSPrintInfo {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = paperSize
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = max(24, settings.marginTop)
        printInfo.bottomMargin = max(24, settings.marginBottom)
        printInfo.leftMargin = max(16, settings.marginLeft)
        printInfo.rightMargin = max(16, settings.marginRight)
        return printInfo
    }

    private static func buildAttributedDocument(
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        scale: Double
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, node) in document.nodes.enumerated() {
            let roleStyle = style.style(forLevel: node.level)
            let text = normalizedDisplayText(for: node)
            let line = NSMutableAttributedString(string: text, attributes: attributes(for: roleStyle, scale: scale))
            if roleStyle.hasBackgroundBar {
                line.addAttribute(.backgroundColor, value: nsColor(from: roleStyle), range: NSRange(location: 0, length: line.length))
            }
            output.append(line)
            if index < document.nodes.count - 1 {
                output.append(NSAttributedString(string: "\n"))
            }
        }
        return output
    }

    private static func normalizedDisplayText(for node: NodeMarkdownNode) -> String {
        let raw = node.text.trimmingCharacters(in: .newlines)
        guard !raw.isEmpty else { return " " }
        return raw
    }

    private static func attributes(for style: NodeMarkdownRoleStyle, scale: Double) -> [NSAttributedString.Key: Any] {
        let fontSize = CGFloat(max(8, style.fontSize * scale))
        let font = resolvedFont(name: style.fontName, size: fontSize, bold: style.isBold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = CGFloat(max(0, style.paragraphSpacingBefore * scale))
        paragraph.paragraphSpacing = CGFloat(max(0, style.paragraphSpacingAfter * scale))
        paragraph.lineSpacing = CGFloat(max(0, style.peerLineSpacing * scale))
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: font,
            .foregroundColor: nsColor(from: style),
            .paragraphStyle: paragraph
        ]
    }

    private static func resolvedFont(name: String, size: CGFloat, bold: Bool) -> NSFont {
        if let exact = NSFont(name: name, size: size) {
            if bold, let boldVersion = NSFontManager.shared.convert(exact, toHaveTrait: .boldFontMask) as NSFont? {
                return boldVersion
            }
            return exact
        }
        let weight: NSFont.Weight = bold ? .bold : .regular
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func nsColor(from style: NodeMarkdownRoleStyle) -> NSColor {
        if style.semanticColor == .adaptiveBlackWhite {
            return .labelColor
        }
        return .labelColor
    }
    #endif

    private static func paperSize(for settings: TeachingPDFExportSettings) -> CGSize {
        let base: CGSize = switch settings.paperPreset {
        case .a4:
            CGSize(width: 595, height: 842)
        case .letter:
            CGSize(width: 612, height: 792)
        case .custom:
            CGSize(width: max(200, settings.customWidth), height: max(200, settings.customHeight))
        }
        switch settings.orientation {
        case .portrait: return base
        case .landscape: return CGSize(width: base.height, height: base.width)
        }
    }
}
