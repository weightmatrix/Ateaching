// PIPELINE MARKER: NodeMarkdown legacy pipeline (TeachingPrint export service).
import Foundation

enum TeachingPrintExportService {
    struct JobToken: Hashable, Sendable {
        let id: UUID
    }

    struct ExportLogEntry: Sendable {
        let jobID: UUID
        let startedAt: Date
        let finishedAt: Date
        let success: Bool
        let message: String
    }

    actor Coordinator {
        static let shared = Coordinator()
        private var tasks: [UUID: Task<Void, Never>] = [:]
        private(set) var logs: [ExportLogEntry] = []

        func start(
            sourceFileURL: URL,
            destinationURL: URL,
            styleSheet: TeachingPrintStyleSheet,
            retryCount: Int
        ) -> JobToken {
            let token = JobToken(id: UUID())
            let task = Task(priority: .utility) {
                let startedAt = Date()
                var attempts = 0
                var lastError: Error?
                while attempts <= retryCount {
                    attempts += 1
                    if Task.isCancelled { break }
                    do {
                        try await MainActor.run {
                            try TeachingPrintExportService.exportNodeMarkdown(
                                sourceFileURL: sourceFileURL,
                                destinationURL: destinationURL,
                                styleSheet: styleSheet
                            )
                        }
                        appendLog(
                            ExportLogEntry(
                                jobID: token.id,
                                startedAt: startedAt,
                                finishedAt: Date(),
                                success: true,
                                message: "导出成功，尝试次数：\(attempts)"
                            )
                        )
                        clearTask(id: token.id)
                        return
                    } catch {
                        lastError = error
                    }
                }
                appendLog(
                    ExportLogEntry(
                        jobID: token.id,
                        startedAt: startedAt,
                        finishedAt: Date(),
                        success: false,
                        message: lastError?.localizedDescription ?? "导出失败"
                    )
                )
                clearTask(id: token.id)
            }
            tasks[token.id] = task
            return token
        }

        func cancel(_ token: JobToken) {
            tasks[token.id]?.cancel()
            tasks[token.id] = nil
        }

        func latestLogs(limit: Int = 20) -> [ExportLogEntry] {
            Array(logs.suffix(max(1, limit)))
        }

        private func appendLog(_ entry: ExportLogEntry) {
            logs.append(entry)
        }

        private func clearTask(id: UUID) {
            tasks[id] = nil
        }
    }

    private static let exportQueue = DispatchQueue(label: "com.ateaching.node-markdown-print-export.serial", qos: .utility)

    static func submitExport(
        sourceFileURL: URL,
        destinationURL: URL,
        styleSheet: TeachingPrintStyleSheet,
        retryCount: Int = 1
    ) async -> JobToken {
        await Coordinator.shared.start(
            sourceFileURL: sourceFileURL,
            destinationURL: destinationURL,
            styleSheet: styleSheet,
            retryCount: max(0, retryCount)
        )
    }

    static func cancel(_ token: JobToken) async {
        await Coordinator.shared.cancel(token)
    }

    static func latestLogs(limit: Int = 20) async -> [ExportLogEntry] {
        await Coordinator.shared.latestLogs(limit: limit)
    }

    static func exportNodeMarkdownQueued(
        sourceFileURL: URL,
        destinationURL: URL,
        styleSheet: TeachingPrintStyleSheet,
        retryCount: Int = 1
    ) throws {
        let enqueueTime = Date()
        TeachingDebugLogStore.append(
            "排队导出(TeachingPrint)：\(sourceFileURL.lastPathComponent) -> \(destinationURL.lastPathComponent)",
            category: "PDF.Export"
        )
        let attemptsLimit = max(0, retryCount) + 1
        let result: Result<Void, Error> = exportQueue.sync {
            let startTime = Date()
            let wait = startTime.timeIntervalSince(enqueueTime)
            TeachingDebugLogStore.append(
                String(format: "开始导出(TeachingPrint)：%@，排队等待 %.3fs", sourceFileURL.lastPathComponent, wait),
                category: "PDF.Export"
            )

            var attempt = 0
            var lastError: Error?
            while attempt < attemptsLimit {
                attempt += 1
                do {
                    try exportNodeMarkdown(
                        sourceFileURL: sourceFileURL,
                        destinationURL: destinationURL,
                        styleSheet: styleSheet
                    )
                    let cost = Date().timeIntervalSince(startTime)
                    let bytes = (try? Data(contentsOf: destinationURL).count) ?? 0
                    TeachingDebugLogStore.append(
                        String(format: "导出成功(TeachingPrint)：%@，尝试 %d/%d，总耗时 %.3fs，大小 %d bytes", destinationURL.lastPathComponent, attempt, attemptsLimit, cost, bytes),
                        category: "PDF.Export"
                    )
                    return .success(())
                } catch {
                    lastError = error
                    TeachingDebugLogStore.append(
                        "导出失败(TeachingPrint)：\(destinationURL.lastPathComponent)，尝试 \(attempt)/\(attemptsLimit)，错误：\(error.localizedDescription)",
                        category: "PDF.Export"
                    )
                }
            }

            let cost = Date().timeIntervalSince(startTime)
            TeachingDebugLogStore.append(
                String(format: "导出终止(TeachingPrint)：%@，总耗时 %.3fs", destinationURL.lastPathComponent, cost),
                category: "PDF.Export"
            )
            return .failure(lastError ?? NSError(
                domain: "TeachingPrintExportService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "导出失败"]
            ))
        }
        try result.get()
    }

