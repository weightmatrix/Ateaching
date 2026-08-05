import Foundation
import SwiftUI

// MARK: - 档案条目模型 - v1 - 描述档案列表中的文件与文件夹
struct ArchiveEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let metaType: String?

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var fileSortPriority: Int {
        return fileVisualKind.sortPriority
    }

    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        switch fileVisualKind {
        case .template:
            return "square.grid.2x2.fill"
        case .table:
            return "tablecells.fill"
        case .checklist:
            return "checklist.checked"
        case .markdown:
            return "doc.text.fill"
        case .nodeMarkdown:
            return "point.3.connected.trianglepath.dotted"
        case .generic:
            return "doc.fill"
        }
    }

    var iconColor: Color {
        switch fileVisualKind {
        case .template:
            return Color(red: 0.86, green: 0.22, blue: 0.58)
        case .table:
            return Color(red: 0.20, green: 0.67, blue: 0.32)
        case .checklist:
            return Color(red: 0.93, green: 0.75, blue: 0.18)
        case .markdown:
            return Color(red: 0.83, green: 0.65, blue: 0.13)
        case .nodeMarkdown:
            return Color(red: 0.90, green: 0.52, blue: 0.18)
        case .generic:
            return .secondary
        }
    }

    private var fileVisualKind: FileVisualKind {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let lowerName = name.lowercased()

        if path.contains("/系统/模板/") {
            return .template
        }
        if ext == "md" {
            return .markdown
        }
        if ext == "nodemarkdown" || ext == "nmd" || ext == "node.md" {
            return .nodeMarkdown
        }
        if ext == "csv" {
            if let metaType {
                switch metaType.lowercased() {
                case "templatesinglelist", "templatechecklist":
                    return .template
                case "checklist":
                    return .checklist
                case "singlelist", "autosinglelist":
                    return .table
                case "nodemarkdown", "nodesmarkdown", "lessonplan":
                    return .nodeMarkdown
                default:
                    break
                }
            }
            if lowerName.contains("清单") || lowerName.contains("checklist") {
                return .checklist
            }
            return .table
        }
        return .generic
    }

    private enum FileVisualKind {
        case template
        case table
        case checklist
        case markdown
        case nodeMarkdown
        case generic

        var sortPriority: Int {
            switch self {
            case .template:
                return 0
            case .checklist:
                return 1
            case .table:
                return 2
            case .nodeMarkdown:
                return 3
            case .markdown:
                return 4
            case .generic:
                return 5
            }
        }
    }
}

// MARK: - 模板分类枚举 - v1 - 定义单列模板和清单模板目录与类型标记
enum TemplateCategory: String, CaseIterable, Identifiable, Hashable {
    case singleList
    case checklist

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singleList:
            return "单列模板"
        case .checklist:
            return "清单模板"
        }
    }

    var folderName: String {
        switch self {
        case .singleList:
            return "单列表模板"
        case .checklist:
            return "清单模板"
        }
    }

    var metaType: String {
        switch self {
        case .singleList:
            return "templatesinglelist"
        case .checklist:
            return "templatechecklist"
        }
    }
}

// MARK: - 单列文字样式 - v2 - 行名和内容各自拥有完整字体设置
struct SingleListTextStyle: Codable, Hashable {
    var fontName: String
    var fontSize: Double
    var colorHex: String

    static let `default` = SingleListTextStyle(
        fontName: "Apple System Monospaced",
        fontSize: 15,
        colorHex: SingleListRowConfig.adaptiveColorToken
    )

    static let titleDefault = SingleListTextStyle(
        fontName: "Apple System Monospaced",
        fontSize: 34,
        colorHex: SingleListRowConfig.adaptiveColorToken
    )
}

// MARK: - 单列行配置模型 - v2 - 兼容旧版单套字体JSON
struct SingleListRowConfig: Codable, Hashable {
    var keyNameStyle: SingleListTextStyle
    var contentStyle: SingleListTextStyle

    static let adaptiveColorToken = "adaptive-bw"
    static let `default` = SingleListRowConfig(keyNameStyle: .default, contentStyle: .default)

    private enum CodingKeys: String, CodingKey {
        case keyNameStyle
        case contentStyle
        case fontName
        case fontSize
        case colorHex
    }

