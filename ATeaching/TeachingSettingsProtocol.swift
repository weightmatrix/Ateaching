import Foundation

// MARK: - 授课设置快照 - v3 - 统一承载授课配置并加入功能开关与学生级覆盖
struct TeachingSettingsSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var savedAt: String
    var students: [TeachingStudentItem]
    var studentSystem: TeachingStudentSystemSettings
    var lessonPlanSystem: TeachingLessonPlanSystemSettings
    var featureFlags: TeachingFeatureFlags
    var studentProfiles: [String: TeachingStudentProfileSettings]

    static func initial(students: [TeachingStudentItem]) -> TeachingSettingsSnapshot {
        TeachingSettingsSnapshot(
            schemaVersion: currentSchemaVersion,
            savedAt: ISO8601DateFormatter().string(from: Date()),
            students: students,
            studentSystem: .init(),
            lessonPlanSystem: .init(),
            featureFlags: .init(),
            studentProfiles: [:]
        )
    }

    init(
        schemaVersion: Int,
        savedAt: String,
        students: [TeachingStudentItem],
        studentSystem: TeachingStudentSystemSettings,
        lessonPlanSystem: TeachingLessonPlanSystemSettings,
        featureFlags: TeachingFeatureFlags = .init(),
        studentProfiles: [String: TeachingStudentProfileSettings] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.students = students
        self.studentSystem = studentSystem
        self.lessonPlanSystem = lessonPlanSystem
        self.featureFlags = featureFlags
        self.studentProfiles = studentProfiles
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case savedAt
        case students
        case studentSystem
        case lessonPlanSystem
        case featureFlags
        case studentProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        savedAt = try container.decode(String.self, forKey: .savedAt)
        students = try container.decode([TeachingStudentItem].self, forKey: .students)
        studentSystem = try container.decode(TeachingStudentSystemSettings.self, forKey: .studentSystem)
        lessonPlanSystem = try container.decode(TeachingLessonPlanSystemSettings.self, forKey: .lessonPlanSystem)
        featureFlags = try container.decodeIfPresent(TeachingFeatureFlags.self, forKey: .featureFlags) ?? .init()
        studentProfiles = try container.decodeIfPresent([String: TeachingStudentProfileSettings].self, forKey: .studentProfiles) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encode(students, forKey: .students)
        try container.encode(studentSystem, forKey: .studentSystem)
        try container.encode(lessonPlanSystem, forKey: .lessonPlanSystem)
        try container.encode(featureFlags, forKey: .featureFlags)
        try container.encode(studentProfiles, forKey: .studentProfiles)
    }

    func normalized() -> TeachingSettingsSnapshot {
        var next = self
        next.schemaVersion = max(TeachingSettingsSnapshot.currentSchemaVersion, schemaVersion)
        next.savedAt = savedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ISO8601DateFormatter().string(from: Date())
            : savedAt
        next.students = students.map { student in
            var value = student
            value.name = student.name.trimmingCharacters(in: .whitespacesAndNewlines)
            value.iconName = student.iconName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "person.fill" : student.iconName
            return value
        }
        next.studentSystem = studentSystem.normalized()
        next.lessonPlanSystem = lessonPlanSystem.normalized()
        next.studentProfiles = studentProfiles.mapValues { $0.normalized() }
        let validIDs = Set(next.students.map { $0.id.uuidString })
        next.studentProfiles = next.studentProfiles.filter { validIDs.contains($0.key) }
        return next
    }

    func validationIssues() -> [String] {
        var issues: [String] = []
        let duplicateStudentIDs = Dictionary(grouping: students, by: { $0.id }).filter { $0.value.count > 1 }.keys
        if !duplicateStudentIDs.isEmpty {
            issues.append("students contains duplicate ids")
        }
        if students.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("students contains empty name")
        }
        issues.append(contentsOf: studentSystem.validationIssues(prefix: "studentSystem"))
        issues.append(contentsOf: lessonPlanSystem.validationIssues(prefix: "lessonPlanSystem"))
        for (studentID, profile) in studentProfiles {
            issues.append(contentsOf: profile.validationIssues(prefix: "studentProfiles.\(studentID)"))
        }
        return issues
    }
}

