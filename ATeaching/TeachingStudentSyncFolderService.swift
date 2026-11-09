import Foundation
import CoreGraphics

enum TeachingStudentSyncFolderService {
    static func ensureStructure(syncRootPath: String, studentName: String, fileManager: FileManager = .default) throws {
        let trimmedPath = syncRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }
        try TeachingSecurityScopedAccess.withWritableAccess(toPath: trimmedPath) { writableURL in
            let rootURL = normalizeSyncRootURL(writableURL)
            try ensureDirectory(rootURL, fileManager: fileManager)

            let lessonPDF = rootURL.appendingPathComponent("1·教案", isDirectory: true)
            let questionPDF = rootURL.appendingPathComponent("2·问题", isDirectory: true)
            let paperPDF = rootURL.appendingPathComponent("3·试卷", isDirectory: true)
            try ensureDirectory(lessonPDF, fileManager: fileManager)
            try ensureDirectory(questionPDF, fileManager: fileManager)
            try ensureDirectory(paperPDF, fileManager: fileManager)
            let manual = "\"1·教案\"内是上课的教案，与上课电子教案完全同步，\"随堂笔记·\(studentName).PDF\"和\"随堂笔记·\(studentName).HTML\"是上课完整笔记，内容是一样的。\"随堂笔记·\(studentName)·笔记按天切分内容相同\"内是按照上课日期切分后的每天的教案，内容上和完整PDF是一样的。\n\"2·问题\"是学生的问题汇集的PDF。\n\"3·试卷\"是学生历史考卷；后两个刚开始是没有内容的。\n"
            try Data(manual.utf8).write(to: rootURL.appendingPathComponent("同步文件夹使用手册.txt"), options: .atomic)

            let questionFile = questionPDF.appendingPathComponent("问题·\(studentName).pdf", isDirectory: false)
            let paperFile = paperPDF.appendingPathComponent("试卷·\(studentName).pdf", isDirectory: false)
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
        // 旧分类目录的授权也应定位到学生根目录，统一生成新版分类。
        if ["1·教案", "2·问题", "3·试卷", "1-教案PDF", "2-问题PDF", "3-卷子PDF"].contains(name) {
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
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "TeachingStudentSyncFolderService", code: 1)
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
