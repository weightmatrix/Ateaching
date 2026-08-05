import Foundation

// MARK: - 学生建档服务 - v1 - 创建学生目录并生成随堂笔记学生信息上课信息骨架文件
enum TeachingStudentProvisioningService {
    struct EffectiveSettings {
        var studentInfoTemplateID: String?
        var studentNameKeyID: String?
        var classInfoTemplateID: String?
        var classInfoNameKeyID: String?
        var classInfoContentKeyID: String?
        var classInfoTimeKeyID: String?
    }

    static func provisionArchiveSkeleton(
        for student: TeachingStudentItem,
        defaultSettings: TeachingStudentSystemSettings,
        profileOverride: TeachingStudentProfileSettings? = nil,
        fileManager: FileManager = .default
    ) throws {
        let effective = merge(defaults: defaultSettings, override: profileOverride)
        let studentFolderURL = try ensureStudentFolder(studentName: student.name, fileManager: fileManager)

        try createNotebookIfNeeded(studentName: student.name, in: studentFolderURL, fileManager: fileManager)
        try createStudentInfoIfNeeded(studentName: student.name, in: studentFolderURL, settings: effective, fileManager: fileManager)
        try createClassInfoIfNeeded(studentName: student.name, in: studentFolderURL, settings: effective, fileManager: fileManager)
    }

    private static func merge(defaults: TeachingStudentSystemSettings, override: TeachingStudentProfileSettings?) -> EffectiveSettings {
        guard let override else {
            return EffectiveSettings(
                studentInfoTemplateID: defaults.studentInfoTemplateID,
                studentNameKeyID: defaults.studentNameKeyID,
                classInfoTemplateID: defaults.classInfoTemplateID,
                classInfoNameKeyID: defaults.classInfoNameKeyID,
                classInfoContentKeyID: defaults.classInfoContentKeyID,
                classInfoTimeKeyID: defaults.classInfoTimeKeyID
            )
        }
        return EffectiveSettings(
            studentInfoTemplateID: override.studentInfoTemplateID ?? defaults.studentInfoTemplateID,
            studentNameKeyID: override.studentNameKeyID ?? defaults.studentNameKeyID,
            classInfoTemplateID: override.classInfoTemplateID ?? defaults.classInfoTemplateID,
            classInfoNameKeyID: override.classInfoNameKeyID ?? defaults.classInfoNameKeyID,
            classInfoContentKeyID: override.classInfoContentKeyID ?? defaults.classInfoContentKeyID,
            classInfoTimeKeyID: override.classInfoTimeKeyID ?? defaults.classInfoTimeKeyID
        )
    }

    private static func ensureStudentFolder(studentName: String, fileManager: FileManager) throws -> URL {
        let archiveRoot = try ArchiveStorage.ensureArchiveRoot(fileManager: fileManager)
        let studentsRoot = archiveRoot.appendingPathComponent("学生", isDirectory: true)
        try fileManager.createDirectory(at: studentsRoot, withIntermediateDirectories: true)
        let studentFolder = studentsRoot.appendingPathComponent(studentName, isDirectory: true)
        try fileManager.createDirectory(at: studentFolder, withIntermediateDirectories: true)
        return studentFolder
    }

    private static func createNotebookIfNeeded(studentName: String, in studentFolder: URL, fileManager: FileManager) throws {
        let fileURL = studentFolder.appendingPathComponent("随堂笔记_\(studentName).CSV", isDirectory: false)
        guard !fileManager.fileExists(atPath: fileURL.path) else { return }
        let now = Date()
        let document = NodeMarkdownDocument(nodes: [
            NodeMarkdownNode(
                level: 1,
                text: "",
                sourceID: "",
                sourceFile: "",
                cache: NodeMarkdownCacheCodec.encode(mtime: now),
                mtimeCache: now
            )
        ])
        let meta = NodeMarkdownFileMeta(
            id: UUID().uuidString,
            title: "随堂笔记_\(studentName)",
            template: "nil",
            createdAt: ISO8601DateFormatter().string(from: now),
            type: "nodemarkdown"
        )
        try NodeMarkdownFileManager.write(document: document, meta: meta, to: fileURL)
    }

    private static func createStudentInfoIfNeeded(
        studentName: String,
        in studentFolder: URL,
        settings: EffectiveSettings,
        fileManager: FileManager
    ) throws {
        let fileURL = studentFolder.appendingPathComponent("学生信息_\(studentName).CSV", isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            try repairSingleListTemplateIfNeeded(
                targetFileURL: fileURL,
                expectedTemplateID: settings.studentInfoTemplateID,
                fill: { row in
                    if let nameKey = settings.studentNameKeyID, row.id == nameKey {
                        row.content = studentName
                    }
                }
            )
            return
        }
        try createSingleListByTemplateOrFallback(
            targetFileURL: fileURL,
            title: "学生信息_\(studentName)",
            templateID: settings.studentInfoTemplateID,
            fill: { row in
                if let nameKey = settings.studentNameKeyID, row.id == nameKey {
                    row.content = studentName
                }
            }
        )
    }