// MARK: - 功能开关 - v1 - 管理关键路径能力灰度与验收开关
struct TeachingFeatureFlags: Codable, Equatable {
    var enableStudentProvisioning: Bool
    var enableStudentProfileOverride: Bool
    var persistDebugLogs: Bool

    init(
        enableStudentProvisioning: Bool = true,
        enableStudentProfileOverride: Bool = true,
        persistDebugLogs: Bool = false
    ) {
        self.enableStudentProvisioning = enableStudentProvisioning
        self.enableStudentProfileOverride = enableStudentProfileOverride
        self.persistDebugLogs = persistDebugLogs
    }

    private enum CodingKeys: String, CodingKey {
        case enableStudentProvisioning
        case enableStudentProfileOverride
        case persistDebugLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableStudentProvisioning = try container.decodeIfPresent(Bool.self, forKey: .enableStudentProvisioning) ?? true
        enableStudentProfileOverride = try container.decodeIfPresent(Bool.self, forKey: .enableStudentProfileOverride) ?? true
        persistDebugLogs = try container.decodeIfPresent(Bool.self, forKey: .persistDebugLogs) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableStudentProvisioning, forKey: .enableStudentProvisioning)
        try container.encode(enableStudentProfileOverride, forKey: .enableStudentProfileOverride)
        try container.encode(persistDebugLogs, forKey: .persistDebugLogs)
    }
}

// MARK: - PDF导出设置 - v1 - 统一纸张尺寸、页边距和分页策略
struct TeachingPDFExportSettings: Codable, Equatable {
    enum PaperPreset: String, Codable, CaseIterable, Equatable {
        case a4
        case letter
        case custom
    }

    enum PaginationStrategy: String, Codable, CaseIterable, Equatable {
        case paged
        case singleLongPage
    }
    
    enum Orientation: String, Codable, CaseIterable, Equatable {
        case portrait
        case landscape
    }

    var paperPreset: PaperPreset
    var paginationStrategy: PaginationStrategy
    var orientation: Orientation
    var customWidth: Double
    var customHeight: Double
    var marginTop: Double
    var marginBottom: Double
    var marginLeft: Double
    var marginRight: Double
    var nodeMarkdownScalePercent: Double

    init(
        paperPreset: PaperPreset = .a4,
        paginationStrategy: PaginationStrategy = .paged,
        orientation: Orientation = .portrait,
        customWidth: Double = 595,
        customHeight: Double = 842,
        marginTop: Double = 24,
        marginBottom: Double = 24,
        marginLeft: Double = 24,
        marginRight: Double = 24,
        nodeMarkdownScalePercent: Double = 40
    ) {
        self.paperPreset = paperPreset
        self.paginationStrategy = paginationStrategy
        self.orientation = orientation
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.marginTop = marginTop
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
        self.marginRight = marginRight
        self.nodeMarkdownScalePercent = nodeMarkdownScalePercent
    }

    func normalized() -> TeachingPDFExportSettings {
        TeachingPDFExportSettings(
            paperPreset: paperPreset,
            paginationStrategy: paginationStrategy,
            orientation: orientation,
            customWidth: max(200, min(2000, customWidth)),
            customHeight: max(200, min(4000, customHeight)),
            marginTop: max(0, min(200, marginTop)),
            marginBottom: max(0, min(200, marginBottom)),
            marginLeft: max(0, min(200, marginLeft)),
            marginRight: max(0, min(200, marginRight)),
            nodeMarkdownScalePercent: max(10, min(100, nodeMarkdownScalePercent))
        )
    }
}

// MARK: - 学生系统设置 - v1 - 保存学生模板和上课信息字段映射
struct TeachingStudentSystemSettings: Codable, Equatable {
    var studentInfoTemplateID: String?
    var studentNameKeyID: String?
    var classInfoTemplateID: String?
    var classInfoNameKeyID: String?
    var classInfoContentKeyID: String?
    var classInfoTimeKeyID: String?
    var lessonPlanFolderIDs: [String]
    var workbookFileID: String?
    var syncBaseFolderPath: String?
    var pdfExportSettings: TeachingPDFExportSettings
    var lessonChecklistExpandMode: String

