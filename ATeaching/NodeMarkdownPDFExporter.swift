// PIPELINE MARKER: NodeMarkdown legacy/export bridge (not the TextKit2 editor split pipeline).
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// 分H1模式允许文档从任意层级开始；此后每个H1都连同自身从新页开始。
enum NodeMarkdownPDFPaginationMode {
    case natural
    case h1StartsNewPage
}

enum NodeMarkdownPDFExporter {
    static func export(
        sourceFileURL: URL,
        destinationURL: URL
    ) throws {
        do {
            try exportWithTextKitIfAvailable(
                sourceFileURL: sourceFileURL,
                destinationURL: destinationURL
            )
        } catch {
            TeachingDebugLogStore.append(
                "TextKit PDF导出失败，回退旧管线：\(error.localizedDescription)",
                category: "PDF.Export"
            )
            try TeachingNodeMarkdownPrintPipeline.execute(
                job: .init(
                    sourceFileURL: sourceFileURL,
                    destinationURL: destinationURL,
                    mode: .auto,
                    retryCount: 1
                )
            )
        }
    }

    static func renderData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        paginationMode: NodeMarkdownPDFPaginationMode = .natural
    ) throws -> Data {
        do {
            let data = try renderDataWithTextKitIfAvailable(
                sourceFileURL: sourceFileURL,
                document: document,
                style: style,
                paginationMode: paginationMode
            )
            TeachingDebugLogStore.append(
                "上课NodeMarkdown PDF渲染链路：TextKit原生导出，背景条=页面合成10%-2%渐变",
                category: "PDF.Export"
            )
            return data
        } catch {
            TeachingDebugLogStore.append(
                "TextKit PDF数据渲染失败，回退旧管线：\(error.localizedDescription)",
                category: "PDF.Export"
            )
            let settings = try TeachingNodeMarkdownPrintPipeline
                .prepare(sourceFileURL: sourceFileURL, preferredMode: .auto)
                .pdfSettings
            if paginationMode == .h1StartsNewPage {
                let sectionData = try h1Sections(in: document).map { section in
                    try renderFallbackData(
                        sourceFileURL: sourceFileURL,
                        document: section,
                        style: style,
                        settings: settings
                    )
                }
                return try mergePDFSections(sectionData)
            }
            return try renderFallbackData(
                sourceFileURL: sourceFileURL,
                document: document,
                style: style,
                settings: settings
            )
        }
    }

    private static func renderFallbackData(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        settings: TeachingPDFExportSettings
    ) throws -> Data {
        // 黑白导出的高亮与背景条边框属于成品语义。旧TeachingPrint回退器
        // 不保留行内高亮，因此黑白模式直接走支持同一CSS边框契约的HTML渲染。
        if style.usesMonochromeDecorationBorders {
            let scale = max(0.1, min(1.0, settings.nodeMarkdownScalePercent / 100))
            return try NodeMarkdownScaledPDFExporter.renderData(
                sourceFileURL: sourceFileURL,
                document: document,
                style: style,
                scale: scale
            )
        }
        do {
            return try TeachingPrintExportService.renderNodeMarkdownData(
                document: document,
                documentStyle: style,
                pdfSettings: settings
            )
        } catch {
            let scale = max(0.1, min(1.0, settings.nodeMarkdownScalePercent / 100))
            return try NodeMarkdownScaledPDFExporter.renderData(
                sourceFileURL: sourceFileURL,
                document: document,
                style: style,
                scale: scale
            )
        }
    }

    private static func h1Sections(in document: NodeMarkdownDocument) -> [NodeMarkdownDocument] {
        guard !document.nodes.isEmpty else { return [document] }
        var sections: [NodeMarkdownDocument] = []
        var currentNodes: [NodeMarkdownNode] = []
        for node in document.nodes {
            if node.level == 1, !currentNodes.isEmpty {
                sections.append(NodeMarkdownDocument(nodes: currentNodes))
                currentNodes.removeAll(keepingCapacity: true)
            }
            currentNodes.append(node)
        }
        if !currentNodes.isEmpty {
            sections.append(NodeMarkdownDocument(nodes: currentNodes))
        }
        return sections
    }

    private static func mergePDFSections(_ sections: [Data]) throws -> Data {
        #if canImport(PDFKit)
        let merged = PDFDocument()
        var targetIndex = 0
        for sectionData in sections {
            guard let section = PDFDocument(data: sectionData) else {
                throw NSError(
                    domain: "NodeMarkdownPDFExporter",
                    code: -20,
                    userInfo: [NSLocalizedDescriptionKey: "分H1 PDF合并失败：无法读取分段PDF。"]
                )
            }
            for pageIndex in 0..<section.pageCount {
                guard let page = section.page(at: pageIndex) else { continue }
                merged.insert(page, at: targetIndex)
                targetIndex += 1
            }
        }
        guard let result = merged.dataRepresentation(), !result.isEmpty else {
            throw NSError(
                domain: "NodeMarkdownPDFExporter",
                code: -21,
                userInfo: [NSLocalizedDescriptionKey: "分H1 PDF合并失败：输出为空。"]
            )
        }
        return result
        #else
        throw NSError(
            domain: "NodeMarkdownPDFExporter",
            code: -22,
            userInfo: [NSLocalizedDescriptionKey: "当前平台不支持分H1 PDF合并。"]
        )
        #endif
    }

    private static func exportWithTextKitIfAvailable(
        sourceFileURL: URL,
        destinationURL: URL
    ) throws {
        #if os(macOS)
        try NodeMarkdownTextKitPDFExporter.export(
            sourceFileURL: sourceFileURL,
            destinationURL: destinationURL
        )
        #else
        throw textKitPDFUnavailableError()
        #endif
    }

    private static func renderDataWithTextKitIfAvailable(
        sourceFileURL: URL,
        document: NodeMarkdownDocument,
        style: NodeMarkdownDocumentStyle,
        paginationMode: NodeMarkdownPDFPaginationMode
    ) throws -> Data {
        #if os(macOS)
        return try NodeMarkdownTextKitPDFExporter.renderData(
            sourceFileURL: sourceFileURL,
            document: document,
            style: style,
            paginationMode: paginationMode
        )
        #else
        throw textKitPDFUnavailableError()
        #endif
    }

    private static func textKitPDFUnavailableError() -> NSError {
        NSError(
            domain: "NodeMarkdownPDFExporter",
            code: -10,
            userInfo: [NSLocalizedDescriptionKey: "当前平台不支持 TextKit PDF 导出。"]
        )
    }
}