    static func exportNodeMarkdown(
        sourceFileURL: URL,
        destinationURL: URL,
        styleSheet: TeachingPrintStyleSheet
    ) throws {
        let payload = try NodeMarkdownFileManager.read(fileURL: sourceFileURL)
        let document = payload.0
        if shouldUseRichRenderer(document: document) {
            let style = NodeMarkdownSettingsStore.loadDocumentStyle() ?? NodeMarkdownDocumentStyle()
            let settings = effectivePDFSettings()
            let scale = max(0.1, min(1.0, settings.nodeMarkdownScalePercent / 100))
            let data = try NodeMarkdownScaledPDFExporter.renderData(
                sourceFileURL: sourceFileURL,
                document: document,
                style: style,
                baseURL: sourceFileURL.deletingLastPathComponent(),
                scale: scale
            )
            try data.write(to: destinationURL, options: .atomic)
            TeachingDebugLogStore.append(
                "富渲染导出(公式/图片)：\(destinationURL.lastPathComponent)",
                category: "PDF.Export"
            )
            return
        }
        let paragraphs = buildParagraphs(from: document)
        let layout = TeachingPrintLayoutEngine.layout(paragraphs: paragraphs, styleSheet: styleSheet)
        let pdfData = try TeachingPrintRenderEngine.renderPDFData(
            paragraphs: paragraphs,
            layout: layout,
            styleSheet: styleSheet
        )
        try pdfData.write(to: destinationURL, options: .atomic)
    }

    static func renderNodeMarkdownData(
        document: NodeMarkdownDocument,
        documentStyle: NodeMarkdownDocumentStyle,
        pdfSettings: TeachingPDFExportSettings
    ) throws -> Data {
        if shouldUseRichRenderer(document: document) {
            let tempSource = try writeTemporaryNodeMarkdown(document: document)
            let scale = max(0.1, min(1.0, pdfSettings.normalized().nodeMarkdownScalePercent / 100))
            defer { try? FileManager.default.removeItem(at: tempSource) }
            return try NodeMarkdownScaledPDFExporter.renderData(
                sourceFileURL: tempSource,
                document: document,
                style: documentStyle,
                scale: scale
            )
        }
        let styleSheet = makeEffectiveStyleSheet(
            documentStyle: documentStyle,
            pdfSettings: pdfSettings
        )
        let paragraphs = buildParagraphs(from: document)
        let layout = TeachingPrintLayoutEngine.layout(paragraphs: paragraphs, styleSheet: styleSheet)
        return try TeachingPrintRenderEngine.renderPDFData(
            paragraphs: paragraphs,
            layout: layout,
            styleSheet: styleSheet
        )
    }

    static func makeEffectiveStyleSheet(
        documentStyle: NodeMarkdownDocumentStyle,
        pdfSettings: TeachingPDFExportSettings
    ) -> TeachingPrintStyleSheet {
        var sheet = TeachingPrintStyleSheet.make(
            documentStyle: documentStyle,
            pdfSettings: pdfSettings
        )
        if pdfSettings.normalized().paginationStrategy == .singleLongPage {
            sheet.pageSpec.height = 200_000
            sheet.pageSpec.marginBottom = 24
        }
        return sheet
    }

    private static func buildParagraphs(from document: NodeMarkdownDocument) -> [TeachingPrintLayoutParagraph] {
        document.nodes.compactMap { node in
            let trimmed = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let kind: TeachingPrintLayoutParagraph.Kind = {
                switch node.level {
                case 1: return .heading1
                case 2: return .heading2
                case 3: return .heading3
                case 4: return .heading4
                case 5: return .heading5
                case 6: return .heading6
                case 12: return .comment
                default: return .body
                }
            }()
            let stripeEnabled: Bool = {
                switch kind {
                case .heading3:
                    return true
                case .heading4:
                    return true
                case .heading5:
                    return true
                case .body, .heading1, .heading2, .heading6, .comment:
                    return false
                }
            }()
            return TeachingPrintLayoutParagraph(
                text: trimmed,
                kind: kind,
                stripeEnabled: stripeEnabled
            )
        }
    }

    private static func shouldUseRichRenderer(document: NodeMarkdownDocument) -> Bool {
        true
    }

    private static func effectivePDFSettings() -> TeachingPDFExportSettings {
        let dedicated = TeachingPDFSettingsStore.load().normalized()
        let snapshot = (try? TeachingStudentSettingsStore.loadStudentSystemSettings().pdfExportSettings.normalized())
            ?? TeachingPDFExportSettings()
        return dedicated == TeachingPDFExportSettings() ? snapshot : dedicated
    }

    private static func writeTemporaryNodeMarkdown(document: NodeMarkdownDocument) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("node-markdown-export-\(UUID().uuidString).csv", isDirectory: false)
        let meta = NodeMarkdownFileMeta(title: tempURL.deletingPathExtension().lastPathComponent)
        try NodeMarkdownFileManager.write(document: document, meta: meta, to: tempURL)
        return tempURL
    }

}