    init(
        studentInfoTemplateID: String? = nil,
        studentNameKeyID: String? = nil,
        classInfoTemplateID: String? = nil,
        classInfoNameKeyID: String? = nil,
        classInfoContentKeyID: String? = nil,
        classInfoTimeKeyID: String? = nil,
        lessonPlanFolderIDs: [String] = [],
        workbookFileID: String? = nil,
        syncBaseFolderPath: String? = nil,
        pdfExportSettings: TeachingPDFExportSettings = TeachingPDFExportSettings(),
        lessonChecklistExpandMode: String = "l3"
    ) {
        self.studentInfoTemplateID = studentInfoTemplateID
        self.studentNameKeyID = studentNameKeyID
        self.classInfoTemplateID = classInfoTemplateID
        self.classInfoNameKeyID = classInfoNameKeyID
        self.classInfoContentKeyID = classInfoContentKeyID
        self.classInfoTimeKeyID = classInfoTimeKeyID
        self.lessonPlanFolderIDs = lessonPlanFolderIDs
        self.workbookFileID = workbookFileID
        self.syncBaseFolderPath = syncBaseFolderPath
        self.pdfExportSettings = pdfExportSettings
        self.lessonChecklistExpandMode = lessonChecklistExpandMode
    }

    private enum CodingKeys: String, CodingKey {
        case studentInfoTemplateID
        case studentNameKeyID
        case classInfoTemplateID
        case classInfoNameKeyID
        case classInfoContentKeyID
        case classInfoTimeKeyID
        case lessonPlanFolderIDs
        case workbookFileID
        case syncBaseFolderPath
        case pdfExportSettings
        case lessonChecklistExpandMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        studentInfoTemplateID = try container.decodeIfPresent(String.self, forKey: .studentInfoTemplateID)
        studentNameKeyID = try container.decodeIfPresent(String.self, forKey: .studentNameKeyID)
        classInfoTemplateID = try container.decodeIfPresent(String.self, forKey: .classInfoTemplateID)
        classInfoNameKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoNameKeyID)
        classInfoContentKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoContentKeyID)
        classInfoTimeKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoTimeKeyID)
        lessonPlanFolderIDs = try container.decodeIfPresent([String].self, forKey: .lessonPlanFolderIDs) ?? []
        workbookFileID = try container.decodeIfPresent(String.self, forKey: .workbookFileID)
        syncBaseFolderPath = try container.decodeIfPresent(String.self, forKey: .syncBaseFolderPath)
        pdfExportSettings = try container.decodeIfPresent(TeachingPDFExportSettings.self, forKey: .pdfExportSettings) ?? TeachingPDFExportSettings()
        lessonChecklistExpandMode = try container.decodeIfPresent(String.self, forKey: .lessonChecklistExpandMode) ?? "l3"
    }

    func normalized() -> TeachingStudentSystemSettings {
        TeachingStudentSystemSettings(
            studentInfoTemplateID: studentInfoTemplateID?.trimmedNilIfEmpty(),
            studentNameKeyID: studentNameKeyID?.trimmedNilIfEmpty(),
            classInfoTemplateID: classInfoTemplateID?.trimmedNilIfEmpty(),
            classInfoNameKeyID: classInfoNameKeyID?.trimmedNilIfEmpty(),
            classInfoContentKeyID: classInfoContentKeyID?.trimmedNilIfEmpty(),
            classInfoTimeKeyID: classInfoTimeKeyID?.trimmedNilIfEmpty(),
            lessonPlanFolderIDs: lessonPlanFolderIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { partial, item in
                    if !partial.contains(item) { partial.append(item) }
                },
            workbookFileID: workbookFileID?.trimmedNilIfEmpty(),
            syncBaseFolderPath: syncBaseFolderPath?.trimmedNilIfEmpty(),
            pdfExportSettings: pdfExportSettings.normalized(),
            lessonChecklistExpandMode: {
                let mode = lessonChecklistExpandMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return mode == "l1" ? "l1" : "l3"
            }()
        )
    }

    func validationIssues(prefix: String) -> [String] {
        var issues: [String] = []
        let keys = [classInfoNameKeyID, classInfoContentKeyID, classInfoTimeKeyID].compactMap { $0?.trimmedNilIfEmpty() }
        if Set(keys).count != keys.count {
            issues.append("\(prefix) classInfo key ids duplicated")
        }
        return issues
    }
}

