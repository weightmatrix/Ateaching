import CryptoKit
import Foundation

enum TeachingCoursePDFExporter {
    private static let exportQueue = DispatchQueue(label: "com.ateaching.pdf-export.serial", qos: .utility)

    static func exportNotebookPDF(sourceFileURL: URL, destinationURL: URL) throws {
        let result: Result<Void, Error> = exportQueue.sync {
            performExport(sourceFileURL: sourceFileURL, destinationURL: destinationURL, enqueueTime: Date())
        }
        try result.get()
    }

    static func writeNotebookPDFData(sourceFileURL: URL, destinationURL: URL, pdfData: Data) throws {
        let result: Result<Void, Error> = exportQueue.sync {
            performPDFDataWrite(sourceFileURL: sourceFileURL, destinationURL: destinationURL, pdfData: pdfData, enqueueTime: Date())
        }
        try result.get()
    }

    static func enqueueNotebookPDFExport(sourceFileURL: URL, destinationURL: URL, writableAccessPath: String? = nil) {
        let enqueueTime = Date()
        TeachingDebugLogStore.append(
            "后台排队导出：\(sourceFileURL.lastPathComponent) -> \(destinationURL.lastPathComponent)",
            category: "PDF.Export"
        )
        exportQueue.async {
            _ = performExportWithAccess(
                sourceFileURL: sourceFileURL,
                destinationURL: destinationURL,
                writableAccessPath: writableAccessPath,
                enqueueTime: enqueueTime
            )
        }
    }