    init(keyNameStyle: SingleListTextStyle, contentStyle: SingleListTextStyle) {
        self.keyNameStyle = keyNameStyle
        self.contentStyle = contentStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyNameStyle = try container.decodeIfPresent(SingleListTextStyle.self, forKey: .keyNameStyle),
           let contentStyle = try container.decodeIfPresent(SingleListTextStyle.self, forKey: .contentStyle) {
            self.keyNameStyle = keyNameStyle
            self.contentStyle = contentStyle
            return
        }

        let legacyStyle = SingleListTextStyle(
            fontName: try container.decodeIfPresent(String.self, forKey: .fontName) ?? SingleListTextStyle.default.fontName,
            fontSize: try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? SingleListTextStyle.default.fontSize,
            colorHex: try container.decodeIfPresent(String.self, forKey: .colorHex) ?? SingleListTextStyle.default.colorHex
        )
        keyNameStyle = legacyStyle
        contentStyle = legacyStyle
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyNameStyle, forKey: .keyNameStyle)
        try container.encode(contentStyle, forKey: .contentStyle)
    }
}

// MARK: - 单列模板行模型 - v1 - 对应四列UUID/KeyName/Config/Content
struct SingleListTemplateRow: Identifiable, Hashable {
    var id: String
    var keyName: String
    var config: SingleListRowConfig
    var content: String
}

// MARK: - 单列表格行模型 - v1 - 对应UUID/词条名/内容三列业务文件
struct SingleListDocumentRow: Identifiable, Hashable {
    var id: String
    var keyName: String
    var content: String
}

// MARK: - 单列表格元信息模型 - v1 - 映射singlelist文件尾部META信息
struct SingleListDocumentMeta: Hashable {
    var id: String
    var title: String
    var templateID: String
    var createdAt: String
    var type: String
}

// MARK: - 清单模板行模型 - v1 - 对应六列UUID/Task/Level/Status/SourceFile/SourceID
struct ChecklistTemplateRow: Identifiable, Hashable {
    var id: String
    var task: String
    var level: Int
    var status: Int
    var sourceFile: String
    var sourceID: String
}

// MARK: - 任务清单元信息模型 - v1 - 映射checklist文件尾部META信息
struct ChecklistDocumentMeta: Hashable {
    var id: String
    var title: String
    var templateID: String
    var createdAt: String
    var type: String
}

// MARK: - 模板元信息模型 - v1 - 映射META四行元数据
struct TemplateMeta: Hashable {
    var id: String
    var title: String
    var type: String
    var keyCount: Int
    var titleStyle: SingleListTextStyle? = nil
}

// MARK: - 档案存储服务 - v6 - 统一管理档案目录与模板CSV文件读写
enum ArchiveStorage {
    nonisolated static let iCloudContainerIdentifier = "iCloud.Han.ATeaching"
    nonisolated static let archiveFolderName = "档案"
    nonisolated static let settingsFolderName = "设置"
    nonisolated static let systemFolderName = "系统"
    nonisolated static let templateFolderName = "模板"
    nonisolated static let autoFillFolderName = "自动填写"
    nonisolated static let teachingPlanFolderName = "教案"

    // MARK: - 档案新建文件类型 - v1 - 定义档案页新建文件的四种业务类型
    enum ArchiveNewFileType: CaseIterable, Hashable {
        case singleListTable
        case autoFill
        case checklist
        case markdown

        var displayName: String {
            switch self {
            case .singleListTable:
                return "单列表格"
            case .autoFill:
                return "自动填写"
            case .checklist:
                return "任务清单"
            case .markdown:
                return "MD文件"
            }
        }

        var defaultExtension: String {
            switch self {
            case .singleListTable, .autoFill, .checklist:
                return "csv"
            case .markdown:
                return "md"
            }
        }

        var iconName: String {
            switch self {
            case .singleListTable:
                return "tablecells"
            case .autoFill:
                return "wand.and.stars"
            case .checklist:
                return "checklist"
            case .markdown:
                return "doc.text"
            }
        }

        var initialContent: String {
            switch self {
            case .singleListTable:
                return "UUID,KeyName,Config,Content\n"
            case .autoFill:
                return "Key,Value,Rule\n"
            case .checklist:
                return "UUID,Task,Level,Status,SourceFile,SourceID\n"
            case .markdown:
                return "# 标题\n\n"
            }
        }
    }

