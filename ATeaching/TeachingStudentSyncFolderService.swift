import Foundation

enum TeachingStudentSyncFolderService {
    static func ensureStructure(syncRootPath: String, studentName: String, fileManager: FileManager = .default) throws {
        let trimmedPath = syncRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        try TeachingSecurityScopedAccess.withWritableAccess(toPath: trimmedPath) { writableURL in
            let rootURL = normalizeSyncRootURL(writableURL)
            try ensureDirectory(rootURL, fileManager: fileManager)

            let lessonPDF = rootURL.appendingPathComponent("1-教案PDF", isDirectory: true)
            let questionPDF = rootURL.appendingPathComponent("2-问题PDF", isDirectory: true)
            let paperPDF = rootURL.appendingPathComponent("3-卷子PDF", isDirectory: true)
            try ensureDirectory(lessonPDF, fileManager: fileManager)
            try ensureDirectory(questionPDF, fileManager: fileManager)
            try ensureDirectory(paperPDF, fileManager: fileManager)

            let questionFile = questionPDF.appendingPathComponent("问题-\(studentName).pdf", isDirectory: false)
            let paperFile = paperPDF.appendingPathComponent("试卷-\(studentName).pdf", isDirectory: false)
            if !fileManager.fileExists(atPath: questionFile.path) {
                try minimalPDFData().write(to: questionFile, options: .atomic)
            }
            if !fileManager.fileExists(atPath: paperFile.path) {
                try minimalPDFData().write(to: paperFile, options: .atomic)
            }
        }
    }

    private static func normalizeSyncRootURL(_ url: URL) -> URL {
        let name = url.lastPathComponent
        if name == "1-教案PDF" || name == "2-问题PDF" || name == "3-卷子PDF" {
            return url.deletingLastPathComponent()
        }
        return url
    }

    private static func ensureDirectory(_ url: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { return }
            throw NSError(
                domain: "TeachingStudentSyncFolderService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "路径已存在同名文件，无法创建文件夹：\(url.path)"]
            )
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func minimalPDFData() throws -> Data {
        let content = """
        %PDF-1.3
        1 0 obj
        << /Type /Catalog /Pages 2 0 R >>
        endobj
        2 0 obj
        << /Type /Pages /Kids [3 0 R] /Count 1 >>
        endobj
        3 0 obj
        << /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] >>
        endobj
        xref
        0 4
        0000000000 65535 f
        0000000010 00000 n
        0000000060 00000 n
        0000000117 00000 n
        trailer
        << /Size 4 /Root 1 0 R >>
        startxref
        186
        %%EOF
        """
        guard let data = content.data(using: .utf8) else {
            throw NSError(
                domain: "TeachingStudentSyncFolderService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "空PDF模板生成失败"]
            )
        }
        return data
    }
}