// MARK: - 教案系统设置 - v1 - 保存教案管理的默认路径与最近打开状态
struct TeachingLessonPlanSystemSettings: Codable, Equatable {
    var rootRelativePath: String?
    var recentLessonPlanFolderIDs: [String]

    init(rootRelativePath: String? = nil, recentLessonPlanFolderIDs: [String] = []) {
        self.rootRelativePath = rootRelativePath
        self.recentLessonPlanFolderIDs = recentLessonPlanFolderIDs
    }

    func normalized() -> TeachingLessonPlanSystemSettings {
        TeachingLessonPlanSystemSettings(
            rootRelativePath: rootRelativePath?.trimmedNilIfEmpty(),
            recentLessonPlanFolderIDs: recentLessonPlanFolderIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { partial, item in
                    if !partial.contains(item) { partial.append(item) }
                }
        )
    }

    func validationIssues(prefix: String) -> [String] {
        if recentLessonPlanFolderIDs.count > 128 {
            return ["\(prefix) recentLessonPlanFolderIDs too large"]
        }
        return []
    }
}

// MARK: - 学生覆盖设置 - v1 - 针对单个学生覆盖模板映射与同步目录
struct TeachingStudentProfileSettings: Codable, Equatable {
    var studentInfoTemplateID: String?
    var studentNameKeyID: String?
    var classInfoTemplateID: String?
    var classInfoNameKeyID: String?
    var classInfoContentKeyID: String?
    var classInfoTimeKeyID: String?
    var lessonPlanFolderIDs: [String]
    var workbookFileID: String?
    var syncBaseFolderPath: String?
    var lessonStatistics: TeachingStudentLessonStatisticsSettings

    init(
        studentInfoTemplateID: String? = nil,
        studentNameKeyID: String? = nil,
        classInfoTemplateID: String? = nil,
        classInfoNameKeyID: String? = nil,
        classInfoContentKeyID: String? = nil,
        classInfoTimeKeyID: String? = nil,
        lessonPlanFolderIDs: [String] = [],
        workbookFileID: String? = nil,
        syncBaseFolderPath: String? = nil,
        lessonStatistics: TeachingStudentLessonStatisticsSettings = TeachingStudentLessonStatisticsSettings()
    ) {
        self.studentInfoTemplateID = studentInfoTemplateID
        self.studentNameKeyID = studentNameKeyID
        self.classInfoTemplateID = classInfoTemplateID
        self.classInfoNameKeyID = classInfoNameKeyID
        self.classInfoContentKeyID = classInfoContentKeyID
        self.classInfoTimeKeyID = classInfoTimeKeyID
        self.lessonPlanFolderIDs = lessonPlanFolderIDs
        self.workbookFileID = workbookFileID
        self.syncBaseFolderPath = syncBaseFolderPath
        self.lessonStatistics = lessonStatistics
    }