    // MARK: - 存储错误定义 - v2 - 描述目录和模板解析创建过程中的错误
    enum StorageError: LocalizedError {
        case iCloudUnavailable
        case invalidName
        case invalidTemplateFormat

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return "iCloud 不可用，请检查 iCloud Drive 和 App 的 iCloud 权限。"
            case .invalidName:
                return "名称无效。"
            case .invalidTemplateFormat:
                return "模板格式无效。"
            }
        }
    }

    nonisolated static func ensureWorkspace(fileManager: FileManager = .default) throws -> URL {
        guard let iCloudContainer = fileManager.url(forUbiquityContainerIdentifier: iCloudContainerIdentifier) else {
            throw StorageError.iCloudUnavailable
        }

        let documentsRootURL = iCloudContainer.appendingPathComponent("Documents", isDirectory: true)

        try fileManager.createDirectory(at: documentsRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documentsRootURL.appendingPathComponent(archiveFolderName, isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documentsRootURL.appendingPathComponent(settingsFolderName, isDirectory: true), withIntermediateDirectories: true)

        let systemFolderURL = documentsRootURL.appendingPathComponent(systemFolderName, isDirectory: true)
        let templateFolderURL = systemFolderURL.appendingPathComponent(templateFolderName, isDirectory: true)

        try fileManager.createDirectory(at: systemFolderURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: systemFolderURL.appendingPathComponent(teachingPlanFolderName, isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: systemFolderURL.appendingPathComponent(autoFillFolderName, isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateFolderURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateFolderURL.appendingPathComponent("单列表模板", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateFolderURL.appendingPathComponent("清单模板", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: templateFolderURL.appendingPathComponent("教案模板", isDirectory: true), withIntermediateDirectories: true)

        return documentsRootURL
    }

    static func ensureArchiveRoot(fileManager: FileManager = .default) throws -> URL {
        let documentsRootURL = try ensureWorkspace(fileManager: fileManager)
        return documentsRootURL.appendingPathComponent(archiveFolderName, isDirectory: true)
    }

    static func loadArchiveEntries(fileManager: FileManager = .default) throws -> (URL, [ArchiveEntry]) {
        let archiveRootURL = try ensureArchiveRoot(fileManager: fileManager)
        let entries = try loadEntries(in: archiveRootURL, fileManager: fileManager)
        return (archiveRootURL, entries)
    }

    static func loadEntries(in directoryURL: URL, fileManager: FileManager = .default) throws -> [ArchiveEntry] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .map { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = values?.isDirectory == true
                let metaType: String?
                if isDirectory || url.pathExtension.lowercased() != "csv" {
                    metaType = nil
                } else {
                    metaType = readMetaType(fileURL: url)
                }
                return ArchiveEntry(url: url, isDirectory: isDirectory, metaType: metaType)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory {
                    return $0.isDirectory && !$1.isDirectory
                }
                if $0.fileSortPriority != $1.fileSortPriority {
                    return $0.fileSortPriority < $1.fileSortPriority
                }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }

    static func createFolder(named folderName: String, in directoryURL: URL, fileManager: FileManager = .default) throws {
        let validatedName = try validateName(folderName)
        let folderURL = directoryURL.appendingPathComponent(validatedName, isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    static func createFile(
        named fileName: String,
        type: ArchiveNewFileType,
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let validatedName = try validateName(fileName)
        let finalName: String
        if validatedName.contains(".") {
            finalName = validatedName
        } else {
            finalName = "\(validatedName).\(type.defaultExtension)"
        }

        let fileURL = directoryURL.appendingPathComponent(finalName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileWriteFileExists)
        }

        try type.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func createSingleListDocument(
        named fileName: String,
        templateFileURL: URL,
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let validatedName = try validateName(fileName)
        let finalName = validatedName.lowercased().hasSuffix(".csv") ? validatedName : "\(validatedName).csv"
        let fileURL = directoryURL.appendingPathComponent(finalName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileWriteFileExists)
        }

        let templateData = try readSingleListTemplate(fileURL: templateFileURL)
        let rows = templateData.0.map { row in
            SingleListDocumentRow(id: row.id, keyName: row.keyName, content: "")
        }
        let formatter = ISO8601DateFormatter()
        let meta = SingleListDocumentMeta(
            id: UUID().uuidString,
            title: (finalName as NSString).deletingPathExtension,
            templateID: templateData.1.id,
            createdAt: formatter.string(from: Date()),
            type: "singlelist"
        )
        try writeSingleListDocument(fileURL: fileURL, rows: rows, meta: meta)
        return fileURL
    }

    static func createAutoFillDocument(
        named fileName: String,
        templateFileURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let validatedName = try validateName(fileName)
        let finalName = validatedName.lowercased().hasSuffix(".csv") ? validatedName : "\(validatedName).csv"
        let directoryURL = try autoFillDirectoryURL(fileManager: fileManager)
        let fileURL = directoryURL.appendingPathComponent(finalName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileWriteFileExists)
        }

        let templateData = try readSingleListTemplate(fileURL: templateFileURL)
        let rows = templateData.0.map { row in
            SingleListDocumentRow(id: row.id, keyName: row.keyName, content: "")
        }
        let formatter = ISO8601DateFormatter()
        let meta = SingleListDocumentMeta(
            id: UUID().uuidString,
            title: (finalName as NSString).deletingPathExtension,
            templateID: templateData.1.id,
            createdAt: formatter.string(from: Date()),
            type: "autosinglelist"
        )
        try writeAutoFillDocument(fileURL: fileURL, rows: rows, meta: meta)
        return fileURL
    }

    static func createChecklistDocument(
        named fileName: String,
        templateFileURL: URL,
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let validatedName = try validateName(fileName)
        let finalName = validatedName.lowercased().hasSuffix(".csv") ? validatedName : "\(validatedName).csv"
        let fileURL = directoryURL.appendingPathComponent(finalName, isDirectory: false)
        if fileManager.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileWriteFileExists)
        }

        let templateData = try readChecklistTemplate(fileURL: templateFileURL)
        let rows = templateData.0.map { row in
            ChecklistTemplateRow(
                id: row.id,
                task: row.task,
                level: row.level,
                status: 0,
                sourceFile: "",
                sourceID: ""
            )
        }
        let formatter = ISO8601DateFormatter()
        let meta = ChecklistDocumentMeta(
            id: UUID().uuidString,
            title: (finalName as NSString).deletingPathExtension,
            templateID: templateData.1.id,
            createdAt: formatter.string(from: Date()),
            type: "checklist"
        )
        try writeChecklistDocument(fileURL: fileURL, rows: rows, meta: meta)
        return fileURL
    }

    @MainActor
    static func renameItem(at itemURL: URL, to newName: String, fileManager: FileManager = .default) throws {
        let validatedName = try validateName(newName)
        if TeachingLessonRenameService.handles(itemURL: itemURL, fileManager: fileManager) {
            try TeachingLessonRenameService.rename(itemURL: itemURL, to: validatedName, fileManager: fileManager)
            return
        }
        let targetURL = itemURL.deletingLastPathComponent().appendingPathComponent(validatedName, isDirectory: false)
        try fileManager.moveItem(at: itemURL, to: targetURL)
    }

    static func moveItem(at itemURL: URL, to targetDirectoryURL: URL, fileManager: FileManager = .default) throws -> URL {
        try fileManager.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        let preferredURL = targetDirectoryURL.appendingPathComponent(itemURL.lastPathComponent, isDirectory: false)
        let destinationURL = uniqueArchiveDestinationURL(preferredURL: preferredURL, fileManager: fileManager)
        guard destinationURL.standardizedFileURL.path != itemURL.standardizedFileURL.path else {
            return itemURL
        }
        try fileManager.moveItem(at: itemURL, to: destinationURL)
        return destinationURL
    }

    static func moveItems(at itemURLs: [URL], to targetDirectoryURL: URL, fileManager: FileManager = .default) throws -> [URL] {
        var moved: [URL] = []
        for itemURL in itemURLs {
            moved.append(try moveItem(at: itemURL, to: targetDirectoryURL, fileManager: fileManager))
        }
        return moved
    }

    static func deleteItem(at itemURL: URL, fileManager: FileManager = .default) throws {
        try fileManager.removeItem(at: itemURL)
    }

    private static func uniqueArchiveDestinationURL(preferredURL: URL, fileManager: FileManager) -> URL {
        guard fileManager.fileExists(atPath: preferredURL.path) else { return preferredURL }
        let folderURL = preferredURL.deletingLastPathComponent()
        let ext = preferredURL.pathExtension
        let baseName = preferredURL.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidateName = ext.isEmpty ? "\(baseName)-\(index)" : "\(baseName)-\(index).\(ext)"
            let candidateURL = folderURL.appendingPathComponent(candidateName, isDirectory: false)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            index += 1
        }
    }

    static func templateDirectoryURL(for category: TemplateCategory, fileManager: FileManager = .default) throws -> URL {
        let root = try ensureWorkspace(fileManager: fileManager)
        let url = root
            .appendingPathComponent(systemFolderName, isDirectory: true)
            .appendingPathComponent(templateFolderName, isDirectory: true)
            .appendingPathComponent(category.folderName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadTemplateEntries(category: TemplateCategory, fileManager: FileManager = .default) throws -> [ArchiveEntry] {
        let folder = try templateDirectoryURL(for: category, fileManager: fileManager)
        return try loadEntries(in: folder, fileManager: fileManager)
            .filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "csv" }
    }

    static func autoFillDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        let root = try ensureWorkspace(fileManager: fileManager)
        let url = root
            .appendingPathComponent(systemFolderName, isDirectory: true)
            .appendingPathComponent(autoFillFolderName, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func loadAutoFillEntries(fileManager: FileManager = .default) throws -> [ArchiveEntry] {
        let folder = try autoFillDirectoryURL(fileManager: fileManager)
        return try loadEntries(in: folder, fileManager: fileManager)
            .filter { !$0.isDirectory && $0.url.pathExtension.lowercased() == "csv" }
    }

    static func createTemplate(
        named name: String,
        category: TemplateCategory,
        checklistMetaTypeOverride: String? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let validatedName = try validateName(name)
        let folder = try templateDirectoryURL(for: category, fileManager: fileManager)
        let fileName = validatedName.lowercased().hasSuffix(".csv") ? validatedName : "\(validatedName).csv"
        let url = folder.appendingPathComponent(fileName, isDirectory: false)
        let title = (fileName as NSString).deletingPathExtension
        let checklistMetaType = checklistMetaTypeOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let metaType: String
        switch category {
        case .singleList:
            metaType = category.metaType
        case .checklist:
            metaType = checklistMetaType?.isEmpty == false ? checklistMetaType ?? category.metaType : category.metaType
        }
        let meta = TemplateMeta(id: UUID().uuidString, title: title, type: metaType, keyCount: 1)

        switch category {
        case .singleList:
            let rows = [SingleListTemplateRow(id: UUID().uuidString, keyName: "示例项", config: .default, content: "")]
            try writeSingleListTemplate(fileURL: url, rows: rows, meta: meta)
        case .checklist:
            let rows = [ChecklistTemplateRow(id: UUID().uuidString, task: "示例任务", level: 1, status: 0, sourceFile: "", sourceID: "")]
            try writeChecklistTemplate(fileURL: url, rows: rows, meta: meta)
        }
        return url
    }

    static func readSingleListTemplate(fileURL: URL) throws -> ([SingleListTemplateRow], TemplateMeta) {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed = parseTemplateCSV(text)
        guard parsed.header.count >= 4 else { throw StorageError.invalidTemplateFormat }

        let rows: [SingleListTemplateRow] = parsed.records.compactMap { record in
            guard record.count >= 4 else { return nil }
            return SingleListTemplateRow(
                id: nonEmpty(record[0]) ?? UUID().uuidString,
                keyName: record[1],
                config: decodeSingleListConfig(record[2]),
                content: record[3]
            )
        }
        return (rows, parsed.meta)
    }

    static func writeSingleListTemplate(fileURL: URL, rows: [SingleListTemplateRow], meta: TemplateMeta) throws {
        let header = ["UUID", "KeyName", "Config", "Content"]
        let records = rows.map { row in
            [row.id, row.keyName, encodeSingleListConfig(row.config), row.content]
        }
        let finalMeta = TemplateMeta(
            id: meta.id,
            title: meta.title,
            type: TemplateCategory.singleList.metaType,
            keyCount: rows.filter { !$0.keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            titleStyle: meta.titleStyle
        )
        let csv = renderTemplateCSV(header: header, records: records, meta: finalMeta)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func readSingleListDocument(fileURL: URL) throws -> ([SingleListDocumentRow], SingleListDocumentMeta) {
        try readSingleListLikeDocument(fileURL: fileURL, defaultType: "singlelist")
    }

    static func readAutoFillDocument(fileURL: URL) throws -> ([SingleListDocumentRow], SingleListDocumentMeta) {
        try readSingleListLikeDocument(fileURL: fileURL, defaultType: "autosinglelist")
    }

    private static func readSingleListLikeDocument(
        fileURL: URL,
        defaultType: String
    ) throws -> ([SingleListDocumentRow], SingleListDocumentMeta) {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let parsedRows = parseCSVRows(text)
        guard !parsedRows.isEmpty else {
            throw StorageError.invalidTemplateFormat
        }

        var records: [[String]] = []
        var metaMap: [String: String] = [:]
        for row in parsedRows.dropFirst() {
            if row.isEmpty || row.allSatisfy({ $0.isEmpty }) {
                continue
            }
            if let first = row.first, first.hasPrefix("[META_"), row.count > 1 {
                metaMap[first] = row[1]
            } else {
                records.append(row)
            }
        }

        let rows: [SingleListDocumentRow] = records.compactMap { record in
            guard record.count >= 3 else { return nil }
            return SingleListDocumentRow(
                id: nonEmpty(record[0]) ?? UUID().uuidString,
                keyName: record[1],
                content: record[2]
            )
        }

        let meta = SingleListDocumentMeta(
            id: metaMap["[META_ID]"] ?? UUID().uuidString,
            title: metaMap["[META_TITLE]"] ?? fileURL.deletingPathExtension().lastPathComponent,
            templateID: metaMap["[META_TEMPLATE]"] ?? "",
            createdAt: metaMap["[META_CREATED]"] ?? "",
            type: metaMap["[META_TYPE]"] ?? defaultType
        )
        return (rows, meta)
    }

    static func writeSingleListDocument(
        fileURL: URL,
        rows: [SingleListDocumentRow],
        meta: SingleListDocumentMeta
    ) throws {
        try writeSingleListLikeDocument(fileURL: fileURL, rows: rows, meta: meta, forcedType: "singlelist")
    }

    static func writeAutoFillDocument(
        fileURL: URL,
        rows: [SingleListDocumentRow],
        meta: SingleListDocumentMeta
    ) throws {
        try writeSingleListLikeDocument(fileURL: fileURL, rows: rows, meta: meta, forcedType: "autosinglelist")
    }

    private static func writeSingleListLikeDocument(
        fileURL: URL,
        rows: [SingleListDocumentRow],
        meta: SingleListDocumentMeta,
        forcedType: String
    ) throws {
        let header = ["UUID", "词条名", "内容"]
        let records = rows.map { row in [row.id, row.keyName, row.content] }

        var lines: [String] = []
        lines.append(renderCSVRow(header))
        lines.append(contentsOf: records.map { renderCSVRow($0) })
        lines.append("")
        lines.append(renderCSVRow(["[META_ID]", meta.id]))
        lines.append(renderCSVRow(["[META_TITLE]", meta.title]))
        lines.append(renderCSVRow(["[META_TEMPLATE]", meta.templateID]))
        lines.append(renderCSVRow(["[META_CREATED]", meta.createdAt]))
        lines.append(renderCSVRow(["[META_TYPE]", forcedType]))
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func readChecklistTemplate(fileURL: URL) throws -> ([ChecklistTemplateRow], TemplateMeta) {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let parsed = parseTemplateCSV(text)
        guard parsed.header.count >= 6 else { throw StorageError.invalidTemplateFormat }

        let rows: [ChecklistTemplateRow] = parsed.records.compactMap { record in
            guard record.count >= 6 else { return nil }
            return ChecklistTemplateRow(
                id: nonEmpty(record[0]) ?? UUID().uuidString,
                task: record[1],
                level: min(6, max(1, Int(record[2]) ?? 1)),
                status: (Int(record[3]) ?? 0) == 0 ? 0 : 1,
                sourceFile: record[4],
                sourceID: record[5]
            )
        }
        return (rows, parsed.meta)
    }

    static func readChecklistDocument(fileURL: URL) throws -> ([ChecklistTemplateRow], ChecklistDocumentMeta) {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let parsedRows = parseCSVRows(text)
        guard !parsedRows.isEmpty else {
            throw StorageError.invalidTemplateFormat
        }

        var records: [[String]] = []
        var metaMap: [String: String] = [:]
        for row in parsedRows.dropFirst() {
            if row.isEmpty || row.allSatisfy({ $0.isEmpty }) {
                continue
            }
            if let first = row.first, first.hasPrefix("[META_"), row.count > 1 {
                metaMap[first] = row[1]
            } else {
                records.append(row)
            }
        }

        let rows: [ChecklistTemplateRow] = records.compactMap { record in
            guard record.count >= 6 else { return nil }
            return ChecklistTemplateRow(
                id: nonEmpty(record[0]) ?? UUID().uuidString,
                task: record[1],
                level: min(6, max(1, Int(record[2]) ?? 1)),
                status: (Int(record[3]) ?? 0) == 0 ? 0 : 1,
                sourceFile: record[4],
                sourceID: record[5]
            )
        }

        let meta = ChecklistDocumentMeta(
            id: metaMap["[META_ID]"] ?? UUID().uuidString,
            title: metaMap["[META_TITLE]"] ?? fileURL.deletingPathExtension().lastPathComponent,
            templateID: metaMap["[META_TEMPLATE]"] ?? "",
            createdAt: metaMap["[META_CREATED]"] ?? "",
            type: metaMap["[META_TYPE]"] ?? "checklist"
        )
        return (rows, meta)
    }

    static func writeChecklistDocument(
        fileURL: URL,
        rows: [ChecklistTemplateRow],
        meta: ChecklistDocumentMeta
    ) throws {
        let header = ["UUID", "Task", "Level", "Status", "SourceFile", "SourceID"]
        let records = rows.map { row in
            [
                row.id,
                row.task,
                String(min(6, max(1, row.level))),
                row.status == 0 ? "0" : "1",
                row.sourceFile,
                row.sourceID
            ]
        }

        var lines: [String] = []
        lines.append(renderCSVRow(header))
        lines.append(contentsOf: records.map { renderCSVRow($0) })
        lines.append("")
        lines.append(renderCSVRow(["[META_ID]", meta.id]))
        lines.append(renderCSVRow(["[META_TITLE]", meta.title]))
        lines.append(renderCSVRow(["[META_TEMPLATE]", meta.templateID]))
        lines.append(renderCSVRow(["[META_CREATED]", meta.createdAt]))
        let metaType = meta.type.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(renderCSVRow(["[META_TYPE]", metaType.isEmpty ? "checklist" : metaType]))
        try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func readMetaType(fileURL: URL) -> String? {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        for row in parseCSVRows(text) {
            if row.count > 1, row[0] == "[META_TYPE]" {
                return row[1]
            }
        }
        return nil
    }

    static func singleListTemplateStyleMap(templateID: String) -> [String: SingleListRowConfig] {
        guard !templateID.isEmpty else { return [:] }
        guard let entries = try? loadTemplateEntries(category: .singleList) else { return [:] }
        for entry in entries {
            guard let (rows, meta) = try? readSingleListTemplate(fileURL: entry.url), meta.id == templateID else {
                continue
            }
            var map: [String: SingleListRowConfig] = [:]
            for row in rows {
                map[row.id] = row.config
            }
            return map
        }
        return [:]
    }

    static func singleListTemplateTitleStyle(templateID: String) -> SingleListTextStyle {
        guard !templateID.isEmpty,
              let entries = try? loadTemplateEntries(category: .singleList) else {
            return .titleDefault
        }
        for entry in entries {
            guard let (_, meta) = try? readSingleListTemplate(fileURL: entry.url), meta.id == templateID else {
                continue
            }
            return meta.titleStyle ?? .titleDefault
        }
        return .titleDefault
    }

    static func writeChecklistTemplate(fileURL: URL, rows: [ChecklistTemplateRow], meta: TemplateMeta) throws {
        let header = ["UUID", "Task", "Level", "Status", "SourceFile", "SourceID"]
        let records = rows.map { row in
            [row.id, row.task, String(min(6, max(1, row.level))), row.status == 0 ? "0" : "1", row.sourceFile, row.sourceID]
        }
        let resolvedMetaType: String = {
            let trimmed = meta.type.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? TemplateCategory.checklist.metaType : trimmed
        }()
        let finalMeta = TemplateMeta(
            id: meta.id,
            title: meta.title,
            type: resolvedMetaType,
            keyCount: rows.filter { !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        )
        let csv = renderTemplateCSV(header: header, records: records, meta: finalMeta)
        try csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func parseTemplateCSV(_ text: String) -> (header: [String], records: [[String]], meta: TemplateMeta) {
        let rows = parseCSVRows(text)
        guard !rows.isEmpty else {
            return ([], [], TemplateMeta(id: UUID().uuidString, title: "未命名模板", type: "", keyCount: 0))
        }

        let header = rows[0]
        var records: [[String]] = []
        var metadata: [String: String] = [:]

        for row in rows.dropFirst() {
            if row.isEmpty || row.allSatisfy({ $0.isEmpty }) {
                continue
            }
            if let first = row.first, first.hasPrefix("[META_") {
                if row.count > 1 {
                    metadata[first] = row[1]
                }
            } else {
                records.append(row)
            }
        }

        let meta = TemplateMeta(
            id: metadata["[META_ID]"] ?? UUID().uuidString,
            title: metadata["[META_TITLE]"] ?? "未命名模板",
            type: metadata["[META_TYPE]"] ?? "",
            keyCount: Int(metadata["[META_KEY_COUNT]"] ?? "") ?? records.count,
            titleStyle: decodeSingleListTextStyle(metadata["[META_TITLE_CONFIG]"])
        )
        return (header, records, meta)
    }

    private static func renderTemplateCSV(header: [String], records: [[String]], meta: TemplateMeta) -> String {
        var lines: [String] = []
        lines.append(renderCSVRow(header))
        lines.append(contentsOf: records.map { renderCSVRow($0) })
        lines.append("")
        lines.append(renderCSVRow(["[META_ID]", meta.id]))
        lines.append(renderCSVRow(["[META_TITLE]", meta.title]))
        lines.append(renderCSVRow(["[META_TYPE]", meta.type]))
        lines.append(renderCSVRow(["[META_KEY_COUNT]", String(meta.keyCount)]))
        if let titleStyle = meta.titleStyle {
            lines.append(renderCSVRow(["[META_TITLE_CONFIG]", encodeSingleListTextStyle(titleStyle)]))
        }
        return lines.joined(separator: "\n")
    }

    /// 供需要保持现有CSV协议的系统级迁移使用，避免迁移器另写一套引号和换行解析。
    @MainActor
    static func parseCSVRowsForMigration(_ text: String) -> [[String]] {
        parseCSVRows(text)
    }

    /// 使用和档案存储完全相同的转义规则重新输出迁移后的CSV。
    @MainActor
    static func renderCSVRowsForMigration(_ rows: [[String]]) -> String {
        rows.map(renderCSVRow).joined(separator: "\n")
    }

    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0

        func appendField() {
            currentRow.append(currentField)
            currentField = ""
        }

        func appendRow() {
            appendField()
            rows.append(currentRow)
            currentRow = []
        }

        while index < characters.count {
            let char = characters[index]
            if inQuotes {
                if char == "\"" {
                    let next = index + 1
                    if next < characters.count, characters[next] == "\"" {
                        currentField.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    appendField()
                case "\n":
                    appendRow()
                case "\r":
                    break
                default:
                    currentField.append(char)
                }
            }
            index += 1
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            appendRow()
        }

        return rows
    }

    private static func renderCSVRow(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }.joined(separator: ",")
    }

    private static func decodeSingleListConfig(_ rawValue: String) -> SingleListRowConfig {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(SingleListRowConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    private static func encodeSingleListConfig(_ value: SingleListRowConfig) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func decodeSingleListTextStyle(_ rawValue: String?) -> SingleListTextStyle? {
        guard let rawValue,
              let data = rawValue.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SingleListTextStyle.self, from: data)
    }

    private static func encodeSingleListTextStyle(_ value: SingleListTextStyle) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else {
            throw StorageError.invalidName
        }
        return trimmed
    }
}