    @discardableResult
    private static func performExportWithAccess(
        sourceFileURL: URL,
        destinationURL: URL,
        writableAccessPath: String?,
        enqueueTime: Date
    ) -> Result<Void, Error> {
        guard let writableAccessPath, !writableAccessPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return performExport(sourceFileURL: sourceFileURL, destinationURL: destinationURL, enqueueTime: enqueueTime)
        }
        do {
            let destinationDirectory = destinationURL.deletingLastPathComponent()
            return try TeachingSecurityScopedAccess.withWritableAccess(toPath: destinationDirectory.path) { writableDirectory in
                let writableDestination = writableDirectory.appendingPathComponent(
                    destinationURL.lastPathComponent,
                    isDirectory: false
                )
                return performExport(
                    sourceFileURL: sourceFileURL,
                    destinationURL: writableDestination,
                    enqueueTime: enqueueTime
                )
            }
        } catch {
            TeachingDebugLogStore.append(
                "后台导出权限失败：\(destinationURL.lastPathComponent)，错误：\(error.localizedDescription)",
                category: "PDF.Export"
            )
            return .failure(error)
        }
    }

    @discardableResult
    private static func performExport(sourceFileURL: URL, destinationURL: URL, enqueueTime: Date) -> Result<Void, Error> {
        let startTime = Date()
        let wait = startTime.timeIntervalSince(enqueueTime)
        TeachingDebugLogStore.append(
            String(format: "开始导出：%@，排队等待 %.3fs", sourceFileURL.lastPathComponent, wait),
            category: "PDF.Export"
        )
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporaryURL = temporaryExportURL(for: destinationURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            try exportNotebookPDFForCurrentPlatform(
                sourceFileURL: sourceFileURL,
                destinationURL: temporaryURL
            )
            let pdfData = try Data(contentsOf: temporaryURL)
            guard !pdfData.isEmpty else {
                throw NSError(domain: "TeachingCoursePDFExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDF导出为空。"])
            }
            try replaceExportedPDFAtomically(sourceURL: temporaryURL, destinationURL: destinationURL)
            try? appendExportSignatureAudit(
                sourceFileURL: sourceFileURL,
                destinationURL: destinationURL,
                pdfData: pdfData
            )
            let cost = Date().timeIntervalSince(startTime)
            TeachingDebugLogStore.append(
                String(format: "导出成功：%@，耗时 %.3fs，大小 %d bytes", destinationURL.lastPathComponent, cost, pdfData.count),
                category: "PDF.Export"
            )
            return .success(())
        } catch {
            let cost = Date().timeIntervalSince(startTime)
            TeachingDebugLogStore.append(
                String(format: "导出失败：%@，耗时 %.3fs，错误：%@", destinationURL.lastPathComponent, cost, error.localizedDescription),
                category: "PDF.Export"
            )
            return .failure(error)
        }
    }

    @discardableResult
    private static func performPDFDataWrite(sourceFileURL: URL, destinationURL: URL, pdfData: Data, enqueueTime: Date) -> Result<Void, Error> {
        let startTime = Date()
        let wait = startTime.timeIntervalSince(enqueueTime)
        TeachingDebugLogStore.append(
            String(format: "开始写入已渲染PDF：%@，排队等待 %.3fs", sourceFileURL.lastPathComponent, wait),
            category: "PDF.Export"
        )
        do {
            guard !pdfData.isEmpty else {
                throw NSError(domain: "TeachingCoursePDFExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDF导出为空。"])
            }
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporaryURL = temporaryExportURL(for: destinationURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try pdfData.write(to: temporaryURL, options: .atomic)
            try replaceExportedPDFAtomically(sourceURL: temporaryURL, destinationURL: destinationURL)
            try? appendExportSignatureAudit(
                sourceFileURL: sourceFileURL,
                destinationURL: destinationURL,
                pdfData: pdfData
            )
            let cost = Date().timeIntervalSince(startTime)
            TeachingDebugLogStore.append(
                String(format: "写入已渲染PDF成功：%@，耗时 %.3fs，大小 %d bytes", destinationURL.lastPathComponent, cost, pdfData.count),
                category: "PDF.Export"
            )
            return .success(())
        } catch {
            let cost = Date().timeIntervalSince(startTime)
            TeachingDebugLogStore.append(
                String(format: "写入已渲染PDF失败：%@，耗时 %.3fs，错误：%@", destinationURL.lastPathComponent, cost, error.localizedDescription),
                category: "PDF.Export"
            )
            return .failure(error)
        }
    }

    private static func temporaryExportURL(for destinationURL: URL) -> URL {
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        let temporaryName = ".\(baseName).\(UUID().uuidString).tmp.pdf"
        return destinationURL.deletingLastPathComponent().appendingPathComponent(temporaryName, isDirectory: false)
    }

    private static func replaceExportedPDFAtomically(sourceURL: URL, destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    private static func exportNotebookPDFForCurrentPlatform(sourceFileURL: URL, destinationURL: URL) throws {
        try NodeMarkdownPDFExporter.export(
            sourceFileURL: sourceFileURL,
            destinationURL: destinationURL
        )
    }

    private struct TeachingCourseExportSignatureRecord: Codable {
        var timestamp: String
        var sourcePath: String
        var destinationPath: String
        var sha256: String
        var bytes: Int
    }

    private static func appendExportSignatureAudit(
        sourceFileURL: URL,
        destinationURL: URL,
        pdfData: Data
    ) throws {
        let digest = SHA256.hash(data: pdfData).map { String(format: "%02x", $0) }.joined()
        let record = TeachingCourseExportSignatureRecord(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sourcePath: sourceFileURL.path,
            destinationPath: destinationURL.path,
            sha256: digest,
            bytes: pdfData.count
        )

        let systemFolder = try ArchiveStorage.ensureWorkspace()
            .appendingPathComponent(ArchiveStorage.systemFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: systemFolder, withIntermediateDirectories: true)
        let logURL = systemFolder.appendingPathComponent("course-export-signatures.log", isDirectory: false)

        let data = try JSONEncoder().encode(record)
        let line = (String(data: data, encoding: .utf8) ?? "{}") + "\n"
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let payload = line.data(using: .utf8) {
                try handle.write(contentsOf: payload)
            }
        } else {
            try line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