    private static func createClassInfoIfNeeded(
        studentName: String,
        in studentFolder: URL,
        settings: EffectiveSettings,
        fileManager: FileManager
    ) throws {
        let dateText = compactDate()
        let fileURL = studentFolder.appendingPathComponent("上课信息_\(studentName)_\(dateText).CSV", isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            try repairSingleListTemplateIfNeeded(
                targetFileURL: fileURL,
                expectedTemplateID: settings.classInfoTemplateID,
                fill: { row in
                    if let nameKey = settings.classInfoNameKeyID, row.id == nameKey {
                        row.content = studentName
                    }
                    if let timeKey = settings.classInfoTimeKeyID, row.id == timeKey {
                        row.content = dateText
                    }
                    if let contentKey = settings.classInfoContentKeyID, row.id == contentKey, row.content.isEmpty {
                        row.content = ""
                    }
                }
            )
            return
        }
        try createSingleListByTemplateOrFallback(
            targetFileURL: fileURL,
            title: "上课信息_\(studentName)_\(dateText)",
            templateID: settings.classInfoTemplateID,
            fill: { row in
                if let nameKey = settings.classInfoNameKeyID, row.id == nameKey {
                    row.content = studentName
                }
                if let timeKey = settings.classInfoTimeKeyID, row.id == timeKey {
                    row.content = dateText
                }
                if let contentKey = settings.classInfoContentKeyID, row.id == contentKey, row.content.isEmpty {
                    row.content = ""
                }
            }
        )
    }

    private static func createSingleListByTemplateOrFallback(
        targetFileURL: URL,
        title: String,
        templateID: String?,
        fill: (inout SingleListDocumentRow) -> Void
    ) throws {
        var rows: [SingleListDocumentRow] = []
        var resolvedTemplateID = ""

        if let templateID, let templateURL = try resolveSingleListTemplateURL(by: templateID) {
            let template = try ArchiveStorage.readSingleListTemplate(fileURL: templateURL)
            rows = template.0.map { row in
                SingleListDocumentRow(id: row.id, keyName: row.keyName, content: "")
            }
            resolvedTemplateID = templateID
        } else {
            rows = [
                SingleListDocumentRow(id: UUID().uuidString, keyName: "姓名", content: ""),
                SingleListDocumentRow(id: UUID().uuidString, keyName: "内容", content: ""),
                SingleListDocumentRow(id: UUID().uuidString, keyName: "时间", content: "")
            ]
        }

        for index in rows.indices {
            fill(&rows[index])
        }

        let meta = SingleListDocumentMeta(
            id: UUID().uuidString,
            title: title,
            templateID: resolvedTemplateID,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            type: "singlelist"
        )
        try ArchiveStorage.writeSingleListDocument(fileURL: targetFileURL, rows: rows, meta: meta)
    }

    private static func repairSingleListTemplateIfNeeded(
        targetFileURL: URL,
        expectedTemplateID: String?,
        fill: (inout SingleListDocumentRow) -> Void
    ) throws {
        guard let expectedTemplateID, !expectedTemplateID.isEmpty else { return }
        var document = try ArchiveStorage.readSingleListDocument(fileURL: targetFileURL)
        guard document.1.templateID != expectedTemplateID else { return }
        guard let templateURL = try resolveSingleListTemplateURL(by: expectedTemplateID) else { return }

        let templateRows = try ArchiveStorage.readSingleListTemplate(fileURL: templateURL).0
        var existingContentByID: [String: String] = [:]
        for row in document.0 where existingContentByID[row.id] == nil {
            existingContentByID[row.id] = row.content
        }
        var existingContentByName: [String: String] = [:]
        for row in document.0 where existingContentByName[row.keyName] == nil {
            existingContentByName[row.keyName] = row.content
        }

        let repairedRows = templateRows.map { templateRow -> SingleListDocumentRow in
            var row = SingleListDocumentRow(
                id: templateRow.id,
                keyName: templateRow.keyName,
                content: existingContentByID[templateRow.id] ?? existingContentByName[templateRow.keyName] ?? ""
            )
            fill(&row)
            return row
        }

        document.1.templateID = expectedTemplateID
        try ArchiveStorage.writeSingleListDocument(fileURL: targetFileURL, rows: repairedRows, meta: document.1)
    }

    private static func resolveSingleListTemplateURL(by templateID: String) throws -> URL? {
        let entries = try ArchiveStorage.loadTemplateEntries(category: .singleList)
        for entry in entries {
            let meta = try? ArchiveStorage.readSingleListTemplate(fileURL: entry.url).1
            if meta?.id == templateID {
                return entry.url
            }
        }
        return nil
    }

    private static func compactDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: Date())
    }
}