    private enum CodingKeys: String, CodingKey {
        case studentInfoTemplateID
        case studentNameKeyID
        case classInfoTemplateID
        case classInfoNameKeyID
        case classInfoContentKeyID
        case classInfoTimeKeyID
        case lessonPlanFolderIDs
        case workbookFileID
        case syncBaseFolderPath
        case lessonStatistics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        studentInfoTemplateID = try container.decodeIfPresent(String.self, forKey: .studentInfoTemplateID)
        studentNameKeyID = try container.decodeIfPresent(String.self, forKey: .studentNameKeyID)
        classInfoTemplateID = try container.decodeIfPresent(String.self, forKey: .classInfoTemplateID)
        classInfoNameKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoNameKeyID)
        classInfoContentKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoContentKeyID)
        classInfoTimeKeyID = try container.decodeIfPresent(String.self, forKey: .classInfoTimeKeyID)
        lessonPlanFolderIDs = try container.decodeIfPresent([String].self, forKey: .lessonPlanFolderIDs) ?? []
        workbookFileID = try container.decodeIfPresent(String.self, forKey: .workbookFileID)
        syncBaseFolderPath = try container.decodeIfPresent(String.self, forKey: .syncBaseFolderPath)
        lessonStatistics = try container.decodeIfPresent(TeachingStudentLessonStatisticsSettings.self, forKey: .lessonStatistics) ?? TeachingStudentLessonStatisticsSettings()
    }

    func normalized() -> TeachingStudentProfileSettings {
        TeachingStudentProfileSettings(
            studentInfoTemplateID: studentInfoTemplateID?.trimmedNilIfEmpty(),
            studentNameKeyID: studentNameKeyID?.trimmedNilIfEmpty(),
            classInfoTemplateID: classInfoTemplateID?.trimmedNilIfEmpty(),
            classInfoNameKeyID: classInfoNameKeyID?.trimmedNilIfEmpty(),
            classInfoContentKeyID: classInfoContentKeyID?.trimmedNilIfEmpty(),
            classInfoTimeKeyID: classInfoTimeKeyID?.trimmedNilIfEmpty(),
            lessonPlanFolderIDs: lessonPlanFolderIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { partial, item in
                    if !partial.contains(item) { partial.append(item) }
                },
            workbookFileID: workbookFileID?.trimmedNilIfEmpty(),
            syncBaseFolderPath: syncBaseFolderPath?.trimmedNilIfEmpty(),
            lessonStatistics: lessonStatistics.normalized()
        )
    }

    func validationIssues(prefix: String) -> [String] {
        var issues: [String] = []
        let keys = [classInfoNameKeyID, classInfoContentKeyID, classInfoTimeKeyID].compactMap { $0?.trimmedNilIfEmpty() }
        if Set(keys).count != keys.count {
            issues.append("\(prefix) classInfo key ids duplicated")
        }
        issues.append(contentsOf: lessonStatistics.validationIssues(prefix: "\(prefix).lessonStatistics"))
        return issues
    }
}

// MARK: - 学生课时统计设置 - v1 - 单个学生的机构与两小时价格
struct TeachingStudentLessonStatisticsSettings: Codable, Equatable {
    var institutionID: UUID?
    var institutionName: String?
    var priceForTwoHours: Double?

    init(
        institutionID: UUID? = nil,
        institutionName: String? = nil,
        priceForTwoHours: Double? = nil
    ) {
        self.institutionID = institutionID
        self.institutionName = institutionName
        self.priceForTwoHours = priceForTwoHours
    }

    func normalized() -> TeachingStudentLessonStatisticsSettings {
        let name = institutionName?.trimmedNilIfEmpty()
        return TeachingStudentLessonStatisticsSettings(
            institutionID: name == nil ? nil : institutionID,
            institutionName: name,
            priceForTwoHours: name == nil ? nil : priceForTwoHours
        )
    }

    var isComplete: Bool {
        institutionID != nil && institutionName?.trimmedNilIfEmpty() != nil && priceForTwoHours != nil
    }

    func validationIssues(prefix: String) -> [String] {
        let hasInstitution = institutionID != nil || institutionName?.trimmedNilIfEmpty() != nil
        let hasPrice = priceForTwoHours != nil
        if hasInstitution && !hasPrice {
            return ["\(prefix) priceForTwoHours missing when institution exists"]
        }
        if !hasInstitution && hasPrice {
            return ["\(prefix) priceForTwoHours exists without institution"]
        }
        return []
    }
}

private extension String {
    func trimmedNilIfEmpty() -> String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
