// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint/WebKit export router).
import Foundation

enum TeachingNodeMarkdownPrintMode: String, Sendable {
    case auto
    case coreText
    case richWebKit
}

enum TeachingNodeMarkdownPipelineGeneration: String, Sendable {
    case legacy
    case platformV1
}

struct TeachingNodeMarkdownPrintJob: Sendable {
    var sourceFileURL: URL
    var destinationURL: URL
    var mode: TeachingNodeMarkdownPrintMode
    var retryCount: Int
}

struct TeachingNodeMarkdownPrintPreparedPayload {
    var document: NodeMarkdownDocument
    var renderingDocument: TeachingRenderingDocument
    var style: NodeMarkdownDocumentStyle
    var pdfSettings: TeachingPDFExportSettings
    var effectiveMode: TeachingNodeMarkdownPrintMode
    var styleSheet: TeachingPrintStyleSheet
    var textKit2LayoutPlan: TeachingTextKit2LayoutPlan
    var formulaLayoutInfos: [TeachingFormulaLayoutInfo]
    var imageLayoutInfos: [TeachingImageLayoutInfo]
    var pipelineGeneration: TeachingNodeMarkdownPipelineGeneration
}

enum TeachingNodeMarkdownPrintPipeline {
    static func prepare(
        sourceFileURL: URL,
        preferredMode: TeachingNodeMarkdownPrintMode = .auto
    ) throws -> TeachingNodeMarkdownPrintPreparedPayload {
        let payload = try NodeMarkdownFileManager.read(fileURL: sourceFileURL)
        let document = payload.0
        let style = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
        let renderingDocument = TeachingRenderingDomainBuilder.build(from: document, style: style)
        let settings = effectivePDFSettings()
        let styleSheet = TeachingPrintExportService.makeEffectiveStyleSheet(
            documentStyle: style,
            pdfSettings: settings
        )
        let textKit2LayoutPlan = TeachingTextKit2PrintLayoutEngine.buildLayoutPlan(
            renderingDocument: renderingDocument,
            styleSheet: styleSheet
        )
        let formulaLayoutInfos = TeachingFormulaRenderService.collectLayoutInfos(from: renderingDocument)
        let imageLayoutInfos = TeachingImageRenderService.collectLayoutInfos(
            from: renderingDocument,
            baseURL: sourceFileURL.deletingLastPathComponent()
        )
        let pipelineGeneration = activePipelineGeneration()
        let mode: TeachingNodeMarkdownPrintMode
        switch preferredMode {
        case .auto:
            mode = requiresRichRendering(renderingDocument: renderingDocument) ? .richWebKit : .coreText
        case .coreText, .richWebKit:
            mode = preferredMode
        }
        return TeachingNodeMarkdownPrintPreparedPayload(
            document: document,
            renderingDocument: renderingDocument,
            style: style,
            pdfSettings: settings,
            effectiveMode: mode,
            styleSheet: styleSheet,
            textKit2LayoutPlan: textKit2LayoutPlan,
            formulaLayoutInfos: formulaLayoutInfos,
            imageLayoutInfos: imageLayoutInfos,
            pipelineGeneration: pipelineGeneration
        )
    }

    static func execute(job: TeachingNodeMarkdownPrintJob) throws {
        let prepared = try prepare(sourceFileURL: job.sourceFileURL, preferredMode: job.mode)
        let unresolvedImageCount = prepared.imageLayoutInfos.filter { $0.resolvedURL == nil }.count
        TeachingDebugLogStore.append(
            "导出规划模式：\(prepared.effectiveMode.rawValue) | generation=\(prepared.pipelineGeneration.rawValue), blocks=\(prepared.renderingDocument.blocks.count), resources=\(prepared.renderingDocument.resources.count), formulas=\(prepared.formulaLayoutInfos.count), images=\(prepared.imageLayoutInfos.count), unresolvedImages=\(unresolvedImageCount), planPages=\(prepared.textKit2LayoutPlan.estimatedPageCount), planLines=\(prepared.textKit2LayoutPlan.measuredLineCount) | \(job.sourceFileURL.lastPathComponent)",
            category: "PDF.Export"
        )
        switch prepared.effectiveMode {
        case .coreText:
            try TeachingPrintExportService.exportNodeMarkdownQueued(
                sourceFileURL: job.sourceFileURL,
                destinationURL: job.destinationURL,
                styleSheet: prepared.styleSheet,
                retryCount: max(0, job.retryCount)
            )
        case .richWebKit:
            let scale = (prepared.pdfSettings.nodeMarkdownScalePercent / 100).clamped(to: 0.1...1.0)
            try NodeMarkdownScaledPDFExporter.export(
                sourceFileURL: job.sourceFileURL,
                destinationURL: job.destinationURL,
                scale: scale
            )
        case .auto:
            break
        }
    }

    private static func requiresRichRendering(renderingDocument: TeachingRenderingDocument) -> Bool {
        true
    }

    private static func effectivePDFSettings() -> TeachingPDFExportSettings {
        let dedicated = TeachingPDFSettingsStore.load().normalized()
        let snapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        return dedicated == TeachingPDFExportSettings() ? snapshot : dedicated
    }

    private static func activePipelineGeneration() -> TeachingNodeMarkdownPipelineGeneration {
        let value = UserDefaults.standard.string(forKey: "teaching.pdf.pipeline.generation")
        return TeachingNodeMarkdownPipelineGeneration(rawValue: value ?? "") ?? .platformV1
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
