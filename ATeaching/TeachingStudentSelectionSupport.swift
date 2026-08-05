import Foundation

// MARK: - 选择项模型 - v1 - 统一系统设置与学生覆盖页的模板/目录选项结构
struct TeachingTemplateRowOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isEmptyContent: Bool
}

struct TeachingSingleListTemplateOption: Identifiable, Hashable {
    let id: String
    let title: String
    let rows: [TeachingTemplateRowOption]
}

struct TeachingChecklistTemplateOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct TeachingSelectionData: Hashable {
    var singleListTemplates: [TeachingSingleListTemplateOption]
    var checklistTemplates: [TeachingChecklistTemplateOption]
    var lessonPlanFolders: [String]

    static let empty = TeachingSelectionData(
        singleListTemplates: [],
        checklistTemplates: [],
        lessonPlanFolders: []
    )
}

// MARK: - 学生设置映射协议 - v1 - 抽象系统设置与学生覆盖设置的公共字段
protocol TeachingStudentMappingSettings {
    var studentInfoTemplateID: String? { get set }
    var studentNameKeyID: String? { get set }
    var classInfoTemplateID: String? { get set }
    var classInfoNameKeyID: String? { get set }
    var classInfoContentKeyID: String? { get set }
    var classInfoTimeKeyID: String? { get set }
    var lessonPlanFolderIDs: [String] { get set }
    var workbookFileID: String? { get set }
    var syncBaseFolderPath: String? { get set }
}

extension TeachingStudentSystemSettings: TeachingStudentMappingSettings {}
extension TeachingStudentProfileSettings: TeachingStudentMappingSettings {}

// MARK: - 学生设置选择支持 - v1 - 统一加载模板选项并清理失效配置
enum TeachingStudentSelectionSupport {
    static func loadSelectionData() throws -> TeachingSelectionData {
        let singleEntries = try ArchiveStorage.loadTemplateEntries(category: .singleList)
        let singleListTemplates = singleEntries.compactMap { entry -> TeachingSingleListTemplateOption? in
            guard let template = try? ArchiveStorage.readSingleListTemplate(fileURL: entry.url) else { return nil }
            let rows = template.0.map {
                TeachingTemplateRowOption(
                    id: $0.id,
                    title: $0.keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.id : $0.keyName,
                    isEmptyContent: $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            let fallbackTitle = entry.url.deletingPathExtension().lastPathComponent
            let title = template.1.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : template.1.title
            return TeachingSingleListTemplateOption(id: template.1.id, title: title, rows: rows)
        }

        let checklistEntries = try ArchiveStorage.loadTemplateEntries(category: .checklist)
        let checklistTemplates = checklistEntries.compactMap { entry -> TeachingChecklistTemplateOption? in
            guard let template = try? ArchiveStorage.readChecklistTemplate(fileURL: entry.url) else { return nil }
            let fallbackTitle = entry.url.deletingPathExtension().lastPathComponent
            let title = template.1.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : template.1.title
            return TeachingChecklistTemplateOption(id: template.1.id, title: title)
        }

        let (_, lessonEntries) = try LessonPlanStorage.loadRootEntries()
        let lessonPlanFolders = lessonEntries.filter(\.isDirectory).map(\.name)

        return TeachingSelectionData(
            singleListTemplates: singleListTemplates,
            checklistTemplates: checklistTemplates,
            lessonPlanFolders: lessonPlanFolders
        )
    }

    static func rowOptions(for templateID: String?, in selectionData: TeachingSelectionData) -> [TeachingTemplateRowOption] {
        guard let templateID else { return [] }
        return selectionData.singleListTemplates.first(where: { $0.id == templateID })?.rows ?? []
    }

    static func classInfoRowOptions(for templateID: String?, in selectionData: TeachingSelectionData) -> [TeachingTemplateRowOption] {
        rowOptions(for: templateID, in: selectionData).filter(\.isEmptyContent)
    }

    static func singleListTemplateTitle(for templateID: String?, in selectionData: TeachingSelectionData) -> String {
        guard let templateID else { return "未设置" }
        return selectionData.singleListTemplates.first(where: { $0.id == templateID })?.title ?? templateID
    }

    static func rowTitle(
        rowID: String?,
        templateID: String?,
        in selectionData: TeachingSelectionData
    ) -> String {
        guard let rowID else { return "未设置" }
        return rowOptions(for: templateID, in: selectionData).first(where: { $0.id == rowID })?.title ?? rowID
    }

    static func checklistTemplateTitle(for templateID: String?, in selectionData: TeachingSelectionData) -> String {
        guard let templateID else { return "未设置" }
        return selectionData.checklistTemplates.first(where: { $0.id == templateID })?.title ?? templateID
    }

    static func sanitizeSelections<T: TeachingStudentMappingSettings>(
        _ settings: inout T,
        using selectionData: TeachingSelectionData
    ) {
        let singleListTemplates = selectionData.singleListTemplates
        let checklistTemplates = selectionData.checklistTemplates
        let lessonPlanFolders = selectionData.lessonPlanFolders

        if let templateID = settings.studentInfoTemplateID,
           !singleListTemplates.contains(where: { $0.id == templateID }) {
            settings.studentInfoTemplateID = nil
            settings.studentNameKeyID = nil
        } else {
            let validIDs = Set(rowOptions(for: settings.studentInfoTemplateID, in: selectionData).map(\.id))
            if let selected = settings.studentNameKeyID, !validIDs.contains(selected) {
                settings.studentNameKeyID = nil
            }
        }

        if let templateID = settings.classInfoTemplateID,
           !singleListTemplates.contains(where: { $0.id == templateID }) {
            settings.classInfoTemplateID = nil
            settings.classInfoNameKeyID = nil
            settings.classInfoContentKeyID = nil
            settings.classInfoTimeKeyID = nil
        } else {
            let validIDs = Set(classInfoRowOptions(for: settings.classInfoTemplateID, in: selectionData).map(\.id))
            if let selected = settings.classInfoNameKeyID, !validIDs.contains(selected) {
                settings.classInfoNameKeyID = nil
            }
            if let selected = settings.classInfoContentKeyID, !validIDs.contains(selected) {
                settings.classInfoContentKeyID = nil
            }
            if let selected = settings.classInfoTimeKeyID, !validIDs.contains(selected) {
                settings.classInfoTimeKeyID = nil
            }
        }

        let validLessonPlanFolders = Set(lessonPlanFolders)
        var sanitizedFolders: [String] = []
        for folder in settings.lessonPlanFolderIDs where validLessonPlanFolders.contains(folder) {
            if !sanitizedFolders.contains(folder) {
                sanitizedFolders.append(folder)
            }
        }
        settings.lessonPlanFolderIDs = sanitizedFolders

        if let workbookID = settings.workbookFileID,
           !checklistTemplates.contains(where: { $0.id == workbookID }) {
            settings.workbookFileID = nil
        }
    }
}
